///|
fn drum_named(name : String) -> @score.Drum {
  @score.Drum::parse(name).unwrap()
}

///|
/// The pitch `event` plays, if it is a note.
fn pitch_of(event : @score.ScoreEvent) -> Double? {
  match event.sound {
    Note(_, pitch~) => Some(pitch)
    Hit(_) => None
  }
}

///|
/// An event with `controls`: a note at their `Note` when they set one, else a
/// hit, which gives its voice no pitch.
fn played(controls : @pattern.ControlMap) -> @score.ScoreEvent {
  let rest = @pattern.ControlMap::empty()
  let mut rest = rest
  controls.each((key, value) => if key != Note { rest = rest.set(key, value) })
  match controls.get(Note) {
    Some(pitch) =>
      { sound: Note(@score.Instrument::default(), pitch~), controls: rest, }
    None => { sound: Hit(drum_named("bd")), controls: rest, }
  }
}
