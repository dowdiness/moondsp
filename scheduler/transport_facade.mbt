///|
pub using @transport {type TransportError}

///|
/// A parsed tempo. Its representation stays inside the scheduler boundary.
pub struct Tempo {
  priv value : @transport.Tempo
}

///|
fn Tempo::Tempo(value : @transport.Tempo) -> Tempo {
  { value, }
}

///|
pub fn Tempo::from_bpm(bpm : Double) -> Result[Tempo, TransportError] {
  @transport.Tempo::from_bpm(bpm).map(value => Tempo(value))
}

///|
pub fn Tempo::bpm(self : Tempo) -> Double {
  self.value.bpm()
}

///|
/// Check a future zero-anchored performance without mutating a scheduler.
pub fn Tempo::sample_at_start(
  self : Tempo,
  position : @pattern.Rational,
  sample_rate~ : Double,
) -> Result[Int64, TransportError] {
  match @transport.Clock::at_start(self.value, sample_rate) {
    Err(error) => Err(error)
    Ok(clock) => clock.sample_at(position)
  }
}

///|
/// Return the exact musical span covered by a number of audio samples.
///
/// The conversion uses the zero-anchored transport clock, preserving the
/// accepted sample-rate checks and millibeats-per-minute precision.
pub fn Tempo::span_for_samples(
  self : Tempo,
  samples : Int,
  sample_rate~ : Double,
) -> Result[@pattern.Rational, TransportError] {
  let clock = match @transport.Clock::at_start(self.value, sample_rate) {
    Err(error) => return Err(error)
    Ok(clock) => clock
  }
  clock.position(samples.to_int64())
}

///|
/// Audio-block frame derived from the scheduler clock.
///
/// `logical_arc` is the rational musical span on the current anchored clock;
/// the sample range identifies where its output will be rendered.
pub struct BlockFrame {
  sample_begin : Int64
  sample_end : Int64
  logical_arc : @pattern.TimeSpan
}

///|
/// Absolute performance/audio time in samples.
pub struct PerformanceTime {
  sample : Int64
}

///|
pub fn PerformanceTime::PerformanceTime(sample : Int64) -> PerformanceTime {
  { sample, }
}

///|
/// Parse external tempo input.
fn parse_tempo(bpm : Double) -> Result[Tempo, TransportError] {
  Tempo::from_bpm(bpm)
}

///|
pub fn PatternScheduler::sample_counter(self : PatternScheduler) -> Int64 {
  self.clock.sample()
}

///|
/// Current accepted tempo, rounded to the nearest 0.001 BPM.
pub fn PatternScheduler::bpm(self : PatternScheduler) -> Double {
  self.clock.tempo().bpm()
}

///|
/// Current block frame without advancing the scheduler clock.
pub fn PatternScheduler::current_block(
  self : PatternScheduler,
) -> Result[BlockFrame, TransportError] {
  let next = match self.clock.advance(self.ctx.block_size()) {
    Ok(next) => next
    Err(e) => return Err(e)
  }
  Ok({
    sample_begin: self.clock.sample(),
    sample_end: next.sample(),
    logical_arc: @pattern.TimeSpan::new(
      self.clock.position(self.clock.sample()).unwrap(),
      next.position(next.sample()).unwrap(),
    ),
  })
}

///|
fn PatternScheduler::render_frame(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> BlockFrame? {
  match self.current_block() {
    Ok(frame) => Some(frame)
    Err(e) => {
      self.last_error = Some(e)
      left.fill(0.0)
      right.fill(0.0)
      pool.kill_all()
      self.active_notes.clear()
      None
    }
  }
}

///|
/// An all-or-none tempo update plan. Plans never escape this serialized
/// operation; applying one only assigns already-computed state.
priv struct TempoPlan {
  clock : @transport.Clock
  deadlines : Array[Int64?]
  restart : Bool
}

///|
fn PatternScheduler::tempo_plan(
  self : PatternScheduler,
  tempo : Tempo,
  restart : Bool,
  end_? : @pattern.Rational,
) -> Result[TempoPlan, TransportError] {
  let proposed = if restart {
    self.clock.reset().with_tempo(tempo.value)
  } else {
    self.clock.with_tempo(tempo.value)
  }
  match proposed.advance(self.ctx.block_size()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if end_ is Some(position) {
    match proposed.sample_at(position) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let deadlines = if restart {
    []
  } else {
    match self.active_notes.compute_retime(end_ => proposed.sample_at(end_)) {
      Err(e) => return Err(e)
      Ok(deadlines) => deadlines
    }
  }
  Ok({ clock: proposed, deadlines, restart, })
}

///|
fn PatternScheduler::apply_tempo_plan(
  self : PatternScheduler,
  plan : TempoPlan,
) -> Unit {
  self.clock = plan.clock
  if plan.restart {
    self.previous_clock = self.clock
    self.previous_events = []
    self.last_error = None
    self.active_notes.clear()
    self.playback_state.reset()
  } else {
    self.active_notes.apply_retime(plan.deadlines)
  }
}

///|
/// Change tempo at the next unrendered sample, retaining musical position.
pub fn PatternScheduler::set_bpm(
  self : PatternScheduler,
  bpm : Double,
) -> Result[Unit, TransportError] {
  let tempo = match parse_tempo(bpm) {
    Ok(tempo) => tempo
    Err(e) => return Err(e)
  }
  let plan = match self.tempo_plan(tempo, false) {
    Err(e) => return Err(e)
    Ok(plan) => plan
  }
  self.apply_tempo_plan(plan)
  Ok(())
}

///|
/// Atomically change tempo across all schedulers. Existing note deadlines and
/// an optional finite performance endpoint are checked on each proposed clock
/// before any scheduler is mutated.
pub fn set_tempo_all(
  schedulers : Array[PatternScheduler],
  tempo : Tempo,
  restart? : Bool = false,
  end_? : @pattern.Rational,
) -> Result[Unit, TransportError] {
  let plans : Array[TempoPlan] = []
  for scheduler in schedulers {
    match scheduler.tempo_plan(tempo, restart, end_?) {
      Err(e) => return Err(e)
      Ok(plan) => plans.push(plan)
    }
  }
  for i in 0..<schedulers.length() {
    schedulers[i].apply_tempo_plan(plans[i])
  }
  Ok(())
}

///|
pub(all) enum PlaybackAdmissionError {
  MaterialLimit
  Transport(TransportError)
}

///|
/// Atomically accept bounded material state and tempo across all routes.
/// Rejection leaves every clock, accepted snapshot, and note deadline intact.
/// The limit covers both retained entries and a future repetition's entries.
pub fn accept_playback_all(
  targets : Array[(PatternScheduler, PlaybackSnapshot)],
  tempo : Tempo,
  material_limit~ : Int,
  restart? : Bool = false,
  end_? : @pattern.Rational,
) -> Result[Unit, PlaybackAdmissionError] {
  let plans : Array[(TempoPlan, @playback.PlaybackState)] = []
  for target in targets {
    let (scheduler, snapshot) = target
    let plan = match scheduler.tempo_plan(tempo, restart, end_?) {
      Err(error) => return Err(Transport(error))
      Ok(plan) => plan
    }
    let now = match plan.clock.position(plan.clock.sample()) {
      Err(error) => return Err(Transport(error))
      Ok(now) => now
    }
    guard scheduler.playback_state.prepare_acceptance(
        snapshot.raw(),
        now,
        material_limit~,
        restart~,
      )
      is Some(state) else {
      return Err(MaterialLimit)
    }
    plans.push((plan, state))
  }
  for index in 0..<targets.length() {
    let scheduler = targets[index].0
    let (tempo_plan, playback) = plans[index]
    scheduler.apply_tempo_plan(tempo_plan)
    scheduler.playback_state.install_acceptance(playback)
  }
  Ok(())
}

///|
pub fn PatternScheduler::last_transport_error(
  self : PatternScheduler,
) -> TransportError? {
  self.last_error
}

///|
pub fn PatternScheduler::sample_at(
  self : PatternScheduler,
  position : @pattern.Rational,
) -> Result[Int64, TransportError] {
  self.clock.sample_at(position)
}

///|
fn PatternScheduler::advance_block(self : PatternScheduler) -> Unit {
  match self.clock.advance(self.ctx.block_size()) {
    Ok(clock) => self.clock = clock
    Err(e) => self.last_error = Some(e)
  }
}

///|
/// Reset the transport to the beginning and forget tracked active notes.
pub fn PatternScheduler::reset_transport(self : PatternScheduler) -> Unit {
  self.clock = self.clock.reset()
  self.previous_clock = self.clock
  self.previous_events = []
  self.last_error = None
  self.active_notes.clear()
  self.playback_state.reset()
}

///|
/// Reset the transport and immediately kill every voice in `pool`.
///
/// WHY whole-pool kill: active-note tracking removes a note as soon as
/// gate-off is sent, while the voice may keep releasing for a few blocks.
/// Browser pattern swaps need a hard boundary so old releases or templates
/// cannot leak into the next pattern.
pub fn PatternScheduler::reset_transport_and_kill_notes(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  pool.kill_all()
  self.reset_transport()
}
