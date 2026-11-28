///|
/// What a scheduler reports as it plays, to the one observer its host
/// attaches. The scheduler calls these on the render path: an observer must
/// not allocate.
pub(open) trait PlaybackObserver {
  /// A tracked event dispatched at `sample`.
  fn onset(Self, Int64, @pattern.EventWithOrigin[@score.ScoreEvent]) -> Unit
  /// What a sounding voice following `signal` reads at the block that starts
  /// at `sample`: `value`, at `material` cycles on the clock of the material
  /// that dispatched the voice's note. Voices that follow one signal at one
  /// material time are reported once per block.
  fn signal(Self, Int64, @identity.SourceAtomId, Double, Double) -> Unit
  /// A voice followed a signal the scheduler could not observe: it observes
  /// at most 64 followed signals at once.
  fn signal_lost(Self) -> Unit
}

///|
/// Followed signals of sounding voices the scheduler observes at once.
const SIGNAL_FOLLOWER_CAPACITY : Int32 = 64

///|
/// The signals sounding voices follow, preallocated when an observer is
/// attached. The voice pools own which voices still follow what; a follower
/// here only names one, so it ends exactly when the voice does.
priv struct SignalFollowers {
  mut count : Int32
  /// Per follower: the `index`-th follower of the voice behind `handle` in
  /// the pool of `instrument`, and the signal it reads.
  instruments : FixedArray[Int32]
  handles : FixedArray[@moondsp.VoiceHandle?]
  indices : FixedArray[Int32]
  signals : FixedArray[@identity.SourceAtomId?]
  /// Playback cycle `t` is material time `(t - origin) * rate`.
  origins : FixedArray[Double]
  rates : FixedArray[Double]
  /// Material time this block, and whether the follower was reported at it.
  materials : FixedArray[Double]
  reported : FixedArray[Bool]
}

///|
fn SignalFollowers::SignalFollowers() -> SignalFollowers {
  {
    count: 0,
    instruments: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0),
    handles: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, None),
    indices: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0),
    signals: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, None),
    origins: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0.0),
    rates: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 1.0),
    materials: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, 0.0),
    reported: FixedArray::make(SIGNAL_FOLLOWER_CAPACITY, false),
  }
}

///|
/// The observing state of a scheduler with an attached observer.
priv struct Observing {
  observer : &PlaybackObserver
  mut onsets : Bool
  mut signals : Bool
  followers : SignalFollowers
}

///|
/// Report to `observer` from now on. Reporting starts disabled; enable it
/// with `observe_onsets` and `observe_signals`. Allocates the follower
/// storage; a scheduler without an observer has none and no overhead.
pub fn PatternScheduler::attach_observer(
  self : PatternScheduler,
  observer : &PlaybackObserver,
) -> Unit {
  self.observing = Some({
    observer,
    onsets: false,
    signals: false,
    followers: SignalFollowers(),
  })
}

///|
/// Whether to report tracked onsets to the attached observer.
pub fn PatternScheduler::observe_onsets(
  self : PatternScheduler,
  enabled : Bool,
) -> Unit {
  if self.observing is Some(observing) {
    observing.onsets = enabled
  }
}

///|
/// Whether to report followed signal values to the attached observer.
/// Disabling forgets the voices it followed.
pub fn PatternScheduler::observe_signals(
  self : PatternScheduler,
  enabled : Bool,
) -> Unit {
  if self.observing is Some(observing) {
    observing.signals = enabled
    if !enabled {
      observing.followers.count = 0
    }
  }
}

///|
/// Report the onset of a tracked event dispatched at `sample`.
fn Observing::onset(
  self : Observing,
  sample : Int64,
  source : @pattern.EventWithOrigin[@score.ScoreEvent]?,
) -> Unit {
  if self.onsets && source is Some(source) {
    self.observer.onset(sample, source)
  }
}

///|
/// Observe the authored signals the voice behind `handle`, in the pool of
/// `instrument`, follows, as its note's `controls` give them, for as long as
/// the voice follows them.
fn Observing::follow(
  self : Observing,
  controls : @pattern.Controls,
  pool : @moondsp.BoundVoicePool,
  instrument : Int32,
  handle : @moondsp.VoiceHandle,
) -> Unit {
  guard self.signals else { return }
  let followers = self.followers
  let mut index = 0
  while pool.followed(handle, index) is Some(follower) {
    index += 1
    guard controls.signal_source(follower.key()) is Some(signal) else {
      continue
    }
    guard followers.count < SIGNAL_FOLLOWER_CAPACITY else {
      self.observer.signal_lost()
      continue
    }
    let slot = followers.count
    followers.count += 1
    followers.instruments[slot] = instrument
    followers.handles[slot] = Some(handle)
    followers.indices[slot] = index - 1
    followers.signals[slot] = Some(signal)
    // As doubles, so observing a block needs no exact arithmetic.
    followers.origins[slot] = controls.material_origin().to_double()
    followers.rates[slot] = controls.material_rate().to_double()
  }
}

///|
/// Report what each followed signal gives at the block that starts at
/// playback time `at` and sample `sample`, once per signal and material, and
/// stop observing voices of `pools` that no longer follow it.
fn Observing::observe(
  self : Observing,
  pools : Array[@moondsp.BoundVoicePool],
  at : @pattern.Rational,
  sample : Int64,
) -> Unit {
  let followers = self.followers
  guard self.signals && followers.count > 0 else { return }
  let cycle = at.num.to_double() / at.den.to_double()
  let mut slot = 0
  while slot < followers.count {
    guard followers.handles[slot] is Some(handle) &&
      followers.signals[slot] is Some(signal) &&
      pools[followers.instruments[slot]].followed(
        handle,
        followers.indices[slot],
      )
      is Some(follower) else {
      // Swap in the last follower; its slot is checked next.
      let last = followers.count - 1
      followers.instruments[slot] = followers.instruments[last]
      followers.handles[slot] = followers.handles[last]
      followers.indices[slot] = followers.indices[last]
      followers.signals[slot] = followers.signals[last]
      followers.origins[slot] = followers.origins[last]
      followers.rates[slot] = followers.rates[last]
      followers.count = last
      continue
    }
    let material = (cycle - followers.origins[slot]) * followers.rates[slot]
    followers.materials[slot] = material
    followers.reported[slot] = false
    // Every follower before this slot was observed this block: chord tones
    // following one signal give one report.
    if !followers.reported_before(slot, signal, material) {
      let value = follower.read()(at.num, at.den)
      if !value.is_absent() {
        self.observer.signal(sample, signal, material, value.unwrap_or(0.0))
        followers.reported[slot] = true
      }
    }
    slot += 1
  }
}

///|
/// Whether a follower before `slot` was reported this block for `signal` at
/// `material` time.
fn SignalFollowers::reported_before(
  self : SignalFollowers,
  slot : Int32,
  signal : @identity.SourceAtomId,
  material : Double,
) -> Bool {
  for earlier in 0..<slot {
    if self.reported[earlier] &&
      self.materials[earlier] == material &&
      self.signals[earlier] is Some(other) &&
      other == signal {
      return true
    }
  }
  false
}
