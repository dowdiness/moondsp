// Shared observation only: the producer never waits, allocates, or posts messages.
// Slot ownership: free(0), writing(1), ready(2), reading(3), as in the onset ring.
// Each row is the value a sounding note follows from one authored signal at a
// block start: [audio time, source epoch, source serial, material cycles, value].
export const SIGNAL_CAPACITY = 256;
export const SIGNAL_FIELDS = 5;
const STRIDE = SIGNAL_FIELDS + 1;
const HEADER_WORDS = 2;
const CONTROL_BYTES = (HEADER_WORDS + SIGNAL_CAPACITY) * Int32Array.BYTES_PER_ELEMENT;
export const SIGNAL_BYTES = CONTROL_BYTES + SIGNAL_CAPACITY * STRIDE * Float64Array.BYTES_PER_ELEMENT;

export class SignalRing {
  constructor(buffer) {
    if (buffer.byteLength !== SIGNAL_BYTES) throw new RangeError("Invalid signal observation buffer");
    this.buffer = buffer;
    this.control = new Int32Array(buffer, 0, HEADER_WORDS + SIGNAL_CAPACITY);
    this.rows = new Float64Array(buffer, CONTROL_BYTES);
    this.cursor = 0;
  }

  write(wasm, engineBlockStart, audioBlockTime, sampleRate, generation) {
    const count = wasm.player_signal_count();
    for (let index = 0; index < count; index++) {
      const slot = this.cursor;
      this.cursor = (slot + 1) % SIGNAL_CAPACITY;
      const lock = HEADER_WORDS + slot;
      const previous = Atomics.load(this.control, lock);
      if ((previous !== 0 && previous !== 2) || Atomics.compareExchange(this.control, lock, previous, 1) !== previous) {
        Atomics.add(this.control, 1, 1);
        continue;
      }
      const base = slot * STRIDE;
      this.rows[base] = audioBlockTime + (wasm.player_signal_field(index, 0) - engineBlockStart) / sampleRate;
      for (let field = 1; field < SIGNAL_FIELDS; field++) this.rows[base + field] = wasm.player_signal_field(index, field);
      this.rows[base + SIGNAL_FIELDS] = generation;
      Atomics.store(this.control, lock, 2);
      Atomics.add(this.control, 0, 1);
    }
    Atomics.add(this.control, 1, wasm.player_signal_dropped() | 0);
    wasm.player_signal_clear();
  }

  // Main thread only. Copies while owning each slot, so reads cannot tear.
  read(generation) {
    const observations = [];
    for (let slot = 0; slot < SIGNAL_CAPACITY; slot++) {
      const lock = HEADER_WORDS + slot;
      if (Atomics.compareExchange(this.control, lock, 2, 3) !== 2) continue;
      try {
        const base = slot * STRIDE;
        if (this.rows[base + SIGNAL_FIELDS] === generation) observations.push(Array.from(this.rows.subarray(base, base + SIGNAL_FIELDS)));
      } finally {
        Atomics.store(this.control, lock, 0);
      }
    }
    return observations;
  }

  statistics() {
    return { written: Atomics.load(this.control, 0) >>> 0, dropped: Atomics.load(this.control, 1) >>> 0 };
  }
}
