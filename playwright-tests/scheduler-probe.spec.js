const { test, expect } = require('@playwright/test');

const BLOCK_SIZE = 128;
const SAMPLE_RATE = 48_000;
const BPM = 120;
const GAIN = 0.5;
const EPSILON = 1e-12;
const CYCLE_FRAMES = SAMPLE_RATE * 60 / BPM;

const REQUIRED_EXPORTS = [
  'init_scheduler_graph',
  'process_scheduler_block',
  'scheduler_left_sample',
  'scheduler_right_sample',
  'clear_playback_input',
  'push_playback_char',
  'prepare_pattern_input',
  'apply_prepared_playback',
  'get_playback_error_length',
  'get_playback_error_char',
  'get_browser_error_length',
  'get_browser_error_char',
  'set_scheduler_bpm',
  'set_scheduler_gain',
];

const TEST_DIAGNOSTIC_EXPORTS = [
  'init_scheduler_sine_graph',
  'scheduler_last_sanitized_count',
  'scheduler_synth_active_voice_count',
  'scheduler_synth_voice_capacity',
];

const PRODUCTION_CASES = [
  {
    name: 'production-note-triad',
    patternText: 'note("60 64 67")',
    maxBlocks: 128,
    expectParseOk: true,
    expectActiveAudio: true,
  },
  {
    name: 'production-drum-basic',
    patternText: 's("bd sd hh sd")',
    maxBlocks: 128,
    expectParseOk: true,
    expectActiveAudio: true,
  },
  {
    name: 'production-silence',
    patternText: 's("bd(0,8)")',
    maxBlocks: 64,
    expectParseOk: true,
    expectActiveAudio: false,
  },
  {
    name: 'production-invalid-pattern',
    patternText: 'invalid!!!',
    maxBlocks: 8,
    expectParseOk: false,
    expectActiveAudio: false,
  },
];

const PATTERN_MATRIX = [
  {
    name: 'single-note-release-reuse',
    patternText: 'note("60")',
    maxBlocks: 512,
    eventPeriodFrames: CYCLE_FRAMES,
    expectActiveAudio: true,
  },
  {
    name: 'triad-third-cycle-onsets',
    patternText: 'note("60 64 67")',
    maxBlocks: 256,
    eventPeriodFrames: CYCLE_FRAMES / 3,
    expectActiveAudio: true,
  },
  {
    name: 'dense-overlap',
    patternText: 'note("60,64,67").fast(8)',
    maxBlocks: 128,
    eventPeriodFrames: CYCLE_FRAMES / 24,
    expectActiveAudio: true,
  },
  {
    name: 'thirteen-note-stack-voice-pressure-near-event',
    patternText: 'note("48,49,50,51,52,53,54,55,56,57,58,59,60").fast(8)',
    maxBlocks: 128,
    eventPeriodFrames: CYCLE_FRAMES / 8,
    expectActiveAudio: true,
    expectVoicePressureNearEvent: true,
  },
  {
    name: 'silence-output-stage',
    patternText: 's("bd(0,8)")',
    maxBlocks: 64,
    eventPeriodFrames: 0,
    expectActiveAudio: false,
  },
];

const WAVEFORMS = [
  { waveform: 'triangle', initExportName: 'init_scheduler_graph' },
  { waveform: 'sine', initExportName: 'init_scheduler_sine_graph' },
];

function expectHealthyRender(summary, label) {
  expect(summary.processorErrors, label).toEqual([]);
  expect(summary.parseStatus, label).toBe(0);
  expect(summary.patternError, label).toBe('');
  expect(summary.blockCount, label).toBe(summary.maxBlocks);
  expect(summary.page.ok, label).toBe(true);
  expect(summary.page.parseStatus, label).toBe(0);
  expect(summary.page.nanOrInfCount, `${label} page non-finite`).toBe(0);
  expect(summary.worklet.nanOrInfCount, `${label} worklet non-finite`).toBe(0);
  expect(summary.page.sanitizedCount, `${label} page sanitizer`).toBe(0);
  expect(summary.worklet.sanitizedCount, `${label} worklet sanitizer`).toBe(0);
  expect(summary.pcm.maxResidual, `${label} Float32 residual`).toBe(0);
  expect(summary.pcm.mismatchCount, `${label} Float32 mismatches`).toBe(0);
  if (summary.expectActiveAudio) {
    expect(summary.worklet.peak, label).toBeGreaterThan(0);
  } else {
    expect(summary.worklet.peak, label).toBe(0);
  }
}

test('scheduler probe: production AudioWorklet path remains healthy', async ({ page }) => {
  test.setTimeout(30_000);
  await page.goto('/');
  const result = await page.evaluate(async ({
    cases,
    requiredExports,
    blockSize,
    sampleRate,
    bpm,
    gain,
  }) => {
    const response = await fetch('moonbit_dsp.wasm');
    if (!response.ok) {
      return { error: `moonbit_dsp.wasm fetch failed: ${response.status}` };
    }
    const wasmModule = await WebAssembly.compile(await response.arrayBuffer());
    const exportNames = WebAssembly.Module.exports(wasmModule).map((entry) => entry.name);
    const missing = requiredExports.filter((name) => !exportNames.includes(name));
    if (missing.length > 0) {
      return { error: `moonbit_dsp.wasm missing exports: ${missing.join(', ')}` };
    }

    const render = async (probeCase) => {
      const context = new OfflineAudioContext(2, blockSize * probeCase.maxBlocks, sampleRate);
      await context.audioWorklet.addModule('scheduler-probe-processor.js');
      const messages = [];
      let resolveTerminal;
      const terminal = new Promise((resolve) => {
        resolveTerminal = resolve;
      });
      const node = new AudioWorkletNode(context, 'moondsp-scheduler-probe', {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          patternText: probeCase.patternText,
          maxBlocks: probeCase.maxBlocks,
          initialBpm: bpm,
          initialGain: gain,
        },
      });
      node.port.onmessage = ({ data }) => {
        messages.push(data);
        if (data?.type === 'done' || data?.type === 'error') {
          resolveTerminal(data);
        }
      };
      node.connect(context.destination);
      const [rendered] = await Promise.all([context.startRendering(), terminal]);
      const blocks = messages.filter((message) => message?.type === 'block-metrics');
      const done = messages.find((message) => message?.type === 'done');
      let peak = 0;
      let nanOrInfCount = 0;
      let nonZeroSampleCount = 0;
      for (let channel = 0; channel < rendered.numberOfChannels; channel += 1) {
        for (const sample of rendered.getChannelData(channel)) {
          if (!Number.isFinite(sample)) {
            nanOrInfCount += 1;
          } else {
            peak = Math.max(peak, Math.abs(sample));
            nonZeroSampleCount += Math.abs(sample) > 1e-12 ? 1 : 0;
          }
        }
      }
      return {
        ...probeCase,
        processorErrors: messages.filter((message) => message?.type === 'error'),
        patternError: messages.find((message) => message?.type === 'pattern-error')?.message || '',
        parseStatus: done?.parseStatus ??
          messages.find((message) => message?.type === 'pattern-error')?.status ??
          null,
        blockCount: blocks.length,
        peak,
        nanOrInfCount,
        nonZeroSampleCount,
      };
    };

    const summaries = [];
    for (const probeCase of cases) {
      summaries.push(await render(probeCase));
    }
    return { summaries };
  }, {
    cases: PRODUCTION_CASES,
    requiredExports: REQUIRED_EXPORTS,
    blockSize: BLOCK_SIZE,
    sampleRate: SAMPLE_RATE,
    bpm: BPM,
    gain: GAIN,
  });

  expect(result.error, 'production scheduler probe').toBeFalsy();
  for (const summary of result.summaries) {
    expect(summary.processorErrors, summary.name).toEqual([]);
    expect(summary.nanOrInfCount, summary.name).toBe(0);
    if (summary.expectParseOk) {
      expect(summary.parseStatus, summary.name).toBe(0);
      expect(summary.patternError, summary.name).toBe('');
      expect(summary.blockCount, summary.name).toBe(summary.maxBlocks);
      if (summary.expectActiveAudio) {
        expect(summary.peak, summary.name).toBeGreaterThan(0);
      } else {
        expect(summary.peak, summary.name).toBe(0);
      }
    } else {
      expect(summary.parseStatus, summary.name).toBe(1);
      expect(summary.patternError.length, summary.name).toBeGreaterThan(0);
      expect(summary.blockCount, summary.name).toBe(0);
    }
  }
  console.log(`scheduler-production-report ${JSON.stringify(result.summaries)}`);
});

test('scheduler probe: Triangle/Sine page and AudioWorklet Float32 PCM match', async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto('/');
  const cases = PATTERN_MATRIX.flatMap((pattern) =>
    WAVEFORMS.map((waveform) => ({ ...pattern, ...waveform })));

  const result = await page.evaluate(async ({
    cases: probeCases,
    requiredExports,
    diagnosticExports,
    blockSize,
    sampleRate,
    bpm,
    gain,
    epsilon,
  }) => {
    if (typeof OfflineAudioContext !== 'function' || typeof AudioWorkletNode !== 'function') {
      return { error: 'OfflineAudioContext or AudioWorkletNode unavailable' };
    }
    const response = await fetch('moonbit_dsp_test.wasm');
    if (!response.ok) {
      return { error: `moonbit_dsp_test.wasm fetch failed: ${response.status}` };
    }
    const wasmModule = await WebAssembly.compile(await response.arrayBuffer());
    const exportNames = WebAssembly.Module.exports(wasmModule).map((entry) => entry.name);
    const missing = [...requiredExports, ...diagnosticExports].filter(
      (name) => !exportNames.includes(name),
    );
    if (missing.length > 0) {
      return { error: `moonbit_dsp_test.wasm missing exports: ${missing.join(', ')}` };
    }
    const imports = {
      spectest: { print_char() {} },
      'moonbit:ffi': {
        make_closure(funcref, closure) {
          return funcref.bind(null, closure);
        },
      },
    };

    const setPattern = (wasm, text) => {
      wasm.clear_playback_input();
      for (let index = 0; index < text.length; index += 1) {
        wasm.push_playback_char(text.charCodeAt(index));
      }
      const token = wasm.prepare_pattern_input();
      return token === 0 ? 1 : wasm.apply_prepared_playback(token, true);
    };

    const emptyPcmSummary = () => ({
      peak: 0,
      nanOrInfCount: 0,
      clippedSampleCount: 0,
      nonZeroSampleCount: 0,
      sanitizedCount: 0,
      maxActiveVoiceCount: 0,
      voiceCapacity: 0,
      voicePressureBlockCount: 0,
    });

    const measureSample = (summary, sample) => {
      if (!Number.isFinite(sample)) {
        summary.nanOrInfCount += 1;
        return;
      }
      const abs = Math.abs(sample);
      summary.peak = Math.max(summary.peak, abs);
      summary.clippedSampleCount += abs > 1 ? 1 : 0;
      summary.nonZeroSampleCount += abs > epsilon ? 1 : 0;
    };

    const renderOnPage = (probeCase) => {
      const instance = new WebAssembly.Instance(wasmModule, imports);
      const wasm = instance.exports;
      const totalFrames = blockSize * probeCase.maxBlocks;
      const left = new Float32Array(totalFrames);
      const right = new Float32Array(totalFrames);
      const summary = emptyPcmSummary();
      const ok = wasm[probeCase.initExportName](sampleRate, blockSize);
      if (!ok) {
        return { ok, parseStatus: null, left, right, ...summary };
      }
      wasm.set_scheduler_bpm(bpm);
      wasm.set_scheduler_gain(gain);
      const parseStatus = setPattern(wasm, probeCase.patternText);
      if (parseStatus !== 0) {
        return { ok, parseStatus, left, right, ...summary };
      }
      for (let block = 0; block < probeCase.maxBlocks; block += 1) {
        if (!wasm.process_scheduler_block()) {
          return { ok: false, parseStatus, left, right, ...summary };
        }
        summary.sanitizedCount += wasm.scheduler_last_sanitized_count();
        const active = wasm.scheduler_synth_active_voice_count();
        const capacity = wasm.scheduler_synth_voice_capacity();
        summary.maxActiveVoiceCount = Math.max(summary.maxActiveVoiceCount, active);
        summary.voiceCapacity = capacity;
        if (probeCase.expectVoicePressureNearEvent && active >= capacity) {
          summary.voicePressureBlockCount += 1;
        }
        const offset = block * blockSize;
        for (let index = 0; index < blockSize; index += 1) {
          const leftSample = Math.fround(wasm.scheduler_left_sample(index));
          const rightSample = Math.fround(wasm.scheduler_right_sample(index));
          left[offset + index] = leftSample;
          right[offset + index] = rightSample;
          measureSample(summary, leftSample);
          measureSample(summary, rightSample);
        }
      }
      return { ok: true, parseStatus, left, right, ...summary };
    };

    const renderInWorklet = async (probeCase) => {
      const context = new OfflineAudioContext(
        2,
        blockSize * probeCase.maxBlocks,
        sampleRate,
      );
      await context.audioWorklet.addModule('scheduler-probe-processor.js');
      const messages = [];
      let resolveTerminal;
      const terminal = new Promise((resolve) => {
        resolveTerminal = resolve;
      });
      const node = new AudioWorkletNode(context, 'moondsp-scheduler-probe', {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          patternText: probeCase.patternText,
          maxBlocks: probeCase.maxBlocks,
          initialBpm: bpm,
          initialGain: gain,
          initExportName: probeCase.initExportName,
          eventPeriodFrames: probeCase.eventPeriodFrames,
          expectVoicePressureNearEvent: probeCase.expectVoicePressureNearEvent || false,
        },
      });
      node.port.onmessage = ({ data }) => {
        messages.push(data);
        if (data?.type === 'done' || data?.type === 'error') {
          resolveTerminal(data);
        }
      };
      node.connect(context.destination);
      const [rendered] = await Promise.all([context.startRendering(), terminal]);
      return { rendered, messages };
    };

    const comparePcm = (pagePcm, rendered) => {
      let mismatchCount = 0;
      let maxResidual = 0;
      let firstMismatch = null;
      for (let channel = 0; channel < 2; channel += 1) {
        const expected = channel === 0 ? pagePcm.left : pagePcm.right;
        const actual = rendered.getChannelData(channel);
        for (let frame = 0; frame < actual.length; frame += 1) {
          const residual = Math.abs(actual[frame] - expected[frame]);
          if (residual !== 0) {
            mismatchCount += 1;
            if (firstMismatch === null) {
              firstMismatch = {
                channel,
                frame,
                page: expected[frame],
                worklet: actual[frame],
              };
            }
          }
          maxResidual = Math.max(maxResidual, residual);
        }
      }
      return { mismatchCount, maxResidual, firstMismatch };
    };

    const summarizeWorklet = (rendered, done) => {
      const summary = emptyPcmSummary();
      for (let channel = 0; channel < rendered.numberOfChannels; channel += 1) {
        for (const sample of rendered.getChannelData(channel)) {
          measureSample(summary, sample);
        }
      }
      summary.sanitizedCount = done?.totalSanitizedCount || 0;
      summary.maxActiveVoiceCount = done?.maxActiveVoiceCount || 0;
      summary.voiceCapacity = done?.voiceCapacity || 0;
      summary.voicePressureBlockCount = done?.voicePressureBlockCount || 0;
      summary.discontinuityRegions = done?.discontinuityRegions || null;
      summary.topDiscontinuities = done?.topDiscontinuities || [];
      return summary;
    };

    const summaries = [];
    for (const probeCase of probeCases) {
      const pagePcm = renderOnPage(probeCase);
      const { rendered, messages } = await renderInWorklet(probeCase);
      const done = messages.find((message) => message?.type === 'done');
      summaries.push({
        ...probeCase,
        page: {
          ...pagePcm,
          left: undefined,
          right: undefined,
        },
        worklet: summarizeWorklet(rendered, done),
        pcm: comparePcm(pagePcm, rendered),
        processorErrors: messages.filter((message) => message?.type === 'error'),
        patternError: messages.find((message) => message?.type === 'pattern-error')?.message || '',
        parseStatus: done?.parseStatus ?? null,
        blockCount: messages.filter((message) => message?.type === 'block-metrics').length,
      });
    }
    return { summaries };
  }, {
    cases,
    requiredExports: REQUIRED_EXPORTS,
    diagnosticExports: TEST_DIAGNOSTIC_EXPORTS,
    blockSize: BLOCK_SIZE,
    sampleRate: SAMPLE_RATE,
    bpm: BPM,
    gain: GAIN,
    epsilon: EPSILON,
  });

  expect(result.error, 'scheduler comparison setup').toBeFalsy();
  for (const summary of result.summaries) {
    const label = `${summary.waveform}/${summary.name}`;
    expectHealthyRender(summary, label);
    expect(summary.worklet.discontinuityRegions, `${label} regions`).toBeTruthy();
    if (summary.expectVoicePressureNearEvent) {
      expect(summary.page.maxActiveVoiceCount, `${label} page voice pressure`).toBe(
        summary.page.voiceCapacity,
      );
      expect(summary.worklet.maxActiveVoiceCount, `${label} worklet voice pressure`).toBe(
        summary.worklet.voiceCapacity,
      );
      expect(summary.page.voicePressureBlockCount, label).toBeGreaterThan(0);
      expect(summary.worklet.voicePressureBlockCount, label).toBeGreaterThan(0);
      expect(
        summary.worklet.discontinuityRegions.voicePressureNearEvent.sampleStepCount,
        `${label} voice-pressure-near-event interval`,
      ).toBeGreaterThan(0);
    }
  }

  console.log(`scheduler-page-worklet-report ${JSON.stringify(result.summaries)}`);
});
