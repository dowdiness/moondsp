///|
const ONSET_RING_CAPACITY : Int = 256

///|
const ONSET_ROW_WIDTH : Int = 103

///|
const ONSET_MAX_BINDINGS : Int = 32

///|
/// Fixed-capacity scalar storage for opt-in dispatched-onset observation.
/// Its sole allocation happens when the player creates the buffer.
pub struct OnsetBuffer {
  priv mut enabled : Bool
  priv mut head : Int
  priv mut count : Int
  priv mut dropped_count : Int
  priv rows : Array[Double]
}

///|
pub fn OnsetBuffer::new() -> OnsetBuffer {
  {
    enabled: false,
    head: 0,
    count: 0,
    dropped_count: 0,
    rows: Array::make(ONSET_RING_CAPACITY * ONSET_ROW_WIDTH, 0.0),
  }
}

///|
pub fn OnsetBuffer::enable(self : OnsetBuffer, enabled : Bool) -> Unit {
  self.enabled = enabled
}

///|
pub fn OnsetBuffer::count(self : OnsetBuffer) -> Int {
  self.count
}

///|
/// Read one scalar field without allocating or copying a path.
pub fn OnsetBuffer::field(
  self : OnsetBuffer,
  index : Int,
  field : Int,
) -> Double {
  if index < 0 || index >= self.count || field < 0 || field >= ONSET_ROW_WIDTH {
    return 0.0
  }
  let base = (self.head + index) % ONSET_RING_CAPACITY * ONSET_ROW_WIDTH
  if field >= 7 && field >= 7 + self.rows[base + 6].to_int() * 3 {
    return 0.0
  }
  self.rows[base + field]
}

///|
pub fn OnsetBuffer::clear(self : OnsetBuffer) -> Unit {
  self.head = 0
  self.count = 0
  self.dropped_count = 0
}

///|
pub fn OnsetBuffer::dropped(self : OnsetBuffer) -> Double {
  self.dropped_count.to_double()
}

///|
fn origin_id_is_wire_safe(value : Int64) -> Bool {
  value >= 0L && value <= 9007199254740991L
}

///|
fn OnsetBuffer::record(
  self : OnsetBuffer,
  sample : Int64,
  origin : @pattern.EventOrigin?,
  source_frame? : @identity.SourceFrameId? = None,
  source_start? : Double = -1.0,
  source_pitch? : Double = -1.0,
) -> Unit {
  if !self.enabled {
    return
  }
  guard origin is Some(origin) else { return }
  if !origin_id_is_wire_safe(sample) ||
    !origin_id_is_wire_safe(origin.atom().epoch().serial()) ||
    !origin_id_is_wire_safe(origin.atom().serial()) {
    self.dropped_count += 1
    return
  }
  if source_frame is Some(frame) &&
    (
      frame.epoch() != origin.atom().epoch() ||
      !origin_id_is_wire_safe(frame.serial())
    ) {
    self.dropped_count += 1
    return
  }
  let slot = (self.head + self.count) % ONSET_RING_CAPACITY
  let base = slot * ONSET_ROW_WIDTH
  let binding_count = origin.write_binding_serials(
    self.rows,
    base + 7,
    ONSET_MAX_BINDINGS,
  )
  if binding_count < 0 {
    self.dropped_count += 1
    return
  }
  if self.count == ONSET_RING_CAPACITY {
    self.head = (self.head + 1) % ONSET_RING_CAPACITY
    self.dropped_count += 1
  } else {
    self.count += 1
  }
  self.rows[base] = sample.to_double()
  self.rows[base + 1] = origin.atom().epoch().serial().to_double()
  self.rows[base + 2] = origin.atom().serial().to_double()
  self.rows[base + 3] = match source_frame {
    Some(frame) => frame.serial().to_double()
    None => 0.0
  }
  self.rows[base + 4] = source_start
  self.rows[base + 5] = source_pitch
  self.rows[base + 6] = binding_count.to_double()
}

///|
/// Attach the player-owned ring to a route scheduler. Default schedulers have
/// no observation storage or recording overhead.
pub fn PatternScheduler::attach_onset_buffer(
  self : PatternScheduler,
  buffer : OnsetBuffer,
) -> Unit {
  self.onsets = Some(buffer)
}
