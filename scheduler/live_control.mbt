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
  if target.is_empty() || controls.is_empty() {
    return Ok(0)
  }
  let raw_target = target.to_edit_policy()
  match
    self.active_notes.try_each_matching_handle(raw_target, fn(handle) {
      pool.validate_voice_controls_result(handle, controls)
    }) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  self.active_notes.try_count_matching_handles(raw_target, fn(handle) {
    pool.apply_voice_controls_result(handle, controls)
  })
}
