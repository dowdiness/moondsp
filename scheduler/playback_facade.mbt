///|
/// Prepared scheduler input for the next authoring snapshot commit: one
/// pattern or lowered song, built once. Patterns and songs share the same
/// pending slot so callers have one coherent staging boundary. Whether its
/// events carry event origins is decided by the material it was built from.
pub struct PlaybackSnapshot {
  priv raw : @playback.PlaybackSnapshot
}

///|
/// A pattern that plays forever: an untracked or tracked snapshot's
/// `playback()`.
pub fn PlaybackSnapshot::pattern(
  pattern : @pattern.PlaybackPattern[@score.ScoreEvent],
) -> PlaybackSnapshot {
  { raw: @playback.PlaybackSnapshot::pattern(pattern), }
}

///|
/// A lowered song that ends after its last occurrence, or repeats without
/// resetting the transport or releasing voices when `repeat` is true.
pub fn[C : @song.SongContent] PlaybackSnapshot::song(
  snapshot : @song.SongSnapshot[C],
  repeat~ : Bool = false,
) -> PlaybackSnapshot {
  { raw: @playback.PlaybackSnapshot::song(snapshot, repeat~), }
}

///|
/// Number of source entries, including occurrences outside the current cycle.
pub fn PlaybackSnapshot::material_count(self : PlaybackSnapshot) -> Int32 {
  self.raw.material_count()
}

///|
pub fn PlaybackSnapshot::query(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  self.raw.query_events(arc)
}
