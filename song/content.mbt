///|
/// What a section plays: content that denotes one control pattern.
///
/// Song structure is generic over its content (ADR-0021). An anonymous runtime
/// pattern is content as it is; an exact pattern snapshot also carries source
/// provenance, which consumers read through `SongSlice::content`.
pub trait SongContent {
  fn pat(Self) -> @pattern.Pat[@score.ScoreEvent]
}

///|
pub impl SongContent for @pattern.Pat[@score.ScoreEvent] with fn pat(self) {
  self
}

///|
pub impl SongContent for @pattern.PatternSnapshotWithOrigins[@score.ScoreEvent] with fn pat(
  self,
) {
  self.pat()
}
