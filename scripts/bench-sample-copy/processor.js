// AudioWorklet half of scripts/bench-sample-copy/run.cjs. AudioWorkletGlobalScope
// has no performance.now in Chromium, so timings batch passes over Date.now.
const now = () => (globalThis.performance?.now ? performance.now() : Date.now());
class P extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const o = options.processorOptions;
    this.w = new WebAssembly.Instance(o.wasmModule, {
      spectest: { print_char() {} },
      'moonbit:ffi': { make_closure(f, c) { return f.bind(null, c); } },
    }).exports;
    this.clock = globalThis.performance?.now ? 'performance.now' : 'Date.now';
    const N = 480000;
    const src = new Float32Array(N);
    let expect = 0;
    for (let i = 0; i < N; i++) { src[i] = Math.fround(Math.sin(i * 0.01) * 0.5); expect += src[i]; }
    this.src = src; this.N = N; this.expect = expect;
    const w = this.w;
    // warm up
    w.sample_copy_reserve(N);
    const coldT0 = now();
    for (let i = 0; i < N; i++) w.sample_copy_write(i, src[i]);
    const cold = now() - coldT0;
    for (let r = 0; r < 3; r++) for (let i = 0; i < N; i++) w.sample_copy_write(i, src[i]);
    const full = [];
    for (let r = 0; r < 9; r++) {
      w.sample_copy_reserve(N);
      const t0 = now();
      for (let k = 0; k < 20; k++) for (let i = 0; i < N; i++) w.sample_copy_write(i, src[i]);
      full.push((now() - t0) / 20);
    }
    const checksumOk = Math.abs(w.sample_copy_checksum() - expect) < 1e-6 * N;
    const spot = w.sample_copy_sample(12345) === src[12345];
    // empty-call baseline: write outside the waveform
    const emptyT0 = now();
    for (let k = 0; k < 20; k++) for (let i = 0; i < N; i++) w.sample_copy_write(-1, 0);
    const empty = (now() - emptyT0) / 20;
    // a JS-only loop over the same source, to separate loop cost from call cost
    let acc = 0; const jsT0 = now();
    for (let k = 0; k < 20; k++) for (let i = 0; i < N; i++) acc += src[i];
    const jsOnly = (now() - jsT0) / 20; this.acc = acc;
    const reserveT0 = now();
    for (let r = 0; r < 20; r++) w.sample_copy_reserve(N);
    const reserve = (now() - reserveT0) / 20;
    this.result = { clock: this.clock, cold, full, checksumOk, spot, empty, jsOnly, reserve };
    // chunked copy inside process()
    this.chunk = o.chunk;
    this.pos = 0;
    this.blockTimes = [];
    w.sample_copy_reserve(N);
  }
  process(_i, outputs) {
    if (this.pos < this.N) {
      const end = Math.min(this.N, this.pos + this.chunk);
      const t0 = now();
      for (let i = this.pos; i < end; i++) this.w.sample_copy_write(i, this.src[i]);
      this.blockTimes.push(now() - t0);
      this.pos = end;
      if (this.pos >= this.N) {
        const ok = Math.abs(this.w.sample_copy_checksum() - this.expect) < 1e-6 * this.N;
        this.port.postMessage({ ...this.result, chunk: this.chunk, blocks: this.blockTimes.length, blockTimes: this.blockTimes, chunkedChecksumOk: ok });
      }
    }
    outputs[0][0].fill(0);
    return true;
  }
}
registerProcessor('sample-copy', P);
