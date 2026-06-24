///|
/// Audio-block frame derived from the scheduler clock.
///
/// `logical_arc` keeps the existing rational-cycle semantics; the sample range
/// gives the future song layer a stable audio-time anchor without changing the
/// current pattern scheduler behavior.
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
/// Reject NaN/Inf and clamp to minimum 1.0 BPM.
fn sanitize_bpm(bpm : Double) -> Double {
  @transport.sanitize_bpm(bpm)
}

///|
/// Derive the cycle-time arc for a block from the integer sample counter.
///
/// At BPM, one cycle lasts 60/BPM seconds. The formula
/// `sample_counter * bpm / (sample_rate * 60)` gives the cycle position —
/// how many cycles have elapsed since playback started. Using Rational
/// arithmetic keeps this exact (no floating-point drift). Denominators are
/// bounded by `sample_rate * 60` (e.g. 2,880,000 for 48kHz).
pub fn compute_arc(
  sample_counter : Int64,
  bpm : Double,
  ctx : @moondsp.DspContext,
) -> @pattern.TimeSpan {
  @transport.compute_arc(sample_counter, bpm, ctx)
}

///|
/// Convert an absolute logical cycle position into the first sample at or after
/// that cycle position for the scheduler's BPM scaling convention.
pub fn cycle_to_sample(
  cycle : @pattern.Rational,
  bpm : Double,
  ctx : @moondsp.DspContext,
) -> Int64 {
  @transport.cycle_to_sample(cycle, bpm, ctx)
}

///|
pub fn PatternScheduler::sample_counter(self : PatternScheduler) -> Int64 {
  self.sample_counter
}

///|
/// Current tempo in beats per minute. The value is always sanitized:
/// construction and `set_bpm` reject NaN/Inf and clamp to a minimum of 1.0.
pub fn PatternScheduler::bpm(self : PatternScheduler) -> Double {
  self.bpm
}

///|
/// Current block frame without advancing the scheduler clock.
pub fn PatternScheduler::current_block(self : PatternScheduler) -> BlockFrame {
  let sample_begin = self.sample_counter
  let sample_end = @transport.block_sample_end(sample_begin, self.ctx)
  {
    sample_begin,
    sample_end,
    logical_arc: compute_arc(sample_begin, self.bpm, self.ctx),
  }
}

///|
/// Update tempo in-place. Newly scheduled notes use the updated tempo. Active
/// notes keep their already-computed performance-time gate-off sample.
pub fn PatternScheduler::set_bpm(self : PatternScheduler, bpm : Double) -> Unit {
  self.bpm = sanitize_bpm(bpm)
}

///|
fn PatternScheduler::advance_block(self : PatternScheduler) -> Unit {
  self.sample_counter = @transport.advance_block_sample(
    self.sample_counter,
    self.ctx,
  )
}

///|
/// Reset the transport to the beginning and forget tracked active notes.
pub fn PatternScheduler::reset_transport(self : PatternScheduler) -> Unit {
  self.sample_counter = 0L
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
