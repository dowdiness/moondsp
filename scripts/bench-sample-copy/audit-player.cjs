// Count Wasm GC constructions while a compiled sample player renders, after
// it is built. See docs/performance/2026-11-24-sample-copy.md.
//
// node --experimental-wasm-custom-descriptors scripts/bench-sample-copy/audit-player.cjs counted.wasm reference.wasm
const fs = require('node:fs');
const assert = require('node:assert/strict');

async function instantiate(path) {
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(path), {
    spectest: { print_char() {} },
    'moonbit:ffi': { make_closure: (fn, closure) => fn.bind(null, closure) },
  });
  return instance.exports;
}

// Each case renders 1,000 blocks of 128 frames from a one-second sine:
// - at the root pitch, so the waveform ends after 375 blocks and the rest is silence;
// - at 1.5 times speed and another pitch, which interpolates;
// - backwards;
// - with a reset every 50 blocks, which binds the waveform again;
// - on a begin/end slice, forwards and backwards, which computes the slice at each bind.
const CASES = [
  { name: 'root pitch, speed 1', pitch: 69, speed: 1, resetEvery: 0 },
  { name: 'pitch 62, speed 1.5', pitch: 62, speed: 1.5, resetEvery: 0 },
  { name: 'speed -1', pitch: 69, speed: -1, resetEvery: 0 },
  { name: 'reset every 50 blocks', pitch: 69, speed: 1, resetEvery: 50 },
  { name: 'slice 0.25-0.75, reset every 50 blocks', pitch: 69, speed: 1, begin: 0.25, end: 0.75, resetEvery: 50 },
  { name: 'slice 0.25-0.75 backwards, reset every 50 blocks', pitch: 69, speed: -1, begin: 0.25, end: 0.75, resetEvery: 50 },
];

(async () => {
  const [countedPath, referencePath] = process.argv.slice(2);
  const counted = await instantiate(countedPath);
  const reference = await instantiate(referencePath);
  const counters = Object.entries(counted).filter(([name]) => name.startsWith('alloc:'));
  assert.ok(counters.length > 0, 'the counted module exports counters');
  for (const c of CASES) {
    for (const h of [counted, reference]) assert.equal(h.sample_player_probe_init(c.pitch, c.speed, c.begin ?? 0, c.end ?? 1), 1);
    const built = counters.reduce((sum, [, v]) => sum + v.value, 0n);
    assert.ok(built > 0n, 'building the store and graph is an allocation-positive control');
    for (const [, v] of counters) v.value = 0n;
    const sum = counted.sample_player_probe_process(1000, c.resetEvery);
    const allocating = counters.filter(([, v]) => v.value > 0n).map(([n, v]) => `${n}=${v.value}`);
    const expected = reference.sample_player_probe_process(1000, c.resetEvery);
    assert.equal(sum, expected, 'instrumentation does not change the output');
    assert.ok(sum !== 0, 'the player renders sound');
    console.log(JSON.stringify({ case: c.name, constructionsWhileRendering: allocating.length ? allocating : 0, outputEnergy: sum }));
    assert.deepEqual(allocating, []);
  }
})();
