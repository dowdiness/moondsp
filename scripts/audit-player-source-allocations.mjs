// Count Wasm GC constructions while the Player renders tracked and untracked
// material (patterns and songs), with onset observation off and on. Setup, the
// update, and the first second of playback are excluded. Each case also runs
// uninstrumented: the PCM must match. Prints one JSON line per case: onset rows,
// a sum of every onset field (NaN counted as 7), constructions, and a PCM hash.
// AUDIT_SITES=1 adds the executed count of each construction site.
// Usage: node --experimental-wasm-custom-descriptors scripts/audit-player-source-allocations.mjs \
//   counted.wasm reference.wasm authoring.js
import fs from "node:fs";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";
const [countedPath, referencePath, authoringPath] = process.argv.slice(2);
const authoring = await import(pathToFileURL(authoringPath).href);
function prepare(text) {
  let handle;
  authoring.create_draft(text, c => { handle = c; }, m => { throw new Error(m); });
  const r = JSON.parse(authoring.prepare_playback(handle));
  assert.ok(r.input, JSON.stringify(r));
  return r.input;
}
const text = t => JSON.stringify({ schema: 1, kind: "text", text: t });
async function run(path, wire, onsets) {
  const { instance: { exports: h } } = await WebAssembly.instantiate(fs.readFileSync(path), {
    spectest: { print_char() {} }, "moonbit:ffi": { make_closure: (fn, c) => fn.bind(null, c) } });
  assert.equal(h.init_scheduler_graph(48000, 128), 1);
  h.player_onset_enable(onsets ? 1 : 0);
  h.clear_playback_input();
  for (let i = 0; i < wire.length; i++) h.push_playback_char(wire.charCodeAt(i));
  assert.equal(h.player_update_input(), 0);
  assert.equal(h.player_play(), 0);
  let rows = 0, fieldSum = 0;
  const drain = () => { const n = h.player_onset_count(); for (let i = 0; i < n; i++) for (let f = 0; f < 6; f++) { const v = h.player_onset_field(i, f); fieldSum += Number.isNaN(v) ? 7 : v; } rows += n; h.player_onset_clear(); };
  for (let b = 0; b < 375; b++) { assert.ok(h.process_scheduler_block()); drain(); }
  const counters = Object.entries(h).filter(([n]) => n.startsWith("alloc:"));
  if (counters.length) assert.ok(counters.some(([, v]) => v.value > 0n));
  for (const [, v] of counters) v.value = 0n;
  rows = 0; fieldSum = 0;
  const pcm = new Float64Array(3000 * 256);
  for (let b = 0; b < 3000; b++) {
    assert.ok(h.process_scheduler_block()); drain();
    for (let i = 0; i < 128; i++) { pcm[b*256+i*2] = h.scheduler_left_sample(i); pcm[b*256+i*2+1] = h.scheduler_right_sample(i); }
  }
  assert.ok(pcm.some(x => Math.abs(x) > 0.001));
  const total = counters.reduce((a, [, v]) => a + Number(v.value), 0);
  const sites = Object.fromEntries(counters.filter(([, v]) => v.value !== 0n).map(([k, v]) => [k, Number(v.value)]));
  return { sites, counterCount: counters.length, rows, fieldSum, total, pcmHash: crypto.createHash("sha256").update(Buffer.from(pcm.buffer)).digest("hex").slice(0, 16) };
}
const pat = 'bpm(240); $: note("C2*8 E2 G2*3").s("bass")\n$: s("bd*4 sd hh*8")';
const song = 'bpm(240); song(section("a", 2, note("C2*4")),\n  section("b", 4, s("bd*4 hh*8")),\n  part("p1", "a"), part("p2", "b"))';
const cases = { tracked_pattern: prepare(pat), tracked_song: prepare(song), untracked_pattern: text(pat), untracked_song: text(song) };
for (const [name, wire] of Object.entries(cases)) for (const onsets of [false, true]) {
  const m = await run(countedPath, wire, onsets);
  const r = await run(referencePath, wire, onsets);
  assert.ok(m.counterCount > 0);
  assert.equal(m.pcmHash, r.pcmHash);
  console.log(JSON.stringify({ case: name, onsets, rows: m.rows, fieldSum: m.fieldSum, constructed: m.total, pcm: m.pcmHash,
    ...(process.env.AUDIT_SITES ? { sites: m.sites } : {}) }));
}
