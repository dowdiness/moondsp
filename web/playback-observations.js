// Shared observation rings from the scheduler Worklet to the main thread. The
// producer never waits, allocates, or posts messages. Slot ownership: free(0),
// writing(1), ready(2), reading(3). A slow reader can retain one slot without
// blocking audio; newer observations replace unread ones.
//
// Each slot holds one row of at most `fields` doubles and its observation
// generation. Header counters: written, overwritten, reader busy, engine drops.
const HEADER_WORDS = 4;

const ringBytes = (capacity, fields) =>
  (HEADER_WORDS + capacity) * Int32Array.BYTES_PER_ELEMENT + capacity * (fields + 1) * Float64Array.BYTES_PER_ELEMENT;

class ObservationRing {
  constructor(buffer, capacity, fields) {
    if (buffer.byteLength !== ringBytes(capacity, fields)) throw new RangeError("Invalid observation buffer");
    this.buffer = buffer;
    this.capacity = capacity;
    this.fields = fields;
    this.control = new Int32Array(buffer, 0, HEADER_WORDS + capacity);
    this.rows = new Float64Array(buffer, (HEADER_WORDS + capacity) * Int32Array.BYTES_PER_ELEMENT);
    this.cursor = 0;
  }

  // Audio thread. `fill(index, rows, base)` writes row `index` at `base` and
  // returns false to discard it.
  writeRows(count, fill, engineDropped, generation) {
    const stride = this.fields + 1;
    for (let index = 0; index < count; index++) {
      const slot = this.cursor;
      this.cursor = (slot + 1) % this.capacity;
      const lock = HEADER_WORDS + slot;
      const previous = Atomics.load(this.control, lock);
      if ((previous !== 0 && previous !== 2) || Atomics.compareExchange(this.control, lock, previous, 1) !== previous) {
        Atomics.add(this.control, 2, 1);
        continue;
      }
      if (previous === 2) Atomics.add(this.control, 1, 1);
      const base = slot * stride;
      if (!fill(index, this.rows, base)) {
        Atomics.store(this.control, lock, 0);
        continue;
      }
      this.rows[base + this.fields] = generation;
      Atomics.store(this.control, lock, 2);
      Atomics.add(this.control, 0, 1);
    }
    Atomics.add(this.control, 3, engineDropped | 0);
  }

  // Main thread only. Copies while owning each slot, so concurrent Float64
  // reads/writes cannot tear even when the producer wraps around the ring.
  // `length(rows, base)` gives the row's field count, or null to skip it.
  readRows(generation, length) {
    const stride = this.fields + 1;
    const observations = [];
    for (let slot = 0; slot < this.capacity; slot++) {
      const lock = HEADER_WORDS + slot;
      if (Atomics.compareExchange(this.control, lock, 2, 3) !== 2) continue;
      try {
        const base = slot * stride;
        if (this.rows[base + this.fields] !== generation) continue;
        const fields = length(this.rows, base);
        if (fields !== null) observations.push(Array.from(this.rows.subarray(base, base + fields)));
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

// Dispatched onsets: [audio time, epoch, atom serial, frame serial, local onset,
// pitch, binding count, then reference/binding/definition serial triples].
export const ONSET_CAPACITY = 256;
export const ONSET_FIELDS = 103;
export const ONSET_BYTES = ringBytes(ONSET_CAPACITY, ONSET_FIELDS);

const onsetLength = bindings => Number.isInteger(bindings) && bindings >= 0 && bindings <= 32 ? 7 + bindings * 3 : null;

export class OnsetRing extends ObservationRing {
  constructor(buffer) { super(buffer, ONSET_CAPACITY, ONSET_FIELDS); }

  write(wasm, engineBlockStart, audioBlockTime, sampleRate, generation) {
    this.writeRows(wasm.player_onset_count(), (index, rows, base) => {
      const fields = onsetLength(wasm.player_onset_field(index, 6));
      if (fields === null) return false;
      rows[base] = audioBlockTime + (wasm.player_onset_field(index, 0) - engineBlockStart) / sampleRate;
      for (let field = 1; field < fields; field++) rows[base + field] = wasm.player_onset_field(index, field);
      return true;
    }, wasm.player_onset_dropped(), generation);
    wasm.player_onset_clear();
  }

  read(generation) {
    return this.readRows(generation, (rows, base) => onsetLength(rows[base + 6]));
  }
}

// Followed signal values at a block start: [audio time, source epoch, source
// serial, material cycles, value].
export const SIGNAL_CAPACITY = 256;
export const SIGNAL_FIELDS = 5;
export const SIGNAL_BYTES = ringBytes(SIGNAL_CAPACITY, SIGNAL_FIELDS);

export class SignalRing extends ObservationRing {
  constructor(buffer) { super(buffer, SIGNAL_CAPACITY, SIGNAL_FIELDS); }

  write(wasm, engineBlockStart, audioBlockTime, sampleRate, generation) {
    this.writeRows(wasm.player_signal_count(), (index, rows, base) => {
      rows[base] = audioBlockTime + (wasm.player_signal_field(index, 0) - engineBlockStart) / sampleRate;
      for (let field = 1; field < SIGNAL_FIELDS; field++) rows[base + field] = wasm.player_signal_field(index, field);
      return true;
    }, wasm.player_signal_dropped(), generation);
    wasm.player_signal_clear();
  }

  read(generation) {
    return this.readRows(generation, () => SIGNAL_FIELDS);
  }
}
