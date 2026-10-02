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
      seek(id, cycleMilli) { send({ type: 'player-seek', id, cycleMilli }); },
      loop(id, beginMilli, endMilli) { send({ type: 'player-loop', id, beginMilli, endMilli }); },
      seekSection(id, sectionIndex) { send({ type: 'player-seek-section', id, sectionIndex }); },
      loopSection(id, sectionIndex) { send({ type: 'player-loop-section', id, sectionIndex }); },
      whole(id) { send({ type: 'player-whole', id }); },
      render(blocks = 1) {
        for (let i = 0; i < blocks; i++) {
          if (!wasm.process_scheduler_block()) throw new Error('render failed');
        }
      },
      receipts() { return replies.splice(0); },
      snapshot() {
        return controller.snapshot();
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
    state: 'Paused', samplePosition: 1024, tempo: 90,
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
    restartRequired: false, state: 'Playing', samplePosition: 1024,
  }));
  expect(result.after).toEqual(expect.objectContaining({ state: 'Playing', samplePosition: 1024 }));
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
  expect(result.ended).toEqual(expect.objectContaining({ state: 'Ended', mode: 'song', samplePosition: 480, cyclePosition: 0.01 }));
  expect(result.update).toEqual(expect.objectContaining({
    id: 2, operation: 'update', accepted: true, state: 'Ended', mode: 'pattern', samplePosition: 480, cyclePosition: 0.01,
  }));
  expect(result.replay).toEqual(expect.objectContaining({ id: 3, operation: 'play', accepted: true, state: 'Playing', samplePosition: 0 }));
  expect(result.after).toEqual(expect.objectContaining({ state: 'Playing', samplePosition: 128 }));
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
  expect(result.resumed).toEqual(expect.objectContaining({ id: 4, operation: 'play', accepted: true, state: 'Playing' }));
  expect(result.after.samplePosition).toBe(result.paused.samplePosition + 128);
});

test('accepted sections preview across boundaries and restore whole-song playback', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.restart(1, 'song(section("theme",2,note("60").slow(2)),section("break",2,note("64").slow(2)),section("return",2,note("67").slow(2)),part("a","theme"),part("b","break"),part("c","return"))');
    const initial = p.receipts()[0];
    p.seek(2, 1000);
    const seek = p.receipts()[0];
    p.loop(3, 1000, 5000);
    const loop = p.receipts()[0];
    p.setTempo(9, 1000);
    const tempo = p.receipts()[0];
    p.render(91);
    const wrapped = p.snapshot();
    p.update(6, 'song(section("theme",2,note("62").slow(2)),section("break",2,note("64").slow(2)),section("return",2,note("67").slow(2)),part("a","theme"),part("b","break"),part("c","return"))');
    const updated = p.receipts()[0];
    p.loop(4, 4000, 4000);
    const rejected = p.receipts()[0];
    const retained = p.snapshot();
    p.whole(5);
    const whole = p.receipts()[0];
    p.render(10);
    return { initial, seek, loop, tempo, wrapped, updated, rejected, retained, whole, after: p.snapshot() };
  });
  expect(result.initial).toMatchObject({
    accepted: true, sections: [
      { label: 'a', start: 0, end: 2 },
      { label: 'b', start: 2, end: 4 },
      { label: 'c', start: 4, end: 6 },
    ],
  });
  expect(result.seek).toMatchObject({ accepted: true, cyclePosition: 1 });
  expect(result.loop).toMatchObject({ accepted: true, loopRange: { begin: 1, end: 5 }, cyclePosition: 1 });
  expect(result.tempo).toMatchObject({ type: 'tempo-updated', tempo: 1000 });
  expect(result.wrapped.cyclePosition).toBeGreaterThanOrEqual(1);
  expect(result.wrapped.cyclePosition).toBeLessThan(1.05);
  expect(result.updated).toMatchObject({ accepted: true, loopRange: { begin: 1, end: 5 } });
  expect(result.rejected.accepted).toBe(false);
  expect(result.retained.loopRange).toEqual({ begin: 1, end: 5 });
  expect(result.whole).toMatchObject({ accepted: true, loopRange: null, cyclePosition: 0 });
  expect(result.after.cyclePosition).toBeGreaterThan(0);
});

test('section controls retain fractional accepted timing', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.restart(1, 'song(section("lead",1/7,note("60")),section("answer",2,note("64")),part("a","lead"),part("b","answer"))');
    p.receipts();
    p.seekSection(2, 1);
    const seek = p.receipts()[0];
    p.loopSection(3, 1);
    const loop = p.receipts()[0];
    return { seek, loop };
  });
  expect(result.seek.accepted).toBe(true);
  expect(result.seek.cyclePosition).toBeCloseTo(1 / 7, 7);
  expect(result.loop).toMatchObject({ accepted: true, loopRange: { end: 15 / 7 } });
  expect(result.loop.loopRange.begin).toBeCloseTo(1 / 7, 7);
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
  expect(result.accepted).toMatchObject({ accepted: true, state: 'Playing', tempo: 80 });
  expect(result.rejected).toEqual([
    expect.objectContaining({ id: 2, operation: 'update', accepted: false, state: 'Playing', tempo: 80, samplePosition: 1024 }),
    expect.objectContaining({ id: 3, operation: 'restart', accepted: false, state: 'Playing', tempo: 80, samplePosition: 1024 }),
  ]);
  expect(result.after).toEqual(expect.objectContaining({ state: 'Playing', tempo: 80, samplePosition: 1152 }));
});

test('status position follows the piecewise musical clock across tempo edits', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    const empty = p.snapshot();
    p.restart(1, 'note("60")');
    p.render(125);
    const before = p.snapshot();
    p.update(2, 'bpm(120); note("60")');
    const changed = p.receipts().at(-1);
    p.render(125);
    const after = p.snapshot();
    p.pause(3);
    p.render(10);
    return { empty, before, changed, after, paused: p.snapshot() };
  });
  expect(result.empty).toMatchObject({ state: 'Empty', mode: 'none', cyclePosition: 0 });
  expect(result.before).toMatchObject({ state: 'Playing', mode: 'pattern', tempo: 60, samplePosition: 16000 });
  expect(result.before.cyclePosition).toBeCloseTo(1 / 3, 12);
  expect(result.changed).toMatchObject({ accepted: true, tempo: 120, samplePosition: 16000 });
  expect(result.changed.cyclePosition).toBe(result.before.cyclePosition);
  expect(result.after.cyclePosition).toBeCloseTo(1, 12);
  expect(result.paused.cyclePosition).toBe(result.after.cyclePosition);
});

test('pending status counts musical materials through independent entry boundaries', async ({ page }) => {
  const result = await page.evaluate(() => {
    const p = window.playback;
    p.restart(1, 'bpm(400); let melody = note("60").slow(3); let drums = s("bd").slow(4); stack(melody, drums)');
    p.render();
    p.update(2, 'bpm(400); let melody = note("72").slow(3); let drums = s("sd").slow(4); stack(melody, drums)');
    const accepted = p.receipts().at(-1);
    p.render(170);
    const firstEntry = p.snapshot();
    p.render(57);
    return { accepted, firstEntry, secondEntry: p.snapshot() };
  });
  expect(result.accepted).toMatchObject({ accepted: true, pendingCount: 2 });
  expect(result.firstEntry.pendingCount).toBe(1);
  expect(result.secondEntry.pendingCount).toBe(0);
});
