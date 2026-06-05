///|
/// Internal provenance payload for an event queried from a playback snapshot.
pub struct PlaybackEventSource {
  priv pattern_nodes : Array[@identity.PatternNodeId]
  priv section : @identity.SectionId?
  priv layer : @identity.SectionLayerId?
  priv occurrence : @identity.OccurrenceId?
}

///|
fn PlaybackEventSource::pattern(
  pattern_nodes~ : Array[@identity.PatternNodeId],
) -> PlaybackEventSource {
  {
    pattern_nodes: pattern_nodes.copy(),
    section: None,
    layer: None,
    occurrence: None,
  }
}

///|
fn PlaybackEventSource::song(
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId,
) -> PlaybackEventSource {
  { pattern_nodes: [], section, layer, occurrence: Some(occurrence) }
}

///|
pub fn PlaybackEventSource::pattern_nodes(
  self : PlaybackEventSource,
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes.copy()
}

///|
pub fn PlaybackEventSource::section(
  self : PlaybackEventSource,
) -> @identity.SectionId? {
  self.section
}

///|
pub fn PlaybackEventSource::layer(
  self : PlaybackEventSource,
) -> @identity.SectionLayerId? {
  self.layer
}

///|
pub fn PlaybackEventSource::occurrence(
  self : PlaybackEventSource,
) -> @identity.OccurrenceId? {
  self.occurrence
}

///|
/// Internal event wrapper returned by playback snapshot queries.
pub struct PlaybackEventRecord {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv source : PlaybackEventSource
}

///|
fn PlaybackEventRecord::PlaybackEventRecord(
  event~ : @pattern.Event[@pattern.ControlMap],
  source~ : PlaybackEventSource,
) -> PlaybackEventRecord {
  { event, source }
}

///|
pub fn PlaybackEventRecord::event(
  self : PlaybackEventRecord,
) -> @pattern.Event[@pattern.ControlMap] {
  self.event
}

///|
pub fn PlaybackEventRecord::source(
  self : PlaybackEventRecord,
) -> PlaybackEventSource {
  self.source
}

///|
/// Internal prepared scheduler input for active/pending playback state.
pub enum PlaybackSnapshot {
  Pattern(@pattern.PatternSnapshot[@pattern.ControlMap])
  Song(@song.SongSnapshot[@pattern.ControlMap])
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
pub fn PlaybackSnapshot::revision(
  self : PlaybackSnapshot,
) -> @identity.Revision {
  match self {
    Pattern(snapshot) => snapshot.revision()
    Song(snapshot) => snapshot.revision()
  }
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  match self {
    Pattern(_) => None
    Song(snapshot) => Some(snapshot.layout_revision())
  }
}

///|
fn PlaybackSnapshot::is_pattern(self : PlaybackSnapshot) -> Bool {
  match self {
    Pattern(_) => true
    Song(_) => false
  }
}

///|
fn PlaybackSnapshot::is_song(self : PlaybackSnapshot) -> Bool {
  match self {
    Pattern(_) => false
    Song(_) => true
  }
}

///|
pub fn PlaybackSnapshot::query_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  match self {
    Pattern(snapshot) => query_pattern_events(snapshot, arc)
    Song(snapshot) => query_song_events(snapshot, arc)
  }
}

///|
pub fn PlaybackSnapshot::query_playback_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackEventRecord] {
  match self {
    Pattern(snapshot) => query_pattern_playback_events(snapshot, arc)
    Song(snapshot) => query_song_playback_events(snapshot, arc)
  }
}

///|
/// Internal active/pending playback snapshot queue. Pending commits are explicit
/// so the scheduler facade can preserve block-boundary commit semantics.
pub struct PlaybackState {
  priv mut active : PlaybackSnapshot?
  priv mut pending : PlaybackSnapshot?
}

///|
pub fn PlaybackState::PlaybackState() -> PlaybackState {
  { active: None, pending: None }
}

///|
pub fn PlaybackState::queue(
  self : PlaybackState,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.pending = Some(snapshot)
}

///|
pub fn PlaybackState::commit_pending(self : PlaybackState) -> Unit {
  match self.pending {
    Some(snapshot) => {
      self.active = Some(snapshot)
      self.pending = None
    }
    None => ()
  }
}

///|
pub fn PlaybackState::has_active_pattern(self : PlaybackState) -> Bool {
  match self.active {
    Some(snapshot) => snapshot.is_pattern()
    None => false
  }
}

///|
pub fn PlaybackState::has_pending_pattern(self : PlaybackState) -> Bool {
  match self.pending {
    Some(snapshot) => snapshot.is_pattern()
    None => false
  }
}

///|
pub fn PlaybackState::has_active_song(self : PlaybackState) -> Bool {
  match self.active {
    Some(snapshot) => snapshot.is_song()
    None => false
  }
}

///|
pub fn PlaybackState::has_pending_song(self : PlaybackState) -> Bool {
  match self.pending {
    Some(snapshot) => snapshot.is_song()
    None => false
  }
}

///|
pub fn PlaybackState::has_active(self : PlaybackState) -> Bool {
  match self.active {
    Some(_) => true
    None => false
  }
}

///|
pub fn PlaybackState::has_pending(self : PlaybackState) -> Bool {
  match self.pending {
    Some(_) => true
    None => false
  }
}

///|
pub fn PlaybackState::active_revision(
  self : PlaybackState,
) -> @identity.Revision? {
  match self.active {
    Some(snapshot) => Some(snapshot.revision())
    None => None
  }
}

///|
pub fn PlaybackState::active_song_revision(
  self : PlaybackState,
) -> @identity.Revision? {
  if self.has_active_song() {
    self.active_revision()
  } else {
    None
  }
}

///|
pub fn PlaybackState::active_song_layout_revision(
  self : PlaybackState,
) -> @identity.Revision? {
  match self.active {
    Some(snapshot) => snapshot.song_layout_revision()
    None => None
  }
}

///|
pub fn PlaybackState::query_active_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  match self.active {
    Some(snapshot) => snapshot.query_events(arc)
    None => []
  }
}

///|
fn query_pattern_events(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  snapshot.query(arc)
}

///|
fn query_song_events(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  snapshot.query(arc)
}

///|
fn query_pattern_playback_events(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
  arc : @pattern.TimeSpan,
) -> Array[PlaybackEventRecord] {
  let result : Array[PlaybackEventRecord] = []
  let events = snapshot.query_sourced_events(arc)
  for event in events {
    let source = PlaybackEventSource::pattern(
      pattern_nodes=event.pattern_nodes(),
    )
    result.push(PlaybackEventRecord(event=event.event(), source~))
  }
  result
}

///|
fn query_song_playback_events(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
  arc : @pattern.TimeSpan,
) -> Array[PlaybackEventRecord] {
  let result : Array[PlaybackEventRecord] = []
  let events = snapshot.query_sourced_events(arc)
  for event in events {
    let source = PlaybackEventSource::song(
      section=event.section(),
      layer=event.layer(),
      occurrence=event.occurrence(),
    )
    result.push(PlaybackEventRecord(event=event.event(), source~))
  }
  result
}
