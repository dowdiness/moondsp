///|
/// One event of a score: the sound it plays and its controls (ADR-0022).
#derive(Eq, Debug)
pub(all) struct ScoreEvent {
  sound : Sound
  controls : @pattern.ControlMap
}

///|
pub extend ScoreEvent with Eq::{not_equal, equal}

///|
pub extend ScoreEvent with Debug::{to_repr}

///|
/// An event that plays `sound` with no controls set.
pub fn ScoreEvent::ScoreEvent(sound : Sound) -> ScoreEvent {
  { sound, controls: @pattern.ControlMap::empty(), }
}

///|
pub impl @pattern.WithControls for ScoreEvent with fn controls(self) {
  self.controls
}

///|
pub impl @pattern.WithControls for ScoreEvent with fn with_controls(
  self,
  controls,
) {
  { ..self, controls: self.controls.merge(controls), }
}

///|
/// A pattern of one note at `pitch` (a MIDI note number) on the default
/// instrument, filling each cycle.
pub fn note(pitch : Double) -> @pattern.Pat[ScoreEvent] {
  let sound = Note(Instrument::default(), pitch~)
  @pattern.Pat::pure(ScoreEvent(sound), content=sound.content())
}

///|
/// A pattern of one `drum` hit, filling each cycle.
pub fn hit(drum : Drum) -> @pattern.Pat[ScoreEvent] {
  let sound = Hit(drum)
  @pattern.Pat::pure(ScoreEvent(sound), content=sound.content())
}
