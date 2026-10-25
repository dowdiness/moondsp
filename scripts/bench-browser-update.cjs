const fs = require('node:fs');
// Compare matched Wasm artifacts, not protocols selected as a runtime fallback.
const mode = process.argv[3];
if (!process.argv[2] || !['json', 'numeric'].includes(mode)) {
  throw Error('Usage: node scripts/bench-browser-update.cjs <browser.wasm> <json|numeric>');
}
(async () => {
  const { instance: { exports: host } } = await WebAssembly.instantiate(fs.readFileSync(process.argv[2]), {
    spectest: { print_char() {} },
    'moonbit:ffi': { make_closure: (fn, closure) => fn.bind(null, closure) },
  });
  const input = text => {
    host.graph_host_clear_input();
    for (const char of text) host.graph_host_push_char(char.codePointAt(0));
  };
  host.graph_host_init(48000);
  input(JSON.stringify({ params: { volume: 0.1 }, nodes: [
    { type: 'oscillator', waveform: 'square', frequency: 375 },
    { type: 'gain', input: 0, gain: { param: 'volume' } },
    { type: 'output', input: 1 },
  ] }));
  const handle = host.graph_host_mount();
  if (!handle) throw Error('mount failed');
  const run = mode === 'numeric' ? i => {
    host.graph_host_begin_update();
    if (!host.graph_host_push_update(0, i % 2 ? 0.2 : 0.1)) throw Error('push failed');
    if (!host.graph_host_update(handle)) throw Error('update failed');
  } : i => {
    input(JSON.stringify({params: { volume: i % 2 ? 0.2 : 0.1 }}));
    if (!host.graph_host_update(handle)) throw Error('update failed');
  };
  for (let i = 0; i < 10000; i++) run(i);
  const samples = [];
  for (let round = 0; round < 7; round++) {
    const start = performance.now();
    for (let i = 0; i < 100000; i++) run(i);
    samples.push((performance.now() - start) * 1000 / 100000);
  }
  host.graph_host_command(handle, 0);
  host.graph_host_process(128);
  if (host.graph_host_sample(32) !== 0.2) throw Error('Updated gain did not reach rendered audio');
  console.log(JSON.stringify({ node: process.version, usPerUpdate: samples, sample: host.graph_host_sample(32) }));
})();
