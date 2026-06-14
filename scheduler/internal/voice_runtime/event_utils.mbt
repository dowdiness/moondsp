///|
/// Convert MIDI note number to frequency in Hz.
pub fn midi_to_hz(midi : Double) -> Double {
  440.0 * @math.pow(2.0, (midi - 69.0) / 12.0)
}

///|
pub fn copy_control_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  events.copy()
}

///|
/// Sort note-on capable events before continuous/no-whole events.
pub fn compare_event_onset(
  a : @pattern.Event[@pattern.ControlMap],
  b : @pattern.Event[@pattern.ControlMap],
) -> Int {
  match (a.whole, b.whole) {
    (Some(wa), Some(wb)) => wa.begin.compare(wb.begin)
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}
