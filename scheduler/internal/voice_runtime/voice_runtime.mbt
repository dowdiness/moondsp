///|
/// Scheduler-owned active voice with its performance-sample gate-off time.
pub struct ActiveNote {
  priv handle : @voice.VoiceHandle
  priv source : @model.EventSource
  priv end_sample : Int64
}

///|
pub fn ActiveNote::ActiveNote(
  handle~ : @voice.VoiceHandle,
  source~ : @model.EventSource,
  end_sample~ : Int64,
) -> ActiveNote {
  { handle, source, end_sample }
}

///|
pub fn ActiveNote::handle(self : ActiveNote) -> @voice.VoiceHandle {
  self.handle
}

///|
pub fn ActiveNote::source(self : ActiveNote) -> @model.EventSource {
  self.source
}

///|
pub fn ActiveNote::matches_edit_policy(
  self : ActiveNote,
  target : @edit_policy.AffectedVoiceTarget,
) -> Bool {
  let source = self.source
  @edit_policy.source_parts_match_target(
    pattern_nodes=source.borrow_pattern_nodes(),
    section=source.section(),
    layer=source.layer(),
    occurrence=source.occurrence(),
    target,
  )
}

///|
pub fn ActiveNote::expires_at(self : ActiveNote, sample : Int64) -> Bool {
  self.end_sample <= sample
}

///|
pub fn ActiveNote::note_off(
  self : ActiveNote,
  pool : @voice.BoundVoicePool,
) -> Unit {
  ignore(pool.note_off_result(self.handle))
}

///|
pub fn ActiveNote::kill(
  self : ActiveNote,
  pool : @voice.BoundVoicePool,
) -> Unit {
  ignore(pool.kill_result(self.handle))
}

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
