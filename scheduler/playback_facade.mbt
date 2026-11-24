///|
/// A lowered song the scheduler can play. Its sections hold either anonymous
/// runtime patterns or exact, origin-bearing pattern snapshots (ADR-0021).
pub(all) enum SongMaterial {
  Runtime(@song.SongSnapshot[@pattern.Pat[@score.ScoreEvent]])
  Exact(
    @song.SongSnapshot[@pattern.PatternSnapshotWithOrigins[@score.ScoreEvent]],
  )
}

///|
fn SongMaterial::raw(self : SongMaterial) -> @playback.SongMaterial {
  match self {
    Runtime(snapshot) => Runtime(snapshot)
    Exact(snapshot) => Exact(snapshot)
  }
}

///|
fn SongMaterial::from_raw(material : @playback.SongMaterial) -> SongMaterial {
  match material {
    Runtime(snapshot) => Runtime(snapshot)
    Exact(snapshot) => Exact(snapshot)
  }
}

///|
/// Prepared scheduler input for the next authoring snapshot commit.
///
/// Pattern and song snapshots share the same pending slot so callers have one
/// coherent staging boundary when higher-level live orchestration prepares the
/// next playback state.
pub enum PlaybackSnapshot {
  Pattern(@pattern.PatternSnapshot[@score.ScoreEvent])
  PatternWithOrigins(@pattern.PatternSnapshotWithOrigins[@score.ScoreEvent])
  Song(SongMaterial)
  RepeatSong(SongMaterial)
}

///|
pub fn PlaybackSnapshot::pattern(
  snapshot : @pattern.PatternSnapshot[@score.ScoreEvent],
) -> PlaybackSnapshot {
  Pattern(snapshot)
}

///|
pub fn PlaybackSnapshot::pattern_with_origins(
  snapshot : @pattern.PatternSnapshotWithOrigins[@score.ScoreEvent],
) -> PlaybackSnapshot {
  PatternWithOrigins(snapshot)
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
    Pattern(snapshot) => @playback.PlaybackSnapshot::pattern(snapshot)
    PatternWithOrigins(snapshot) =>
      @playback.PlaybackSnapshot::pattern_with_origins(snapshot)
    Song(song) => @playback.PlaybackSnapshot::song(song.raw())
    RepeatSong(song) => @playback.PlaybackSnapshot::repeat_song(song.raw())
  }
}

///|
fn PlaybackSnapshot::from_raw(
  snapshot : @playback.PlaybackSnapshot,
) -> PlaybackSnapshot {
  match snapshot {
    @playback.PlaybackSnapshot::Pattern(pattern) => Pattern(pattern)
    @playback.PlaybackSnapshot::PatternWithOrigins(pattern) =>
      PatternWithOrigins(pattern)
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
