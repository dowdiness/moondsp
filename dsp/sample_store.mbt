///|
/// The limit a registration exceeded (ADR-0026 Decision 6).
#derive(Eq, Debug)
pub(all) enum SampleLimit {
  /// The sample number is outside the store's entries.
  Entries
  /// The waveform is longer than one waveform may be.
  Length
  /// The store has no free memory left for the waveform.
  Memory
}

///|
pub extend SampleLimit with Eq::{not_equal, equal}

///|
pub extend SampleLimit with Debug::{to_repr}

///|
/// Recorded waveforms by sample number, at the engine's sample rate, as 32-bit
/// floats (ADR-0026). The store allocates its memory once, when it is made;
/// registering copies into that memory and allocates nothing, and the
/// renderer only reads it.
///
/// A waveform is registered in three steps so a host can copy it in chunks:
/// `begin`, then `write` for each sample, then `commit`. A voice that started
/// on an entry keeps reading the waveform it started on after the entry is
/// replaced, because a replacement is written to fresh memory.
pub struct SampleStore {
  priv memory : FixedArray[Float]
  priv max_length : Int32
  priv starts : FixedArray[Int32]
  /// The waveform length of each entry; -1 for an entry with no waveform.
  priv lengths : FixedArray[Int32]
  priv roots : FixedArray[Double]
  /// Memory below this is committed or pending.
  priv mut used : Int32
  /// The entry being registered, or -1.
  priv mut pending_entry : Int32
  priv mut pending_start : Int32
  priv mut pending_length : Int32
  priv mut pending_root : Double
}

///|
/// A store of `entries` sample numbers, each waveform at most `max_length`
/// samples long, `capacity` samples in all. Negative sizes count as zero.
pub fn SampleStore::SampleStore(
  entries~ : Int32,
  max_length~ : Int32,
  capacity~ : Int32,
) -> SampleStore {
  let entries = if entries > 0 { entries } else { 0 }
  {
    memory: FixedArray::make(if capacity > 0 { capacity } else { 0 }, 0.0),
    max_length: if max_length > 0 {
      max_length
    } else {
      0
    },
    starts: FixedArray::make(entries, 0),
    lengths: FixedArray::make(entries, -1),
    roots: FixedArray::make(entries, 0.0),
    used: 0,
    pending_entry: -1,
    pending_start: 0,
    pending_length: 0,
    pending_root: 0.0,
  }
}

///|
/// The store of a context made without one: it has no entries, so every
/// registration fails and every sample number plays silence.
let empty_sample_store : SampleStore = SampleStore(
  entries=0,
  max_length=0,
  capacity=0,
)

///|
/// The number of sample numbers.
pub fn SampleStore::entries(self : SampleStore) -> Int32 {
  self.lengths.length()
}

///|
/// The number of samples the store holds in all.
pub fn SampleStore::capacity(self : SampleStore) -> Int32 {
  self.memory.length()
}

///|
/// Whether `entry` has a committed waveform, so a host can report the samples
/// a score plays that are still loading (ADR-0026 Decision 5).
pub fn SampleStore::has(self : SampleStore, entry : Int32) -> Bool {
  entry >= 0 && entry < self.lengths.length() && self.lengths[entry] >= 0
}

///|
/// Start registering a waveform of `length` samples for `entry`, whose
/// recorded pitch is the MIDI note `root_pitch`. A registration still pending
/// is abandoned and its memory reused. Returns the limit it exceeds, leaving
/// the store unchanged, or `None`.
pub fn SampleStore::begin(
  self : SampleStore,
  entry : Int32,
  length : Int32,
  root_pitch~ : Double,
) -> SampleLimit? {
  if entry < 0 || entry >= self.lengths.length() {
    return Some(Entries)
  }
  if length < 0 || length > self.max_length {
    return Some(Length)
  }
  let start = if self.pending_entry >= 0 {
    self.pending_start
  } else {
    self.used
  }
  if length > self.memory.length() - start {
    return Some(Memory)
  }
  self.used = start + length
  self.pending_entry = entry
  self.pending_start = start
  self.pending_length = length
  self.pending_root = root_pitch
  None
}

///|
/// Write sample `offset` of the pending waveform. A non-finite value writes
/// 0; an offset outside the waveform, or no pending registration, writes
/// nothing.
pub fn SampleStore::write(
  self : SampleStore,
  offset : Int32,
  value : Float,
) -> Unit {
  if self.pending_entry >= 0 && offset >= 0 && offset < self.pending_length {
    self.memory[self.pending_start + offset] = if value.is_nan() ||
      value.is_inf() {
      0.0
    } else {
      value
    }
  }
}

///|
/// Make the pending waveform the entry's waveform. Returns false when no
/// registration is pending.
///
/// The memory of a waveform it replaces is not reused yet: only the sampler
/// pool can tell when no voice reads it (ADR-0026, stage 4).
pub fn SampleStore::commit(self : SampleStore) -> Bool {
  let entry = self.pending_entry
  guard entry >= 0 else { return false }
  self.starts[entry] = self.pending_start
  self.lengths[entry] = self.pending_length
  self.roots[entry] = self.pending_root
  self.pending_entry = -1
  true
}

///|
/// Register `data` for `entry` in one call: `begin`, a `write` per sample,
/// and `commit`.
pub fn SampleStore::register(
  self : SampleStore,
  entry : Int32,
  data : FixedArray[Float],
  root_pitch~ : Double,
) -> SampleLimit? {
  match self.begin(entry, data.length(), root_pitch~) {
    Some(limit) => Some(limit)
    None => {
      for offset in 0..<data.length() {
        self.write(offset, data[offset])
      }
      ignore(self.commit())
      None
    }
  }
}
