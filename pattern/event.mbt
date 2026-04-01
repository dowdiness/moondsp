///|
/// A value positioned in time with both "ideal" and "actual" spans.
///
/// WHY two spans:
/// - `whole` — the event's ideal duration (e.g., a full cycle for a pure value).
///   Phase 5 uses this to determine gate-on/gate-off timing for note events.
/// - `part` — the portion of the event intersecting the query arc. When a query
///   slices through the middle of an event, `part` is the intersection.
/// - `whole` is None for continuous (non-onset) signals that don't trigger notes.
///
/// All combinators must transform both `whole` and `part` independently.
pub struct Event[A] {
  whole : TimeSpan?
  part : TimeSpan
  value : A
} derive(Show)
