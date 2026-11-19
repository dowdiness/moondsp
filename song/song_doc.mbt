///|
#derive(Eq, Debug)
pub(all) suberror SongDocBuildError {
  EmptySongDoc
  DuplicateSongDocOccurrenceId(String)
  DuplicateSongDocOccurrenceName(String)
}

///|
#derive(Eq, Debug)
pub(all) suberror SongDocEditError {
  MissingSongDocOccurrenceId(String)
  DuplicateEditedSongDocOccurrenceId(String)
  DuplicateEditedSongDocOccurrenceName(String)
  InvalidSongDocOccurrenceIndex(Int32)
  CannotRemoveLastSongDocOccurrence
}

///|
/// Identity-bearing authoring placement for one section occurrence.
///
/// The display `name` can change without changing the stable `id`.
/// `layout_revision` advances only when placement or section length can change
/// computed song spans.
pub struct SongOccurrenceDoc {
  priv id : @identity.OccurrenceId
  priv name : String
  priv start : @pattern.Rational?
  priv section : SectionDoc
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
}

///|
pub fn SongOccurrenceDoc::SongOccurrenceDoc(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : SectionDoc,
) -> SongOccurrenceDoc {
  {
    id,
    name,
    start: None,
    section,
    revision: @identity.Revision::zero(),
    layout_revision: @identity.Revision::zero(),
  }
}

///|
pub fn SongOccurrenceDoc::at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  name~ : String,
  section~ : SectionDoc,
) -> SongOccurrenceDoc {
  {
    id,
    name,
    start: Some(start),
    section,
    revision: @identity.Revision::zero(),
    layout_revision: @identity.Revision::zero().next(),
  }
}

///|
pub fn SongOccurrenceDoc::id(
  self : SongOccurrenceDoc,
) -> @identity.OccurrenceId {
  self.id
}

///|
pub fn SongOccurrenceDoc::name(self : SongOccurrenceDoc) -> String {
  self.name
}

///|
pub fn SongOccurrenceDoc::start(self : SongOccurrenceDoc) -> @pattern.Rational? {
  self.start
}

///|
pub fn SongOccurrenceDoc::section(self : SongOccurrenceDoc) -> SectionDoc {
  self.section
}

///|
pub fn SongOccurrenceDoc::revision(
  self : SongOccurrenceDoc,
) -> @identity.Revision {
  self.revision.combine(self.section.revision())
}

///|
pub fn SongOccurrenceDoc::layout_revision(
  self : SongOccurrenceDoc,
) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn SongOccurrenceDoc::rename(
  self : SongOccurrenceDoc,
  name~ : String,
) -> SongOccurrenceDoc {
  {
    id: self.id,
    name,
    start: self.start,
    section: self.section,
    revision: self.revision.next(),
    layout_revision: self.layout_revision,
  }
}

///|
pub fn SongOccurrenceDoc::with_start(
  self : SongOccurrenceDoc,
  start~ : @pattern.Rational,
) -> SongOccurrenceDoc {
  {
    id: self.id,
    name: self.name,
    start: Some(start),
    section: self.section,
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
  }
}

///|
pub fn SongOccurrenceDoc::clear_start(
  self : SongOccurrenceDoc,
) -> SongOccurrenceDoc {
  {
    id: self.id,
    name: self.name,
    start: None,
    section: self.section,
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
  }
}

///|
pub fn SongOccurrenceDoc::replace_section(
  self : SongOccurrenceDoc,
  section~ : SectionDoc,
) -> SongOccurrenceDoc {
  let layout_revision = if self.section.length_cycles() ==
    section.length_cycles() {
    self.layout_revision
  } else {
    self.layout_revision.next()
  }
  {
    id: self.id,
    name: self.name,
    start: self.start,
    section,
    revision: self.revision.next(),
    layout_revision,
  }
}

///|
fn SongOccurrenceDoc::to_part(self : SongOccurrenceDoc) -> SongPart {
  match self.start {
    Some(start) =>
      SongPart::with_id_at(
        id=self.id,
        start~,
        name=self.name,
        section=self.section.to_section(),
      )
    None =>
      SongPart::with_id(
        id=self.id,
        name=self.name,
        section=self.section.to_section(),
      )
  }
}

///|
fn copy_song_occurrence_docs(
  parts : Array[SongOccurrenceDoc],
) -> Array[SongOccurrenceDoc] {
  parts.copy()
}

///|
fn song_doc_find_occurrence_index(
  parts : Array[SongOccurrenceDoc],
  id : @identity.OccurrenceId,
) -> Int32? {
  for index in 0..<parts.length() {
    if parts[index].id() == id {
      return Some(index)
    }
  }
  None
}

///|
fn song_doc_has_occurrence_id(
  parts : Array[SongOccurrenceDoc],
  id : @identity.OccurrenceId,
) -> Bool {
  song_doc_find_occurrence_index(parts, id) is Some(_)
}

///|
fn song_doc_has_occurrence_name_except(
  parts : Array[SongOccurrenceDoc],
  name : String,
  id : @identity.OccurrenceId,
) -> Bool {
  parts.iter().any(part => part.id() != id && part.name() == name)
}

///|
fn validate_song_doc_parts(
  parts : Array[SongOccurrenceDoc],
) -> Unit raise SongDocBuildError {
  if parts.is_empty() {
    raise EmptySongDoc
  }
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  for part in parts {
    let id_value = part.id().value()
    if ids.contains(id_value) {
      raise DuplicateSongDocOccurrenceId(id_value)
    }
    if names.contains(part.name()) {
      raise DuplicateSongDocOccurrenceName(part.name())
    }
    ids[id_value] = true
    names[part.name()] = true
  }
}

///|
fn aggregate_song_doc_revision(
  parts : Array[SongOccurrenceDoc],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for part in parts {
    revision = revision.combine(part.revision())
  }
  revision.next()
}

///|
fn aggregate_song_doc_layout_revision(
  parts : Array[SongOccurrenceDoc],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for part in parts {
    revision = revision.combine(part.layout_revision())
  }
  revision.next()
}

///|
fn insert_song_doc_occurrence_at(
  parts : Array[SongOccurrenceDoc],
  index : Int32,
  occurrence : SongOccurrenceDoc,
) -> Array[SongOccurrenceDoc] {
  [..parts[0:index], occurrence, ..parts[index:]]
}

///|
fn move_song_doc_occurrence_to(
  parts : Array[SongOccurrenceDoc],
  current_index : Int32,
  target_index : Int32,
) -> Array[SongOccurrenceDoc] {
  let moving = parts[current_index]
  let without = [ for index, part in parts if index != current_index => part ]
  [..without[0:target_index], moving, ..without[target_index:]]
}

///|
priv struct SourcedSongSnapshotLayer {
  id : @identity.SectionLayerId
  body : @pattern.Pat[@pattern.ControlMap]
  source_snapshot : @pattern.PatternSnapshotWithOrigins?
}

///|
priv struct SourcedSongSnapshotOccurrence {
  occurrence : SectionOccurrence
  section : @identity.SectionId
  layers : Array[SourcedSongSnapshotLayer]
}

///|
fn source_song_snapshot_occurrence(
  occurrence : SectionOccurrence,
  authored : SongOccurrenceDoc,
) -> SourcedSongSnapshotOccurrence {
  let authored_section = authored.section()
  let layers = match
    (authored_section.body(), occurrence.section().section_body()) {
    (Single(authored_layer), Single(body)) =>
      [
        {
          id: authored_layer.id(),
          body,
          source_snapshot: authored_layer.source_snapshot,
        },
      ]
    (Layers(authored_layers), Layers(runtime_layers)) => {
      guard authored_layers.length() == runtime_layers.length() else {
        abort("lowered song layer provenance is incomplete")
      }
      [
        for index, authored_layer in authored_layers => {
          {
            id: authored_layer.id(),
            body: runtime_layers[index].body(),
            source_snapshot: authored_layer.source_snapshot,
          }
        }
      ]
    }
    _ => abort("lowered song section shape changed")
  }
  { occurrence, section: authored_section.id(), layers, }
}

///|
fn source_song_snapshot_occurrences(
  song : Song,
  authored : Array[SongOccurrenceDoc],
) -> Array[SourcedSongSnapshotOccurrence] {
  let occurrences = song.occurrences()
  guard occurrences.length() == authored.length() else {
    abort("lowered song occurrence provenance is incomplete")
  }
  [
    for index, part in authored => {
      source_song_snapshot_occurrence(occurrences[index], part)
    }
  ]
}

///|
priv struct SourcedSongSnapshotEntry {
  occurrence : SectionOccurrence
  section : @identity.SectionId
  layer : @identity.SectionLayerId
  body : @pattern.Pat[@pattern.ControlMap]
  source_snapshot : @pattern.PatternSnapshotWithOrigins?
  source_index : Int32
}

///|
fn source_song_snapshot_entries(
  sourced_occurrences : Array[SourcedSongSnapshotOccurrence],
) -> Array[SourcedSongSnapshotEntry] {
  let result : Array[SourcedSongSnapshotEntry] = []
  for sourced in sourced_occurrences {
    for layer in sourced.layers {
      for source_index, body in layer.body.entries() {
        result.push({
          occurrence: sourced.occurrence,
          section: sourced.section,
          layer: layer.id,
          body,
          source_snapshot: layer.source_snapshot,
          source_index,
        })
      }
    }
  }
  result
}

///|
#derive(Eq, Debug)
pub struct SongEventOrigin {
  priv occurrence : @identity.OccurrenceId
  priv section : @identity.SectionId
  priv layer : @identity.SectionLayerId
}

///|
fn SongEventOrigin::SongEventOrigin(
  occurrence~ : @identity.OccurrenceId,
  section~ : @identity.SectionId,
  layer~ : @identity.SectionLayerId,
) -> SongEventOrigin {
  { occurrence, section, layer, }
}

///|
pub fn SongEventOrigin::occurrence(
  self : SongEventOrigin,
) -> @identity.OccurrenceId {
  self.occurrence
}

///|
pub fn SongEventOrigin::section(self : SongEventOrigin) -> @identity.SectionId {
  self.section
}

///|
pub fn SongEventOrigin::layer(
  self : SongEventOrigin,
) -> @identity.SectionLayerId {
  self.layer
}

///|
pub struct SongSnapshotEvent {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv origin : SongEventOrigin
  priv source_origin : @pattern.EventOrigin?
  priv source_frame : @identity.SourceFrameId?
  priv source_start : Double
  priv source_pitch : Double
  priv controls : @pattern.Controls
}

///|
pub fn SongSnapshotEvent::event(
  self : SongSnapshotEvent,
) -> @pattern.Event[@pattern.ControlMap] {
  self.event
}

///|
pub fn SongSnapshotEvent::origin(self : SongSnapshotEvent) -> SongEventOrigin {
  self.origin
}

///|
/// Exact atom and binding provenance, when this section was compiled from
/// an origin-bearing pattern rather than an anonymous runtime pattern.
pub fn SongSnapshotEvent::source_origin(
  self : SongSnapshotEvent,
) -> @pattern.EventOrigin? {
  self.source_origin
}

///|
pub fn SongSnapshotEvent::source_frame(
  self : SongSnapshotEvent,
) -> @identity.SourceFrameId? {
  self.source_frame
}

///|
pub fn SongSnapshotEvent::source_start(self : SongSnapshotEvent) -> Double {
  self.source_start
}

///|
pub fn SongSnapshotEvent::source_pitch(self : SongSnapshotEvent) -> Double {
  self.source_pitch
}

///|
/// This event's controls, on the song clock.
pub fn SongSnapshotEvent::controls(
  self : SongSnapshotEvent,
) -> @pattern.Controls {
  self.controls
}

///|
pub fn SongSnapshotEvent::occurrence(
  self : SongSnapshotEvent,
) -> @identity.OccurrenceId {
  self.origin.occurrence()
}

///|
pub fn SongSnapshotEvent::section(
  self : SongSnapshotEvent,
) -> @identity.SectionId {
  self.origin.section()
}

///|
pub fn SongSnapshotEvent::layer(
  self : SongSnapshotEvent,
) -> @identity.SectionLayerId {
  self.origin.layer()
}

///|
/// Lowered song snapshot for scheduler/runtime consumers.
///
/// `revision` tracks any authoring content change. `layout_revision` advances
/// only when occurrence placement or section length can change computed song
/// spans, giving schedulers a stable boundary for layout-sensitive commits.
pub struct SongSnapshot {
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
  priv song : Song
  priv sourced_occurrences : Array[SourcedSongSnapshotOccurrence]
  priv sourced_entries : Array[SourcedSongSnapshotEntry]
}

///|
pub fn SongSnapshot::revision(self : SongSnapshot) -> @identity.Revision {
  self.revision
}

///|
pub fn SongSnapshot::layout_revision(self : SongSnapshot) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn SongSnapshot::song(self : SongSnapshot) -> Song {
  self.song
}

///|
pub fn SongSnapshot::section_id_for_occurrence(
  self : SongSnapshot,
  occurrence : @identity.OccurrenceId,
) -> @identity.SectionId? {
  for sourced in self.sourced_occurrences {
    if sourced.occurrence.id() == occurrence {
      return Some(sourced.section)
    }
  }
  None
}

///|
fn query_scoped_snapshot_layer(
  body : @pattern.Pat[@pattern.ControlMap],
  scope : TimeScope,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  if scope.is_identity() {
    body.query(arc)
  } else {
    body.fast(scope.rate()).query(arc)
  }
}

///|
fn push_song_snapshot_events(
  result : Array[SongSnapshotEvent],
  body : @pattern.Pat[@pattern.ControlMap],
  snapshot : @pattern.PatternSnapshotWithOrigins?,
  source_index : Int32,
  occurrence : SectionOccurrence,
  section : @identity.SectionId,
  layer : @identity.SectionLayerId,
  global_arc : @pattern.TimeSpan,
) -> Unit {
  let origin = SongEventOrigin(occurrence=occurrence.id(), section~, layer~)
  match snapshot {
    Some(snapshot) => {
      let placement = @pattern.Placement(
        origin=occurrence.start(),
        rate=occurrence.section().scope().rate(),
      )
      let query_arc = placement.local_span(global_arc)
      let events = if source_index < 0 {
        snapshot.query(query_arc)
      } else {
        snapshot.query_for_entry(source_index, query_arc)
      }
      for sourced in events {
        result.push({
          event: sourced.event().placed(placement),
          origin,
          source_origin: Some(sourced.origin()),
          source_frame: sourced.source_frame(),
          source_start: sourced.source_start(),
          source_pitch: sourced.source_pitch(),
          controls: sourced.controls().placed(placement),
        })
      }
    }
    None => {
      let events = query_scoped_snapshot_layer(
        body,
        occurrence.section().scope(),
        unshift_span(global_arc, occurrence.start()),
      )
      for event in events {
        let event = event.shift(occurrence.start())
        result.push({
          event,
          origin,
          source_origin: None,
          source_frame: None,
          source_start: -1.0,
          source_pitch: -1.0,
          controls: @pattern.Controls::fixed(event.value),
        })
      }
    }
  }
}

///|
pub fn SongSnapshot::query_sourced_events(
  self : SongSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[SongSnapshotEvent] {
  let result : Array[SongSnapshotEvent] = []
  for sourced in self.sourced_occurrences {
    let occurrence = sourced.occurrence
    match occurrence.span().intersect(arc) {
      Some(global_arc) =>
        for layer in sourced.layers {
          push_song_snapshot_events(
            result,
            layer.body,
            layer.source_snapshot,
            -1,
            occurrence,
            sourced.section,
            layer.id,
            global_arc,
          )
        }
      None => ()
    }
  }
  result
}

///|
/// Query one canonical playback entry with authored provenance.
/// `source_index` is the entry index retained by playback entry state.
/// Invalid indexes return an empty result.
pub fn SongSnapshot::query_sourced_events_for_entry(
  self : SongSnapshot,
  source_index : Int32,
  arc : @pattern.TimeSpan,
) -> Array[SongSnapshotEvent] {
  let source = match self.sourced_entries.get(source_index) {
    Some(source) => source
    None => return []
  }
  match source.occurrence.span().intersect(arc) {
    None => []
    Some(global_arc) => {
      let result : Array[SongSnapshotEvent] = []
      push_song_snapshot_events(
        result,
        source.body,
        source.source_snapshot,
        source.source_index,
        source.occurrence,
        source.section,
        source.layer,
        global_arc,
      )
      result
    }
  }
}

///|
pub fn SongSnapshot::query(
  self : SongSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.song.query(arc)
}

///|
/// Identity-bearing song layout document for incremental occurrence edits.
///
/// This authoring layer keeps stable occurrence IDs across display renames,
/// insertion, removal, and reordering. It lowers back to the existing playback
/// song surface so scheduler/query semantics remain unchanged.
pub struct SongDoc {
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
  priv parts : Array[SongOccurrenceDoc]
}

///|
pub fn SongDoc::SongDoc(
  parts~ : Array[SongOccurrenceDoc],
) -> SongDoc raise SongDocBuildError {
  validate_song_doc_parts(parts)
  {
    revision: aggregate_song_doc_revision(parts),
    layout_revision: aggregate_song_doc_layout_revision(parts),
    parts: copy_song_occurrence_docs(parts),
  }
}

///|
pub fn SongDoc::revision(self : SongDoc) -> @identity.Revision {
  self.revision
}

///|
pub fn SongDoc::layout_revision(self : SongDoc) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn SongDoc::occurrence_count(self : SongDoc) -> Int32 {
  self.parts.length()
}

///|
pub fn SongDoc::occurrences(self : SongDoc) -> Array[SongOccurrenceDoc] {
  copy_song_occurrence_docs(self.parts)
}

///|
pub fn SongDoc::occurrence(self : SongDoc, index : Int32) -> SongOccurrenceDoc? {
  match self.parts.get(index) {
    Some(part) => Some(part)
    None => None
  }
}

///|
pub fn SongDoc::get_occurrence(
  self : SongDoc,
  id : @identity.OccurrenceId,
) -> SongOccurrenceDoc? {
  match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => Some(self.parts[index])
    None => None
  }
}

///|
pub fn SongDoc::rename_occurrence(
  self : SongDoc,
  id : @identity.OccurrenceId,
  name~ : String,
) -> SongDoc raise SongDocEditError {
  let index = match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => index
    None => raise MissingSongDocOccurrenceId(id.value())
  }
  if song_doc_has_occurrence_name_except(self.parts, name, id) {
    raise DuplicateEditedSongDocOccurrenceName(name)
  }
  let result = copy_song_occurrence_docs(self.parts)
  result[index] = result[index].rename(name~)
  {
    revision: self.revision.next(),
    layout_revision: self.layout_revision,
    parts: result,
  }
}

///|
pub fn SongDoc::replace_occurrence_section(
  self : SongDoc,
  id : @identity.OccurrenceId,
  section~ : SectionDoc,
) -> SongDoc raise SongDocEditError {
  let index = match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => index
    None => raise MissingSongDocOccurrenceId(id.value())
  }
  let layout_revision = if self.parts[index].section().length_cycles() ==
    section.length_cycles() {
    self.layout_revision
  } else {
    self.layout_revision.next()
  }
  let result = copy_song_occurrence_docs(self.parts)
  result[index] = result[index].replace_section(section~)
  {
    revision: self.revision.next().combine(section.revision()),
    layout_revision,
    parts: result,
  }
}

///|
pub fn SongDoc::set_occurrence_start(
  self : SongDoc,
  id : @identity.OccurrenceId,
  start~ : @pattern.Rational,
) -> SongDoc raise SongDocEditError {
  let index = match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => index
    None => raise MissingSongDocOccurrenceId(id.value())
  }
  let result = copy_song_occurrence_docs(self.parts)
  result[index] = result[index].with_start(start~)
  {
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
    parts: result,
  }
}

///|
pub fn SongDoc::clear_occurrence_start(
  self : SongDoc,
  id : @identity.OccurrenceId,
) -> SongDoc raise SongDocEditError {
  let index = match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => index
    None => raise MissingSongDocOccurrenceId(id.value())
  }
  let result = copy_song_occurrence_docs(self.parts)
  result[index] = result[index].clear_start()
  {
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
    parts: result,
  }
}

///|
pub fn SongDoc::insert_occurrence(
  self : SongDoc,
  index~ : Int32,
  occurrence~ : SongOccurrenceDoc,
) -> SongDoc raise SongDocEditError {
  if index < 0 || index > self.parts.length() {
    raise InvalidSongDocOccurrenceIndex(index)
  }
  if song_doc_has_occurrence_id(self.parts, occurrence.id()) {
    raise DuplicateEditedSongDocOccurrenceId(occurrence.id().value())
  }
  if song_doc_has_occurrence_name_except(
      self.parts,
      occurrence.name(),
      occurrence.id(),
    ) {
    raise DuplicateEditedSongDocOccurrenceName(occurrence.name())
  }
  {
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
    parts: insert_song_doc_occurrence_at(self.parts, index, occurrence),
  }
}

///|
pub fn SongDoc::remove_occurrence(
  self : SongDoc,
  id : @identity.OccurrenceId,
) -> SongDoc raise SongDocEditError {
  let index = match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => index
    None => raise MissingSongDocOccurrenceId(id.value())
  }
  if self.parts.length() == 1 {
    raise CannotRemoveLastSongDocOccurrence
  }
  {
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
    parts: [
      for cursor, part in self.parts if cursor != index => part
    ],
  }
}

///|
pub fn SongDoc::move_occurrence(
  self : SongDoc,
  id : @identity.OccurrenceId,
  index~ : Int32,
) -> SongDoc raise SongDocEditError {
  if index < 0 || index >= self.parts.length() {
    raise InvalidSongDocOccurrenceIndex(index)
  }
  let current_index = match song_doc_find_occurrence_index(self.parts, id) {
    Some(current_index) => current_index
    None => raise MissingSongDocOccurrenceId(id.value())
  }
  {
    revision: self.revision.next(),
    layout_revision: self.layout_revision.next(),
    parts: move_song_doc_occurrence_to(self.parts, current_index, index),
  }
}

///|
pub fn SongDoc::to_song(self : SongDoc) -> Song raise SongBuildError {
  Song(parts=[ for part in self.parts => part.to_part() ])
}

///|
pub fn SongDoc::lower(self : SongDoc) -> SongSnapshot raise SongBuildError {
  let song = self.to_song()
  let sourced_occurrences = source_song_snapshot_occurrences(song, self.parts)
  {
    revision: self.revision,
    layout_revision: self.layout_revision,
    song,
    sourced_occurrences,
    sourced_entries: source_song_snapshot_entries(sourced_occurrences),
  }
}

///|
pub extend SongDocBuildError with Debug::{to_repr}

///|
pub extend SongDocBuildError with Eq::{not_equal, equal}

///|
pub extend SongDocEditError with Debug::{to_repr}

///|
pub extend SongDocEditError with Eq::{not_equal, equal}

///|
pub extend SongEventOrigin with Debug::{to_repr}

///|
pub extend SongEventOrigin with Eq::{not_equal, equal}
