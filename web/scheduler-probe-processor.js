// Test-only AudioWorklet diagnostic harness for #212. This file is loaded by
// Playwright's scheduler probe only; production playback uses
// scheduler-processor.js. It mirrors the production scheduler call order but
// uses synchronous wasm instantiation so OfflineAudioContext starts rendering
// deterministically on the first quantum.
const SCHEDULER_PROBE_MAX_BLOCK_COUNT = 4096;
const SCHEDULER_PROBE_TOP_DISCONTINUITY_COUNT = 8;
const SCHEDULER_PROBE_EPSILON = 1e-12;
const SCHEDULER_PROBE_DEFAULT_BPM = 120;
const SCHEDULER_PROBE_DEFAULT_GAIN = 0.5;
// Keep in sync with REQUIRED_EXPORTS in playwright-tests/scheduler-probe.spec.js.
const SCHEDULER_PROBE_REQUIRED_EXPORTS = [
  'init_scheduler_graph',
  'process_scheduler_block',
  'scheduler_left_sample',
  'scheduler_right_sample',
  'clear_pattern_input',
  'push_pattern_char',
  'eval_pattern_input',
  'get_pattern_error_length',
  'get_pattern_error_char',
  'get_browser_error_length',
  'get_browser_error_char',
  'set_scheduler_bpm',
  'set_scheduler_gain',
];

class MoonDspSchedulerProbeProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const processorOptions = options?.processorOptions || {};
    this.wasm = null;
    this.ready = false;
    this.graphInitialized = false;
    this.patternInitialized = false;
    this.done = false;
    this.reportedError = false;
    this.reportedDone = false;
    this.blockIndex = 0;
    this.absoluteFrame = 0;
    this.previousSamples = { left: 0, right: 0 };
    this.patternText = String(processorOptions.patternText ?? '');
    this.initialBpm = this.numberOption(processorOptions.initialBpm, SCHEDULER_PROBE_DEFAULT_BPM);
    this.initialGain = this.numberOption(processorOptions.initialGain, SCHEDULER_PROBE_DEFAULT_GAIN);
    this.maxBlocks = Math.min(
      SCHEDULER_PROBE_MAX_BLOCK_COUNT,
      Math.max(1, this.integerOption(processorOptions.maxBlocks, 512)),
    );
    this.topDiscontinuities = [];
    this.rendered = {
      left: this.emptyAggregate(),
      right: this.emptyAggregate(),
    };
    this.parseStatus = null;
    this.parseError = '';

    const wasmModule = processorOptions.wasmModule;
    if (!wasmModule) {
      this.postError('Missing wasm module');
      return;
    }

    try {
      const instance = new WebAssembly.Instance(wasmModule, {
        spectest: { print_char() {} },
        'moonbit:ffi': {
          make_closure(funcref, closure) {
            return funcref.bind(null, closure);
          },
        },
      });
      this.wasm = instance.exports;
      const missingExports = this.missingExports(SCHEDULER_PROBE_REQUIRED_EXPORTS);
      if (missingExports.length > 0) {
        throw new Error(`Scheduler probe exports not found: ${missingExports.join(', ')}`);
      }
      this.ready = true;
      this.port.postMessage({ type: 'ready' });
    } catch (error) {
      this.postError(error instanceof Error ? error.message : String(error));
    }
  }

  process(_inputs, outputs) {
    const output = outputs[0];
    if (!output || output.length === 0) {
      return true;
    }
    const left = output[0];
    const right = output[1];
    if (!left) {
      return true;
    }

    if (!this.ready || !this.wasm || this.done) {
      this.fillSilence(left, right);
      return true;
    }

    if (!this.ensureSchedulerGraph(left.length)) {
      this.stopWithSilence(left, right);
      return true;
    }

    if (!this.patternInitialized && !this.setPatternText(this.patternText)) {
      this.stopWithSilence(left, right);
      return true;
    }

    if (this.blockIndex >= this.maxBlocks) {
      this.fillSilence(left, right);
      return true;
    }

    if (!this.wasm.process_scheduler_block()) {
      this.postError(this.browserErrorMessage('Scheduler block processing failed'));
      this.stopWithSilence(left, right);
      return true;
    }

    const absoluteFrameStart = this.absoluteFrame;
    const leftMetrics = this.copyAndMeasureChannel('left', 'scheduler_left_sample', left, absoluteFrameStart);
    // Playwright configures stereo output; keep the guard so a misconfigured
    // probe reports partial telemetry instead of throwing in the worklet.
    const rightMetrics = right
      ? this.copyAndMeasureChannel('right', 'scheduler_right_sample', right, absoluteFrameStart)
      : null;

    this.port.postMessage({
      type: 'block-metrics',
      blockIndex: this.blockIndex,
      absoluteFrameStart,
      left: leftMetrics,
      right: rightMetrics,
    });

    this.blockIndex += 1;
    this.absoluteFrame += left.length;
    if (this.blockIndex >= this.maxBlocks) {
      this.done = true;
      this.postDone();
    }
    return true;
  }

  ensureSchedulerGraph(blockSize) {
    if (this.graphInitialized) {
      return true;
    }
    const ok = this.wasm.init_scheduler_graph(sampleRate, blockSize);
    if (!ok) {
      this.postError(this.browserErrorMessage('Scheduler graph initialization failed'));
      return false;
    }
    this.graphInitialized = true;
    this.wasm.set_scheduler_bpm(this.initialBpm);
    this.wasm.set_scheduler_gain(this.initialGain);
    this.port.postMessage({
      type: 'initialized',
      sampleRate,
      blockSize,
      bpm: this.initialBpm,
      gain: this.initialGain,
    });
    return true;
  }

  setPatternText(text) {
    this.wasm.clear_pattern_input();
    for (let index = 0; index < text.length; index += 1) {
      this.wasm.push_pattern_char(text.charCodeAt(index));
    }
    const status = this.wasm.eval_pattern_input();
    this.parseStatus = status;
    this.parseError = status === 0 ? '' : this.patternErrorMessage();
    if (status === 0) {
      this.patternInitialized = true;
      this.port.postMessage({ type: 'pattern-updated', status });
      return true;
    }
    this.port.postMessage({ type: 'pattern-error', status, message: this.parseError });
    return false;
  }

  copyAndMeasureChannel(channel, exportName, output, absoluteFrameStart) {
    const metrics = {
      peak: 0,
      rms: 0,
      nanOrInfCount: 0,
      maxStep: 0,
      maxStepFrame: absoluteFrameStart,
      maxStepBefore: this.previousSamples[channel],
      maxStepAfter: this.previousSamples[channel],
      boundaryStep: 0,
      boundaryBefore: this.previousSamples[channel],
      boundaryAfter: this.previousSamples[channel],
    };
    let sumSquares = 0;
    let previous = this.previousSamples[channel];
    const aggregate = this.rendered[channel];

    for (let index = 0; index < output.length; index += 1) {
      const rawSample = this.wasm[exportName](index);
      let sample = rawSample;
      let sanitized = !Number.isFinite(sample);
      if (sanitized) {
        sample = 0;
      }
      output[index] = sample;
      if (!Number.isFinite(output[index])) {
        sanitized = true;
        sample = 0;
        output[index] = 0;
      }

      if (sanitized) {
        metrics.nanOrInfCount += 1;
        aggregate.nanOrInfCount += 1;
      }

      const abs = Math.abs(sample);
      metrics.peak = Math.max(metrics.peak, abs);
      aggregate.peak = Math.max(aggregate.peak, abs);
      if (abs > SCHEDULER_PROBE_EPSILON) {
        aggregate.nonZeroSampleCount += 1;
        if (aggregate.firstActiveFrame === null) {
          aggregate.firstActiveFrame = absoluteFrameStart + index;
        }
      }
      sumSquares += sample * sample;
      aggregate.sumSquares += sample * sample;
      aggregate.sampleCount += 1;

      const frame = absoluteFrameStart + index;
      const step = Math.abs(sample - previous);
      const isBoundary = index === 0;
      if (isBoundary) {
        metrics.boundaryStep = step;
        metrics.boundaryBefore = previous;
        metrics.boundaryAfter = sample;
      }
      if (!isBoundary && step > metrics.maxStep) {
        metrics.maxStep = step;
        metrics.maxStepFrame = frame;
        metrics.maxStepBefore = previous;
        metrics.maxStepAfter = sample;
      }
      this.recordDiscontinuity({
        step,
        channel,
        blockIndex: this.blockIndex,
        frame,
        before: previous,
        after: sample,
        kind: this.classifyStep(previous, sample, isBoundary),
      });
      previous = sample;
    }

    this.previousSamples[channel] = previous;
    metrics.rms = Math.sqrt(sumSquares / Math.max(1, output.length));
    return metrics;
  }

  classifyStep(before, after, isBoundary) {
    const beforeActive = Math.abs(before) > SCHEDULER_PROBE_EPSILON;
    const afterActive = Math.abs(after) > SCHEDULER_PROBE_EPSILON;
    if (!beforeActive && afterActive) {
      return 'first-active-after-silence';
    }
    if (beforeActive && !afterActive) {
      return 'silence-after-active';
    }
    return isBoundary ? 'block-boundary' : 'mid-block';
  }

  recordDiscontinuity(entry) {
    if (!Number.isFinite(entry.step) || entry.step <= 0) {
      return;
    }
    const last = this.topDiscontinuities[this.topDiscontinuities.length - 1];
    if (this.topDiscontinuities.length >= SCHEDULER_PROBE_TOP_DISCONTINUITY_COUNT &&
        last && entry.step <= last.step) {
      return;
    }
    this.topDiscontinuities.push(entry);
    this.topDiscontinuities.sort((a, b) => b.step - a.step);
    if (this.topDiscontinuities.length > SCHEDULER_PROBE_TOP_DISCONTINUITY_COUNT) {
      this.topDiscontinuities.length = SCHEDULER_PROBE_TOP_DISCONTINUITY_COUNT;
    }
  }

  postDone() {
    if (this.reportedDone) {
      return;
    }
    this.reportedDone = true;
    const maxDiscontinuity = this.topDiscontinuities[0] || null;
    this.port.postMessage({
      type: 'done',
      blockCount: this.blockIndex,
      absoluteFrameCount: this.absoluteFrame,
      parseStatus: this.parseStatus,
      parseError: this.parseError,
      maxDiscontinuity,
      maxDiscontinuityKind: maxDiscontinuity?.kind ?? 'none',
      topDiscontinuities: this.topDiscontinuities,
      rendered: {
        left: this.aggregateSummary(this.rendered.left),
        right: this.aggregateSummary(this.rendered.right),
      },
    });
  }

  aggregateSummary(aggregate) {
    return {
      peak: aggregate.peak,
      rms: Math.sqrt(aggregate.sumSquares / Math.max(1, aggregate.sampleCount)),
      nanOrInfCount: aggregate.nanOrInfCount,
      nonZeroSampleCount: aggregate.nonZeroSampleCount,
      firstActiveFrame: aggregate.firstActiveFrame,
    };
  }

  emptyAggregate() {
    return {
      peak: 0,
      sumSquares: 0,
      sampleCount: 0,
      nanOrInfCount: 0,
      nonZeroSampleCount: 0,
      firstActiveFrame: null,
    };
  }

  missingExports(names) {
    return names.filter((name) => typeof this.wasm[name] !== 'function');
  }

  numberOption(value, fallback) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  integerOption(value, fallback) {
    const number = Number(value);
    return Number.isInteger(number) ? number : fallback;
  }

  stopWithSilence(left, right) {
    this.fillSilence(left, right);
    this.done = true;
    this.postDone();
  }

  fillSilence(left, right) {
    left.fill(0);
    if (right) {
      right.fill(0);
    }
  }

  patternErrorMessage() {
    return this.stringFromCharExports(
      'get_pattern_error_length',
      'get_pattern_error_char',
      'pattern parse error',
    );
  }

  browserErrorMessage(fallback) {
    return this.stringFromCharExports('get_browser_error_length', 'get_browser_error_char', fallback);
  }

  stringFromCharExports(lengthExport, charExport, fallback) {
    if (this.wasm &&
        typeof this.wasm[lengthExport] === 'function' &&
        typeof this.wasm[charExport] === 'function') {
      const len = this.wasm[lengthExport]();
      if (len > 0) {
        const codes = new Array(len);
        for (let i = 0; i < len; i += 1) {
          codes[i] = this.wasm[charExport](i);
        }
        return String.fromCharCode(...codes);
      }
    }
    return fallback;
  }

  postError(message) {
    if (!this.reportedError) {
      this.reportedError = true;
      this.port.postMessage({ type: 'error', message });
    }
  }
}

registerProcessor('moondsp-scheduler-probe', MoonDspSchedulerProbeProcessor);
