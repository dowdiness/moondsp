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
/// What a memory block of a `SampleStore` holds.
priv enum SampleBlock {
  /// The slot describes no block.
  Unused
  Free
  /// The waveform of an entry, or one being registered.
  Live
  /// A waveform its entry replaced, kept while players read it.
  Retired
}

///|
/// Recorded waveforms by sample number, at the engine's sample rate, as 32-bit
/// floats (ADR-0026). The store allocates its memory once, when it is made;
/// registering copies into that memory and allocates nothing, and the
/// renderer only reads it.
///
/// A waveform is registered in three steps so a host can copy it in chunks:
/// `begin`, then `write` for each sample, then `commit`. A voice that started
/// on an entry keeps reading the waveform it started on after the entry is
/// replaced, because a replacement is written to free memory.
///
/// A replaced waveform's memory is free again after a scan finds no player
/// reading it (ADR-0026): `begin_scan`, then `mark_samples` on every graph
/// that reads the store, then `end_scan`. A host scans before it begins a
/// registration. A graph it leaves out of the scan may hear another waveform
/// in memory its own was replaced from.
///
/// Memory is a fixed table of blocks: one per waveform, and free blocks that
/// merge with their free neighbours. The table holds every entry's waveform
/// with as many replaced ones again still sounding; a registration that
/// would need more blocks fails with `Memory`.
pub struct SampleStore {
  priv memory : FixedArray[Float]
  priv max_length : Int32
  priv starts : FixedArray[Int32]
  /// The waveform length of each entry; -1 for an entry with no waveform.
  priv lengths : FixedArray[Int32]
  priv roots : FixedArray[Double]
  /// The block of each entry's waveform, or -1.
  priv blocks : FixedArray[Int32]
  priv block_kind : FixedArray[SampleBlock]
  priv block_start : FixedArray[Int32]
  priv block_length : FixedArray[Int32]
  /// Whether the scan in progress found a player reading each block.
  priv block_marked : FixedArray[Bool]
  /// The entry being registered, or -1.
  priv mut pending_entry : Int32
  /// The pending registration's block, or -1 for an empty waveform.
  priv mut pending_block : Int32
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
  let capacity = if capacity > 0 { capacity } else { 0 }
  // Each entry's waveform, as many retired ones, the pending one, and a free
  // block beside each of them.
  let slots = 4 * entries + 4
  let block_kind = FixedArray::make(slots, SampleBlock::Unused)
  let block_length = FixedArray::make(slots, 0)
  if capacity > 0 {
    block_kind[0] = Free
    block_length[0] = capacity
  }
  {
    memory: FixedArray::make(capacity, 0.0),
    max_length: if max_length > 0 {
      max_length
    } else {
      0
    },
    starts: FixedArray::make(entries, 0),
    lengths: FixedArray::make(entries, -1),
    roots: FixedArray::make(entries, 0.0),
    blocks: FixedArray::make(entries, -1),
    block_kind,
    block_start: FixedArray::make(slots, 0),
    block_length,
    block_marked: FixedArray::make(slots, false),
    pending_entry: -1,
    pending_block: -1,
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
/// Start a scan for the waveforms players read: no block is marked.
pub fn SampleStore::begin_scan(self : SampleStore) -> Unit {
  self.block_marked.fill(false)
}

///|
/// A player reads `block`.
fn SampleStore::mark(self : SampleStore, block : Int32) -> Unit {
  self.block_marked[block] = true
}

///|
/// End a scan: a replaced waveform no player was marked reading is free.
pub fn SampleStore::end_scan(self : SampleStore) -> Unit {
  for block in 0..<self.block_kind.length() {
    if self.block_kind[block] is Retired && !self.block_marked[block] {
      self.free_block(block)
    }
  }
}

///|
/// Mark `block` free and merge it with a free block on either side.
fn SampleStore::free_block(self : SampleStore, block : Int32) -> Unit {
  self.block_kind[block] = Free
  let mut block = block
  for other in 0..<self.block_kind.length() {
    if other != block &&
      self.block_kind[other] is Free &&
      self.block_start[other] + self.block_length[other] ==
      self.block_start[block] {
      self.block_length[other] += self.block_length[block]
      self.block_kind[block] = Unused
      block = other
      break
    }
  }
  for other in 0..<self.block_kind.length() {
    if other != block &&
      self.block_kind[other] is Free &&
      self.block_start[block] + self.block_length[block] ==
      self.block_start[other] {
      self.block_length[block] += self.block_length[other]
      self.block_kind[other] = Unused
      break
    }
  }
}

///|
/// Start registering a waveform of `length` samples for `entry`, whose
/// recorded pitch is the MIDI note `root_pitch`. A registration still pending
/// is abandoned and its memory reused. Returns the limit it exceeds, leaving
/// the registered waveforms unchanged, or `None`. A waveform that needs
/// memory a replaced waveform still holds fails with `Memory`.
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
  if self.pending_entry >= 0 {
    if self.pending_block >= 0 {
      self.free_block(self.pending_block)
    }
    self.pending_entry = -1
  }
  let mut found = -1
  if length > 0 {
    for block in 0..<self.block_kind.length() {
      if self.block_kind[block] is Free && self.block_length[block] >= length {
        found = block
        break
      }
    }
    guard found >= 0 else { return Some(Memory) }
    let rest = self.block_length[found] - length
    if rest > 0 {
      let mut spare = -1
      for slot in 0..<self.block_kind.length() {
        if self.block_kind[slot] is Unused {
          spare = slot
          break
        }
      }
      guard spare >= 0 else { return Some(Memory) }
      self.block_kind[spare] = Free
      self.block_start[spare] = self.block_start[found] + length
      self.block_length[spare] = rest
      self.block_length[found] = length
    }
    self.block_kind[found] = Live
  }
  self.pending_entry = entry
  self.pending_block = found
  self.pending_start = if found >= 0 { self.block_start[found] } else { 0 }
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
/// registration is pending. A waveform it replaces stays readable by the
/// players that read it until a scan finds none does.
pub fn SampleStore::commit(self : SampleStore) -> Bool {
  let entry = self.pending_entry
  guard entry >= 0 else { return false }
  let replaced = self.blocks[entry]
  if replaced >= 0 {
    self.block_kind[replaced] = Retired
  }
  self.blocks[entry] = self.pending_block
  self.starts[entry] = self.pending_start
  self.lengths[entry] = self.pending_length
  self.roots[entry] = self.pending_root
  self.pending_entry = -1
  self.pending_block = -1
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
