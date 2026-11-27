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
    /** Names the page is still fetching or decoding. */
    this.pending = new Set();
    /** Name -> why the page could not fetch or decode it. */
    this.failed = new Map();
  }

  /**
   * Take a message about bank samples: `sample-pending` and `sample-failed`
   * from the page, which fetches and decodes, a `sample-load`, or
   * `sample-report`, which asks for the current status: reports go out only
   * when it changes, so a page that missed them asks again.
   */
  receive(message) {
    const { type, name } = message;
    if (type === "sample-report") {
      this.report();
      return;
    }
    if (typeof name !== "string" || (type === "sample-failed" && typeof message.reason !== "string")) {
      this.post({ type: "error", message: `invalid ${type} message` });
      return;
    }
    if (type === "sample-load") {
      this.enqueue(message);
      return;
    }
    if (!this.names.includes(name)) this.unknown.add(name);
    else if (type === "sample-pending") {
      this.pending.add(name);
      this.failed.delete(name);
    } else {
      this.pending.delete(name);
      this.failed.set(name, message.reason);
    }
    this.report();
  }

  /**
   * Queue a `{ type: "sample-load", name, data: Float32Array }` message. The
   * engine knows each bank sample's root pitch.
   */
  enqueue(message) {
    const { name, data } = message;
    if (typeof name !== "string" || !(data instanceof Float32Array)) {
      this.post({ type: "error", message: "invalid sample-load message" });
      return;
    }
    const entry = this.names.indexOf(name);
    this.pending.delete(name);
    this.failed.delete(name);
    if (entry < 0) this.unknown.add(name);
    else this.queue.push({ entry, name, data, offset: -1 });
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
        const refusal = this.wasm.sample_load_begin(load.entry, load.data.length);
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

  /**
   * What the page shows: samples still loading, whether the page is fetching
   * them or they wait to be copied, and loads that failed.
   */
  status() {
    return {
      type: "sample-status",
      loading: [...new Set([...this.pending, ...this.queue.map(load => load.name)])],
      failed: [...this.failed].map(([name, reason]) => ({ name, reason })),
      overLimit: [...this.overLimit].map(([name, limit]) => ({ name, limit })),
      unknown: [...this.unknown],
    };
  }

  report() {
    this.post(this.status());
  }
}
