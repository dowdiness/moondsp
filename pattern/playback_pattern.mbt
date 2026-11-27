///|
/// What a player plays of one pattern snapshot, whether or not its events
/// carry event origins. Untracked and tracked snapshots both become one, so
/// playback has one path whose events carry an origin when their material
/// has one.
pub struct PlaybackPattern[A] {
  priv material : PlaybackMaterial[A]
}

///|
priv enum PlaybackMaterial[A] {
  Untracked(UntrackedPatternSnapshot[A])
  Tracked(TrackedPatternSnapshot[A])
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
pub fn[A] PlaybackPattern::revision(
  self : PlaybackPattern[A],
) -> @identity.Revision {
  match self.material {
    Untracked(snapshot) => snapshot.revision()
    Tracked(snapshot) => snapshot.revision()
  }
}

///|
/// The canonical entries playback keys its materials by, in
/// `Pat::entries` order.
pub fn[A] PlaybackPattern::entries(self : PlaybackPattern[A]) -> Array[Pat[A]] {
  match self.material {
    Untracked(snapshot) => snapshot.pat().entries()
    Tracked(snapshot) => snapshot.pat().entries()
  }
}

///|
/// This pattern for material that entered `delay` after its origin: its
/// one-shot signals start there (ADR-0025).
pub fn[A : WithControls] PlaybackPattern::entered(
  self : PlaybackPattern[A],
  delay : Rational,
) -> PlaybackPattern[A] {
  match self.material {
    Untracked(snapshot) => { material: Untracked(snapshot.entered(delay)), }
    Tracked(snapshot) => { material: Tracked(snapshot.entered(delay)), }
  }
}

///|
/// Entry `index`'s events over `arc`, on the playback clock: content time
/// placed by `within` (a song section's placement, when there is one), then
/// by `at`, the material's placement on the playback clock. Each event is
/// handed to `each` with its node path, its controls, and its event origin
/// when the material is tracked. Invalid indexes return an empty result.
pub fn[A : WithControls, B] PlaybackPattern::query_for_entry(
  self : PlaybackPattern[A],
  index : Int32,
  arc : TimeSpan,
  at~ : Placement,
  within? : Placement,
  each : (Event[A], PatternNodePath, Controls, EventWithOrigin[A]?) -> B,
) -> Array[B] {
  match self.material {
    Untracked(snapshot) =>
      snapshot
      .query_sourced_events_for_entry(index, arc)
      .map(event => {
        each(
          on_playback_clock(event.event, within, at),
          event.path,
          controls_on_playback_clock(event.controls, within, at),
          None,
        )
      })
    Tracked(snapshot) =>
      snapshot
      .query_for_entry(index, arc)
      .map(event => {
        each(
          on_playback_clock(event.event, within, at),
          event.scope,
          controls_on_playback_clock(event.controls, within, at),
          Some(event),
        )
      })
  }
}

///|
fn[A] on_playback_clock(
  event : Event[A],
  within : Placement?,
  at : Placement,
) -> Event[A] {
  match within {
    Some(within) => event.placed(within).placed(at)
    None => event.placed(at)
  }
}

///|
fn controls_on_playback_clock(
  controls : Controls,
  within : Placement?,
  at : Placement,
) -> Controls {
  let placed = match within {
    Some(within) => controls.placed(within)
    None => controls
  }
  placed.on_playback_clock(at.origin)
}
