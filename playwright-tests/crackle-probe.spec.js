const { test, expect } = require('@playwright/test');

const ROUTES = [
  { id: 0, name: 'direct_tick' },
  { id: 1, name: 'direct_process' },
  { id: 2, name: 'compiled_static_osc' },
  { id: 3, name: 'compiled_value0_osc' },
  { id: 4, name: 'compiled_static_osc_from' },
  { id: 5, name: 'compiled_value0_osc_from' },
  { id: 6, name: 'bound_voice_pool_note_binding' },
  { id: 7, name: 'bound_voice_pool_browser_synth_shape' },
];

const WAVEFORMS = [
  { id: 0, name: 'sine', routes: ROUTES },
  { id: 3, name: 'triangle', routes: ROUTES.filter((route) => route.id >= 2) },
];

test('crackle probe: browser wasm-gc oscillator route metrics', async ({ page }) => {
  await page.goto('/');
  const result = await page.evaluate(async ({ routes, waveforms }) => {
    const response = await fetch('moonbit_dsp_test.wasm');
    if (!response.ok) {
      return { error: `fetch failed: ${response.status}` };
    }
    const bytes = await response.arrayBuffer();
    const module = await WebAssembly.compile(bytes);
    const exportNames = WebAssembly.Module.exports(module).map((entry) => entry.name);
    const imports = {
      spectest: { print_char() {} },
      'moonbit:ffi': {
        make_closure(funcref, closure) {
          return funcref.bind(null, closure);
        },
      },
    };
    const instance = await WebAssembly.instantiate(module, imports);
    const required = [
      'crackle_probe_reset',
      'crackle_probe_run',
      'crackle_probe_metric',
      'crackle_probe_sample',
      'crackle_probe_last_error',
      'crackle_probe_block_count',
    ];
    const missing = required.filter((name) => typeof instance.exports[name] !== 'function');
    if (missing.length > 0) {
      return { error: `missing exports: ${missing.join(', ')}`, exportNames };
    }

    const metricIds = {
      peak: 0,
      sanitizedCount: 4,
      maxStep: 5,
      boundaryStep: 6,
      maxResidual: 7,
      rmsResidual: 8,
      boundaryStepDifference: 11,
    };
    const summarizeBlocks = (exports, blockCount) => {
      const summary = {
        maxPeak: 0,
        maxSanitizedCount: 0,
        maxStep: 0,
        maxBoundaryStep: 0,
        maxResidual: 0,
        maxRmsResidual: 0,
        maxBoundaryStepDifference: 0,
        maxResidualBlock: 0,
        maxBoundaryStepDifferenceBlock: 0,
      };
      for (let block = 0; block < blockCount; block += 1) {
        const peak = exports.crackle_probe_metric(block, metricIds.peak);
        const sanitizedCount = exports.crackle_probe_metric(block, metricIds.sanitizedCount);
        const maxStep = exports.crackle_probe_metric(block, metricIds.maxStep);
        const boundaryStep = exports.crackle_probe_metric(block, metricIds.boundaryStep);
        const maxResidual = exports.crackle_probe_metric(block, metricIds.maxResidual);
        const rmsResidual = exports.crackle_probe_metric(block, metricIds.rmsResidual);
        const boundaryStepDifference = exports.crackle_probe_metric(
          block,
          metricIds.boundaryStepDifference,
        );
        summary.maxPeak = Math.max(summary.maxPeak, peak);
        summary.maxSanitizedCount = Math.max(summary.maxSanitizedCount, sanitizedCount);
        summary.maxStep = Math.max(summary.maxStep, maxStep);
        summary.maxBoundaryStep = Math.max(summary.maxBoundaryStep, boundaryStep);
        summary.maxRmsResidual = Math.max(summary.maxRmsResidual, rmsResidual);
        if (maxResidual > summary.maxResidual) {
          summary.maxResidual = maxResidual;
          summary.maxResidualBlock = block;
        }
        if (boundaryStepDifference > summary.maxBoundaryStepDifference) {
          summary.maxBoundaryStepDifference = boundaryStepDifference;
          summary.maxBoundaryStepDifferenceBlock = block;
        }
      }
      return summary;
    };

    const summaries = [];
    for (const waveform of waveforms) {
      for (const route of waveform.routes) {
        instance.exports.crackle_probe_reset();
        const ok = instance.exports.crackle_probe_run(
          route.id,
          waveform.id,
          440.0,
          48000.0,
          128,
          512,
        );
        const lastError = instance.exports.crackle_probe_last_error();
        const blockCount = instance.exports.crackle_probe_block_count();
        summaries.push({
          waveform: waveform.name,
          route: route.name,
          routeId: route.id,
          ok,
          lastError,
          blockCount,
          ...summarizeBlocks(instance.exports, blockCount),
          lastOutput0: instance.exports.crackle_probe_sample(0, 0),
          lastReference0: instance.exports.crackle_probe_sample(1, 0),
          lastResidual0: instance.exports.crackle_probe_sample(2, 0),
        });
      }
    }

    return { summaries };
  }, { routes: ROUTES, waveforms: WAVEFORMS });

  expect(result.error, result.error || '').toBeFalsy();
  expect(result.summaries.every((summary) => summary.ok)).toBe(true);

  for (const summary of result.summaries) {
    expect(summary.maxPeak, `${summary.route} maxPeak`).toBeGreaterThan(0);
    expect(summary.maxSanitizedCount, `${summary.route} sanitized`).toBe(0);
    if (summary.routeId <= 6) {
      expect(summary.maxResidual, `${summary.route} maxResidual`).toBeLessThan(1e-9);
      expect(summary.maxBoundaryStepDifference, `${summary.route} boundary delta`).toBeLessThan(1e-9);
    }
  }

  console.log(`crackle-probe-report ${JSON.stringify(result.summaries)}`);
});

const STREAM_CASES = [
  ...ROUTES.map((route) => ({
    routeId: route.id,
    route: route.name,
    waveformId: 0,
    waveform: 'sine',
  })),
  {
    routeId: 7,
    route: 'bound_voice_pool_browser_synth_shape',
    waveformId: 3,
    waveform: 'triangle',
  },
];

test('crackle probe: AudioWorklet streaming oscillator route metrics', async ({ page }) => {
  test.setTimeout(30_000);
  await page.goto('/');
  const result = await page.evaluate(async ({ cases }) => {
    if (typeof OfflineAudioContext !== 'function' || typeof AudioWorkletNode !== 'function') {
      return { error: 'OfflineAudioContext or AudioWorkletNode unavailable' };
    }

    const response = await fetch('moonbit_dsp_test.wasm');
    if (!response.ok) {
      return { error: `fetch failed: ${response.status}` };
    }
    const bytes = await response.arrayBuffer();
    const wasmModule = await WebAssembly.compile(bytes);
    const exportNames = WebAssembly.Module.exports(wasmModule).map((entry) => entry.name);
    const required = [
      'crackle_probe_stream_init',
      'crackle_probe_stream_process',
      'crackle_probe_metric',
      'crackle_probe_sample',
      'crackle_probe_last_error',
      'crackle_probe_block_count',
    ];
    const missing = required.filter((name) => !exportNames.includes(name));
    if (missing.length > 0) {
      return { error: `missing exports: ${missing.join(', ')}`, exportNames };
    }

    const renderCase = async (config) => {
      const blockSize = 128;
      const blockCount = 512;
      const sampleRate = 48000;
      const context = new OfflineAudioContext(2, blockSize * blockCount, sampleRate);
      await context.audioWorklet.addModule('crackle-probe-processor.js');
      const messages = [];
      const node = new AudioWorkletNode(context, 'moondsp-crackle-probe', {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: {
          wasmModule,
          routeId: config.routeId,
          waveformId: config.waveformId,
          freqHz: 440,
          blockCount,
        },
      });
      node.port.onmessage = (event) => {
        messages.push(event.data);
      };
      node.connect(context.destination);
      const rendered = await context.startRendering();
      await new Promise((resolve) => setTimeout(resolve, 0));

      const error = messages.find((message) => message?.type === 'error');
      const blocks = messages.filter((message) => message?.type === 'block-metrics');
      const done = messages.find((message) => message?.type === 'done');
      const summary = {
        ...config,
        blockCount: blocks.length,
        doneBlockCount: done?.blockCount || 0,
        doneWasmBlockCount: done?.wasmBlockCount || 0,
        sequential: blocks.every(
          (message, index) => message.blockIndex === index && message.wasmBlockIndex === index,
        ),
        lastError: error?.message || '',
        maxLastErrorCode: 0,
        maxPeak: 0,
        maxNanOrInfCount: 0,
        maxSanitizedCount: 0,
        maxStep: 0,
        maxBoundaryStep: 0,
        maxResidual: 0,
        maxRmsResidual: 0,
        maxBoundaryStepDifference: 0,
        maxResidualBlock: 0,
        maxBoundaryStepDifferenceBlock: 0,
        renderedPeak: 0,
        renderedNanOrInfCount: 0,
      };
      for (const block of blocks) {
        const metrics = block.metrics;
        summary.maxLastErrorCode = Math.max(summary.maxLastErrorCode, block.lastError || 0);
        summary.maxPeak = Math.max(summary.maxPeak, metrics.peak);
        summary.maxNanOrInfCount = Math.max(summary.maxNanOrInfCount, metrics.nanOrInfCount);
        summary.maxSanitizedCount = Math.max(summary.maxSanitizedCount, metrics.sanitizedCount);
        summary.maxStep = Math.max(summary.maxStep, metrics.maxStep);
        summary.maxBoundaryStep = Math.max(summary.maxBoundaryStep, metrics.boundaryStep);
        summary.maxRmsResidual = Math.max(summary.maxRmsResidual, metrics.rmsResidual);
        if (metrics.maxResidual > summary.maxResidual) {
          summary.maxResidual = metrics.maxResidual;
          summary.maxResidualBlock = block.blockIndex;
        }
        if (metrics.boundaryStepDifference > summary.maxBoundaryStepDifference) {
          summary.maxBoundaryStepDifference = metrics.boundaryStepDifference;
          summary.maxBoundaryStepDifferenceBlock = block.blockIndex;
        }
      }
      const left = rendered.getChannelData(0);
      for (let index = 0; index < left.length; index += 1) {
        const sample = left[index];
        if (!Number.isFinite(sample)) {
          summary.renderedNanOrInfCount += 1;
        } else {
          summary.renderedPeak = Math.max(summary.renderedPeak, Math.abs(sample));
        }
      }
      return summary;
    };

    const summaries = [];
    for (const probeCase of cases) {
      summaries.push(await renderCase(probeCase));
    }
    return { summaries };
  }, { cases: STREAM_CASES });

  expect(result.error, result.error || '').toBeFalsy();
  for (const summary of result.summaries) {
    const label = `${summary.waveform}/${summary.route}`;
    expect(summary.lastError, label).toBe('');
    expect(summary.blockCount, label).toBe(512);
    expect(summary.doneBlockCount, label).toBe(512);
    expect(summary.doneWasmBlockCount, label).toBe(512);
    expect(summary.sequential, label).toBe(true);
    expect(summary.renderedPeak, label).toBeGreaterThan(0.001);
    expect(summary.renderedNanOrInfCount, label).toBe(0);
    expect(summary.maxPeak, label).toBeGreaterThan(0.001);
    expect(summary.maxLastErrorCode, label).toBe(0);
    expect(summary.maxNanOrInfCount, label).toBe(0);
    expect(summary.maxSanitizedCount, label).toBe(0);
    expect(summary.maxStep, label).toBeLessThan(0.25);
    expect(summary.maxBoundaryStep, label).toBeLessThan(0.25);
    if (summary.routeId <= 6) {
      expect(summary.maxResidual, `${label} maxResidual`).toBeLessThan(1e-9);
      expect(summary.maxBoundaryStepDifference, `${label} boundary delta`).toBeLessThan(1e-9);
    }
  }

  console.log(`crackle-stream-probe-report ${JSON.stringify(result.summaries)}`);
});
