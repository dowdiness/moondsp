///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  self.active_notes.length()
}

///|
/// Track an externally triggered voice of `instrument` (an index into the
/// constructor's instrument list) with a musical gate-off deadline.
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  instrument : Int,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
) -> Result[Unit, TransportError] {
  let end_sample = match self.clock.sample_at(end_time) {
    Ok(sample) => sample
    Err(e) => return Err(e)
  }
  self.active_notes.push_note(
    instrument~,
    handle~,
    origin=@model.VoiceOrigin::Anonymous,
    end_sample~,
    musical_end=end_time,
  )
  Ok(())
}

///|
/// Track an externally triggered voice of `instrument` with a physical
/// gate-off deadline. Tempo changes leave this deadline unchanged.
pub fn PatternScheduler::push_active_note_until(
  self : PatternScheduler,
  instrument : Int,
  handle : @moondsp.VoiceHandle,
  end_time : PerformanceTime,
) -> Unit {
  self.active_notes.push_note(
    instrument~,
    handle~,
    origin=@model.VoiceOrigin::Anonymous,
    end_sample=end_time.sample,
  )
}
