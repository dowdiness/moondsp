///|
/// Plays one waveform of a `SampleStore` (ADR-0026).
///
/// The player takes its waveform from the store the first time it renders
/// after a reset, or when its sample number changes, and keeps it: a waveform
/// the store replaces later plays to its end. Its state is that waveform and
/// a read position, and `reset` clears both. The slice follows `begin` and
/// `end` as they arrive; a voice keeps them fixed from its onset because
/// those controls do not follow (`Control::follows`).
///
/// Playback ends when the read position leaves the slice: the player lets go
/// of its waveform and stays silent until it takes one again. Until then,
/// `mark_samples` marks its waveform in a store scan, so the store keeps a
/// replaced waveform's memory while the player reads it.
pub struct SamplePlayer {
  priv store : SampleStore
  priv mut bound : Bool
  priv mut number : Double
  priv mut start : Int32
  /// The store block of its waveform, or -1 when it has none.
  priv mut block : Int32
  /// 0 when it has no waveform.
  priv mut length : Int32
  /// The `begin` and `end` fractions the slice was computed from.
  priv mut begin : Double
  priv mut end : Double
  /// The slice that plays: waveform samples `first` to `last`, inclusive.
  /// Empty when `last < first`.
  priv mut first : Int32
  priv mut last : Int32
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
    block: -1,
    length: 0,
    begin: 0.0,
    end: 1.0,
    first: 0,
    last: -1,
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
  self.block = -1
  self.number = 0.0
  self.start = 0
  self.length = 0
  self.first = 0
  self.last = -1
  self.root = 0.0
  self.position = 0.0
  self.rate_known = false
  self.rate = 0.0
}

///|
/// Copy the waveform and read position from another player of the same
/// store, so a graph that replaces another keeps playing. Both graphs are
/// compiled with the same `DspContext`, so they share its store.
pub fn SamplePlayer::copy_state_from(
  self : SamplePlayer,
  source : SamplePlayer,
) -> Unit {
  self.bound = source.bound
  self.number = source.number
  self.block = source.block
  self.start = source.start
  self.length = source.length
  self.begin = source.begin
  self.end = source.end
  self.first = source.first
  self.last = source.last
  self.root = source.root
  self.position = source.position
  self.rate_known = source.rate_known
  self.pitch = source.pitch
  self.speed = source.speed
  self.rate = source.rate
}

///|
fn SamplePlayer::bind(
  self : SamplePlayer,
  number : Double,
  speed : Double,
  begin : Double,
  end : Double,
) -> Unit {
  let store = self.store
  let entry = number.to_int()
  self.bound = true
  self.number = number
  if entry.to_double() == number && store.has(entry) {
    self.block = store.blocks[entry]
    self.start = store.starts[entry]
    self.length = store.lengths[entry]
    self.root = store.roots[entry]
  } else {
    self.block = -1
    self.start = 0
    self.length = 0
    self.root = 0.0
  }
  self.slice(begin, end)
  self.position = if speed < 0.0 {
    self.last.to_double()
  } else {
    self.first.to_double()
  }

  // The root may differ, so the next tick recomputes the rate.
  self.rate_known = false
}

///|
/// Play waveform samples from `begin × length` up to, not including,
/// `end × length`, each rounded to the nearest sample and clamped to the
/// waveform.
fn SamplePlayer::slice(
  self : SamplePlayer,
  begin : Double,
  end : Double,
) -> Unit {
  self.begin = begin
  self.end = end
  self.first = slice_bound(begin, self.length)
  self.last = slice_bound(end, self.length) - 1
}

///|
/// End playback by letting go of the waveform: once no scan marks it, its
/// memory may hold another one.
fn SamplePlayer::finish(self : SamplePlayer) -> Unit {
  self.block = -1
  self.length = 0
  self.first = 0
  self.last = -1
}

///|
/// Mark the waveform this player holds in a scan of its store
/// (`SampleStore::begin_scan`).
pub fn SamplePlayer::mark_samples(self : SamplePlayer) -> Unit {
  if self.block >= 0 {
    self.store.mark(self.block)
  }
}

///|
/// The waveform sample nearest `fraction` of `length` samples, with
/// `fraction` clamped to 0–1.
fn slice_bound(fraction : Double, length : Int32) -> Int32 {
  let clamped = if fraction < 0.0 {
    0.0
  } else if fraction > 1.0 {
    1.0
  } else {
    fraction
  }
  (clamped * length.to_double()).round().to_int()
}

///|
/// The next sample of sample `number` at MIDI pitch `pitch`, times `speed`,
/// read from the read position with linear interpolation. A waveform plays at
/// its recorded rate at its root pitch and speed 1; a negative speed plays
/// backwards. Only the slice from `begin` to `end`, as fractions of the
/// waveform, plays. Outside the slice, or for a number with no waveform, it
/// is 0, and once the read position leaves the slice it stays 0.
pub fn SamplePlayer::tick(
  self : SamplePlayer,
  number~ : Double,
  pitch~ : Double,
  speed~ : Double,
  begin~ : Double = 0.0,
  end~ : Double = 1.0,
) -> Double {
  if !self.bound || self.number != number {
    self.bind(number, speed, begin, end)
  } else if begin != self.begin || end != self.end {
    self.slice(begin, end)
  }
  if !self.rate_known || pitch != self.pitch || speed != self.speed {
    self.rate_known = true
    let rate = @math.pow(2.0, (pitch - self.root) / 12.0) * speed
    self.pitch = pitch
    self.speed = speed
    self.rate = if is_finite(rate) { rate } else { 0.0 }
  }
  let position = self.position
  guard position >= self.first.to_double() && position <= self.last.to_double() else {
    self.finish()
    return 0.0
  }
  let memory = self.store.memory
  let whole = position.to_int()
  let fraction = position - whole.to_double()
  let current = memory[self.start + whole].to_double()
  self.position = position + self.rate
  if fraction == 0.0 {
    current
  } else {
    // A fractional position at most `last` lies before the slice's last
    // sample, which lies in the waveform.
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
  begin~ : Double = 0.0,
  end~ : Double = 1.0,
) -> Unit {
  let sample_count = effective_sample_count(context, output)
  for index in 0..<sample_count {
    output.set(index, self.tick(number~, pitch~, speed~, begin~, end~))
  }
  for index in sample_count..<output.length() {
    output.set(index, 0.0)
  }
}
