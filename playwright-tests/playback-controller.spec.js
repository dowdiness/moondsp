const { test, expect } = require('@playwright/test');

// The fixture only boots real WASM and exposes the public playback protocol.
// Each test owns its requests, render boundary and expected receipts.
test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.evaluate(async () => {
    const { PlaybackController } = await import('/playback-controller.js');
    const { instance } = await WebAssembly.instantiate(
      await (await fetch('/moonbit_dsp.wasm')).arrayBuffer(),
      { spectest: { print_char() {} },
        'moonbit:ffi': { make_closure(fn, closure) { return fn.bind(null, closure); } } },
    );
    const wasm = instance.exports;
    if (!wasm.init_scheduler_graph(48000, 128)) throw new Error('init failed');
    const replies = [];
    const controller = new PlaybackController(wasm, reply => replies.push(reply));
    window.playback = {
      apply(revision, policy, text = 'note("60")', mode = 'pattern') {
        controller.handle({ type: 'apply-score', mode, revision, policy, text });
      },
      restart(revision) { controller.handle({ type: 'restart-playback', revision }); },
      render() {
        if (!wasm.process_scheduler_block()) throw new Error('render failed');
        controller.didRender(128);
      },
      receipts() { return replies.splice(0); },
    };
  });
});

test('initial application is acknowledged only after rendering, despite a rejected restart', async ({ page }) => {
  const { before, after } = await page.evaluate(() => {
    const p = window.playback;
    p.apply(1, 'restart');
    p.restart(2);
    const before = p.receipts();
    p.render();
    return { before, after: p.receipts() };
  });
  expect(before).toEqual([expect.objectContaining({ type: 'playback-error', phase: 'restart', revision: 2 })]);
  expect(after).toEqual([expect.objectContaining({ type: 'pattern-updated', revision: 1, scoreRevision: 1, acceptedAtSample: 0, samplePosition: 128 })]);
});

test('failed preparation preserves the accepted update and its receipt', async ({ page }) => {
  const { before, after } = await page.evaluate(() => {
    const p = window.playback;
    p.apply(1, 'restart'); p.render(); p.receipts();
    p.apply(2, 'continue', 'note("64")');
    p.apply(3, 'continue', 'note(');
    const before = p.receipts();
    p.render();
    return { before, after: p.receipts() };
  });
  expect(before).toEqual([expect.objectContaining({ type: 'pattern-error', phase: 'prepare', revision: 3 })]);
  expect(after).toEqual([expect.objectContaining({ type: 'pattern-updated', revision: 2, scoreRevision: 2, acceptedAtSample: 128, samplePosition: 256 })]);
});

test('unrepresentable tempo is rejected without superseding the accepted receipt', async ({ page }) => {
  const { before, after } = await page.evaluate(() => {
    const p = window.playback;
    const body = 'section("a",1,note("60").fast(10000019).fast(100000003).slow(100000000)),part("r","a"))';
    const score = 'song(bpm(0.001),' + body;
    p.apply(1, 'restart', score, 'song'); p.render(); p.receipts();
    p.apply(2, 'continue', score, 'song');
    p.apply(3, 'continue', 'song(bpm(1000),' + body, 'song');
    const before = p.receipts();
    p.render();
    return { before, after: p.receipts() };
  });
  expect(before).toEqual([expect.objectContaining({
    type: 'song-error', phase: 'apply', revision: 3,
    message: 'tempo change exceeds transport range',
  })]);
  expect(after).toEqual([expect.objectContaining({
    type: 'song-updated', revision: 2, scoreRevision: 2, acceptedAtSample: 128,
  })]);
});

test('restart supersedes replacements and acknowledges the applied score', async ({ page }) => {
  const { before, after } = await page.evaluate(() => {
    const p = window.playback;
    p.apply(1, 'restart'); p.render(); p.receipts();
    p.apply(2, 'continue', 'note("67")');
    p.apply(3, 'continue', 'note("72")');
    p.restart(4);
    const before = p.receipts();
    p.render();
    return { before, after: p.receipts() };
  });
  expect(before).toEqual([
    { type: 'playback-superseded', revision: 2 },
    { type: 'playback-superseded', revision: 3 },
  ]);
  expect(after).toEqual([expect.objectContaining({ type: 'playback-restarted', revision: 4, scoreRevision: 1, acceptedAtSample: 0, samplePosition: 128 })]);
});
