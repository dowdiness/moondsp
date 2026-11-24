// Count Wasm GC constructions while the Player renders a draft whose notes follow
// control signals, with signal observation off and on. Setup, the update, and
// the first second of playback are excluded; observation must add nothing.
// Usage: node --experimental-wasm-custom-descriptors scripts/audit-player-signal-allocations.mjs \
//   counted.wasm reference.wasm web/live/src/generated/authoring.js
import fs from "node:fs";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";

const [countedPath, referencePath, authoringPath] = process.argv.slice(2);
const authoring = await import(pathToFileURL(authoringPath).href);

function prepare(text) {
  let handle;
  authoring.create_draft(text, created => { handle = created; }, message => { throw new Error(message); });
  const result = JSON.parse(authoring.prepare_playback(handle));
  assert.ok(result.input, `draft must prepare: ${JSON.stringify(result)}`);
  return result.input;
}

async function run(path, wire, signals) {
  const { instance: { exports: h } } = await WebAssembly.instantiate(fs.readFileSync(path), {
    spectest: { print_char() {} },
    "moonbit:ffi": { make_closure: (fn, closure) => fn.bind(null, closure) },
  });
  assert.equal(h.init_scheduler_graph(48000, 128), 1);
  h.player_onset_enable(0);
  h.player_signal_enable(signals ? 1 : 0);
  h.clear_playback_input();
  for (let i = 0; i < wire.length; i++) h.push_playback_char(wire.charCodeAt(i));
  assert.equal(h.player_update_input(), 0);
  assert.equal(h.player_play(), 0);
  let rows = 0;
  const values = [];
  // What the Worklet's SignalRing reads each block.
  const drain = () => {
    const count = h.player_signal_count();
    for (let index = 0; index < count; index++) values.push(h.player_signal_field(index, 4));
    rows += count;
    h.player_signal_clear();
  };
  for (let block = 0; block < 375; block++) { assert.ok(h.process_scheduler_block()); drain(); }
  const counters = Object.entries(h).filter(([name]) => name.startsWith("alloc:"));
  if (counters.length) assert.ok(counters.some(([, v]) => v.value > 0n), "setup is an allocation-positive control");
  for (const [, value] of counters) value.value = 0n;
  rows = 0;
  values.length = 0;
  const pcm = new Float64Array(3000 * 256);
  for (let block = 0; block < 3000; block++) {
    assert.ok(h.process_scheduler_block());
    drain();
    for (let i = 0; i < 128; i++) {
      pcm[block * 256 + i * 2] = h.scheduler_left_sample(i);
      pcm[block * 256 + i * 2 + 1] = h.scheduler_right_sample(i);
    }
  }
  assert.equal(h.player_signal_dropped(), 0);
  assert.ok(pcm.some(x => Math.abs(x) > 0.001), "must render audible nonzero PCM");
  const allocations = Object.fromEntries(counters.filter(([, v]) => v.value !== 0n).map(([k, v]) => [k, Number(v.value)]));
  return { counterCount: counters.length, rows, low: Math.min(...values), high: Math.max(...values), allocations,
    total: Object.values(allocations).reduce((a, b) => a + b, 0),
    pcmHash: crypto.createHash("sha256").update(Buffer.from(pcm.buffer)).digest("hex") };
}

const drafts = {
  pattern: { text: 'bpm(240); $: note("C2*8").lpf(saw.range(200, 4000).slow(4))\n$: note("G3*4").gain(isaw.range(0, 0.8)).pan(tri)' },
  song: { text: 'bpm(240); song(section("a", 2, note("C2*4")),\n  section("b", 4, note("C2*4").lpf(saw.range(4000, 200).slow(4))),\n  part("p1", "a"), part("p2", "b"))' },
  sine: { text: 'bpm(240); note("G3*4").pan(sine)' },
  cosine: { text: 'bpm(240); note("G3*4").pan(cosine)' },
};
for (const [name, { text }] of Object.entries(drafts)) {
  const wire = prepare(text);
  const results = {};
  for (const signals of [false, true]) {
    const measured = await run(countedPath, wire, signals);
    const reference = await run(referencePath, wire, signals);
    assert.ok(measured.counterCount > 0, "first input must be instrumented");
    assert.equal(measured.pcmHash, reference.pcmHash, "instrumentation must preserve every sample");
    results[signals ? "on" : "off"] = measured;
  }
  const { on, off } = results;
  assert.equal(on.pcmHash, off.pcmHash, "observation must not change audio");
  assert.equal(off.rows, 0);
  assert.ok(on.rows > 0, "observation must record rows");
  const added = Object.fromEntries(Object.keys({ ...on.allocations, ...off.allocations })
    .map(key => [key, (on.allocations[key] ?? 0) - (off.allocations[key] ?? 0)]).filter(([, n]) => n !== 0));
  assert.deepEqual(added, {}, "observation must not construct anything");
  console.log(JSON.stringify({ draft: name, blocks: 3000, rows: on.rows, low: on.low, high: on.high,
    constructedOff: off.total, constructedOn: on.total, added, pcmHash: on.pcmHash }));
}
