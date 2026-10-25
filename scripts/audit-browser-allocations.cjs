// Count Wasm GC constructions, excluding initialization/mounting and JS allocations.
// Usage: node --experimental-wasm-custom-descriptors scripts/audit-browser-allocations.cjs counted.wasm reference.wasm
const fs = require('node:fs');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

async function run(path, waveform, mode, scenario) {
  const bytes = fs.readFileSync(path);
  const { instance: { exports: h } } = await WebAssembly.instantiate(bytes, {
    spectest: { print_char() {} },
    'moonbit:ffi': { make_closure: (fn, closure) => fn.bind(null, closure) },
  });
  assert.equal(h.graph_host_init(48000), 1);
  const description = { params: { pitch: 220, volume: 0.1, sustain: 0.7, cutoff: 1200 }, gates: { amp: 2 }, nodes: [
    { type: 'oscillator', waveform, frequency: { param: 'pitch' } },
    { type: 'biquad', input: 0, mode, cutoff: { param: 'cutoff' }, q: 0.7 },
    { type: 'adsr', attackMs: 2, decayMs: 20, sustain: { param: 'sustain' }, releaseMs: 30 },
    { type: 'mul', input0: 1, input1: 2 },
    { type: 'gain', input: 3, gain: { param: 'volume' } },
    { type: 'output', input: 4 },
  ] };
  h.graph_host_clear_input();
  for (const char of JSON.stringify(description)) h.graph_host_push_char(char.codePointAt(0));
  const handle = h.graph_host_mount();
  assert.ok(handle);
  let text = '';
  for (let i = 0; i < h.graph_host_bindings_length(); i++) text += String.fromCharCode(h.graph_host_bindings_char(i));
  const bindings = JSON.parse(text);
  const update = entries => {
    h.graph_host_begin_update();
    for (const [id, value] of entries) assert.equal(h.graph_host_push_update(id, value), 1);
    return h.graph_host_update(handle);
  };
  assert.equal(update([[bindings.gates.amp, 1]]), 1);
  assert.equal(h.graph_host_command(handle, 0), 1);
  for (let i = 0; i < 200; i++) assert.equal(h.graph_host_process(128), 1);
  const counters = Object.entries(h).filter(([name]) => name.startsWith('alloc:'));
  if (counters.length) assert.ok(counters.some(([, v]) => v.value > 0n), 'mounting is an allocation-positive control');
  for (const [, value] of counters) value.value = 0n;
  const pcm = new Float64Array(1000 * 128);
  for (let block = 0; block < 1000; block++) {
    if (scenario === 'params') assert.equal(update([
      [bindings.params.pitch[0], 220 + block % 12 * 20],
      [bindings.params.cutoff[0], 600 + block % 7 * 100],
      [bindings.params.volume[0], 0.08 + block % 3 * 0.01],
    ]), 1);
    if (scenario === 'gates') assert.equal(update([[bindings.gates.amp, 0], [bindings.gates.amp, 1]]), 1);
    if (scenario === 'rejected') assert.equal(update([
      [bindings.params.volume[0], 0.2], [bindings.params.sustain[0], 1.5],
    ]), 0);
    assert.equal(h.graph_host_process(128), 1);
    for (let i = 0; i < 128; i++) {
      const sample = h.graph_host_sample(i);
      assert.ok(Number.isFinite(sample));
      pcm[block * 128 + i] = sample;
    }
  }
  assert.ok(pcm.some(x => Math.abs(x) > 0.001), 'must render audible nonzero PCM');
  const allocations = Object.fromEntries(counters.filter(([, v]) => v.value !== 0n).map(([k, v]) => [k, Number(v.value)]));
  return { counterCount: counters.length, allocations, total: Object.values(allocations).reduce((a, b) => a + b, 0),
    pcmHash: crypto.createHash('sha256').update(Buffer.from(pcm.buffer)).digest('hex') };
}

(async () => {
  for (const waveform of ['sine', 'square', 'saw', 'triangle']) {
    for (const mode of ['lowpass', 'highpass', 'bandpass']) {
      let continuous;
      for (const scenario of ['continuous', 'params', 'gates', 'rejected']) {
        const measured = await run(process.argv[2], waveform, mode, scenario);
        const reference = await run(process.argv[3], waveform, mode, scenario);
        assert.ok(measured.counterCount > 0, 'first input must be instrumented');
        assert.equal(measured.pcmHash, reference.pcmHash, 'instrumentation must preserve every sample');
        if (scenario === 'continuous') continuous = measured.pcmHash;
        if (scenario === 'rejected') assert.equal(measured.pcmHash, continuous, 'rejection must preserve audio');
        console.log(JSON.stringify({ waveform, mode, scenario, ...measured }));
      }
    }
  }
})();
