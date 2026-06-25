const { test, expect } = require('@playwright/test');

const PROBE_BLOCK_SIZE = 128;
const PROBE_SAMPLE_RATE = 48000;
const PROBE_INITIAL_BPM = 120;
const PROBE_INITIAL_GAIN = 0.5;
const PROBE_EPSILON = 1e-12;

// Keep in sync with SCHEDULER_PROBE_REQUIRED_EXPORTS in web/scheduler-probe-processor.js.
const REQUIRED_EXPORTS = [
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

const PROBE_CASES = [
  {
    name: 'note-triad',
    patternText: 'note("60 64 67")',
    maxBlocks: 128,
    expectParseOk: true,
    expectActiveAudio: true,
  },
  {
    name: 'drum-basic',
    patternText: 's("bd sd hh sd")',
    maxBlocks: 128,
    expectParseOk: true,
    expectActiveAudio: true,
  },
  // Current Mini notation rejects s("~"); a zero-pulse Euclid is the
  // narrow valid silent pattern for this production-path probe.
  {
    name: 'silent-zero-euclid',
    patternText: 's("bd(0,8)")',
    maxBlocks: 128,
    expectParseOk: true,
    expectActiveAudio: false,
  },
  {
    name: 'invalid-pattern',
    patternText: 'invalid!!!',
    maxBlocks: 8,
    expectParseOk: false,
    expectActiveAudio: false,
  },
];

function expectBaseHealth(summary, label) {
  expect(summary.processorErrors, label).toEqual([]);
  expect(summary.rendered.nanOrInfCount, label).toBe(0);
}

function expectParsedSummary(summary, label) {
  expect(summary.patternError, label).toBe('');
  expect(summary.patternUpdated, label).toBe(true);
  expect(summary.parseStatus, label).toBe(0);
  expect(summary.blockCount, label).toBe(summary.maxBlocks);
  expect(summary.doneBlockCount, label).toBe(summary.maxBlocks);
  expect(summary.doneAbsoluteFrameCount, label).toBe(PROBE_BLOCK_SIZE * summary.maxBlocks);
  expect(summary.sequential, label).toBe(true);
  expect(summary.totalNanOrInfCount, label).toBe(0);
  expect(summary.doneRendered?.left?.nanOrInfCount, `${label} left`).toBe(0);
  expect(summary.doneRendered?.right?.nanOrInfCount, `${label} right`).toBe(0);
}

function expectAudioActivity(summary, label) {
  if (summary.expectActiveAudio) {
    expect(summary.maxPeak, label).toBeGreaterThan(0);
    expect(summary.rendered.peak, label).toBeGreaterThan(0);
    expect(summary.rendered.nonZeroSampleCount, label).toBeGreaterThan(0);
  } else {
    expect(summary.maxPeak, label).toBe(0);
    expect(summary.rendered.peak, label).toBe(0);
    expect(summary.rendered.nonZeroSampleCount, label).toBe(0);
  }
}

function expectParseErrorSummary(summary, label) {
  expect(summary.patternUpdated, label).toBe(false);
  expect(summary.patternError.length, label).toBeGreaterThan(0);
  expect(summary.parseStatus, label).toBe(1);
  expect(summary.parseError, label).toBe(summary.patternError);
  expect(summary.blockCount, label).toBe(0);
  expect(summary.doneBlockCount, label).toBe(0);
  expect(summary.doneAbsoluteFrameCount, label).toBe(0);
  expect(summary.rendered.peak, label).toBe(0);
  expect(summary.rendered.nonZeroSampleCount, label).toBe(0);
}

test('scheduler probe: AudioWorklet pattern playback telemetry', async ({ page }) => {
  test.setTimeout(30_000);
  await page.goto('/');

  const result = await page.evaluate(async ({
    cases,
    requiredExports,
    blockSize,
    sampleRate,
    initialBpm,
    initialGain,
    epsilon,
  }) => {
    if (typeof OfflineAudioContext !== 'function' || typeof AudioWorkletNode !== 'function') {
      return { error: 'OfflineAudioContext or AudioWorkletNode unavailable' };
    }

    const response = await fetch('moonbit_dsp.wasm');
    if (!response.ok) {
      return { error: `fetch failed: ${response.status}` };
    }
    const bytes = await response.arrayBuffer();
    const wasmModule = await WebAssembly.compile(bytes);
    const exportNames = WebAssembly.Module.exports(wasmModule).map((entry) => entry.name);
    const missing = requiredExports.filter((name) => !exportNames.includes(name));
    if (missing.length > 0) {
      return { error: `missing exports: ${missing.join(', ')}`, exportNames };
    }

    const summarizeRendered = (rendered) => {
      const summary = {
        peak: 0,
        rms: 0,
        nanOrInfCount: 0,
        nonZeroSampleCount: 0,
      };
      let sumSquares = 0;
      let sampleCount = 0;
      for (let channel = 0; channel < rendered.numberOfChannels; channel += 1) {
        const data = rendered.getChannelData(channel);
        for (let index = 0; index < data.length; index += 1) {
          const sample = data[index];
          sampleCount += 1;
          if (!Number.isFinite(sample)) {
            summary.nanOrInfCount += 1;
          } else {
            const abs = Math.abs(sample);
            summary.peak = Math.max(summary.peak, abs);
            sumSquares += sample * sample;
            if (abs > epsilon) {
              summary.nonZeroSampleCount += 1;
            }
          }
        }
      }
      summary.rms = Math.sqrt(sumSquares / Math.max(1, sampleCount));
      return summary;
    };

    const summarizeBlocks = (blocks) => {
      const summary = {
        maxPeak: 0,
        totalNanOrInfCount: 0,
        maxStep: 0,
        maxBoundaryStep: 0,
        sequential: blocks.every(
          (message, index) => message.blockIndex === index &&
            message.absoluteFrameStart === index * blockSize,
        ),
      };
      for (const block of blocks) {
        for (const channel of [block.left, block.right]) {
          if (!channel) {
            continue;
          }
          summary.maxPeak = Math.max(summary.maxPeak, channel.peak);
          summary.totalNanOrInfCount += channel.nanOrInfCount;
          summary.maxStep = Math.max(summary.maxStep, channel.maxStep);
          summary.maxBoundaryStep = Math.max(summary.maxBoundaryStep, channel.boundaryStep);
        }
      }
      return summary;
    };

    const renderCase = async (probeCase) => {
      const context = new OfflineAudioContext(2, blockSize * probeCase.maxBlocks, sampleRate);
      await context.audioWorklet.addModule('scheduler-probe-processor.js');
      const messages = [];
      let resolveTerminalMessage;
      const terminalMessage = new Promise((resolve) => {
        resolveTerminalMessage = resolve;
      });
      const node = new AudioWorkletNode(context, 'moondsp-scheduler-probe', {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          patternText: probeCase.patternText,
          maxBlocks: probeCase.maxBlocks,
          initialBpm,
          initialGain,
        },
      });
      node.port.onmessage = (event) => {
        const message = event.data;
        messages.push(message);
        if (message?.type === 'done' || message?.type === 'error') {
          resolveTerminalMessage(message);
        }
      };
      node.connect(context.destination);
      const [rendered] = await Promise.all([context.startRendering(), terminalMessage]);

      const processorErrors = messages.filter((message) => message?.type === 'error');
      const blocks = messages.filter((message) => message?.type === 'block-metrics');
      const done = messages.find((message) => message?.type === 'done') || null;
      const patternError = messages.find((message) => message?.type === 'pattern-error') || null;
      const patternUpdated = messages.find((message) => message?.type === 'pattern-updated') || null;
      const blockSummary = summarizeBlocks(blocks);
      return {
        ...probeCase,
        processorErrors,
        patternError: patternError?.message || '',
        patternUpdated: Boolean(patternUpdated),
        blockCount: blocks.length,
        doneBlockCount: done?.blockCount ?? null,
        doneAbsoluteFrameCount: done?.absoluteFrameCount ?? null,
        parseStatus: done?.parseStatus ?? null,
        parseError: done?.parseError || '',
        maxDiscontinuity: done?.maxDiscontinuity || null,
        maxDiscontinuityKind: done?.maxDiscontinuityKind || 'none',
        topDiscontinuities: done?.topDiscontinuities || [],
        doneRendered: done?.rendered || null,
        rendered: summarizeRendered(rendered),
        ...blockSummary,
      };
    };

    const summaries = [];
    for (const probeCase of cases) {
      summaries.push(await renderCase(probeCase));
    }
    return { summaries };
  }, {
    cases: PROBE_CASES,
    requiredExports: REQUIRED_EXPORTS,
    blockSize: PROBE_BLOCK_SIZE,
    sampleRate: PROBE_SAMPLE_RATE,
    initialBpm: PROBE_INITIAL_BPM,
    initialGain: PROBE_INITIAL_GAIN,
    epsilon: PROBE_EPSILON,
  });

  expect(result.error, 'page-level scheduler probe error').toBeFalsy();
  for (const summary of result.summaries) {
    const label = summary.name;
    expectBaseHealth(summary, label);

    if (summary.expectParseOk) {
      expectParsedSummary(summary, label);
      expectAudioActivity(summary, label);
    } else {
      expectParseErrorSummary(summary, label);
    }
  }

  console.log(`scheduler-probe-report ${JSON.stringify(result.summaries)}`);
});
