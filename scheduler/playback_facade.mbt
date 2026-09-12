///|

///|
/// Prepared scheduler input for the next authoring snapshot commit.
///
/// Pattern and song snapshots share the same pending slot so callers have one
/// coherent staging boundary when higher-level live orchestration prepares the
/// next playback state.
pub enum PlaybackSnapshot {
  Pattern(@pattern.PatternSnapshot[@pattern.ControlMap])
  Song(@song.SongSnapshot[@pattern.ControlMap])
}

///|
pub fn PlaybackSnapshot::pattern(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  Pattern(snapshot)
}

///|
pub fn PlaybackSnapshot::song(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  Song(snapshot)
}

///|
fn PlaybackSnapshot::raw(self : PlaybackSnapshot) -> @playback.PlaybackSnapshot {
  match self {
    Pattern(snapshot) => @playback.PlaybackSnapshot::pattern(snapshot)
    Song(snapshot) => @playback.PlaybackSnapshot::song(snapshot)
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
pub fn PlaybackSnapshot::query(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.raw().query_events(arc)
}
