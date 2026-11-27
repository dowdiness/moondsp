///|
/// What a section plays: content that denotes one control pattern.
///
/// Song structure is generic over its content (ADR-0021). An untracked
/// pattern snapshot carries node paths; a tracked one also carries source
/// provenance, which consumers read through `SongEntry::content`.
pub trait SongContent {
  fn pat(Self) -> @pattern.Pat[@score.ScoreEvent]
  /// What playback plays of this content.
  fn playback(Self) -> @pattern.PlaybackPattern[@score.ScoreEvent]
}

///|
pub impl SongContent for @pattern.UntrackedPatternSnapshot[@score.ScoreEvent] with fn pat(
  self,
) {
  self.pat()
}

///|
pub impl SongContent for @pattern.UntrackedPatternSnapshot[@score.ScoreEvent] with fn playback(
  self,
) {
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
