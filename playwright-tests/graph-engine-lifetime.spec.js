const { test, expect } = require('@playwright/test');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const host = path.join(root, 'packages/browser/host');
const driver = path.join(host, '_build/js/debug/build/browser_test/browser_test.js');
test.use({ launchOptions: { args: ['--disable-audio-output'] } });

test.beforeAll(() => {
  test.setTimeout(120_000);
  execFileSync('moon', ['build', '--target', 'js'], {
    cwd: host, env: { ...process.env, NEW_MOON_MOD: '0' }, stdio: 'inherit', timeout: 120_000,
  });
});

test.beforeEach(async ({ page }) => {
  await page.route('**/lifetime-test-driver.js', route => route.fulfill({ path: driver, contentType: 'application/javascript' }));
  await page.goto('/graph-example.html');
});

test('pause and rejected controls remain live; normal close retains one result for multiple and late waits', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new OfflineAudioContext(1, 128, 48000);
    const engine = await GraphEngine({ context });
    const graph = await engine.mount({ nodes: [{ type: 'oscillator', waveform: 'sine', frequency: 220 }, { type: 'output', input: 0 }] });
    let exited = false;
    const first = engine.wait().then(exit => { exited = true; return exit; });
    const second = engine.wait();
    await graph.play();
    await graph.pause();
    const invalid = await graph.applyControls([{ type: 'setParam', node: 99, slot: 'value0', value: 1 }]).catch(error => error.code);
    const live = !exited;
    await engine.close();
    const exit = await first;
    const controller = new AbortController();
    controller.abort('gone');
    const abortedLate = await engine.wait({ signal: controller.signal }).then(() => 'wrong', error => error.name);
    return { invalid, live, type: exit.type, same: exit === await second && exit === await engine.wait(), abortedLate, state: context.state };
  });
  expect(result).toEqual({ invalid: 'INVALID_CONTROL', live: true, type: 'closed', same: true, abortedLate: 'AbortError', state: 'suspended' });
});

test('cancelled and completed waits detach signal listeners without ending the engine', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const engine = await GraphEngine({ context: new OfflineAudioContext(1, 128, 48000) });
    let active = 0;
    const controller = () => {
      const owner = new AbortController();
      const add = owner.signal.addEventListener.bind(owner.signal);
      const remove = owner.signal.removeEventListener.bind(owner.signal);
      owner.signal.addEventListener = (type, listener, options) => { active++; add(type, listener, options); };
      owner.signal.removeEventListener = (type, listener, options) => { active--; remove(type, listener, options); };
      return owner;
    };
    for (let i = 0; i < 1000; i++) {
      const owner = controller();
      const waiting = engine.wait({ signal: owner.signal }).catch(error => error.name);
      owner.abort();
      if (await waiting !== 'AbortError' || active !== 0) throw new Error('cancelled wait retained a listener');
    }
    const owner = controller();
    const waiting = engine.wait({ signal: owner.signal });
    await engine.close();
    const exit = await waiting;
    owner.abort();
    return { active, type: exit.type, same: exit === await engine.wait() };
  });
  expect(result).toEqual({ active: 0, type: 'closed', same: true });
});

test('processor failure during close wins and command admission remains closed', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const engine = await GraphEngine({ context });
      const waiting = engine.wait();
      const closing = engine.close().catch(error => error);
      engine.output.onprocessorerror(new Event('processorerror'));
      const error = await closing;
      const exit = await waiting;
      const admission = await engine.mount({ nodes: [] }).catch(error => error.code);
      return { type: exit.type, code: exit.error.code, same: exit.error === error && exit === await engine.wait(), admission };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ type: 'failed', code: 'PROCESSOR_FAILED', same: true, admission: 'ENGINE_CLOSED' });
});

test('close deadline releases a silent worklet and rejects its pending commands', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const engine = await GraphEngine({ context, closeTimeoutMs: 30 });
      let portClosed = false;
      const portClose = engine.output.port.close.bind(engine.output.port);
      engine.output.port.close = () => { portClosed = true; portClose(); };
      // Drop outgoing messages after real initialization: the host never gets an ack.
      engine.output.port.postMessage = () => {};
      const pending = engine.mount({ nodes: [] }).catch(error => error);
      const closing = engine.close();
      const repeated = engine.close();
      const error = await closing.catch(error => error);
      const exit = await engine.wait();
      return { code: error.code, type: exit.type, same: closing === repeated && error === exit.error && await pending === error, portClosed, state: context.state };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ code: 'HOST_ERROR', type: 'failed', same: true, portClosed: true, state: 'suspended' });
});

test('MoonBit wait and close preserve a native cleanup error and its metadata by identity', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine, GraphEngineError } = await import('/graph-engine.js');
    const bridge = await import('/lifetime-test-driver.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const engine = await GraphEngine({ context });
      const error = new GraphEngineError('HOST_ERROR', 'native cleanup failed', 7);
      const cause = { operation: 'disconnect' };
      error.cause = cause;
      engine.output.disconnect = () => { throw error; };
      const closed = await bridge.engine_lifetime_close(engine);
      const exit = await bridge.engine_lifetime_wait(engine, new AbortController().signal);
      return { ok: closed.ok, type: exit.type, same: closed.error === error && exit.error === error && exit.error.cause === cause, code: exit.error.code, nodeIndex: exit.error.nodeIndex };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ ok: false, type: 'failed', same: true, code: 'HOST_ERROR', nodeIndex: 7 });
});

test('cancelling one MoonBit observer leaves another observer and the engine alive', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const bridge = await import('/lifetime-test-driver.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const engine = await GraphEngine({ context });
      const controller = new AbortController();
      const cancelled = bridge.engine_lifetime_wait(engine, controller.signal).catch(error => error.name);
      const survivor = bridge.engine_lifetime_wait(engine, new AbortController().signal);
      await new Promise(resolve => setTimeout(resolve, 0));
      controller.abort();
      const cancellation = await cancelled;
      const alreadyAborted = await bridge.engine_lifetime_wait(engine, controller.signal).catch(error => error.name);
      await engine.mount({ nodes: [{ type: 'oscillator', waveform: 'sine', frequency: 220 }, { type: 'output', input: 0 }] });
      engine.output.onprocessorerror(new Event('processorerror'));
      const exit = await survivor;
      const late = await bridge.engine_lifetime_wait(engine, new AbortController().signal);
      await engine.close();
      return { cancellation, alreadyAborted, type: exit.type, code: exit.error.code, same: exit.error === late.error && exit.error === (await engine.wait()).error };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ cancellation: 'AbortError', alreadyAborted: 'AbortError', type: 'failed', code: 'PROCESSOR_FAILED', same: true });
});

for (const ending of ['failure', 'context-close']) {
  test(`MoonBit group joins its worker before cleanup on ${ending}`, async ({ page }) => {
    const result = await page.evaluate(async ending => {
      const { GraphEngine } = await import('/graph-engine.js');
      const bridge = await import('/lifetime-test-driver.js');
      const context = new AudioContext();
      await context.suspend();
      try {
        const engine = await GraphEngine({ context });
        const log = [];
        const running = bridge.engine_lifetime_group_probe(engine, new AbortController().signal, log);
        await new Promise(resolve => setTimeout(resolve, 0));
        if (ending === 'failure') engine.output.onprocessorerror(new Event('processorerror'));
        else await context.close();
        const exit = await running;
        return { type: exit.type, log: log.map(event => event.type) };
      } finally { if (context.state !== 'closed') await context.close(); }
    }, ending);
    expect(result).toEqual({ type: ending === 'failure' ? 'failed' : 'closed', log: ['worker-stopped', 'cleanup-ok'] });
  });
}

test('MoonBit group cancellation still completes bounded cleanup when close is unanswered', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { GraphEngine } = await import('/graph-engine.js');
    const bridge = await import('/lifetime-test-driver.js');
    const context = new AudioContext();
    await context.suspend();
    try {
      const engine = await GraphEngine({ context, closeTimeoutMs: 30 });
      engine.output.port.postMessage = () => {};
      const log = [];
      const controller = new AbortController();
      const running = bridge.engine_lifetime_group_probe(engine, controller.signal, log).catch(error => error.name);
      await new Promise(resolve => setTimeout(resolve, 0));
      controller.abort();
      const cancellation = await running;
      const exit = await engine.wait();
      return { cancellation, type: exit.type, code: exit.error.code, log: log.map(event => event.type), same: log[1].error === exit.error, state: context.state };
    } finally { await context.close(); }
  });
  expect(result).toEqual({ cancellation: 'AbortError', type: 'failed', code: 'HOST_ERROR', log: ['worker-stopped', 'cleanup-failed'], same: true, state: 'suspended' });
});
