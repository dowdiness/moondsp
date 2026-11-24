///|
/// Plays one waveform of a `SampleStore` (ADR-0026).
///
/// The player takes its waveform from the store the first time it renders
/// after a reset, or when its sample number changes, and keeps it: a waveform
/// the store replaces later plays to its end. Its state is that waveform and
/// a read position, and `reset` clears both.
pub struct SamplePlayer {
  priv store : SampleStore
  priv mut bound : Bool
  priv mut number : Double
  priv mut start : Int32
  /// 0 when the sample number had no waveform.
  priv mut length : Int32
  priv mut root : Double
  priv mut position : Double
  /// Whether `rate` was computed from `pitch` and `speed` and the root.
  priv mut rate_known : Bool
  priv mut pitch : Double
  priv mut speed : Double
  /// Waveform samples advanced per output sample.
  priv mut rate : Double
}

///|
pub fn SamplePlayer::SamplePlayer(store : SampleStore) -> SamplePlayer {
  {
    store,
    bound: false,
    number: 0.0,
    start: 0,
    length: 0,
    root: 0.0,
    position: 0.0,
    rate_known: false,
    pitch: 0.0,
    speed: 0.0,
    rate: 0.0,
  }
}

///|
/// Forget the waveform and the read position.
pub fn SamplePlayer::reset(self : SamplePlayer) -> Unit {
  self.bound = false
  self.number = 0.0
  self.start = 0
  self.length = 0
  self.root = 0.0
  self.position = 0.0
  self.rate_known = false
  self.rate = 0.0
}

///|
/// Copy the waveform and read position from another player of the same
/// store, so a graph that replaces another keeps playing. A player of another
/// store copies nothing: its waveform is not in this store's memory.
pub fn SamplePlayer::copy_state_from(
  self : SamplePlayer,
  source : SamplePlayer,
) -> Unit {
  if physical_equal(self.store, source.store) {
    self.bound = source.bound
    self.number = source.number
    self.start = source.start
    self.length = source.length
    self.root = source.root
    self.position = source.position
    self.rate_known = source.rate_known
    self.pitch = source.pitch
    self.speed = source.speed
    self.rate = source.rate
  }
}

///|
fn SamplePlayer::bind(
  self : SamplePlayer,
  number : Double,
  speed : Double,
) -> Unit {
  let store = self.store
  let entry = number.to_int()
  self.bound = true
  self.number = number
  if entry.to_double() == number && store.has(entry) {
    self.start = store.starts[entry]
    self.length = store.lengths[entry]
    self.root = store.roots[entry]
  } else {
    self.start = 0
    self.length = 0
    self.root = 0.0
  }
  self.position = if speed < 0.0 { (self.length - 1).to_double() } else { 0.0 }
  // The root may differ, so the next tick recomputes the rate.
  self.rate_known = false
}

///|
/// The next sample of sample `number` at MIDI pitch `pitch`, times `speed`,
/// read from the read position with linear interpolation. A waveform plays at
/// its recorded rate at its root pitch and speed 1; a negative speed plays
/// backwards. Outside the first and last samples, or for a number with no
/// waveform, it is 0.
pub fn SamplePlayer::tick(
  self : SamplePlayer,
  number~ : Double,
  pitch~ : Double,
  speed~ : Double,
) -> Double {
  if !self.bound || self.number != number {
    self.bind(number, speed)
  }
  if !self.rate_known || pitch != self.pitch || speed != self.speed {
    self.rate_known = true
    let rate = @math.pow(2.0, (pitch - self.root) / 12.0) * speed
    self.pitch = pitch
    self.speed = speed
    self.rate = if is_finite(rate) { rate } else { 0.0 }
  }
  let position = self.position
  let last = self.length - 1
  guard position >= 0.0 && position <= last.to_double() else { return 0.0 }
  let memory = self.store.memory
  let whole = position.to_int()
  let fraction = position - whole.to_double()
  let current = memory[self.start + whole].to_double()
  self.position = position + self.rate
  if fraction == 0.0 {
    current
  } else {
    // A fractional position at most `last` lies before the last sample.
    let next = memory[self.start + whole + 1].to_double()
    current + (next - current) * fraction
  }
}

///|
/// Fill `output` with the next samples, as `tick` makes them.
pub fn SamplePlayer::process(
  self : SamplePlayer,
  context : DspContext,
  output : AudioBuffer,
  number~ : Double,
  pitch~ : Double,
  speed~ : Double,
) -> Unit {
  let sample_count = effective_sample_count(context, output)
  for index in 0..<sample_count {
    output.set(index, self.tick(number~, pitch~, speed~))
  }
  for index in sample_count..<output.length() {
    output.set(index, 0.0)
  }
}
