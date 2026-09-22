const { test, expect } = require('@playwright/test');

// The fixture boots real WASM and exercises the public owner protocol.
// Receipts are immediate; rendering only advances the underlying transport.
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
    function send(data) { controller.handle(data); }
    window.playback = {
      send,
      update(id, text) {
        send({ type: 'player-update', id, input: JSON.stringify({ schema: 1, kind: 'text', text }) });
      },
      restart(id, text) {
        send({ type: 'player-restart', id, input: JSON.stringify({ schema: 1, kind: 'text', text }) });
      },
      play(id = 1) { send({ type: 'player-play', id }); },
      pause(id = 1) { send({ type: 'player-pause', id }); },
      render(blocks = 1) {
        for (let i = 0; i < blocks; i++) {
          if (!wasm.process_scheduler_block()) throw new Error('render failed');
        }
      },
      receipts() { return replies.splice(0); },
      snapshot() {
        return { state: wasm.player_state(), samplePosition: wasm.scheduler_sample_position(), tempo: wasm.scheduler_bpm() };
      },
      setTempo(revision, bpm) { controller.handle({ type: 'set-scheduler-bpm', revision, bpm }); },
    };
  });
});

test('draft failures retain their version without degrading to text admission', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.restart(1, 'note("60").slow(8)'); p.render(8); p.receipts();
    const before = p.snapshot();
    p.send({ type: 'player-restart', id: 2, input: JSON.stringify({
      schema: 1, kind: 'pattern', text: 'note("72")', version: [9, 3],
      sourceMap: { epoch: 9, atoms: [], definitions: [], references: [] },
    }) });
    const rejected = p.receipts()[0];
    const after = p.snapshot();
    p.send({ type: 'player-restart', id: 3, input: JSON.stringify({
      schema: 1, kind: 'song', version: [10, 4],
      text: 'song(section("a",1,note("67")),part("first","a"))',
    }) });
    return { before, after, rejected, accepted: p.receipts()[0] };
  });
  expect(result.after).toEqual(result.before);
  expect(result.rejected).toEqual(expect.objectContaining({
    id: 2, accepted: false, draftVersion: [9, 3], samplePosition: 1024,
  }));
  expect(result.accepted).toEqual(expect.objectContaining({
    id: 3, accepted: true, draftVersion: [10, 4], samplePosition: 0,
  }));
});

test('paused update is accepted immediately and commits source tempo without advancing', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.update(1, 'note("60").slow(8)'); p.play(2); p.render(8); p.pause(3);
    p.receipts();
    p.update(4, 'bpm(90); note("72").slow(8)');
    const update = p.receipts()[0];
    const beforeRender = p.snapshot();
    p.render(10);
    return { update, beforeRender, afterRender: p.snapshot() };
  });
  expect(result.update).toEqual(expect.objectContaining({
    type: 'player-receipt', id: 4, operation: 'update', accepted: true,
    state: 3, samplePosition: 1024, tempo: 90,
  }));
  expect(result.afterRender).toEqual(result.beforeRender);
});

test('invalid restart preserves the current song and transport position', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.update(1, 'note("60").slow(8)'); p.play(); p.render(8); p.receipts();
    p.restart(2, 'note(');
    const rejected = p.receipts()[0];
    const after = p.snapshot();
    p.render();
    return { rejected, after, advanced: p.snapshot() };
  });
  expect(result.rejected).toEqual(expect.objectContaining({
    type: 'player-receipt', id: 2, operation: 'restart', accepted: false,
    restartRequired: false, state: 2, samplePosition: 1024,
  }));
  expect(result.after).toEqual(expect.objectContaining({ state: 2, samplePosition: 1024 }));
  expect(result.advanced.samplePosition).toBe(1152);
});

test('ended update keeps tails while Play replays the newest song', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    const finite = 'song(section("a",1/100,note("60").release(1).room(1)),part("a1","a"))';
    p.update(1, finite); p.play(); p.receipts(); p.render(4);
    const ended = p.snapshot();
    p.update(2, 'note("72")');
    const update = p.receipts()[0];
    p.play(3);
    const replay = p.receipts()[0];
    p.render();
    return { ended, update, replay, after: p.snapshot() };
  });
  expect(result.ended).toEqual(expect.objectContaining({ state: 4, samplePosition: 480 }));
  expect(result.update).toEqual(expect.objectContaining({
    id: 2, operation: 'update', accepted: true, state: 4, samplePosition: 480,
  }));
  expect(result.replay).toEqual(expect.objectContaining({ id: 3, operation: 'play', accepted: true, state: 2, samplePosition: 0 }));
  expect(result.after).toEqual(expect.objectContaining({ state: 2, samplePosition: 128 }));
});

test('Pause freezes transport until Play resumes it', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.update(1, 'note("60").slow(8)'); p.play(2); p.render(20); p.pause(3); p.receipts();
    const paused = p.snapshot();
    p.render(100);
    const frozen = p.snapshot();
    p.play(4);
    const resumed = p.receipts()[0];
    p.render();
    return { paused, frozen, resumed, after: p.snapshot() };
  });
  expect(result.frozen).toEqual(result.paused);
  expect(result.resumed).toEqual(expect.objectContaining({ id: 4, operation: 'play', accepted: true, state: 2 }));
  expect(result.after.samplePosition).toBe(result.paused.samplePosition + 128);
});

test('source tempo replaces the legacy tempo setting, including omission default', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.setTempo(1, 72.12345);
    const tempo = p.receipts()[0];
    p.update(2, 'note("60")');
    return { tempo, update: p.receipts()[0] };
  });
  expect(result.tempo).toEqual({ type: 'tempo-updated', revision: 1, tempo: 72.123 });
  expect(result.update).toEqual(expect.objectContaining({ operation: 'update', accepted: true, tempo: 60 }));
});

test('source size boundary preserves playback for rejected Update and Restart', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.restart(1, 'bpm(80); note("60").slow(8)'.padEnd(8192, ' '));
    const accepted = p.receipts()[0];
    p.render(8);
    const tooLarge = 'bpm(96); note("72")'.padEnd(8193, ' ');
    p.update(2, tooLarge);
    p.restart(3, tooLarge);
    const rejected = p.receipts();
    p.render();
    return { accepted, rejected, after: p.snapshot() };
  });
  expect(result.accepted).toMatchObject({ accepted: true, state: 2, tempo: 80 });
  expect(result.rejected).toEqual([
    expect.objectContaining({ id: 2, operation: 'update', accepted: false, state: 2, tempo: 80, samplePosition: 1024 }),
    expect.objectContaining({ id: 3, operation: 'restart', accepted: false, state: 2, tempo: 80, samplePosition: 1024 }),
  ]);
  expect(result.after).toEqual({ state: 2, tempo: 80, samplePosition: 1152 });
});
