///|
/// The pitch `event` plays, if it is a note.
fn pitch_of(event : @score.ScoreEvent) -> Double? {
  match event.sound {
    Note(_, pitch~) => Some(pitch)
    Hit(_) => None
  }
}

///|
/// The name of the drum `event` hits, if it is a hit.
fn drum_of(event : @score.ScoreEvent) -> String? {
  match event.sound {
    Hit(drum) => Some(drum.name())
    Note(_, ..) => None
  }
}
