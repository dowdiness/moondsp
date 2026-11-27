///|
fn drum_named(name : String) -> @score.Drum {
  @score.Drum::parse(name).unwrap()
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
