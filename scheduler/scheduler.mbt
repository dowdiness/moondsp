///|
pub fn midi_to_hz(midi : Double) -> Double {
  440.0 * Double::pow(2.0, (midi - 69.0) / 12.0)
}
