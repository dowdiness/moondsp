///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  self.active_notes.length()
}

///|
pub(all) enum ActiveNoteError {
  /// Not an index into the constructor's instrument list.
  UnknownInstrument(Int)
  Transport(TransportError)
} derive(Eq, Debug)

///|
pub extend ActiveNoteError with Eq::{not_equal, equal}

///|
pub extend ActiveNoteError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Track an externally triggered voice of `instrument` (an index into the
/// constructor's instrument list) with a musical gate-off deadline.
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  instrument : Int,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
) -> Result[Unit, ActiveNoteError] {
  guard instrument >= 0 && instrument < self.pools.length() else {
    return Err(UnknownInstrument(instrument))
  }
  let end_sample = match self.clock.sample_at(end_time) {
    Ok(sample) => sample
    Err(e) => return Err(Transport(e))
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
) -> Result[Unit, ActiveNoteError] {
  guard instrument >= 0 && instrument < self.pools.length() else {
    return Err(UnknownInstrument(instrument))
  }
  self.active_notes.push_note(
    instrument~,
    handle~,
    origin=@model.VoiceOrigin::Anonymous,
    end_sample=end_time.sample,
  )
  Ok(())
}
