///|
pub using @transport {type TransportError}

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
/// Validate and normalize external tempo input before preparing playback.
pub fn normalize_bpm(bpm : Double) -> Result[Double, TransportError] {
  @transport.Tempo::from_bpm(bpm).map(tempo => tempo.bpm())
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
/// Change tempo at the next unrendered sample, retaining musical position.
/// Invalid input or unrepresentable active endpoints leave all state unchanged.
pub fn PatternScheduler::set_bpm(
  self : PatternScheduler,
  bpm : Double,
) -> Result[Unit, TransportError] {
  let tempo = match @transport.Tempo::from_bpm(bpm) {
    Ok(tempo) => tempo
    Err(e) => return Err(e)
  }
  let next = self.clock.with_tempo(tempo)
  match next.advance(self.ctx.block_size()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.active_notes.retime(end_ => next.sample_at(end_)) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.clock = next
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

///|
/// Read-only admission for coordinating an edit across sound routes.
pub fn PatternScheduler::validate_bpm(
  self : PatternScheduler,
  bpm : Double,
) -> Result[Unit, TransportError] {
  let tempo = match @transport.Tempo::from_bpm(bpm) {
    Ok(tempo) => tempo
    Err(e) => return Err(e)
  }
  let next = self.clock.with_tempo(tempo)
  match next.advance(self.ctx.block_size()) {
    Err(e) => return Err(e)
    Ok(_) => self.active_notes.validate_retime(end_ => next.sample_at(end_))
  }
}
