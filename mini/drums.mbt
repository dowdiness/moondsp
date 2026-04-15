///|
pub fn drum_midi(name : String) -> Int? {
  match name {
    "bd" => Some(36)
    "sd" => Some(38)
    "hh" => Some(42)
    _ => None
  }
}
