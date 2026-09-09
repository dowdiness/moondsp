///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  self.active_notes.length()
}

///|
pub fn PatternScheduler::active_note_source(
  self : PatternScheduler,
  index : Int,
) -> EventSource? {
  match self.active_notes.source(index) {
    Some(source) => Some(EventSource::from_model(source))
    None => None
  }
}

///|
/// Convert MIDI note number to frequency in Hz.
/// Uses equal temperament: A4 (MIDI 69) = 440 Hz, each semitone is 2^(1/12).
pub fn midi_to_hz(midi : Double) -> Double {
  @voice_runtime.midi_to_hz(midi)
}

///|
/// Track an externally triggered voice with a musical gate-off deadline.
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
) -> Result[Unit, TransportError] {
  let end_sample = match self.clock.sample_at(end_time) {
    Ok(sample) => sample
    Err(e) => return Err(e)
  }
  self.active_notes.push_note(
    handle~,
    source=EventSource::none().to_model(),
    end_sample~,
    musical_end=end_time,
  )
  Ok(())
}

///|
/// Track an externally triggered voice with a physical gate-off deadline.
/// Tempo changes leave this deadline unchanged.
pub fn PatternScheduler::push_active_note_until(
  self : PatternScheduler,
  handle : @moondsp.VoiceHandle,
  end_time : PerformanceTime,
) -> Unit {
  self.active_notes.push_note(
    handle~,
    source=EventSource::none().to_model(),
    end_sample=end_time.sample,
  )
}
