// Shared observation only: the producer never waits, allocates, or posts messages.
// Slot ownership: free(0), writing(1), ready(2), reading(3). A slow reader can
// retain one slot without blocking audio; newer observations replace unread ones.
export const ONSET_CAPACITY = 256;
export const ONSET_FIELDS = 103;
const STRIDE = ONSET_FIELDS + 1;
const HEADER_WORDS = 4;
const CONTROL_BYTES = (HEADER_WORDS + ONSET_CAPACITY) * Int32Array.BYTES_PER_ELEMENT;
export const ONSET_BYTES = CONTROL_BYTES + ONSET_CAPACITY * STRIDE * Float64Array.BYTES_PER_ELEMENT;

export class OnsetRing {
  constructor(buffer) {
    if (buffer.byteLength !== ONSET_BYTES) throw new RangeError("Invalid onset observation buffer");
    this.buffer = buffer;
    this.control = new Int32Array(buffer, 0, HEADER_WORDS + ONSET_CAPACITY);
    this.rows = new Float64Array(buffer, CONTROL_BYTES);
    this.cursor = 0;
  }

  write(wasm, engineBlockStart, audioBlockTime, sampleRate, generation) {
    const count = wasm.player_onset_count();
    for (let index = 0; index < count; index++) {
      const slot = this.cursor;
      this.cursor = (slot + 1) % ONSET_CAPACITY;
      const lock = HEADER_WORDS + slot;
      const previous = Atomics.load(this.control, lock);
      if ((previous !== 0 && previous !== 2) || Atomics.compareExchange(this.control, lock, previous, 1) !== previous) {
        Atomics.add(this.control, 2, 1);
        continue;
      }
      if (previous === 2) Atomics.add(this.control, 1, 1);
      const base = slot * STRIDE;
      const bindings = wasm.player_onset_field(index, 6);
      if (!Number.isInteger(bindings) || bindings < 0 || bindings > 32) {
        Atomics.store(this.control, lock, 0);
        continue;
      }
      this.rows[base] = audioBlockTime + (wasm.player_onset_field(index, 0) - engineBlockStart) / sampleRate;
      for (let field = 1; field < 7 + bindings * 3; field++) {
        this.rows[base + field] = wasm.player_onset_field(index, field);
      }
      this.rows[base + ONSET_FIELDS] = generation;
      Atomics.store(this.control, lock, 2);
      Atomics.add(this.control, 0, 1);
    }
    Atomics.add(this.control, 3, wasm.player_onset_dropped() | 0);
    wasm.player_onset_clear();
  }

  // Main thread only. Copies while owning each slot, so concurrent Float64
  // reads/writes cannot tear even when the producer wraps around the ring.
  read(generation) {
    const observations = [];
    for (let slot = 0; slot < ONSET_CAPACITY; slot++) {
      const lock = HEADER_WORDS + slot;
      if (Atomics.compareExchange(this.control, lock, 2, 3) !== 2) continue;
      try {
        const base = slot * STRIDE;
        if (this.rows[base + ONSET_FIELDS] !== generation) continue;
        const bindings = this.rows[base + 6];
        if (!Number.isInteger(bindings) || bindings < 0 || bindings > 32) continue;
        observations.push(Array.from(this.rows.subarray(base, base + 7 + bindings * 3)));
      } finally {
        Atomics.store(this.control, lock, 0);
      }
    }
    return observations;
  }

  statistics() {
    return {
      written: Atomics.load(this.control, 0) >>> 0,
      overwritten: Atomics.load(this.control, 1) >>> 0,
      busy: Atomics.load(this.control, 2) >>> 0,
      engineDropped: Atomics.load(this.control, 3) >>> 0,
    };
  }
}
