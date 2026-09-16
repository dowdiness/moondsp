///|
/// Stage an authored snapshot for acceptance at the next render block. Each
/// edited material keeps its current interval until its next source entry.
pub fn PatternScheduler::queue_pattern_snapshot(
  self : PatternScheduler,
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> Unit {
  self.queue_playback_snapshot(PlaybackSnapshot::pattern(snapshot))
}

///|
/// Stage a lowered song snapshot for playback. The snapshot carries both the
/// authoring revision and the narrower layout revision; both become observable
/// at acceptance in the next block, before all material edits may be audible.
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
/// The snapshot accepted by an explicit owner operation or render-block commit.
///
/// Its changed materials may still be waiting for their own entry boundaries.
pub fn PatternScheduler::accepted_snapshot(
  self : PatternScheduler,
) -> PlaybackSnapshot? {
  self.playback_state.inspect().current.map(PlaybackSnapshot::from_raw)
}

///|
/// The latest snapshot queued for acceptance at the next render-block boundary.
pub fn PatternScheduler::queued_snapshot(
  self : PatternScheduler,
) -> PlaybackSnapshot? {
  self.playback_state.inspect().staged.map(PlaybackSnapshot::from_raw)
}

///|
/// Accepted material changes still waiting for a reserved entry boundary.
pub fn PatternScheduler::pending_material_change_count(
  self : PatternScheduler,
) -> Int {
  self.playback_state.inspect().pending_materials
}

///|
/// Accepted finite material changes that cannot enter during this Play.
pub fn PatternScheduler::skipped_material_change_count(
  self : PatternScheduler,
) -> Int {
  self.playback_state.inspect().skipped_materials
}

///|
fn PatternScheduler::commit_pending_playback_snapshot(
  self : PatternScheduler,
) -> Unit {
  self.playback_state.commit_pending(
    self.clock.position(self.clock.sample()).unwrap(),
  )
}

///|
/// Render prepared playback with the same per-material entry rules as songs.
pub fn PatternScheduler::process_snapshot_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.process_playback_snapshot_block(pool, left, right)
}

///|
/// Render prepared song playback. Acceptance occurs at block start; audible
/// edits use each material's next entry within its occurrence.
pub fn PatternScheduler::process_song_snapshot_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.process_playback_snapshot_block(pool, left, right)
}
