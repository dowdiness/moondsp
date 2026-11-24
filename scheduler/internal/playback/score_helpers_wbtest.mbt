///|
/// The pitch `event` plays, if it is a note.
fn pitch_of(event : @score.ScoreEvent) -> Double? {
  match event.sound {
    Note(_, pitch~) => Some(pitch)
    Hit(_) => None
  }
}
