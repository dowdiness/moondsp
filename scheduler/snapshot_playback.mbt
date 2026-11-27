///|
/// Stage the next prepared playback snapshot. Pattern and song snapshots use
/// the same pending slot; if several edits arrive before the next audio block,
/// only the latest successfully prepared snapshot commits.
pub fn PatternScheduler::queue_playback_snapshot(
  self : PatternScheduler,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.playback_state.queue(snapshot.raw)
}

///|
/// Accept at the next unrendered sample without advancing the clock. Owners
/// call this between blocks, including while the performance is paused.
pub fn PatternScheduler::accept_playback_snapshot(
  self : PatternScheduler,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.queue_playback_snapshot(snapshot)
  self.commit_pending_playback_snapshot()
}

///|
/// Accepted material changes still waiting for a reserved entry boundary.
pub fn PatternScheduler::pending_material_change_count(
  self : PatternScheduler,
) -> Int32 {
  self.playback_state.pending_entry_count()
}

///|
/// Accepted finite material changes that cannot enter during this Play.
pub fn PatternScheduler::skipped_material_change_count(
  self : PatternScheduler,
) -> Int32 {
  self.playback_state.skipped_entry_count()
}

///|
fn PatternScheduler::commit_pending_playback_snapshot(
  self : PatternScheduler,
) -> Unit {
  self.playback_state.commit_pending(
    self.clock.position(self.clock.sample()).unwrap(),
  )
}
