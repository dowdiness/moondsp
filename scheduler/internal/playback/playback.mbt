///|
/// A playback event paired with the material version that produced it.
/// `source` is the lowered event with its authored origin, which only tracked
/// material has; it is `None` for untracked material. Read only its origin,
/// source frame, source start and sound from it: those do not depend on where
/// the event is placed. Its `event()` and `controls()` are not placed; use this
/// type's own `event()` and `controls()` for times and controls.
pub struct PlaybackSourcedEvent {
  priv event : @pattern.Event[@score.ScoreEvent]
  priv origin : @model.VoiceOrigin
  priv source : @pattern.EventWithOrigin[@score.ScoreEvent]?
  priv controls : @pattern.Controls
}

///|
/// This event's controls, on the playback clock.
pub fn PlaybackSourcedEvent::controls(
  self : PlaybackSourcedEvent,
) -> @pattern.Controls {
  self.controls
}

///|
/// The tracked source of this event, as described on the type. `None` for
/// untracked material.
pub fn PlaybackSourcedEvent::source(
  self : PlaybackSourcedEvent,
) -> @pattern.EventWithOrigin[@score.ScoreEvent]? {
  self.source
}

///|
pub fn PlaybackSourcedEvent::event(
  self : PlaybackSourcedEvent,
) -> @pattern.Event[@score.ScoreEvent] {
  self.event
}

///|
pub fn PlaybackSourcedEvent::origin(
  self : PlaybackSourcedEvent,
) -> @model.VoiceOrigin {
  self.origin
}

///|
/// Playback material built once from a pattern or a lowered song: its
/// arrangement, its repetition period, and one entry per canonical material.
/// Whether events carry event origins is the material's own business
/// (`@pattern.PlaybackPattern`); nothing here branches on it.
pub struct PlaybackSnapshot {
  /// A song's occurrences; a pattern has none.
  priv arrangement : Array[OccurrenceSpan]?
  /// How long one repetition of a repeating song lasts.
  priv period : @pattern.Rational?
  /// Where a song that does not repeat ends.
  priv finite_end : @pattern.Rational?
  priv specs : Array[EntrySpec]
}

///|
/// Where one occurrence of a song plays.
priv struct OccurrenceSpan {
  id : @identity.OccurrenceId
  start : @pattern.Rational
  end_ : @pattern.Rational
}

///|
/// A pattern that plays forever.
pub fn PlaybackSnapshot::pattern(
  pattern : @pattern.PlaybackPattern[@score.ScoreEvent],
) -> PlaybackSnapshot {
  {
    arrangement: None,
    period: None,
    finite_end: None,
    specs: pattern_entry_specs(pattern),
  }
}

///|
/// A lowered song that ends after its last occurrence, or repeats without
/// resetting the transport when `repeat` is true.
pub fn[C : @song.SongContent] PlaybackSnapshot::song(
  snapshot : @song.SongSnapshot[C],
  repeat~ : Bool = false,
) -> PlaybackSnapshot {
  {
    arrangement: Some(
      snapshot
      .song()
      .occurrences()
      .map(occurrence => {
        id: occurrence.id(),
        start: occurrence.start(),
        end_: occurrence.end_(),
      }),
    ),
    period: if repeat {
      Some(snapshot.song().duration())
    } else {
      None
    },
    finite_end: if repeat {
      None
    } else {
      Some(snapshot.song().duration())
    },
    specs: song_entry_specs(snapshot),
  }
}

///|
/// Whether this is a song rather than a pattern.
pub fn PlaybackSnapshot::is_song(self : PlaybackSnapshot) -> Bool {
  self.arrangement is Some(_)
}

///|
/// How long one repetition lasts, for a song that repeats.
pub fn PlaybackSnapshot::period(self : PlaybackSnapshot) -> @pattern.Rational? {
  self.period
}

///|
/// Where a song that does not repeat ends.
pub fn PlaybackSnapshot::finite_end(
  self : PlaybackSnapshot,
) -> @pattern.Rational? {
  self.finite_end
}

///|
/// Whether `next` can replace `self` while playing: both are patterns, or
/// both are songs that repeat alike and place the same occurrences at the
/// same spans. A finite occurrence never joins midway, so a song arranged
/// differently would leave started occurrences silent until a new Play.
fn PlaybackSnapshot::continues_as(
  self : PlaybackSnapshot,
  next : PlaybackSnapshot,
) -> Bool {
  match (self.arrangement, next.arrangement) {
    (None, None) => true
    (Some(current), Some(arrangement)) =>
      self.period == next.period &&
      current.length() == arrangement.length() &&
      current
      .iter()
      .all(span => {
        arrangement
        .iter()
        .any(other => {
          other.id == span.id &&
          other.start == span.start &&
          other.end_ == span.end_
        })
      })
    _ => false
  }
}

///|
/// Count source entries independently of the current play position.
pub fn PlaybackSnapshot::material_count(self : PlaybackSnapshot) -> Int32 {
  self.specs.length()
}

///|
fn PlaybackSnapshot::cycle_at(
  self : PlaybackSnapshot,
  now : @pattern.Rational,
) -> Int64 {
  match self.period {
    Some(period) if period > @pattern.Rational::from_int(0) =>
      (now / period).floor()
    _ => 0L
  }
}

///|
fn PlaybackSnapshot::offset_at(
  self : PlaybackSnapshot,
  cycle : Int64,
) -> @pattern.Rational {
  match self.period {
    Some(period) => period * @pattern.Rational(cycle, 1L)
    None => @pattern.Rational::from_int(0)
  }
}

///|
/// A running entry set cannot exist without the snapshot that owns its identity.
priv struct PlaybackRun {
  snapshot : PlaybackSnapshot
  entries : Array[EntryState]
  cycle : Int64
}

///|
fn PlaybackRun::PlaybackRun(
  snapshot : PlaybackSnapshot,
  entries : Array[EntryState],
  cycle : Int64,
) -> PlaybackRun {
  { snapshot, entries, cycle, }
}

///|
pub struct PlaybackState {
  priv mut running : PlaybackRun?
  priv mut pending : PlaybackSnapshot?
}

///|
pub fn PlaybackState::PlaybackState() -> PlaybackState {
  { running: None, pending: None, }
}

///|
pub fn PlaybackState::queue(
  self : PlaybackState,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.pending = Some(snapshot)
}

///|
pub fn PlaybackState::commit_pending(
  self : PlaybackState,
  now : @pattern.Rational,
) -> Unit {
  let running = self.running.map(run => {
    let cycle = run.snapshot.cycle_at(now)
    let entries = if cycle != run.cycle {
      run.snapshot.start_entries()
    } else {
      run.entries
    }
    PlaybackRun(
      run.snapshot,
      settle_entries(entries, now - run.snapshot.offset_at(cycle)),
      cycle,
    )
  })
  self.running = match self.pending {
    None => running
    Some(snapshot) => {
      let cycle = snapshot.cycle_at(now)
      let local_now = now - snapshot.offset_at(cycle)
      let entries = match running {
        None => snapshot.start_entries()
        Some(run) => snapshot.reconcile_entries(run.entries, local_now)
      }
      Some(PlaybackRun(snapshot, settle_entries(entries, local_now), cycle))
    }
  }
  self.pending = None
}

///|
/// Build a bounded owner update without changing the live state. The snapshot
/// limit also covers entries rebuilt by a future song repetition.
pub fn PlaybackState::prepare_acceptance(
  self : PlaybackState,
  snapshot : PlaybackSnapshot,
  now : @pattern.Rational,
  material_limit~ : Int32,
  restart~ : Bool,
) -> PlaybackState? {
  guard snapshot.material_count() <= material_limit else { return None }
  let proposed = PlaybackState()
  proposed.running = if restart { None } else { self.running }
  proposed.pending = Some(snapshot)
  proposed.commit_pending(now)
  guard proposed.running is Some(run) && run.entries.length() <= material_limit else {
    return None
  }
  Some(proposed)
}

///|
/// Whether `snapshot` can replace the latest accepted snapshot without a
/// restart; see `PlaybackSnapshot::continues_as`. Nothing accepted yet
/// continues as anything.
pub fn PlaybackState::continues_as(
  self : PlaybackState,
  snapshot : PlaybackSnapshot,
) -> Bool {
  match self.latest() {
    Some(current) => current.continues_as(snapshot)
    None => true
  }
}

///|
/// The latest accepted snapshot's finite end. Matched directly, not through
/// `latest`, because the render path asks every block.
pub fn PlaybackState::finite_end(self : PlaybackState) -> @pattern.Rational? {
  match self.pending {
    Some(pending) => pending.finite_end
    None =>
      match self.running {
        Some(run) => run.snapshot.finite_end
        None => None
      }
  }
}

///|
/// The latest accepted snapshot: queued, or else running.
pub fn PlaybackState::latest(self : PlaybackState) -> PlaybackSnapshot? {
  match self.pending {
    Some(pending) => Some(pending)
    None => self.running.map(run => run.snapshot)
  }
}

///|
/// Install an already-checked state in the same serialized owner operation.
pub fn PlaybackState::install_acceptance(
  self : PlaybackState,
  proposed : PlaybackState,
) -> Unit {
  self.running = proposed.running
  self.pending = proposed.pending
}

///|
pub fn PlaybackState::reset(self : PlaybackState) -> Unit {
  self.running = None
  self.pending = None
}

///|
pub fn PlaybackState::has_pending(self : PlaybackState) -> Bool {
  guard self.pending is None else { return true }
  match self.running {
    Some(run) => run.entries.any(entry => entry.has_pending())
    None => false
  }
}

///|
pub fn PlaybackState::skipped_entry_count(self : PlaybackState) -> Int32 {
  match self.running {
    None => 0
    Some(run) => run.entries.iter().filter(entry => entry.is_skipped()).count()
  }
}

///|
/// Accepted material changes still waiting for a reserved entry boundary.
pub fn PlaybackState::pending_entry_count(self : PlaybackState) -> Int32 {
  match self.running {
    None => 0
    Some(run) => run.entries.iter().filter(entry => entry.has_pending()).count()
  }
}

///|
/// Split at repetition boundaries, rebuilding the next repetition from the
/// latest accepted snapshot even if the boundary falls inside an audio block.
/// Queries never mutate the owner; a subsequent query of the same span agrees.
fn PlaybackRun::query(
  self : PlaybackRun,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  guard self.snapshot.period is Some(duration) else {
    return query_sourced_entries(self.entries, arc)
  }
  guard duration > @pattern.Rational::from_int(0) else { return [] }
  let result : Array[PlaybackSourcedEvent] = []
  let mut cursor = arc.begin
  while cursor < arc.end_ {
    let cycle = self.snapshot.cycle_at(cursor)
    let offset = self.snapshot.offset_at(cycle)
    let end_ = if offset + duration < arc.end_ {
      offset + duration
    } else {
      arc.end_
    }
    let entries = if cycle == self.cycle {
      self.entries
    } else {
      self.snapshot.start_entries()
    }
    let local_arc = @pattern.TimeSpan(cursor - offset, end_ - offset)
    let placement = @pattern.Placement(origin=offset)
    for event in query_sourced_entries(entries, local_arc) {
      result.push({
        event: event.event.placed(placement),
        origin: event.origin,
        source: event.source,
        controls: event.controls.placed(placement),
      })
    }
    cursor = end_
  }
  result
}

///|
pub fn PlaybackState::query_active_sourced_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  match self.running {
    None => []
    Some(run) => run.query(arc)
  }
}

///|
pub fn PlaybackSnapshot::query_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  PlaybackRun(self, self.start_entries(), self.cycle_at(arc.begin))
  .query(arc)
  .map(event => event.event)
}
