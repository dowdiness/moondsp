const { test, expect } = require('@playwright/test');

test.use({ launchOptions: { args: ['--disable-audio-output'] } });

test.beforeEach(async ({ page }) => {
  // Capture only for native failure injection, never through the engine API.
  await page.addInitScript(() => {
    window.__workletNodes = [];
    const NativeNode = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) {
        super(...args);
        window.__workletNodes.push(this);
      }
    };
  });
  await page.goto('/graph-example.html');
});

test('private output preserves native duplicate, indexed and AudioParam routing with targeted removal', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine, Graph } = await import('/graph-engine.js');
    const context = new OfflineAudioContext(3, 1024, 48000);
    const engine = await GraphEngine({ context });
    const hidden = !('output' in engine) && !('port' in engine);
    const source = await engine.mount(Graph({}, g => ({ output: g.gain(g.oscillator('square', 375), 0.125) })));
    const merger = context.createChannelMerger(3);
    merger.connect(context.destination);
    const returnedNode = engine.connect(merger, 0, 0) === merger;
    engine.connect(merger, 0, 0); // Native duplicate connects must not double PCM.
    engine.connect(merger, 0, 1);
    engine.disconnect(merger, 0, 1); // Must retain input 0 of this same node.
    const carrier = context.createConstantSource();
    const modulated = context.createGain();
    modulated.gain.value = 0;
    carrier.connect(modulated).connect(merger, 0, 2);
    carrier.start();
    const returnedParam = engine.connect(modulated.gain, 0) === undefined;
    engine.disconnect(modulated.gain, 0);
    engine.connect(modulated.gain);
    const errors = [];
    for (const operation of [
      () => engine.connect(merger, 1, 0),
      () => engine.connect(merger, 0, 3),
      () => engine.disconnect(merger, 0, 1),
    ]) {
      try { operation(); errors.push('did not throw'); }
      catch (error) { errors.push(error instanceof DOMException ? error.name : 'wrapped'); }
    }
    await source.play();
    const buffer = await context.startRendering();
    const residuals = [0, 0, 0];
    for (let channel = 0; channel < 3; channel++) {
      const samples = buffer.getChannelData(channel);
      for (let i = 0; i < samples.length; i++) {
        const expected = channel === 1 ? 0 : (i % 128 < 64 ? 0.125 : -0.125);
        residuals[channel] = Math.max(residuals[channel], Math.abs(samples[i] - expected));
      }
    }
    await engine.close();
    return { hidden, returnedNode, returnedParam, errors, residuals, nodes: window.__workletNodes.length };
  });
  expect(result).toMatchObject({
    hidden: true, returnedNode: true, returnedParam: true, nodes: 1,
    errors: ['IndexSizeError', 'IndexSizeError', 'InvalidAccessError'],
  });
  for (const residual of result.residuals) expect(residual).toBeLessThan(1e-6);
});

test('connect rejects synchronously as close starts, while native disconnect remains available', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const engine = await GraphEngine({ context });
      engine.connect(context.destination);
      const closing = engine.close();
      let immediate;
      try { engine.connect(context.destination); }
      catch (error) { immediate = error.code; }
      const during = engine.disconnect() === undefined;
      await closing;
      const after = engine.disconnect(0) === undefined;
      let nativeError;
      try { engine.disconnect(context.destination); }
      catch (error) { nativeError = error instanceof DOMException && error.name; }
      let closed;
      try { engine.connect(context.destination); }
      catch (error) { closed = error.code; }
      return { immediate, closed, during, after, nativeError };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ immediate: 'ENGINE_CLOSED', closed: 'ENGINE_CLOSED', during: true, after: true, nativeError: 'InvalidAccessError' });
});

test('processor failure rejects routing synchronously without affecting another engine in the same context', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const first = await GraphEngine({ context });
      const firstNode = window.__workletNodes.at(-1);
      const second = await GraphEngine({ context });
      firstNode.onprocessorerror(new Event('processorerror'));
      let failure;
      try { first.connect(context.destination); }
      catch (error) { failure = error; }
      const exit = await first.wait();
      const independent = second.connect(context.destination) === context.destination;
      await first.close();
      const cleanup = first.disconnect() === undefined;
      await second.close();
      return { code: failure?.code, same: failure === exit.error, independent, cleanup, nodes: window.__workletNodes.length };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ code: 'PROCESSOR_FAILED', same: true, independent: true, cleanup: true, nodes: 2 });
});
