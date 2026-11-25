///|
/// A lowered song the scheduler can play. Its sections hold either untracked
/// patterns or tracked pattern snapshots (ADR-0021).
pub(all) enum SongMaterial {
  Untracked(@song.SongSnapshot[@pattern.Pat[@score.ScoreEvent]])
  Tracked(
    @song.SongSnapshot[@pattern.TrackedPatternSnapshot[@score.ScoreEvent]],
  )
}

///|
fn SongMaterial::raw(self : SongMaterial) -> @playback.SongMaterial {
  match self {
    Untracked(snapshot) => Untracked(snapshot)
    Tracked(snapshot) => Tracked(snapshot)
  }
}

///|
fn SongMaterial::from_raw(material : @playback.SongMaterial) -> SongMaterial {
  match material {
    Untracked(snapshot) => Untracked(snapshot)
    Tracked(snapshot) => Tracked(snapshot)
  }
}

///|
/// Prepared scheduler input for the next authoring snapshot commit.
///
/// Pattern and song snapshots share the same pending slot so callers have one
/// coherent staging boundary when higher-level live orchestration prepares the
/// next playback state.
pub enum PlaybackSnapshot {
  UntrackedPattern(@pattern.UntrackedPatternSnapshot[@score.ScoreEvent])
  TrackedPattern(@pattern.TrackedPatternSnapshot[@score.ScoreEvent])
  Song(SongMaterial)
  RepeatSong(SongMaterial)
}

///|
pub fn PlaybackSnapshot::untracked_pattern(
  snapshot : @pattern.UntrackedPatternSnapshot[@score.ScoreEvent],
) -> PlaybackSnapshot {
  UntrackedPattern(snapshot)
}

///|
pub fn PlaybackSnapshot::tracked_pattern(
  snapshot : @pattern.TrackedPatternSnapshot[@score.ScoreEvent],
) -> PlaybackSnapshot {
  TrackedPattern(snapshot)
}

///|
pub fn PlaybackSnapshot::song(snapshot : SongMaterial) -> PlaybackSnapshot {
  Song(snapshot)
}

///|
/// Repeat an arranged song without resetting the transport or releasing voices.
pub fn PlaybackSnapshot::repeat_song(
  snapshot : SongMaterial,
) -> PlaybackSnapshot {
  RepeatSong(snapshot)
}

///|
fn PlaybackSnapshot::raw(self : PlaybackSnapshot) -> @playback.PlaybackSnapshot {
  match self {
    UntrackedPattern(snapshot) =>
      @playback.PlaybackSnapshot::untracked_pattern(snapshot)
    TrackedPattern(snapshot) =>
      @playback.PlaybackSnapshot::tracked_pattern(snapshot)
    Song(song) => @playback.PlaybackSnapshot::song(song.raw())
    RepeatSong(song) => @playback.PlaybackSnapshot::repeat_song(song.raw())
  }
}

///|
fn PlaybackSnapshot::from_raw(
  snapshot : @playback.PlaybackSnapshot,
) -> PlaybackSnapshot {
  match snapshot {
    @playback.PlaybackSnapshot::UntrackedPattern(pattern) =>
      UntrackedPattern(pattern)
    @playback.PlaybackSnapshot::TrackedPattern(pattern) =>
      TrackedPattern(pattern)
    @playback.PlaybackSnapshot::Song(song) => Song(SongMaterial::from_raw(song))
    @playback.PlaybackSnapshot::RepeatSong(song) =>
      RepeatSong(SongMaterial::from_raw(song))
  }
}

///|
pub fn PlaybackSnapshot::revision(
  self : PlaybackSnapshot,
) -> @identity.Revision {
  self.raw().revision()
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  self.raw().song_layout_revision()
}

///|
/// Number of source entries, including occurrences outside the current cycle.
pub fn PlaybackSnapshot::material_count(self : PlaybackSnapshot) -> Int32 {
  self.raw().material_count()
}

///|
pub fn PlaybackSnapshot::query(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  self.raw().query_events(arc)
}
