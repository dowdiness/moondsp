///|
/// What a section plays: content that denotes one control pattern.
///
/// Song structure is generic over its content (ADR-0021). An anonymous runtime
/// pattern is content as it is; an exact pattern snapshot also carries source
/// provenance, which consumers read through `SongSlice::content`.
pub trait SongContent {
  fn pat(Self) -> @pattern.Pat[@pattern.ControlMap]
}

///|
pub impl SongContent for @pattern.Pat[@pattern.ControlMap] with fn pat(self) {
  self
}

///|
pub impl SongContent for @pattern.PatternSnapshotWithOrigins with fn pat(self) {
  self.pat()
}
