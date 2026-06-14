///|
/// Optional authoring provenance for one scheduled event.
///
/// This intentionally lives in `scheduler/` instead of `pattern.Event` so the
/// pattern engine stays payload-polymorphic and independent of authoring IDs.
pub struct EventSource {
  priv raw : @model.EventSource
} derive(Eq, Debug)

///|
pub fn EventSource::EventSource(
  pattern_node~ : @identity.PatternNodeId?,
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  { raw: @model.EventSource(pattern_node~, section~, layer~, occurrence~) }
}

///|
pub fn EventSource::from_pattern_nodes(
  pattern_nodes~ : Array[@identity.PatternNodeId],
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  {
    raw: @model.EventSource::from_pattern_nodes(
      pattern_nodes~,
      section~,
      layer~,
      occurrence~,
    ),
  }
}

///|
pub fn EventSource::none() -> EventSource {
  { raw: @model.EventSource::none() }
}

///|
fn EventSource::from_model(source : @model.EventSource) -> EventSource {
  { raw: source }
}

///|
fn EventSource::to_model(self : EventSource) -> @model.EventSource {
  self.raw
}

///|
pub fn EventSource::pattern_node(
  self : EventSource,
) -> @identity.PatternNodeId? {
  self.raw.pattern_node()
}

///|
pub fn EventSource::pattern_nodes(
  self : EventSource,
) -> Array[@identity.PatternNodeId] {
  self.raw.pattern_nodes()
}

///|
pub fn EventSource::section(self : EventSource) -> @identity.SectionId? {
  self.raw.section()
}

///|
pub fn EventSource::layer(self : EventSource) -> @identity.SectionLayerId? {
  self.raw.layer()
}

///|
pub fn EventSource::occurrence(self : EventSource) -> @identity.OccurrenceId? {
  self.raw.occurrence()
}

///|
pub fn EventSource::is_empty(self : EventSource) -> Bool {
  self.raw.is_empty()
}

///|
/// Scheduler-local event wrapper that keeps provenance out of `pattern.Event`.
pub struct PlaybackEvent {
  priv raw : @model.PlaybackEvent
}

///|
pub fn PlaybackEvent::PlaybackEvent(
  event~ : @pattern.Event[@pattern.ControlMap],
  source~ : EventSource,
) -> PlaybackEvent {
  { raw: @model.PlaybackEvent(event~, source=source.to_model()) }
}

///|
pub fn PlaybackEvent::event(
  self : PlaybackEvent,
) -> @pattern.Event[@pattern.ControlMap] {
  self.raw.event()
}

///|
pub fn PlaybackEvent::source(self : PlaybackEvent) -> EventSource {
  EventSource::from_model(self.raw.source())
}

///|
/// Prepared scheduler input for the next authoring snapshot commit.
///
/// Pattern and song snapshots share the same pending slot so callers have one
/// coherent staging boundary when higher-level live orchestration prepares the
/// next playback state.
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
fn PlaybackSnapshot::raw(self : PlaybackSnapshot) -> @playback.PlaybackSnapshot {
  match self {
    Pattern(snapshot) => @playback.PlaybackSnapshot::pattern(snapshot)
    Song(snapshot) => @playback.PlaybackSnapshot::song(snapshot)
  }
}

///|
pub fn PlaybackSnapshot::revision(
  self : PlaybackSnapshot,
) -> @identity.Revision {
  self.raw().revision()
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  self.raw().song_layout_revision()
}

///|
pub fn PlaybackSnapshot::query(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.raw().query_events(arc)
}

///|
fn event_source_from_playback_source(
  source : @playback.PlaybackEventSource,
) -> EventSource {
  EventSource::from_pattern_nodes(
    pattern_nodes=source.pattern_nodes(),
    section=source.section(),
    layer=source.layer(),
    occurrence=source.occurrence(),
  )
}

///|
fn playback_event_from_record(
  record : @playback.PlaybackEventRecord,
) -> PlaybackEvent {
  PlaybackEvent(
    event=record.event(),
    source=event_source_from_playback_source(record.source()),
  )
}

///|
/// Compatibility helper for consumers that want sourced scheduler events.
///
/// This allocates a wrapper array and is intentionally not used by the
/// audio-block processing path. Pattern snapshots tag queried events with their
/// root pattern node. Song snapshots tag queried events with occurrence,
/// section, and section-layer IDs when the snapshot was lowered from the
/// authoring layer.
pub fn PlaybackSnapshot::query_playback_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackEvent] {
  self
  .raw()
  .query_playback_events(arc)
  .map(event => playback_event_from_record(event))
}
