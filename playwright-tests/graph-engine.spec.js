const { test, expect } = require('@playwright/test');

test.use({ launchOptions: { args: ['--disable-audio-output'] } });

// These tests use the public engine, not WASM exports or worklet messages.
// OfflineAudioContext is the browser's real AudioWorklet render path and lets
// us compare every PCM frame without device timing or listening judgments.
test.beforeEach(async ({ page }) => { await page.goto('/graph-example.html'); });

test('external graph produces the requested oscillator and chained gains', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 4096, 48000);
    const engine = await GraphEngine({ context });
    const source = await engine.mount({ nodes: [
      { type: 'oscillator', waveform: 'sine', frequency: 375 },
      { type: 'gain', input: 0, gain: 0.4 },
      { type: 'gain', input: 1, gain: 0.5 },
      { type: 'output', input: 2 },
    ] });
    engine.output.connect(context.destination);
    await source.play();
    const buffer = await context.startRendering();
    let residual = 0;
    for (let i = 0; i < buffer.length; i++) {
      residual = Math.max(residual, Math.abs(buffer.getChannelData(0)[i] - 0.2 * Math.sin(2 * Math.PI * i / 128)));
    }
    await engine.close();
    return residual;
  });
  expect(result).toBeLessThan(1e-6);
});

test('invalid graphs return reasons without damaging a mounted graph', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 1024, 48000);
    const engine = await GraphEngine({ context });
    const source = await engine.mount({ nodes: [
      { type: 'oscillator', waveform: 'square', frequency: 750 },
      { type: 'gain', input: 0, gain: 0.125 },
      { type: 'output', input: 1 },
    ] });
    const errors = [];
    for (const graph of [
      { nodes: [{ type: 'gain', input: 9, gain: 0.2 }, { type: 'output', input: 0 }] },
      { nodes: [{ type: 'oscillator', waveform: 'unknown', frequency: 440 }] },
      { nodes: [{ type: 'oscillator', waveform: 'sine', frequency: NaN }] },
      { nodes: [{ type: 'oscillator', waveform: 'sine', frequency: 440 }] },
      { nodes: [{ type: 'oscillator', waveform: 'sine', frequency: 440 }, { type: 'output', input: 0 }, { type: 'output', input: 0 }] },
    ]) {
      try { await engine.mount(graph); errors.push(null); }
      catch (error) { errors.push({ code: error.code, nodeIndex: error.nodeIndex }); }
    }
    engine.output.connect(context.destination);
    await source.play();
    const buffer = await context.startRendering();
    let residual = 0;
    for (let i = 0; i < buffer.length; i++) {
      residual = Math.max(residual, Math.abs(buffer.getChannelData(0)[i] - ((i % 64) < 32 ? 0.125 : -0.125)));
    }
    await engine.close();
    return { errors, residual };
  });
  for (const error of result.errors) {
    expect(error).toMatchObject({ code: 'INVALID_GRAPH' });
  }
  expect(result.errors[0].nodeIndex).toBe(0);
  expect(result.residual).toBeLessThan(1e-6);
});

test('external controls apply atomically and gate release keeps the graph playable', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 4096, 48000);
    const engine = await GraphEngine({ context });
    const source = await engine.mount({ nodes: [
      { type: 'oscillator', waveform: 'sine', frequency: 440 },
      { type: 'biquad', input: 0, mode: 'lowpass', cutoff: 2000, q: 0.7 },
      { type: 'adsr', attackMs: 0, decayMs: 0, sustain: 1, releaseMs: 1 },
      { type: 'mul', input0: 1, input1: 2 },
      { type: 'gain', input: 3, gain: 0.2 },
      { type: 'output', input: 4 },
    ] });
    let rejected;
    try {
      await source.applyControls([
        { type: 'setParam', node: 4, slot: 'value0', value: 0.4 },
        { type: 'setParam', node: 4, slot: 'delaySamples', value: 1 },
      ]);
    } catch (error) {
      rejected = { code: error.code, nodeIndex: error.nodeIndex };
    }
    let decodedRejection;
    try {
      await source.applyControls([
        { type: 'setParam', node: 0, slot: 'value0', value: 880 },
        { type: 'setParam', node: 4, slot: 'unknown', value: 0.4 },
      ]);
    } catch (error) {
      decodedRejection = { code: error.code, nodeIndex: error.nodeIndex };
    }
    await source.applyControls([{ type: 'gateOn', node: 2 }]);
    engine.output.connect(context.destination);
    await source.play();
    const suspended = context.suspend(2048 / 48000);
    const rendering = context.startRendering();
    await suspended;
    await source.applyControls([{ type: 'gateOff', node: 2 }]);
    await context.resume();
    const buffer = await rendering;
    let beforeReleasePeak = 0;
    let afterReleasePeak = 0;
    for (let i = 0; i < buffer.length; i++) {
      const sample = Math.abs(buffer.getChannelData(0)[i]);
      if (i < 2048) beforeReleasePeak = Math.max(beforeReleasePeak, sample);
      if (i >= 3072) afterReleasePeak = Math.max(afterReleasePeak, sample);
    }
    await engine.close();
    return { rejected, decodedRejection, beforeReleasePeak, afterReleasePeak };
  });
  expect(result.rejected.code).toBe('INVALID_CONTROL');
  expect(result.rejected.nodeIndex).toBe(4);
  expect(result.decodedRejection).toEqual({ code: 'INVALID_CONTROL', nodeIndex: 4 });
  // The rejected batch did not partially change the gain from 0.2 to 0.4.
  expect(result.beforeReleasePeak).toBeGreaterThan(0.08);
  expect(result.beforeReleasePeak).toBeLessThan(0.3);
  expect(result.afterReleasePeak).toBeLessThan(0.03);
});

test('controls reject after unmount and engine close without reviving a graph', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 128, 48000);
    const engine = await GraphEngine({ context });
    const graph = { nodes: [
      { type: 'oscillator', waveform: 'triangle', frequency: 440 },
      { type: 'output', input: 0 },
    ] };
    const retired = await engine.mount(graph);
    await retired.unmount();
    let afterUnmount;
    try {
      await retired.applyControls([{ type: 'gateOn', node: 0 }]);
    } catch (error) {
      afterUnmount = error.code;
    }
    const replacement = await engine.mount(graph);
    await replacement.play();
    const closing = engine.close();
    let afterClose;
    try {
      await replacement.applyControls([{ type: 'setParam', node: 0, slot: 'value0', value: 1 }]);
    } catch (error) {
      afterClose = error.code;
    }
    await closing;
    return { afterUnmount, afterClose };
  });
  expect(result).toEqual({ afterUnmount: 'INVALID_HANDLE', afterClose: 'ENGINE_CLOSED' });
});

test('unmounting one playing graph preserves the other graph and its phase', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 4096, 48000);
    const engine = await GraphEngine({ context });
    const patch = (frequency, gain) => ({ nodes: [
      { type: 'oscillator', waveform: 'sine', frequency },
      { type: 'gain', input: 0, gain },
      { type: 'output', input: 1 },
    ] });
    const first = await engine.mount(patch(375, 0.2));
    const second = await engine.mount(patch(562.5, 0.1));
    engine.output.connect(context.destination);
    await first.play();
    await second.play();
    const suspended = context.suspend(2048 / 48000);
    const rendering = context.startRendering();
    await suspended;
    const unmounting = first.unmount();
    const duringUnmount = await Promise.allSettled([first.play(), first.pause()]);
    await Promise.all([unmounting, first.unmount()]);
    await first.unmount();
    let staleError;
    try { await first.play(); } catch (error) { staleError = error.code; }
    let mountError;
    try { await engine.mount(patch(440, 0.1)); } catch (error) { mountError = error.code; }
    await context.resume();
    const buffer = await rendering;
    let residual = 0;
    for (let i = 0; i < buffer.length; i++) {
      const expected = 0.1 * Math.sin(2 * Math.PI * 562.5 * i / 48000) +
        (i < 2048 ? 0.2 * Math.sin(2 * Math.PI * 375 * i / 48000) : 0);
      residual = Math.max(residual, Math.abs(buffer.getChannelData(0)[i] - expected));
    }
    await engine.close();
    return { residual, staleError, mountError,
      duringUnmount: duringUnmount.map(result => result.reason?.code) };
  });
  expect(result.residual).toBeLessThan(1e-6);
  expect(result.staleError).toBe('INVALID_HANDLE');
  expect(result.mountError).toBe('MOUNT_CLOSED');
  expect(result.duringUnmount).toEqual(['INVALID_HANDLE', 'INVALID_HANDLE']);
});

test('unmounted handles cannot control a replacement graph in a reused slot', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 1024, 48000);
    const engine = await GraphEngine({ context });
    const patch = { nodes: [
      { type: 'oscillator', waveform: 'triangle', frequency: 375 },
      { type: 'gain', input: 0, gain: 0.2 },
      { type: 'output', input: 1 },
    ] };
    const retired = await engine.mount(patch);
    await Promise.all([retired.unmount(), retired.unmount()]);
    const replacement = await engine.mount(patch);
    await retired.unmount();
    const errors = [];
    for (const operation of ['play', 'pause']) {
      try { await retired[operation](); errors.push(null); }
      catch (error) { errors.push(error.code); }
    }
    // Rejected playback must not close mount admission.
    const afterRejection = await engine.mount(patch);
    await afterRejection.unmount();
    engine.output.connect(context.destination);
    await replacement.play();
    const buffer = await context.startRendering();
    let residual = 0;
    for (let i = 0; i < buffer.length; i++) {
      const phase = (i % 128) / 128;
      const expected = 0.2 * (phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase);
      residual = Math.max(residual, Math.abs(buffer.getChannelData(0)[i] - expected));
    }
    await engine.close();
    return { errors, residual };
  });
  expect(result.errors).toEqual(['INVALID_HANDLE', 'INVALID_HANDLE']);
  expect(result.residual).toBeLessThan(1e-6);
});

test('external page mounts, plays, pauses and unmounts through public controls', async ({ page }) => {
  await page.getByRole('button', { name: 'Mount graph', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Play', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Play', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Pause', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Play', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Unmount', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Mount graph', exact: true })).toBeEnabled();
  await expect(page.getByRole('textbox', { name: 'Graph description' })).toBeEnabled();
  const ownership = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new AudioContext();
    await context.suspend();
    const engine = await GraphEngine({ context });
    await engine.close();
    const state = context.state;
    await context.close();
    return state;
  });
  expect(ownership).toBe('suspended');
});

test('example releases a failed engine and allows mounting again', async ({ page }) => {
  await page.evaluate(() => {
    const NativeNode = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) {
        super(...args);
        window.failedExampleNode = this;
        window.failedExampleContext = args[0];
        window.AudioWorkletNode = NativeNode;
      }
    };
  });
  await page.getByRole('button', { name: 'Mount graph', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Unmount', exact: true })).toBeEnabled();
  // Invoke the browser failure callback while retaining a real context and node.
  await page.evaluate(() => failedExampleNode.onprocessorerror(new Event('processorerror')));
  await page.getByRole('button', { name: 'Unmount', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Mount graph', exact: true })).toBeEnabled();
  await expect(page.getByRole('textbox', { name: 'Graph description' })).toBeEnabled();
  expect(await page.evaluate(() => failedExampleContext.state)).toBe('closed');
  await expect(page.locator('#status')).toContainText('PROCESSOR_FAILED');

  await page.getByRole('button', { name: 'Mount graph', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Play', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Play', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Pause', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Unmount', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Mount graph', exact: true })).toBeEnabled();
});

test('concurrent engine close shares completion and closes admission immediately', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 128, 48000);
    const engine = await GraphEngine({ context });
    const graph = { nodes: [
      { type: 'oscillator', waveform: 'sine', frequency: 440 },
      { type: 'gain', input: 0, gain: 0.1 },
      { type: 'output', input: 1 },
    ] };
    const source = await engine.mount(graph);
    const firstClose = engine.close();
    const secondClose = engine.close();
    // Probe admission before yielding to any close acknowledgement.
    const duringClose = Promise.allSettled([source.play(), engine.mount(graph)]);
    const closed = await Promise.allSettled([firstClose, secondClose]);
    const during = await duringClose;
    await engine.close();
    const after = await Promise.allSettled([source.pause(), source.unmount()]);
    const summarize = outcomes => outcomes.map(outcome =>
      outcome.status === 'fulfilled' ? 'fulfilled' : outcome.reason.code);
    return { closed: summarize(closed), during: summarize(during),
      after: summarize(after), contextState: context.state };
  });
  expect(result.closed).toEqual(['fulfilled', 'fulfilled']);
  expect(result.during).toEqual(['ENGINE_CLOSED', 'ENGINE_CLOSED']);
  expect(result.after).toEqual(['ENGINE_CLOSED', 'ENGINE_CLOSED']);
  expect(result.contextState).toBe('suspended');
});

test('closed engine takes precedence over playback admission and closed context', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new AudioContext();
    await context.suspend();
    const engine = await GraphEngine({ context });
    const graph = { nodes: [
      { type: 'oscillator', waveform: 'sine', frequency: 440 },
      { type: 'output', input: 0 },
    ] };
    const sound = await engine.mount(graph);
    await sound.play();
    const closing = engine.close();
    const pendingMount = engine.mount(graph).catch(error => error.code);
    await closing;
    await context.close();
    const operations = await Promise.allSettled([engine.mount(graph), sound.play(), sound.pause(), sound.unmount()]);
    return [await pendingMount, ...operations.map(result => result.reason?.code)];
  });
  expect(result).toEqual(Array(5).fill('ENGINE_CLOSED'));
});

test('native initialization failures expose structured errors with original causes', async ({ page }) => {
  await page.route('**/broken.wasm', route => route.fulfill({ body: 'not wasm' }));
  await page.route('**/unreachable.wasm', route => route.abort('failed'));
  await page.route('**/broken-processor.js', route => route.fulfill({
    contentType: 'text/javascript', body: 'throw new Error("processor initialization rejected");',
  }));
  const result = await page.evaluate(async () => {
    const { GraphEngine, GraphEngineError } = await import('/graph-engine.js')
    const errors = [];
    for (const options of [
      { wasmUrl: '/broken.wasm' },
      { wasmUrl: '/unreachable.wasm' },
      { processorUrl: '/broken-processor.js' },
    ]) {
      const context = new AudioContext();
      await context.suspend();
      try { await GraphEngine({ context, ...options }); errors.push(null); }
      catch (error) {
        errors.push({ structured: error instanceof GraphEngineError, code: error.code,
          hasCause: error.cause instanceof Error, state: context.state });
      } finally { await context.close(); }
    }
    return errors;
  });
  expect(result).toEqual(Array(3).fill({
    structured: true, code: 'INITIALIZATION_FAILED', hasCause: true, state: 'suspended',
  }));
});

test('pause freezes phase while another graph continues rendering', async ({ page }) => {
  const residual = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 4096, 48000);
    const engine = await GraphEngine({ context });
    const patch = frequency => ({ nodes: [
      { type: 'oscillator', waveform: 'sine', frequency },
      { type: 'gain', input: 0, gain: 0.1 },
      { type: 'output', input: 1 },
    ] });
    const sound = await engine.mount(patch(437));
    const other = await engine.mount(patch(613));
    engine.output.connect(context.destination);
    await sound.play();
    await other.play();
    const pauseAt = context.suspend(1024 / 48000);
    const resumeAt = context.suspend(2048 / 48000);
    const rendering = context.startRendering();
    await pauseAt;
    await sound.pause();
    await context.resume();
    await resumeAt;
    await sound.play();
    await context.resume();
    const buffer = await rendering;
    let error = 0;
    for (let i = 0; i < buffer.length; i++) {
      const soundFrame = i < 1024 ? i : i - 1024;
      const expected = 0.1 * Math.sin(2 * Math.PI * 613 * i / 48000) +
        (i >= 1024 && i < 2048 ? 0 : 0.1 * Math.sin(2 * Math.PI * 437 * soundFrame / 48000));
      error = Math.max(error, Math.abs(buffer.getChannelData(0)[i] - expected));
    }
    await engine.close();
    return error;
  });
  expect(residual).toBeLessThan(1e-6);
});

test('creation aborts before starting and while fetching without closing the context', async ({ page }) => {
  let requestStarted;
  const started = new Promise(resolve => { requestStarted = resolve; });
  await page.route('**/held.wasm', () => { requestStarted(); });
  await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    window.cancelContext = new AudioContext();
    await cancelContext.suspend();
    window.cancelController = new AbortController();
    window.cancelOutcome = null;
    window.cancelCreation = GraphEngine({
      context: cancelContext, signal: cancelController.signal, wasmUrl: '/held.wasm',
    }).then(engine => { window.cancelOutcome = 'unexpected success'; return engine.close(); },
      error => { window.cancelOutcome = { code: error.code, cause: error.cause }; });
  });
  await started;
  await page.evaluate(() => cancelController.abort('navigation'));
  await expect.poll(() => page.evaluate(() => cancelOutcome)).toEqual({ code: 'ABORTED', cause: 'navigation' });
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const errors = await Promise.allSettled([
      GraphEngine({ context: cancelContext, signal: cancelController.signal }),
    ]);
    const engine = await GraphEngine({ context: cancelContext });
    await engine.close();
    const state = cancelContext.state;
    await cancelContext.close();
    return { code: errors[0].reason?.code, state };
  });
  expect(result).toEqual({ code: 'ABORTED', state: 'suspended' });
});

test('aborting ready wait retires the worklet and ignores late readiness', async ({ page }) => {
  // A real worklet withholding ready exercises cancellation after node creation.
  const processorSource = `registerProcessor('moondsp-graph', class extends AudioWorkletProcessor {
      constructor() {
        super();
        this.port.onmessage = ({data}) => {
          if (data.type === 'close') {
            this.stopped = true;
            this.port.postMessage({type:'ready'});
          }
        };
        this.port.postMessage({type:'test-created'});
      }
      process() { return !this.stopped; }
    });`;
  await page.evaluate(async processorSource => {
    const { GraphEngine } = await import('/graph-engine.js')
    window.readyContext = new AudioContext();
    await readyContext.suspend();
    window.readyController = new AbortController();
    window.readyOutcome = null;
    window.readyCreated = false;
    const NativeNode = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) {
        super(...args);
        this.port.addEventListener('message', ({ data }) => {
          if (data.type === 'test-created') window.readyCreated = true;
        });
        window.AudioWorkletNode = NativeNode;
      }
    };
    const processorUrl = URL.createObjectURL(new Blob([processorSource], { type: 'text/javascript' }));
    GraphEngine({ context: readyContext, processorUrl,
      signal: readyController.signal }).then(
      engine => { window.readyOutcome = 'unexpected success'; return engine.close(); },
      error => { window.readyOutcome = error.code; }).finally(() => URL.revokeObjectURL(processorUrl));
  }, processorSource);
  await expect.poll(() => page.evaluate(() => readyCreated)).toBe(true);
  await page.evaluate(() => readyController.abort());
  await expect.poll(() => page.evaluate(() => readyOutcome)).toBe('ABORTED');
  expect(await page.evaluate(() => ({ outcome: readyOutcome, state: readyContext.state })))
    .toEqual({ outcome: 'ABORTED', state: 'suspended' });
  await page.evaluate(() => readyContext.close());
});

test('context closure settles commands whose worklet never replies', async ({ page }) => {
  // Fault injection: the worklet can start, but never acknowledges commands.
  const processorSource = `registerProcessor('moondsp-graph', class extends AudioWorkletProcessor {
      constructor() {
        super();
        this.port.onmessage = () => {};
        this.port.postMessage({type:'ready'});
      }
      process() { return true; }
    });`;
  await page.evaluate(async processorSource => {
    const { GraphEngine } = await import('/graph-engine.js')
    window.shutdownContext = new AudioContext();
    await shutdownContext.suspend();
    const processorUrl = URL.createObjectURL(new Blob([processorSource], { type: 'text/javascript' }));
    window.shutdownEngine = await GraphEngine({
      context: shutdownContext, processorUrl,
    });
    URL.revokeObjectURL(processorUrl);
    const mounting = shutdownEngine.mount({ nodes: [
      { type: 'oscillator', waveform: 'sine', frequency: 440 }, { type: 'output', input: 0 },
    ] });
    const closing = shutdownEngine.close();
    window.shutdownOutcome = null;
    Promise.allSettled([mounting, closing]).then(results => {
      window.shutdownOutcome = results.map(result => result.status === 'fulfilled' ? 'closed' : result.reason.code);
    });
    await shutdownContext.close();
  }, processorSource);
  await expect.poll(() => page.evaluate(() => shutdownOutcome)).toEqual(['ENGINE_CLOSED', 'closed']);
  expect(await page.evaluate(async () => {
    await shutdownEngine.close();
    return shutdownContext.state;
  })).toBe('closed');
});

test('abort signal stops owning the engine after successful creation', async ({ page }) => {
  const peak = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    const context = new OfflineAudioContext(1, 256, 48000);
    const controller = new AbortController();
    const engine = await GraphEngine({ context, signal: controller.signal });
    controller.abort();
    const sound = await engine.mount({ nodes: [
      { type: 'oscillator', waveform: 'square', frequency: 440 },
      { type: 'gain', input: 0, gain: 0.1 }, { type: 'output', input: 1 },
    ] });
    engine.output.connect(context.destination);
    await sound.play();
    const buffer = await context.startRendering();
    await engine.close();
    return Math.max(...buffer.getChannelData(0));
  });
  expect(peak).toBeCloseTo(0.1, 6);
});

test('closing the context interrupts creation while the download is pending', async ({ page }) => {
  let requestStarted;
  const started = new Promise(resolve => { requestStarted = resolve; });
  await page.route('**/closing-download.wasm', () => { requestStarted(); });
  await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    window.downloadContext = new AudioContext();
    await downloadContext.suspend();
    window.downloadOutcome = null;
    GraphEngine({ context: downloadContext, wasmUrl: '/closing-download.wasm' }).then(
      engine => { window.downloadOutcome = 'unexpected success'; return engine.close(); },
      error => { window.downloadOutcome = error.code; });
  });
  await started;
  await page.evaluate(() => downloadContext.close());
  await expect.poll(() => page.evaluate(() => downloadOutcome)).toBe('ENGINE_CLOSED');
});

test('late module loading cannot allocate a node after creation is aborted', async ({ page }) => {
  await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    window.moduleContext = new AudioContext();
    await moduleContext.suspend();
    window.moduleController = new AbortController();
    window.moduleOutcome = null;
    window.moduleLoaded = false;
    window.allocatedNodes = 0;
    const NativeNode = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) { super(...args); window.allocatedNodes++; }
    };
    const addModule = moduleContext.audioWorklet.addModule.bind(moduleContext.audioWorklet);
    moduleContext.audioWorklet.addModule = async (...args) => {
      await addModule(...args);
      // Hold the real loading result, rather than replacing module execution.
      await new Promise(resolve => { window.releaseModule = resolve; window.moduleLoaded = true; });
    };
    window.restoreModuleHost = () => {
      window.AudioWorkletNode = NativeNode;
      moduleContext.audioWorklet.addModule = addModule;
    };
    GraphEngine({ context: moduleContext, signal: moduleController.signal }).then(
      engine => { window.moduleOutcome = 'unexpected success'; return engine.close(); },
      error => { window.moduleOutcome = error.code; });
  });
  await expect.poll(() => page.evaluate(() => moduleLoaded)).toBe(true);
  await page.evaluate(() => moduleController.abort());
  await expect.poll(() => page.evaluate(() => moduleOutcome)).toBe('ABORTED');
  await page.evaluate(() => releaseModule());
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js')
    restoreModuleHost();
    const engine = await GraphEngine({ context: moduleContext });
    await engine.close();
    const result = { abandonedNodes: allocatedNodes, outcome: moduleOutcome, state: moduleContext.state };
    await moduleContext.close();
    return result;
  });
  expect(result).toEqual({ abandonedNodes: 0, outcome: 'ABORTED', state: 'suspended' });
});

test('wait retains processor failure and independently cancels waiters', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new AudioContext();
    await context.suspend();
    let worklet;
    const NativeNode = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) { super(...args); worklet = this; window.AudioWorkletNode = NativeNode; }
    };
    const engine = await GraphEngine({ context });
    const controller = new AbortController();
    const cancelled = engine.wait({ signal: controller.signal }).then(() => 'wrong', error => error.name);
    const survivor = engine.wait();
    controller.abort('not the engine');
    worklet.onprocessorerror(new Event('processorerror'));
    const exit = await survivor;
    const late = await engine.wait();
    await engine.close();
    await context.close();
    return { exit: { type: exit.type, code: exit.error.code }, late: { type: late.type, code: late.error.code }, cancelled: await cancelled };
  });
  expect(result).toEqual({ exit: { type: 'failed', code: 'PROCESSOR_FAILED' }, late: { type: 'failed', code: 'PROCESSOR_FAILED' }, cancelled: 'AbortError' });
});

test('pre-aborted wait rejects without changing engine lifetime', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new OfflineAudioContext(1, 32, 48000);
    const engine = await GraphEngine({ context });
    const controller = new AbortController();
    controller.abort('already gone');
    const outcome = await engine.wait({ signal: controller.signal }).then(() => 'wrong', error => ({ name: error.name, cause: error.cause }));
    await engine.close();
    return { outcome, state: context.state, exit: await engine.wait() };
  });
  expect(result).toEqual({ outcome: { name: 'AbortError', cause: 'already gone' }, state: 'suspended', exit: { type: 'closed' } });
});

test.describe('named parameters', () => {
  test.beforeEach(async ({ page }) => {
    await page.evaluate(async () => {
      const { GraphEngine } = await import('/graph-engine.js');
      const context = new OfflineAudioContext(1, 256, 48000);
      const engine = await GraphEngine({ context });
      engine.output.connect(context.destination);
      window.namedParameters = {
        engine,
        context,
        graph: {
          params: { level: 0.5, pitch: 375 },
          nodes: [
            { type: 'oscillator', waveform: 'square', frequency: { param: 'pitch' } },
            { type: 'gain', input: 0, gain: { param: 'level' } },
            { type: 'gain', input: 1, gain: { param: 'level' } },
            { type: 'output', input: 2 },
          ],
        },
        async render(sound) {
          await sound.play();
          const buffer = await context.startRendering();
          // Observe one full period after the first quantum's envelope transitions.
          return Array.from(buffer.getChannelData(0).slice(128));
        },
      };
    });
  });

  test.afterEach(async ({ page }) => {
    await page.evaluate(() => window.namedParameters?.engine.close());
  });

  function expectSquareWave(samples, level) {
    // A 375 Hz square at 48 kHz has 64 positive and 64 negative samples.
    // Binary-fraction gains let us compare the actual PCM exactly.
    for (let i = 0; i < 128; i++) {
      expect(samples[i], `PCM sample ${i}`).toBe(i < 64 ? level : -level);
    }
  }

  test('one update reaches every reference during playback', async ({ page }) => {
    const samples = await page.evaluate(async () => {
      const { engine, context, graph, render } = window.namedParameters;
      const sound = await engine.mount(graph);
      const boundary = context.suspend(128 / context.sampleRate);
      const output = render(sound);
      await boundary;
      await sound.setParams({ level: 0.25 });
      await context.resume();
      return output;
    });
    expectSquareWave(samples, 0.25 * 0.25);
  });

  test('updating one mount leaves another mount unchanged', async ({ page }) => {
    const samples = await page.evaluate(async () => {
      const { engine, graph, render } = window.namedParameters;
      const changed = await engine.mount(graph);
      const untouched = await engine.mount(graph);
      await changed.setParams({ level: 0.25 });
      return render(untouched);
    });
    expectSquareWave(samples, 0.5 * 0.5);
  });

  test('later caller mutations cannot change a submitted update', async ({ page }) => {
    const samples = await page.evaluate(async () => {
      const { engine, graph, render } = window.namedParameters;
      const sound = await engine.mount(graph);
      await sound.play();
      await sound.pause();
      const values = { level: 0.25 };
      const submitted = sound.setParams(values);
      values.level = 0.75;
      await submitted;
      return render(sound);
    });
    expectSquareWave(samples, 0.25 * 0.25);
  });

  test('named updates overwrite raw edits to their targets', async ({ page }) => {
    const samples = await page.evaluate(async () => {
      const { engine, graph, render } = window.namedParameters;
      const sound = await engine.mount(graph);
      await sound.applyControls([{ type: 'setParam', node: 1, slot: 'value0', value: 0.75 }]);
      await sound.setParams({ level: 0.25 });
      return render(sound);
    });
    expectSquareWave(samples, 0.25 * 0.25);
  });

  test('empty updates preserve the sound', async ({ page }) => {
    const samples = await page.evaluate(async () => {
      const { engine, graph, render } = window.namedParameters;
      const sound = await engine.mount(graph);
      await sound.setParams({});
      return render(sound);
    });
    expectSquareWave(samples, 0.5 * 0.5);
  });

  for (const [reason, values] of [
    ['unknown names', { level: 0.25, unknown: 1 }],
    ['undefined values that JSON would silently omit', { level: undefined }],
  ]) {
    test(`rejects ${reason} without changing the sound`, async ({ page }) => {
      const result = await page.evaluate(async values => {
        const { engine, graph, render } = window.namedParameters;
        const sound = await engine.mount(graph);
        const code = await sound.setParams(values).then(() => null, error => error.code);
        return { code, samples: await render(sound) };
      }, values);
      expect(result.code).toBe('INVALID_CONTROL');
      expectSquareWave(result.samples, 0.5 * 0.5);
    });
  }

  test('one target rejecting a value leaves every target unchanged', async ({ page }) => {
    const result = await page.evaluate(async () => {
      const { engine, render } = window.namedParameters;
      const sound = await engine.mount({
        params: { shared: 0.5 },
        nodes: [
          { type: 'oscillator', waveform: 'square', frequency: 375 },
          { type: 'gain', input: 0, gain: { param: 'shared' } },
          { type: 'adsr', attackMs: 0, decayMs: 0, sustain: { param: 'shared' }, releaseMs: 0 },
          { type: 'mul', input0: 1, input1: 2 },
          { type: 'output', input: 3 },
        ],
      });
      await sound.applyControls([{ type: 'gateOn', node: 2 }]);
      // 1.5 is a valid gain but an invalid sustain.
      const error = await sound.setParams({ shared: 1.5 }).then(() => null,
        error => ({ code: error.code, nodeIndex: error.nodeIndex }));
      return { error, samples: await render(sound) };
    });
    expect(result.error).toEqual({ code: 'INVALID_CONTROL', nodeIndex: 2 });
    expectSquareWave(result.samples, 0.5 * 0.5);
  });

  test('updates respect handle lifetime before validating their values', async ({ page }) => {
    const result = await page.evaluate(async () => {
      const { engine, graph } = window.namedParameters;
      const retired = await engine.mount(graph);
      const remaining = await engine.mount(graph);
      const unmounting = retired.unmount();
      const unmounted = await retired.setParams({}).then(() => null, error => error.code);
      await unmounting;
      await engine.close();
      const closed = await remaining.setParams(null).then(() => null, error => error.code);
      return { unmounted, closed };
    });
    expect(result).toEqual({ unmounted: 'INVALID_HANDLE', closed: 'ENGINE_CLOSED' });
  });

  const oscillator = { type: 'oscillator', waveform: 'square', frequency: 375 };
  const numericNodes = [oscillator, { type: 'gain', input: 0, gain: 0.5 }, { type: 'output', input: 1 }];
  for (const [reason, description] of [
    ['undeclared references', {
      nodes: [oscillator, { type: 'gain', input: 0, gain: { param: 'missing' } }, numericNodes[2]],
    }],
    ['unused declarations', { params: { unused: 1 }, nodes: numericNodes }],
    ['malformed references', {
      params: { level: 0.5 },
      nodes: [oscillator, { type: 'gain', input: 0, gain: { param: 'level', extra: 1 } }, numericNodes[2]],
    }],
    ['undefined defaults that JSON would silently omit', { params: { lost: undefined }, nodes: numericNodes }],
    ['non-finite defaults', {
      params: { level: NaN },
      nodes: [oscillator, { type: 'gain', input: 0, gain: { param: 'level' } }, numericNodes[2]],
    }],
  ]) {
    test(`mount rejects ${reason}`, async ({ page }) => {
      const code = await page.evaluate(description =>
        window.namedParameters.engine.mount(description).then(() => null, error => error.code),
      description);
      expect(code).toBe('INVALID_GRAPH');
    });
  }

  test('a rejected dead binding returns its mount slot', async ({ page }) => {
    const result = await page.evaluate(async () => {
      const { engine, graph, render } = window.namedParameters;
      // The documented capacity is 16. Leave exactly one slot available.
      const capacity = 16;
      for (let i = 0; i < capacity - 1; i++) await engine.mount(graph);
      const orphan = structuredClone(graph);
      orphan.nodes[3].input = 0; // Both named gains are now outside the output path.
      const error = await engine.mount(orphan).then(() => null,
        error => ({ code: error.code, nodeIndex: error.nodeIndex }));
      const replacement = await engine.mount(graph);
      return { error, samples: await render(replacement) };
    });
    expect(result.error).toEqual({ code: 'INVALID_GRAPH', nodeIndex: 1 });
    expectSquareWave(result.samples, 0.5 * 0.5);
  });

  test('names survive JavaScript and Unicode transport unchanged', async ({ page }) => {
    const names = ['__proto__', 'toJSON', 'constructor', '音\u{1F642}'];
    const samples = await page.evaluate(async names => {
      const { engine, render } = window.namedParameters;
      const sound = await engine.mount({
        params: Object.fromEntries(names.map(name => [name, 0.5])),
        nodes: [
          { type: 'oscillator', waveform: 'square', frequency: 375 },
          ...names.map((name, input) => ({ type: 'gain', input, gain: { param: name } })),
          { type: 'output', input: names.length },
        ],
      });
      await sound.setParams(Object.fromEntries(names.map(name => [name, 0.25])));
      return render(sound);
    }, names);
    expectSquareWave(samples, 0.25 ** names.length);
  });
});
