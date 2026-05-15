///|
/// Outcome from staging an edit while reconciling already-active voices.
pub struct PlaybackEditOutcome {
  controlled_voice_count : Int
  removed_active_note_count : Int
} derive(Eq, Debug)

///|
/// Stage a prepared playback edit and reconcile currently active voices.
///
/// The replacement snapshot still commits at the existing audio-block boundary;
/// the affected-voice policy applies immediately to voices whose stored
/// provenance matches the edit scope. Returns the number of scheduler-owned
/// active-note records removed by the policy.
pub fn PatternScheduler::queue_playback_snapshot_edit(
  self : PatternScheduler,
  snapshot~ : PlaybackSnapshot,
  policy~ : AffectedVoicePolicy,
  edit~ : AffectedVoiceEditScope,
  pool~ : @moondsp.BoundVoicePool,
) -> Int {
  self.queue_playback_snapshot(snapshot)
  self.apply_affected_voice_policy_for_edit(policy, edit, pool)
}

///|
/// Stage a prepared playback edit, optionally applying live voice controls first.
///
/// Live controls are validated before any snapshot or policy mutation. Empty
/// control batches are treated as no live-control change.
pub fn PatternScheduler::queue_playback_snapshot_live_control_edit_result(
  self : PatternScheduler,
  snapshot~ : PlaybackSnapshot,
  policy~ : AffectedVoicePolicy,
  edit~ : AffectedVoiceEditScope,
  controls~ : Array[@moondsp.GraphControl],
  pool~ : @moondsp.BoundVoicePool,
) -> Result[PlaybackEditOutcome, @moondsp.VoiceControlError] {
  let controlled_voice_count = match controls {
    [] => 0
    _ =>
      match self.apply_voice_controls_for_edit_result(edit~, controls~, pool~) {
        Ok(count) => count
        Err(error) => return Err(error)
      }
  }
  let removed_active_note_count = self.queue_playback_snapshot_edit(
    snapshot~,
    policy~,
    edit~,
    pool~,
  )
  Ok({ controlled_voice_count, removed_active_note_count })
}

///|
/// Stage a pattern snapshot edit and reconcile currently active voices.
pub fn PatternScheduler::queue_pattern_snapshot_edit(
  self : PatternScheduler,
  snapshot~ : @pattern.PatternSnapshot[@pattern.ControlMap],
  policy~ : AffectedVoicePolicy,
  edit~ : AffectedVoiceEditScope,
  pool~ : @moondsp.BoundVoicePool,
) -> Int {
  self.queue_playback_snapshot_edit(
    snapshot=PlaybackSnapshot::pattern(snapshot),
    policy~,
    edit~,
    pool~,
  )
}

///|
/// Stage a pattern snapshot edit, optionally applying live voice controls first.
pub fn PatternScheduler::queue_pattern_snapshot_live_control_edit_result(
  self : PatternScheduler,
  snapshot~ : @pattern.PatternSnapshot[@pattern.ControlMap],
  policy~ : AffectedVoicePolicy,
  edit~ : AffectedVoiceEditScope,
  controls~ : Array[@moondsp.GraphControl],
  pool~ : @moondsp.BoundVoicePool,
) -> Result[PlaybackEditOutcome, @moondsp.VoiceControlError] {
  self.queue_playback_snapshot_live_control_edit_result(
    snapshot=PlaybackSnapshot::pattern(snapshot),
    policy~,
    edit~,
    controls~,
    pool~,
  )
}

///|
/// Stage a song snapshot edit and reconcile currently active voices.
pub fn PatternScheduler::queue_song_snapshot_edit(
  self : PatternScheduler,
  snapshot~ : @song.SongSnapshot[@pattern.ControlMap],
  policy~ : AffectedVoicePolicy,
  edit~ : AffectedVoiceEditScope,
  pool~ : @moondsp.BoundVoicePool,
) -> Int {
  self.queue_playback_snapshot_edit(
    snapshot=PlaybackSnapshot::song(snapshot),
    policy~,
    edit~,
    pool~,
  )
}

///|
/// Stage a song snapshot edit, optionally applying live voice controls first.
pub fn PatternScheduler::queue_song_snapshot_live_control_edit_result(
  self : PatternScheduler,
  snapshot~ : @song.SongSnapshot[@pattern.ControlMap],
  policy~ : AffectedVoicePolicy,
  edit~ : AffectedVoiceEditScope,
  controls~ : Array[@moondsp.GraphControl],
  pool~ : @moondsp.BoundVoicePool,
) -> Result[PlaybackEditOutcome, @moondsp.VoiceControlError] {
  self.queue_playback_snapshot_live_control_edit_result(
    snapshot=PlaybackSnapshot::song(snapshot),
    policy~,
    edit~,
    controls~,
    pool~,
  )
}
