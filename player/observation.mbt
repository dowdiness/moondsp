///|
/// Observations a player keeps between reads, per kind.
const OBSERVATION_CAPACITY : Int32 = 256

///|
/// The tracked onsets a player dispatched since the last `clear`, oldest
/// first, while `Player::observe_onsets` is on. It keeps the newest 256 and
/// counts the ones it overwrote. Its storage is allocated with the player;
/// recording allocates nothing.
pub struct Onsets {
  priv mut head : Int32
  priv mut count : Int32
  priv mut dropped : Int32
  priv samples : FixedArray[Int64]
  priv sources : FixedArray[@pattern.EventWithOrigin[@score.ScoreEvent]?]
}

///|
fn Onsets::Onsets() -> Onsets {
  {
    head: 0,
    count: 0,
    dropped: 0,
    samples: FixedArray::make(OBSERVATION_CAPACITY, 0L),
    sources: FixedArray::make(OBSERVATION_CAPACITY, None),
  }
}

///|
pub fn Onsets::count(self : Onsets) -> Int32 {
  self.count
}

///|
/// The sample the `index`-th onset sounds at, for `index < count()`.
pub fn Onsets::sample(self : Onsets, index : Int32) -> Int64 {
  self.samples[ring_slot(self.head, self.count, index)]
}

///|
/// The tracked event of the `index`-th onset, for `index < count()`: its
/// source origin, source frame and local start, and what it plays.
pub fn Onsets::source(
  self : Onsets,
  index : Int32,
) -> @pattern.EventWithOrigin[@score.ScoreEvent] {
  match self.sources[ring_slot(self.head, self.count, index)] {
    Some(source) => source
    None => abort("a recorded onset has its event")
  }
}

///|
/// Onsets overwritten since the last `clear`.
pub fn Onsets::dropped(self : Onsets) -> Int32 {
  self.dropped
}

///|
pub fn Onsets::clear(self : Onsets) -> Unit {
  self.head = 0
  self.count = 0
  self.dropped = 0
}

///|
fn Onsets::record(
  self : Onsets,
  sample : Int64,
  source : @pattern.EventWithOrigin[@score.ScoreEvent],
) -> Unit {
  let slot = ring_push(self.head, self.count)
  if self.count == OBSERVATION_CAPACITY {
    self.head = (self.head + 1) % OBSERVATION_CAPACITY
    self.dropped += 1
  } else {
    self.count += 1
  }
  self.samples[slot] = sample
  self.sources[slot] = Some(source)
}

///|
/// The values sounding voices read from the authored signals they follow,
/// one per signal and material time at each block start, since the last
/// `clear`, oldest first, while `Player::observe_signals` is on. It keeps the
/// newest 256 and counts the ones it overwrote or could not observe. Its
/// storage is allocated with the player; recording allocates nothing.
pub struct SignalValues {
  priv mut head : Int32
  priv mut count : Int32
  priv mut dropped : Int32
  priv samples : FixedArray[Int64]
  priv signals : FixedArray[@identity.SourceAtomId?]
  priv materials : FixedArray[Double]
  priv values : FixedArray[Double]
}

///|
fn SignalValues::SignalValues() -> SignalValues {
  {
    head: 0,
    count: 0,
    dropped: 0,
    samples: FixedArray::make(OBSERVATION_CAPACITY, 0L),
    signals: FixedArray::make(OBSERVATION_CAPACITY, None),
    materials: FixedArray::make(OBSERVATION_CAPACITY, 0.0),
    values: FixedArray::make(OBSERVATION_CAPACITY, 0.0),
  }
}

///|
pub fn SignalValues::count(self : SignalValues) -> Int32 {
  self.count
}

///|
/// The sample of the block start the `index`-th value was read at, for
/// `index < count()`.
pub fn SignalValues::sample(self : SignalValues, index : Int32) -> Int64 {
  self.samples[ring_slot(self.head, self.count, index)]
}

///|
/// The source atom of the signal the `index`-th value comes from.
pub fn SignalValues::signal(
  self : SignalValues,
  index : Int32,
) -> @identity.SourceAtomId {
  match self.signals[ring_slot(self.head, self.count, index)] {
    Some(signal) => signal
    None => abort("a recorded value has its signal")
  }
}

///|
/// The time, in cycles of the material that dispatched the reading voice's
/// note, the `index`-th value was read at.
pub fn SignalValues::material(self : SignalValues, index : Int32) -> Double {
  self.materials[ring_slot(self.head, self.count, index)]
}

///|
/// The `index`-th value.
pub fn SignalValues::value(self : SignalValues, index : Int32) -> Double {
  self.values[ring_slot(self.head, self.count, index)]
}

///|
/// Values overwritten, or signals the player could not observe, since the
/// last `clear`.
pub fn SignalValues::dropped(self : SignalValues) -> Int32 {
  self.dropped
}

///|
/// Forget recorded values; followed voices keep being observed.
pub fn SignalValues::clear(self : SignalValues) -> Unit {
  self.head = 0
  self.count = 0
  self.dropped = 0
}

///|
fn SignalValues::record(
  self : SignalValues,
  sample : Int64,
  signal : @identity.SourceAtomId,
  material : Double,
  value : Double,
) -> Unit {
  let slot = ring_push(self.head, self.count)
  if self.count == OBSERVATION_CAPACITY {
    self.head = (self.head + 1) % OBSERVATION_CAPACITY
    self.dropped += 1
  } else {
    self.count += 1
  }
  self.samples[slot] = sample
  self.signals[slot] = Some(signal)
  self.materials[slot] = material
  self.values[slot] = value
}

///|
/// The storage slot of the `index`-th of `count` observations from `head`.
fn ring_slot(head : Int32, count : Int32, index : Int32) -> Int32 {
  guard index >= 0 && index < count else {
    abort("observation index \{index} out of 0..<\{count}")
  }
  (head + index) % OBSERVATION_CAPACITY
}

///|
/// The storage slot the next observation takes: past the newest, or over
/// the oldest when full.
fn ring_push(head : Int32, count : Int32) -> Int32 {
  (head + count) % OBSERVATION_CAPACITY
}

///|
/// What the player's scheduler reports, kept in the player's rings.
priv struct Observations {
  onsets : Onsets
  signals : SignalValues
}

///|
impl @scheduler.PlaybackObserver for Observations with fn onset(
  self,
  sample,
  source,
) {
  self.onsets.record(sample, source)
}

///|
impl @scheduler.PlaybackObserver for Observations with fn signal(
  self,
  sample,
  signal,
  material,
  value,
) {
  self.signals.record(sample, signal, material, value)
}

///|
impl @scheduler.PlaybackObserver for Observations with fn signal_lost(self) {
  self.signals.dropped += 1
}
