///|
/// Apply one live graph control to currently active voices matching an edit.
///
/// The controls affect already-sounding voices only. Future `note_on`s still
/// use the current voice-pool template and bindings.
pub fn PatternScheduler::apply_voice_control_for_edit_result(
  self : PatternScheduler,
  edit~ : AffectedVoiceEditScope,
  control~ : @moondsp.GraphControl,
  pool~ : @moondsp.BoundVoicePool,
) -> Result[Int, @moondsp.VoiceControlError] {
  self.apply_voice_controls_for_edit_result(edit~, controls=[control], pool~)
}

///|
/// Apply a live graph-control batch to currently active voices matching an edit.
///
/// All matched voices are preflighted before any voice is mutated, so stale
/// handles or invalid controls leave the matched voice set unchanged.
pub fn PatternScheduler::apply_voice_controls_for_edit_result(
  self : PatternScheduler,
  edit~ : AffectedVoiceEditScope,
  controls~ : Array[@moondsp.GraphControl],
  pool~ : @moondsp.BoundVoicePool,
) -> Result[Int, @moondsp.VoiceControlError] {
  let target = edit.target()
  if target.is_empty() {
    return Ok(0)
  }
  for note in self.active_notes {
    if note.source.matches(target) {
      match pool.validate_voice_controls_result(note.handle, controls) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
  }
  let mut count = 0
  for note in self.active_notes {
    if note.source.matches(target) {
      match pool.apply_voice_controls_result(note.handle, controls) {
        Ok(_) => count = count + 1
        Err(error) => return Err(error)
      }
    }
  }
  Ok(count)
}
