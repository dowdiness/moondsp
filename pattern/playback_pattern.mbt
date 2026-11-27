///|
/// What a player plays of one pattern, whether or not its events carry event
/// origins. An untracked snapshot, a tracked snapshot and a plain `Pat` all
/// become one, so playback has one path whose events carry an origin when
/// their material has one.
pub struct PlaybackPattern[A] {
  priv material : PlaybackMaterial[A]
}

///|
priv enum PlaybackMaterial[A] {
  Untracked(UntrackedPatternSnapshot[A])
  Tracked(TrackedPatternSnapshot[A])
  /// A plain pattern's canonical entries, computed once.
  Plain(Array[Pat[A]])
}

///|
pub fn[A] UntrackedPatternSnapshot::playback(
  self : UntrackedPatternSnapshot[A],
) -> PlaybackPattern[A] {
  { material: Untracked(self), }
}

///|
pub fn[A] TrackedPatternSnapshot::playback(
  self : TrackedPatternSnapshot[A],
) -> PlaybackPattern[A] {
  { material: Tracked(self), }
}

///|
/// A pattern with no snapshot: no revision, no node paths, no origins.
pub fn[A] Pat::playback(self : Pat[A]) -> PlaybackPattern[A] {
  { material: Plain(self.entries()), }
}

///|
/// The snapshot's revision; a plain pattern has none.
pub fn[A] PlaybackPattern::revision(
  self : PlaybackPattern[A],
) -> @identity.Revision? {
  match self.material {
    Untracked(snapshot) => Some(snapshot.revision())
    Tracked(snapshot) => Some(snapshot.revision())
    Plain(_) => None
  }
}

///|
/// The canonical entries playback keys its materials by, in
/// `Pat::entries` order.
pub fn[A] PlaybackPattern::entries(self : PlaybackPattern[A]) -> Array[Pat[A]] {
  match self.material {
    Untracked(snapshot) => snapshot.pat().entries()
    Tracked(snapshot) => snapshot.pat().entries()
    Plain(entries) => entries
  }
}

///|
/// This pattern for material that entered `delay` after its origin
/// (ADR-0025), or `None` when entering changes nothing.
pub fn[A : WithControls] PlaybackPattern::entered(
  self : PlaybackPattern[A],
  delay : Rational,
) -> PlaybackPattern[A]? {
  match self.material {
    Untracked(snapshot) =>
      Some({ material: Untracked(snapshot.entered(delay)), })
    Tracked(snapshot) => Some({ material: Tracked(snapshot.entered(delay)), })
    Plain(_) => None
  }
}

///|
/// Entry `index`'s events over `arc`, each passed to `each` with `placement`, its node
/// path and its event origin when the material has them. Invalid indexes
/// return an empty result.
pub fn[A : WithControls, B] PlaybackPattern::query_for_entry(
  self : PlaybackPattern[A],
  index : Int32,
  arc : TimeSpan,
  placement : Placement,
  each : (Placement, Event[A], PatternNodePath?, Controls, EventWithOrigin[A]?) -> B,
) -> Array[B] {
  let result : Array[B] = []
  match self.material {
    Untracked(snapshot) => {
      let events = snapshot.query_sourced_events_for_entry(index, arc)
      for i = 0; i < events.length(); i = i + 1 {
        let event = events[i]
        result.push(
          each(placement, event.event, Some(event.path), event.controls, None),
        )
      }
    }
    Tracked(snapshot) => {
      let events = snapshot.query_for_entry(index, arc)
      for i = 0; i < events.length(); i = i + 1 {
        let event = events[i]
        result.push(
          each(
            placement,
            event.event,
            Some(event.scope),
            event.controls,
            Some(event),
          ),
        )
      }
    }
    Plain(entries) =>
      if entries.get(index) is Some(entry) {
        let events = entry.query(arc)
        for i = 0; i < events.length(); i = i + 1 {
          let event = events[i]
          result.push(
            each(
              placement,
              event,
              None,
              Controls::fixed(event.value.controls()),
              None,
            ),
          )
        }
      }
  }
  result
}
