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
