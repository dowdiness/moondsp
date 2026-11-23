///|
/// Followed signals of sounding voices one buffer tracks at once.
const SIGNAL_FOLLOWER_CAPACITY : Int32 = 64

///|
const SIGNAL_RING_CAPACITY : Int32 = 256

///|
/// `[sample, source epoch, source serial, material time in cycles, value]`.
const SIGNAL_ROW_WIDTH : Int32 = 5

///|
/// Fixed-capacity scalar storage for opt-in observation of the values sounding
/// voices follow from authored signals. Its allocations happen when the player
/// creates it; recording and observing a block allocate nothing themselves.
/// Each block records one row per signal and material: the value a voice
/// following it reads at the block start, on the clock of the material that
/// dispatched its note. The voice pools own which voices still follow what;
/// a follower here only names one, so it ends exactly when the voice does.
pub struct SignalBuffer {
  priv mut enabled : Bool
  priv mut head : Int32
  priv mut count : Int32
  priv mut dropped_count : Int32
  priv rows : Array[Double]
  priv mut followers : Int32
  /// Per follower: the `index`-th follower of the voice behind `handle` in
  /// the pool of `instrument`, and the signal it reads.
  priv instruments : FixedArray[Int32]
  priv handles : FixedArray[@moondsp.VoiceHandle?]
  priv indices : FixedArray[Int32]
  priv epochs : FixedArray[Int64]
  priv serials : FixedArray[Int64]
  /// Playback cycle `t` is material time `(t - origin) * rate`.
  priv origins : FixedArray[Double]
  priv rates : FixedArray[Double]
}

///|
pub fn SignalBuffer::SignalBuffer() -> SignalBuffer {
  {
    enabled: false,
    head: 0,
    count: 0,
    dropped_count: 0,
    rows: Array::make(SIGNAL_RING_CAPACITY * SIGNAL_ROW_WIDTH, 0.0),
    followers: 0,
    instruments: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0),
    handles: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, None),
    indices: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0),
    epochs: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0L),
    serials: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0L),
    origins: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0.0),
    rates: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 1.0),
  }
}

///|
pub fn SignalBuffer::enable(self : SignalBuffer, enabled : Bool) -> Unit {
  self.enabled = enabled
  if !enabled {
    self.followers = 0
  }
}

///|
pub fn SignalBuffer::count(self : SignalBuffer) -> Int32 {
  self.count
}

///|
/// Read one scalar field of a recorded row.
pub fn SignalBuffer::field(
  self : SignalBuffer,
  index : Int32,
  field : Int32,
) -> Double {
  if index < 0 || index >= self.count || field < 0 || field >= SIGNAL_ROW_WIDTH {
    return 0.0
  }
  self.rows[(self.head + index) % SIGNAL_RING_CAPACITY * SIGNAL_ROW_WIDTH +
  field]
}

///|
/// Forget recorded rows; followed voices keep being observed.
pub fn SignalBuffer::clear(self : SignalBuffer) -> Unit {
  self.head = 0
  self.count = 0
  self.dropped_count = 0
}

///|
/// Rows the ring overwrote or could not record since the last clear.
pub fn SignalBuffer::dropped(self : SignalBuffer) -> Double {
  self.dropped_count.to_double()
}

///|
/// Observe the authored signals the voice behind `handle`, in the pool of
/// `instrument`, follows, as its note's `controls` give them, for as long as
/// the voice follows them.
fn SignalBuffer::follow(
  self : SignalBuffer,
  controls : @pattern.Controls,
  pool : @moondsp.BoundVoicePool,
  instrument : Int32,
  handle : @moondsp.VoiceHandle,
) -> Unit {
  guard self.enabled else { return }
  let mut index = 0
  while pool.followed(handle, index) is Some(follower) {
    index += 1
    guard controls.signal_source(follower.key()) is Some(source) else {
      continue
    }
    guard origin_id_is_wire_safe(source.epoch().serial()) &&
      origin_id_is_wire_safe(source.serial()) else {
      self.dropped_count += 1
      continue
    }
    guard self.followers < SIGNAL_FOLLOWER_CAPACITY else {
      self.dropped_count += 1
      continue
    }
    let slot = self.followers
    self.followers += 1
    self.instruments[slot] = instrument
    self.handles[slot] = Some(handle)
    self.indices[slot] = index - 1
    self.epochs[slot] = source.epoch().serial()
    self.serials[slot] = source.serial()
    // As doubles, so observing a block needs no exact arithmetic.
    self.origins[slot] = controls.material_origin().to_double()
    self.rates[slot] = controls.material_rate().to_double()
  }
}

///|
/// Record what each followed signal gives at the block that starts at
/// playback time `at` and sample `sample`, once per signal and material, and
/// stop observing voices of `pools` that no longer follow it.
fn SignalBuffer::observe(
  self : SignalBuffer,
  pools : Array[@moondsp.BoundVoicePool],
  at : @pattern.Rational,
  sample : Int64,
) -> Unit {
  guard self.enabled && self.followers > 0 else { return }
  let cycle = at.num.to_double() / at.den.to_double()
  // Rows this block recorded: the newest ones, even after the ring overwrote.
  let mut block_rows = 0
  let mut slot = 0
  while slot < self.followers {
    guard self.handles[slot] is Some(handle) &&
      pools[self.instruments[slot]].followed(handle, self.indices[slot])
      is Some(follower) else {
      // Swap in the last follower; its slot is checked next.
      let last = self.followers - 1
      self.instruments[slot] = self.instruments[last]
      self.handles[slot] = self.handles[last]
      self.indices[slot] = self.indices[last]
      self.epochs[slot] = self.epochs[last]
      self.serials[slot] = self.serials[last]
      self.origins[slot] = self.origins[last]
      self.rates[slot] = self.rates[last]
      self.followers = last
      continue
    }
    let material = (cycle - self.origins[slot]) * self.rates[slot]
    if !self.recorded_in_block(
        block_rows,
        self.epochs[slot],
        self.serials[slot],
        material,
      ) {
      let value = follower.read()(at.num, at.den)
      if !value.is_absent() &&
        self.record(
          sample,
          self.epochs[slot],
          self.serials[slot],
          material,
          value.unwrap_or(0.0),
        ) {
        block_rows += 1
      }
    }
    slot += 1
  }
}

///|
/// Whether one of the newest `block_rows` rows is for the signal `epoch` and
/// `serial` name at `material` time: chord tones following one signal give
/// one row.
fn SignalBuffer::recorded_in_block(
  self : SignalBuffer,
  block_rows : Int32,
  epoch : Int64,
  serial : Int64,
  material : Double,
) -> Bool {
  for index in (self.count - block_rows)..<self.count {
    let base = (self.head + index) % SIGNAL_RING_CAPACITY * SIGNAL_ROW_WIDTH
    if self.rows[base + 1] == epoch.to_double() &&
      self.rows[base + 2] == serial.to_double() &&
      self.rows[base + 3] == material {
      return true
    }
  }
  false
}

///|
/// Record a row; false when its sample cannot cross the wire.
fn SignalBuffer::record(
  self : SignalBuffer,
  sample : Int64,
  epoch : Int64,
  serial : Int64,
  material : Double,
  value : Double,
) -> Bool {
  guard origin_id_is_wire_safe(sample) else {
    self.dropped_count += 1
    return false
  }
  let slot = (self.head + self.count) % SIGNAL_RING_CAPACITY
  if self.count == SIGNAL_RING_CAPACITY {
    self.head = (self.head + 1) % SIGNAL_RING_CAPACITY
    self.dropped_count += 1
  } else {
    self.count += 1
  }
  let base = slot * SIGNAL_ROW_WIDTH
  self.rows[base] = sample.to_double()
  self.rows[base + 1] = epoch.to_double()
  self.rows[base + 2] = serial.to_double()
  self.rows[base + 3] = material
  self.rows[base + 4] = value
  true
}

///|
/// Attach the player-owned signal buffer to a route scheduler. Default
/// schedulers have no observation storage or overhead.
pub fn PatternScheduler::attach_signal_buffer(
  self : PatternScheduler,
  buffer : SignalBuffer,
) -> Unit {
  self.signals = Some(buffer)
}
