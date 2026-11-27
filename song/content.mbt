///|
/// What a section plays: content that denotes one control pattern.
///
/// Song structure is generic over its content (ADR-0021). An untracked
/// pattern is content as it is; a tracked pattern snapshot also carries source
/// provenance, which consumers read through `SongSlice::content`.
pub trait SongContent {
  fn pat(Self) -> @pattern.Pat[@score.ScoreEvent]
  /// What playback plays of this content.
  fn playback(Self) -> @pattern.PlaybackPattern[@score.ScoreEvent]
}

///|
pub impl SongContent for @pattern.Pat[@score.ScoreEvent] with fn pat(self) {
  self
}

///|
pub impl SongContent for @pattern.Pat[@score.ScoreEvent] with fn playback(self) {
  self.playback()
}

///|
pub impl SongContent for @pattern.TrackedPatternSnapshot[@score.ScoreEvent] with fn pat(
  self,
) {
  self.pat()
}

///|
pub impl SongContent for @pattern.TrackedPatternSnapshot[@score.ScoreEvent] with fn playback(
  self,
) {
  self.playback()
}
