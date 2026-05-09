///|
pub fn drum_midi(name : String) -> Int? {
  match name {
    "bd" => Some(36)
    "sd" => Some(38)
    "cp" => Some(39)
    "hh" => Some(42)
    "oh" => Some(46)
    _ => None
  }
}
