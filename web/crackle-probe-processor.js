const CRACKLE_PROBE_MAX_BLOCK_COUNT = 4096;

class MoonDspCrackleProbeProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const processorOptions = options?.processorOptions || {};
    this.wasm = null;
    this.ready = false;
    this.initialized = false;
    this.done = false;
    this.reportedError = false;
    this.blockIndex = 0;
    this.routeId = this.integerOption(processorOptions.routeId, 3);
    this.waveformId = this.integerOption(processorOptions.waveformId, 0);
    this.freqHz = this.numberOption(processorOptions.freqHz, 440);
    this.maxBlocks = Math.min(
      CRACKLE_PROBE_MAX_BLOCK_COUNT,
      Math.max(1, this.integerOption(processorOptions.blockCount, 512)),
    );

    const wasmModule = processorOptions.wasmModule;
    if (!wasmModule) {
      this.postError("Missing wasm module");
      return;
    }

    try {
      // OfflineAudioContext tests pass a precompiled module and render
      // immediately; synchronous instantiation keeps the first render quantum
      // deterministic and avoids async readiness races in this test-only probe.
      const instance = new WebAssembly.Instance(wasmModule, {
        spectest: { print_char() {} },
        "moonbit:ffi": {
          make_closure(funcref, closure) {
            return funcref.bind(null, closure);
          },
        },
      });
      this.wasm = instance.exports;
      const missingExports = this.missingExports([
        "crackle_probe_stream_init",
        "crackle_probe_stream_process",
        "crackle_probe_metric",
        "crackle_probe_sample",
        "crackle_probe_last_error",
        "crackle_probe_block_count",
      ]);
      if (missingExports.length > 0) {
        throw new Error(`Crackle probe exports not found: ${missingExports.join(", ")}`);
      }
      this.ready = true;
      this.port.postMessage({ type: "ready" });
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

    if (!this.initialized) {
      const ok = this.wasm.crackle_probe_stream_init(
        this.routeId,
        this.waveformId,
        this.freqHz,
        sampleRate,
        left.length,
      );
      if (!ok) {
        this.postProbeError("crackle_probe_stream_init failed");
        this.fillSilence(left, right);
        this.done = true;
        return true;
      }
      this.initialized = true;
      this.port.postMessage({
        type: "initialized",
        sampleRate,
        blockSize: left.length,
        routeId: this.routeId,
        waveformId: this.waveformId,
      });
    }

    if (this.blockIndex >= this.maxBlocks) {
      this.fillSilence(left, right);
      return true;
    }

    if (!this.wasm.crackle_probe_stream_process()) {
      this.postProbeError("crackle_probe_stream_process failed");
      this.fillSilence(left, right);
      this.done = true;
      return true;
    }

    for (let index = 0; index < left.length; index += 1) {
      const sample = this.wasm.crackle_probe_sample(0, index);
      left[index] = sample;
      if (right) {
        right[index] = sample;
      }
    }

    const wasmBlockIndex = this.wasm.crackle_probe_block_count() - 1;
    this.port.postMessage({
      type: "block-metrics",
      blockIndex: this.blockIndex,
      wasmBlockIndex,
      metrics: this.readMetrics(wasmBlockIndex),
      lastError: this.wasm.crackle_probe_last_error(),
    });

    this.blockIndex += 1;
    if (this.blockIndex >= this.maxBlocks) {
      this.done = true;
      this.port.postMessage({
        type: "done",
        blockCount: this.blockIndex,
        wasmBlockCount: this.wasm.crackle_probe_block_count(),
      });
    }
    return true;
  }

  readMetrics(blockIndex) {
    return {
      peak: this.wasm.crackle_probe_metric(blockIndex, 0),
      rms: this.wasm.crackle_probe_metric(blockIndex, 1),
      mean: this.wasm.crackle_probe_metric(blockIndex, 2),
      nanOrInfCount: this.wasm.crackle_probe_metric(blockIndex, 3),
      sanitizedCount: this.wasm.crackle_probe_metric(blockIndex, 4),
      maxStep: this.wasm.crackle_probe_metric(blockIndex, 5),
      boundaryStep: this.wasm.crackle_probe_metric(blockIndex, 6),
      maxResidual: this.wasm.crackle_probe_metric(blockIndex, 7),
      rmsResidual: this.wasm.crackle_probe_metric(blockIndex, 8),
      firstSample: this.wasm.crackle_probe_metric(blockIndex, 9),
      lastSample: this.wasm.crackle_probe_metric(blockIndex, 10),
      boundaryStepDifference: this.wasm.crackle_probe_metric(blockIndex, 11),
      maxStepIndex: this.wasm.crackle_probe_metric(blockIndex, 12),
      maxResidualIndex: this.wasm.crackle_probe_metric(blockIndex, 13),
    };
  }

  missingExports(names) {
    return names.filter((name) => typeof this.wasm[name] !== "function");
  }

  numberOption(value, fallback) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  integerOption(value, fallback) {
    const number = Number(value);
    return Number.isInteger(number) ? number : fallback;
  }

  fillSilence(left, right) {
    left.fill(0);
    if (right) {
      right.fill(0);
    }
  }

  postProbeError(message) {
    const lastError = this.wasm && typeof this.wasm.crackle_probe_last_error === "function"
      ? this.wasm.crackle_probe_last_error()
      : -1;
    this.postError(`${message}; last_error=${lastError}`);
  }

  postError(message) {
    if (!this.reportedError) {
      this.reportedError = true;
      this.port.postMessage({ type: "error", message });
    }
  }
}

registerProcessor("moondsp-crackle-probe", MoonDspCrackleProbeProcessor);
