///|
/// Opaque scheduler-package active-note marker.
struct ActiveNote {}

///|
fn ActiveNote::ActiveNote() -> ActiveNote {
  ActiveNote::{ }
}

///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  ignore(self.active_note_interface_anchor)
  self.active_notes.length()
}

///|
/// Convert MIDI note number to frequency in Hz.
/// Uses equal temperament: A4 (MIDI 69) = 440 Hz, each semitone is 2^(1/12).
pub fn midi_to_hz(midi : Double) -> Double {
  @voice_runtime.midi_to_hz(midi)
}

///|
/// Test helper: inject an active note for testing gate-off logic.
/// The caller must ensure the VoiceHandle is currently active in the pool,
/// or gate-off at expiry will silently no-op (note_off returns false).
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
) -> Unit {
  self.active_notes.push_note(
    handle~,
    end_sample=cycle_to_sample(end_time, self.bpm, self.ctx),
  )
}
