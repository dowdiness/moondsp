///|
/// Internal voice-runtime provenance stored with a scheduler-owned active note.
pub struct EventSource {
  priv pattern_nodes : Array[@identity.PatternNodeId]
  priv section : @identity.SectionId?
  priv layer : @identity.SectionLayerId?
  priv occurrence : @identity.OccurrenceId?
}

///|
/// Internal no-copy constructor for scheduler-owned provenance arrays.
pub fn EventSource::from_trusted_parts(
  pattern_nodes~ : Array[@identity.PatternNodeId],
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  { pattern_nodes, section, layer, occurrence }
}

///|
pub fn EventSource::pattern_nodes(
  self : EventSource,
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes.copy()
}

///|
pub fn EventSource::borrow_pattern_nodes(
  self : EventSource,
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes
}

///|
pub fn EventSource::section(self : EventSource) -> @identity.SectionId? {
  self.section
}

///|
pub fn EventSource::layer(self : EventSource) -> @identity.SectionLayerId? {
  self.layer
}

///|
pub fn EventSource::occurrence(self : EventSource) -> @identity.OccurrenceId? {
  self.occurrence
}

///|
/// Scheduler-owned active voice with its performance-sample gate-off time.
pub struct ActiveNote {
  priv handle : @voice.VoiceHandle
  priv source : EventSource
  priv end_sample : Int64
}

///|
pub fn ActiveNote::ActiveNote(
  handle~ : @voice.VoiceHandle,
  source~ : EventSource,
  end_sample~ : Int64,
) -> ActiveNote {
  { handle, source, end_sample }
}

///|
pub fn ActiveNote::handle(self : ActiveNote) -> @voice.VoiceHandle {
  self.handle
}

///|
pub fn ActiveNote::source(self : ActiveNote) -> EventSource {
  self.source
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
