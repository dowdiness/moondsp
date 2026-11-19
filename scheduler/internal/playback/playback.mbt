///|
/// A playback event paired with the material version that produced it.
pub struct PlaybackSourcedEvent {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv origin : @model.VoiceOrigin
  priv source_origin : @pattern.EventOrigin?
  priv source_frame : @identity.SourceFrameId?
  priv source_start : Double
  priv source_pitch : Double
  priv controls : @pattern.Controls
}

///|
pub fn PlaybackSourcedEvent::anonymous(
  event : @pattern.Event[@pattern.ControlMap],
) -> PlaybackSourcedEvent {
  {
    event,
    origin: @model.VoiceOrigin::Anonymous,
    source_origin: None,
    source_frame: None,
    source_start: -1.0,
    source_pitch: -1.0,
    controls: @pattern.Controls::fixed(event.value),
  }
}

///|
/// This event's controls, on the playback clock.
pub fn PlaybackSourcedEvent::controls(
  self : PlaybackSourcedEvent,
) -> @pattern.Controls {
  self.controls
}

///|
pub fn PlaybackSourcedEvent::source_origin(
  self : PlaybackSourcedEvent,
) -> @pattern.EventOrigin? {
  self.source_origin
}

///|
pub fn PlaybackSourcedEvent::source_frame(
  self : PlaybackSourcedEvent,
) -> @identity.SourceFrameId? {
  self.source_frame
}

///|
pub fn PlaybackSourcedEvent::source_start(
  self : PlaybackSourcedEvent,
) -> Double {
  self.source_start
}

///|
pub fn PlaybackSourcedEvent::source_pitch(
  self : PlaybackSourcedEvent,
) -> Double {
  self.source_pitch
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
  Pattern(@pattern.PatternSnapshot)
  PatternWithOrigins(@pattern.PatternSnapshotWithOrigins)
  Song(SongMaterial)
  RepeatSong(SongMaterial)
}

///|
/// A lowered song the scheduler can play. Its sections hold either anonymous
/// runtime patterns or exact, origin-bearing pattern snapshots (ADR-0021).
pub(all) enum SongMaterial {
  Runtime(@song.SongSnapshot[@pattern.Pat[@pattern.ControlMap]])
  Exact(@song.SongSnapshot[@pattern.PatternSnapshotWithOrigins])
}

///|
fn SongMaterial::revision(self : SongMaterial) -> @identity.Revision {
  match self {
    Runtime(snapshot) => snapshot.revision()
    Exact(snapshot) => snapshot.revision()
  }
}

///|
fn SongMaterial::layout_revision(self : SongMaterial) -> @identity.Revision {
  match self {
    Runtime(snapshot) => snapshot.layout_revision()
    Exact(snapshot) => snapshot.layout_revision()
  }
}

///|
fn SongMaterial::duration(self : SongMaterial) -> @pattern.Rational {
  match self {
    Runtime(snapshot) => snapshot.song().duration()
    Exact(snapshot) => snapshot.song().duration()
  }
}

///|
fn SongMaterial::entry_count(self : SongMaterial) -> Int32 {
  match self {
    Runtime(snapshot) => snapshot.entries().length()
    Exact(snapshot) => snapshot.entries().length()
  }
}

///|
fn SongMaterial::query(
  self : SongMaterial,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  match self {
    Runtime(snapshot) => snapshot.song().query(arc)
    Exact(snapshot) => snapshot.song().query(arc)
  }
}

///|
pub fn PlaybackSnapshot::pattern_with_origins(
  snapshot : @pattern.PatternSnapshotWithOrigins,
) -> PlaybackSnapshot {
  PatternWithOrigins(snapshot)
}

///|
pub fn PlaybackSnapshot::pattern(
  snapshot : @pattern.PatternSnapshot,
) -> PlaybackSnapshot {
  Pattern(snapshot)
}

///|
pub fn PlaybackSnapshot::song(snapshot : SongMaterial) -> PlaybackSnapshot {
  Song(snapshot)
}

///|
pub fn PlaybackSnapshot::repeat_song(
  snapshot : SongMaterial,
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
    Song(song) | RepeatSong(song) => song.revision()
  }
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  match self {
    Pattern(_) | PatternWithOrigins(_) => None
    Song(song) | RepeatSong(song) => Some(song.layout_revision())
  }
}

///|
/// Count source entries independently of the current play position.
pub fn PlaybackSnapshot::material_count(self : PlaybackSnapshot) -> Int32 {
  match self {
    Pattern(snapshot) => snapshot.pat().entries().length()
    PatternWithOrigins(snapshot) => snapshot.pat().entries().length()
    Song(song) | RepeatSong(song) => song.entry_count()
  }
}

///|
fn PlaybackSnapshot::cycle_at(
  self : PlaybackSnapshot,
  now : @pattern.Rational,
) -> Int64 {
  match self {
    RepeatSong(song) if song.duration() > @pattern.Rational::from_int(0) =>
      (now / song.duration()).floor()
    _ => 0L
  }
}

///|
fn PlaybackSnapshot::offset_at(
  self : PlaybackSnapshot,
  cycle : Int64,
) -> @pattern.Rational {
  match self {
    RepeatSong(song) => song.duration() * @pattern.Rational(cycle, 1L)
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
}

///|
pub fn PlaybackState::PlaybackState() -> PlaybackState {
  { running: None, pending: None, }
}

///|
pub(all) struct PlaybackInspection {
  current : PlaybackSnapshot?
  staged : PlaybackSnapshot?
  pending_materials : Int32
  skipped_materials : Int32
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
  guard self.snapshot is RepeatSong(song) else {
    return query(self.entries, arc)
  }
  let duration = song.duration()
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
    let local_arc = @pattern.TimeSpan(cursor - offset, end_ - offset)
    for event in query(entries, local_arc) {
      result.push(shift(event, offset))
    }
    cursor = end_
  }
  result
}

///|
pub fn PlaybackState::query_active_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  match self.running {
    None => []
    Some(run) =>
      run.query(arc, query_entries, (event, offset) => event.shift(offset))
  }
}

///|
pub fn PlaybackState::query_active_sourced_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  match self.running {
    None => []
    Some(run) =>
      run.query(arc, query_sourced_entries, (sourced, offset) => {
        let placement = @pattern.Placement(origin=offset)
        {
          event: sourced.event.placed(placement),
          origin: sourced.origin,
          source_origin: sourced.source_origin,
          source_frame: sourced.source_frame,
          source_start: sourced.source_start,
          source_pitch: sourced.source_pitch,
          controls: sourced.controls.placed(placement),
        }
      })
  }
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
    Song(song) => song.query(arc)
    RepeatSong(_) =>
      PlaybackRun(self, self.start_entries(), self.cycle_at(arc.begin)).query(
        arc,
        query_entries,
        (event, offset) => event.shift(offset),
      )
  }
}
