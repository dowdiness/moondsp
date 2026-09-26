///|
/// A playback event paired with the material version that produced it.
pub struct PlaybackSourcedEvent {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv origin : @model.VoiceOrigin
  priv source_origin : @pattern.EventOrigin?
}

///|
pub fn PlaybackSourcedEvent::anonymous(
  event : @pattern.Event[@pattern.ControlMap],
) -> PlaybackSourcedEvent {
  { event, origin: @model.VoiceOrigin::Anonymous, source_origin: None, }
}

///|
pub fn PlaybackSourcedEvent::source_origin(
  self : PlaybackSourcedEvent,
) -> @pattern.EventOrigin? {
  self.source_origin
}

///|
pub fn PlaybackSourcedEvent::event(
  self : PlaybackSourcedEvent,
) -> @pattern.Event[@pattern.ControlMap] {
  self.event
}

///|
pub fn PlaybackSourcedEvent::origin(
  self : PlaybackSourcedEvent,
) -> @model.VoiceOrigin {
  self.origin
}

///|
pub enum PlaybackSnapshot {
  Pattern(@pattern.PatternSnapshot[@pattern.ControlMap])
  PatternWithOrigins(@pattern.PatternSnapshotWithOrigins[@pattern.ControlMap])
  Song(@song.SongSnapshot[@pattern.ControlMap])
  RepeatSong(@song.SongSnapshot[@pattern.ControlMap])
}

///|
pub fn PlaybackSnapshot::pattern_with_origins(
  snapshot : @pattern.PatternSnapshotWithOrigins[@pattern.ControlMap],
) -> PlaybackSnapshot {
  PatternWithOrigins(snapshot)
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
pub fn PlaybackSnapshot::repeat_song(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  RepeatSong(snapshot)
}

///|
pub fn PlaybackSnapshot::revision(
  self : PlaybackSnapshot,
) -> @identity.Revision {
  match self {
    Pattern(snapshot) => snapshot.revision()
    PatternWithOrigins(snapshot) => snapshot.revision()
    Song(snapshot) | RepeatSong(snapshot) => snapshot.revision()
  }
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  match self {
    Pattern(_) | PatternWithOrigins(_) => None
    Song(snapshot) | RepeatSong(snapshot) => Some(snapshot.layout_revision())
  }
}

///|
/// Count source entries independently of the current play position.
pub fn PlaybackSnapshot::material_count(self : PlaybackSnapshot) -> Int {
  match self {
    Pattern(snapshot) => snapshot.pat().entries().length()
    PatternWithOrigins(snapshot) => snapshot.pat().entries().length()
    Song(snapshot) | RepeatSong(snapshot) =>
      for occurrence in snapshot.song().occurrences(); count = 0 {
        continue count +
          occurrence
          .section()
          .body()
          .fast(occurrence.section().scope().rate())
          .entries()
          .length()
      } nobreak {
        count
      }
  }
}

///|
fn PlaybackSnapshot::cycle_at(
  self : PlaybackSnapshot,
  now : @pattern.Rational,
) -> Int64 {
  match self {
    RepeatSong(snapshot) if snapshot.song().duration() >
      @pattern.Rational::from_int(0) =>
      (now / snapshot.song().duration()).floor()
    _ => 0L
  }
}

///|
fn PlaybackSnapshot::offset_at(
  self : PlaybackSnapshot,
  cycle : Int64,
) -> @pattern.Rational {
  match self {
    RepeatSong(snapshot) =>
      snapshot.song().duration() * @pattern.Rational::new(cycle, 1L)
    _ => @pattern.Rational::from_int(0)
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
  priv mut song_loop : (@pattern.Rational, @pattern.Rational)?
}

///|
pub fn PlaybackState::PlaybackState() -> PlaybackState {
  { running: None, pending: None, song_loop: None, }
}

///|
pub fn PlaybackState::can_set_song_loop(
  self : PlaybackState,
  begin : @pattern.Rational,
  end_ : @pattern.Rational,
) -> Bool {
  guard begin >= @pattern.Rational::from_int(0) && begin < end_ else {
    return false
  }
  guard self.running is Some(run) else { return false }
  guard run.snapshot is (Song(snapshot) | RepeatSong(snapshot)) else {
    return false
  }
  end_ <= snapshot.song().duration()
}

///|
pub fn PlaybackState::can_seek_song(
  self : PlaybackState,
  position : @pattern.Rational,
) -> Bool {
  guard self.running is Some(run) else { return false }
  guard run.snapshot is (Song(snapshot) | RepeatSong(snapshot)) else {
    return false
  }
  position >= @pattern.Rational::from_int(0) &&
  position < snapshot.song().duration()
}

///|
/// Change the accepted song's half-open repeat range without replacing its
/// accepted material. The caller must validate all routes before applying it.
pub fn PlaybackState::set_song_loop(
  self : PlaybackState,
  begin : @pattern.Rational,
  end_ : @pattern.Rational,
) -> Bool {
  guard begin >= @pattern.Rational::from_int(0) && begin < end_ else {
    return false
  }
  guard self.running is Some(run) else { return false }
  guard run.snapshot is (Song(snapshot) | RepeatSong(snapshot)) else {
    return false
  }
  guard end_ <= snapshot.song().duration() else { return false }
  self.song_loop = Some((begin, end_))
  true
}

///|
pub fn PlaybackState::clear_song_loop(self : PlaybackState) -> Unit {
  self.song_loop = None
}

///|
pub(all) struct PlaybackInspection {
  current : PlaybackSnapshot?
  staged : PlaybackSnapshot?
  pending_materials : Int
  skipped_materials : Int
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
  let now = match self.song_loop {
    None => now
    Some((begin, end_)) =>
      if now < begin {
        begin
      } else {
        let duration = end_ - begin
        let elapsed = now - begin
        begin +
        elapsed -
        duration * @pattern.Rational::new((elapsed / duration).floor(), 1L)
      }
  }
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
  material_limit~ : Int,
  restart~ : Bool,
) -> PlaybackState? {
  guard snapshot.material_count() <= material_limit else { return None }
  let proposed = PlaybackState()
  proposed.song_loop = if restart { None } else { self.song_loop }
  proposed.running = if restart { None } else { self.running }
  proposed.pending = Some(snapshot)
  proposed.commit_pending(now)
  guard proposed.running is Some(run) && run.entries.length() <= material_limit else {
    return None
  }
  Some(proposed)
}

///|
/// Install an already-checked state in the same serialized owner operation.
pub fn PlaybackState::install_acceptance(
  self : PlaybackState,
  proposed : PlaybackState,
) -> Unit {
  self.running = proposed.running
  self.pending = proposed.pending
  self.song_loop = proposed.song_loop
}

///|
pub fn PlaybackState::reset(self : PlaybackState) -> Unit {
  self.running = None
  self.pending = None
  self.song_loop = None
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
pub fn PlaybackState::skipped_entry_count(self : PlaybackState) -> Int {
  match self.running {
    None => 0
    Some(run) => run.entries.iter().filter(entry => entry.is_skipped()).count()
  }
}

///|
pub fn PlaybackState::inspect(self : PlaybackState) -> PlaybackInspection {
  {
    current: self.running.map(run => run.snapshot),
    staged: self.pending,
    pending_materials: match self.running {
      None => 0
      Some(run) =>
        run.entries.iter().filter(entry => entry.has_pending()).count()
    },
    skipped_materials: self.skipped_entry_count(),
  }
}

///|
/// Split at repetition boundaries, rebuilding the next repetition from the
/// latest accepted snapshot even if the boundary falls inside an audio block.
/// Queries never mutate the owner; a subsequent query of the same span agrees.
fn[A] PlaybackRun::query(
  self : PlaybackRun,
  arc : @pattern.TimeSpan,
  query : (Array[EntryState], @pattern.TimeSpan) -> Array[A],
  shift : (A, @pattern.Rational) -> A,
) -> Array[A] {
  guard self.snapshot is RepeatSong(snapshot) else {
    return query(self.entries, arc)
  }
  let duration = snapshot.song().duration()
  guard duration > @pattern.Rational::from_int(0) else { return [] }
  let result : Array[A] = []
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
    let local_arc = @pattern.TimeSpan::new(cursor - offset, end_ - offset)
    for event in query(entries, local_arc) {
      result.push(shift(event, offset))
    }
    cursor = end_
  }
  result
}

///|
fn[A] PlaybackState::query(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
  query : (Array[EntryState], @pattern.TimeSpan) -> Array[A],
  shift : (A, @pattern.Rational) -> A,
) -> Array[A] {
  match self.running {
    None => []
    Some(run) =>
      match self.song_loop {
        None => run.query(arc, query, shift)
        Some((begin, end_)) => {
          let duration = end_ - begin
          let mut result : Array[A]? = None
          let mut cursor = if arc.begin < begin { begin } else { arc.begin }
          while cursor < arc.end_ {
            let elapsed = cursor - begin
            let cycle = (elapsed / duration).floor()
            let source_begin = begin +
              elapsed -
              duration * @pattern.Rational::new(cycle, 1L)
            let available = end_ - source_begin
            let remaining = arc.end_ - cursor
            let span = if available < remaining { available } else { remaining }
            let source_end = source_begin + span
            let wall_offset = cursor - source_begin
            let events = query(
              run.entries,
              @pattern.TimeSpan::new(source_begin, source_end),
            )
            if wall_offset != @pattern.Rational::from_int(0) {
              for index in 0..<events.length() {
                events[index] = shift(events[index], wall_offset)
              }
            }
            match result {
              Some(combined) =>
                for value in events {
                  combined.push(value)
                }
              None => result = Some(events)
            }
            cursor = cursor + span
          }
          result.unwrap_or([])
        }
      }
  }
}

///|
pub fn PlaybackState::query_active_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.query(arc, query_entries, (event, offset) => event.shift(offset))
}

///|
pub fn PlaybackState::query_active_sourced_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  self.query(arc, query_sourced_entries, (sourced, offset) => {
    event: sourced.event.shift(offset),
    origin: sourced.origin,
    source_origin: sourced.source_origin,
  })
}

///|
pub fn PlaybackSnapshot::query_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  match self {
    Pattern(snapshot) => snapshot.query(arc)
    PatternWithOrigins(snapshot) =>
      snapshot.query(arc).map(event => event.event())
    Song(snapshot) => snapshot.query(arc)
    RepeatSong(_) =>
      PlaybackRun(self, self.start_entries(), self.cycle_at(arc.begin)).query(
        arc,
        query_entries,
        (event, offset) => event.shift(offset),
      )
  }
}
