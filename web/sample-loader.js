// Copies decoded samples into the scheduler's sample store from inside the
// AudioWorklet, a bounded number of samples per render quantum (ADR-0026).
// JS cannot write a wasm-gc array, so every sample is one export call: about
// 6 ns warm, 8-17 ns cold, and 16,384 of them take at most about 10% of a
// 128-frame block at 48 kHz (docs/performance/2026-11-24-sample-copy.md).

export const SAMPLE_CHUNK = 16384;

// `sample_load_begin`'s refusals, as the status channel names them.
const REFUSALS = { 1: "entries", 2: "length", 3: "memory", 4: "no-store" };

export class SampleLoader {
  constructor(wasm, post) {
    this.wasm = wasm;
    this.post = post;
    this.names = [];
    for (let entry = 0; entry < wasm.sample_bank_count(); entry++) {
      const codes = [];
      for (let i = 0; i < wasm.sample_bank_name_length(entry); i++) codes.push(wasm.sample_bank_name_char(entry, i));
      this.names.push(String.fromCharCode(...codes));
    }
    /** Waveforms waiting to be copied, oldest first; the first may be part copied. */
    this.queue = [];
    /** Name -> the limit its last load exceeded. */
    this.overLimit = new Map();
    /** Names a load named that are not in the bank. */
    this.unknown = new Set();
  }

  /**
   * Queue a `{ type: "sample-load", name, data: Float32Array }` message. A
   * bank sample's root pitch comes from the engine; `rootPitch` is for others.
   */
  enqueue(message) {
    const { name, data } = message;
    const rootPitch = message.rootPitch ?? 60;
    if (typeof name !== "string" || !(data instanceof Float32Array) ||
        typeof rootPitch !== "number" || !Number.isFinite(rootPitch)) {
      this.post({ type: "error", message: "invalid sample-load message" });
      return;
    }
    const entry = this.names.indexOf(name);
    if (entry < 0) this.unknown.add(name);
    else this.queue.push({ entry, name, rootPitch, data, offset: -1 });
    this.report();
  }

  /**
   * Copy at most `budget` samples, finishing waveforms in order. Call once
   * per render quantum, before rendering, so a finished waveform plays from
   * this block on. Allocates nothing while copying.
   */
  step(budget = SAMPLE_CHUNK) {
    let changed = false;
    while (budget > 0 && this.queue.length > 0) {
      const load = this.queue[0];
      if (load.offset < 0) {
        const refusal = this.wasm.sample_load_begin(load.entry, load.data.length, load.rootPitch);
        if (refusal !== 0) {
          this.overLimit.set(load.name, REFUSALS[refusal] ?? "unknown");
          this.queue.shift();
          changed = true;
          continue;
        }
        this.overLimit.delete(load.name);
        load.offset = 0;
      }
      const { data } = load;
      const end = Math.min(data.length, load.offset + budget);
      for (let i = load.offset; i < end; i++) this.wasm.sample_load_write(i, data[i]);
      budget -= end - load.offset;
      load.offset = end;
      if (end === data.length) {
        this.wasm.sample_load_commit();
        this.queue.shift();
        changed = true;
      }
    }
    if (changed) this.report();
  }

  /** What the page shows: samples still loading, and loads that failed. */
  status() {
    return {
      type: "sample-status",
      loading: [...new Set(this.queue.map(load => load.name))],
      overLimit: [...this.overLimit].map(([name, limit]) => ({ name, limit })),
      unknown: [...this.unknown],
    };
  }

  report() {
    this.post(this.status());
  }
}
