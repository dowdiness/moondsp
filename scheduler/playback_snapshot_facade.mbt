///|
/// Stage a lowered authoring snapshot for playback. The staged snapshot becomes
/// active at the start of the next `process_snapshot_block` call, giving callers
/// a stable block boundary for pattern edits during playback.
pub fn PatternScheduler::queue_pattern_snapshot(
  self : PatternScheduler,
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> Unit {
  self.queue_playback_snapshot(PlaybackSnapshot::pattern(snapshot))
}

///|
/// Stage a lowered song snapshot for playback. The snapshot carries both the
/// authoring revision and the narrower layout revision; both become observable
/// only when the snapshot commits at the next song snapshot block boundary.
pub fn PatternScheduler::queue_song_snapshot(
  self : PatternScheduler,
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
) -> Unit {
  self.queue_playback_snapshot(PlaybackSnapshot::song(snapshot))
}

///|
/// Stage the next prepared playback snapshot. Pattern and song snapshots use
/// the same pending slot; if several edits arrive before the next audio block,
/// only the latest successfully prepared snapshot commits.
pub fn PatternScheduler::queue_playback_snapshot(
  self : PatternScheduler,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.playback_state.queue(snapshot.raw())
}

///|
pub fn PatternScheduler::has_active_pattern_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_active_pattern()
}

///|
pub fn PatternScheduler::has_pending_pattern_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_pending_pattern()
}

///|
pub fn PatternScheduler::has_active_song_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_active_song()
}

///|
pub fn PatternScheduler::has_pending_song_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_pending_song()
}

///|
pub fn PatternScheduler::has_active_playback_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_active()
}

///|
pub fn PatternScheduler::has_pending_playback_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_pending()
}

///|
pub fn PatternScheduler::active_playback_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.playback_state.active_revision()
}

///|
pub fn PatternScheduler::active_song_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.playback_state.active_song_revision()
}

///|
pub fn PatternScheduler::active_playback_song_layout_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.playback_state.active_song_layout_revision()
}

///|
pub fn PatternScheduler::active_song_layout_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.active_playback_song_layout_revision()
}

///|
fn PatternScheduler::commit_pending_playback_snapshot(
  self : PatternScheduler,
) -> Unit {
  self.playback_state.commit_pending()
}
