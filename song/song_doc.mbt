///|
pub(all) suberror SongDocBuildError {
  EmptySongDoc
  DuplicateSongDocOccurrenceId(String)
  DuplicateSongDocOccurrenceName(String)
} derive(Eq, Debug)

///|
pub(all) suberror SongDocEditError {
  MissingSongDocOccurrenceId(String)
  DuplicateEditedSongDocOccurrenceId(String)
  DuplicateEditedSongDocOccurrenceName(String)
  InvalidSongDocOccurrenceIndex(Int)
  CannotRemoveLastSongDocOccurrence
} derive(Eq, Debug)

///|
/// Identity-bearing authoring placement for one section occurrence.
///
/// The display `name` can change without changing the stable `id`.
/// `layout_revision` advances only when placement or section length can change
/// computed song spans.
pub struct SongOccurrenceDoc[A] {
  priv id : @identity.OccurrenceId
  priv name : String
  priv start : @pattern.Rational?
  priv section : SectionDoc[A]
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
}

///|
pub fn[A] SongOccurrenceDoc::SongOccurrenceDoc(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : SectionDoc[A],
) -> SongOccurrenceDoc[A] {
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
pub fn[A] SongOccurrenceDoc::at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  name~ : String,
  section~ : SectionDoc[A],
) -> SongOccurrenceDoc[A] {
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
pub fn[A] SongOccurrenceDoc::id(
  self : SongOccurrenceDoc[A],
) -> @identity.OccurrenceId {
  self.id
}

///|
pub fn[A] SongOccurrenceDoc::name(self : SongOccurrenceDoc[A]) -> String {
  self.name
}

///|
pub fn[A] SongOccurrenceDoc::start(
  self : SongOccurrenceDoc[A],
) -> @pattern.Rational? {
  self.start
}

///|
pub fn[A] SongOccurrenceDoc::section(
  self : SongOccurrenceDoc[A],
) -> SectionDoc[A] {
  self.section
}

///|
pub fn[A] SongOccurrenceDoc::revision(
  self : SongOccurrenceDoc[A],
) -> @identity.Revision {
  self.revision.combine(self.section.revision())
}

///|
pub fn[A] SongOccurrenceDoc::layout_revision(
  self : SongOccurrenceDoc[A],
) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn[A] SongOccurrenceDoc::rename(
  self : SongOccurrenceDoc[A],
  name~ : String,
) -> SongOccurrenceDoc[A] {
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
pub fn[A] SongOccurrenceDoc::with_start(
  self : SongOccurrenceDoc[A],
  start~ : @pattern.Rational,
) -> SongOccurrenceDoc[A] {
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
pub fn[A] SongOccurrenceDoc::clear_start(
  self : SongOccurrenceDoc[A],
) -> SongOccurrenceDoc[A] {
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
pub fn[A] SongOccurrenceDoc::replace_section(
  self : SongOccurrenceDoc[A],
  section~ : SectionDoc[A],
) -> SongOccurrenceDoc[A] {
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
fn[A] SongOccurrenceDoc::to_part(self : SongOccurrenceDoc[A]) -> SongPart[A] {
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
fn[A] copy_song_occurrence_docs(
  parts : Array[SongOccurrenceDoc[A]],
) -> Array[SongOccurrenceDoc[A]] {
  parts.copy()
}

///|
fn[A] song_doc_find_occurrence_index(
  parts : Array[SongOccurrenceDoc[A]],
  id : @identity.OccurrenceId,
) -> Int? {
  for index in 0..<parts.length() {
    if parts[index].id() == id {
      return Some(index)
    }
  }
  None
}

///|
fn[A] song_doc_has_occurrence_id(
  parts : Array[SongOccurrenceDoc[A]],
  id : @identity.OccurrenceId,
) -> Bool {
  song_doc_find_occurrence_index(parts, id) is Some(_)
}

///|
fn[A] song_doc_has_occurrence_name_except(
  parts : Array[SongOccurrenceDoc[A]],
  name : String,
  id : @identity.OccurrenceId,
) -> Bool {
  parts.iter().any(part => part.id() != id && part.name() == name)
}

///|
fn[A] validate_song_doc_parts(
  parts : Array[SongOccurrenceDoc[A]],
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
fn[A] aggregate_song_doc_revision(
  parts : Array[SongOccurrenceDoc[A]],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for part in parts {
    revision = revision.combine(part.revision())
  }
  revision.next()
}

///|
fn[A] aggregate_song_doc_layout_revision(
  parts : Array[SongOccurrenceDoc[A]],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for part in parts {
    revision = revision.combine(part.layout_revision())
  }
  revision.next()
}

///|
fn[A] insert_song_doc_occurrence_at(
  parts : Array[SongOccurrenceDoc[A]],
  index : Int,
  occurrence : SongOccurrenceDoc[A],
) -> Array[SongOccurrenceDoc[A]] {
  [..parts[0:index], occurrence, ..parts[index:]]
}

///|
fn[A] move_song_doc_occurrence_to(
  parts : Array[SongOccurrenceDoc[A]],
  current_index : Int,
  target_index : Int,
) -> Array[SongOccurrenceDoc[A]] {
  let moving = parts[current_index]
  let without = [ for index, part in parts if index != current_index => part ]
  [..without[0:target_index], moving, ..without[target_index:]]
}

///|
priv struct SourcedSongSnapshotLayer[A] {
  id : @identity.SectionLayerId
  body : @pattern.Pat[A]
}

///|
priv struct SourcedSongSnapshotOccurrence[A] {
  occurrence : SectionOccurrence[A]
  section : @identity.SectionId
  layers : Array[SourcedSongSnapshotLayer[A]]
}

///|
fn[A] source_song_snapshot_occurrence(
  occurrence : SectionOccurrence[A],
  authored : SongOccurrenceDoc[A],
) -> SourcedSongSnapshotOccurrence[A] {
  let authored_section = authored.section()
  let layers = match
    (authored_section.body(), occurrence.section().section_body()) {
    (Single(authored_layer), Single(body)) =>
      [{ id: authored_layer.id(), body, }]
    (Layers(authored_layers), Layers(runtime_layers)) => {
      guard authored_layers.length() == runtime_layers.length() else {
        abort("lowered song layer provenance is incomplete")
      }
      [
        for index, authored_layer in authored_layers => {
          { id: authored_layer.id(), body: runtime_layers[index].body(), }
        }
      ]
    }
    _ => abort("lowered song section shape changed")
  }
  { occurrence, section: authored_section.id(), layers, }
}

///|
fn[A] source_song_snapshot_occurrences(
  song : Song[A],
  authored : Array[SongOccurrenceDoc[A]],
) -> Array[SourcedSongSnapshotOccurrence[A]] {
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
priv struct SourcedSongSnapshotEntry[A] {
  occurrence : SectionOccurrence[A]
  section : @identity.SectionId
  layer : @identity.SectionLayerId
  body : @pattern.Pat[A]
}

///|
fn[A] source_song_snapshot_entries(
  sourced_occurrences : Array[SourcedSongSnapshotOccurrence[A]],
) -> Array[SourcedSongSnapshotEntry[A]] {
  let result : Array[SourcedSongSnapshotEntry[A]] = []
  for sourced in sourced_occurrences {
    for layer in sourced.layers {
      for body in layer.body.entries() {
        result.push({
          occurrence: sourced.occurrence,
          section: sourced.section,
          layer: layer.id,
          body,
        })
      }
    }
  }
  result
}

///|
pub struct SongEventOrigin {
  priv occurrence : @identity.OccurrenceId
  priv section : @identity.SectionId
  priv layer : @identity.SectionLayerId
} derive(Eq, Debug)

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
pub struct SongSnapshotEvent[A] {
  priv event : @pattern.Event[A]
  priv origin : SongEventOrigin
}

///|
pub fn[A] SongSnapshotEvent::event(
  self : SongSnapshotEvent[A],
) -> @pattern.Event[A] {
  self.event
}

///|
pub fn[A] SongSnapshotEvent::origin(
  self : SongSnapshotEvent[A],
) -> SongEventOrigin {
  self.origin
}

///|
pub fn[A] SongSnapshotEvent::occurrence(
  self : SongSnapshotEvent[A],
) -> @identity.OccurrenceId {
  self.origin.occurrence()
}

///|
pub fn[A] SongSnapshotEvent::section(
  self : SongSnapshotEvent[A],
) -> @identity.SectionId {
  self.origin.section()
}

///|
pub fn[A] SongSnapshotEvent::layer(
  self : SongSnapshotEvent[A],
) -> @identity.SectionLayerId {
  self.origin.layer()
}

///|
/// Lowered song snapshot for scheduler/runtime consumers.
///
/// `revision` tracks any authoring content change. `layout_revision` advances
/// only when occurrence placement or section length can change computed song
/// spans, giving schedulers a stable boundary for layout-sensitive commits.
pub struct SongSnapshot[A] {
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
  priv song : Song[A]
  priv sourced_occurrences : Array[SourcedSongSnapshotOccurrence[A]]
  priv sourced_entries : Array[SourcedSongSnapshotEntry[A]]
}

///|
pub fn[A] SongSnapshot::revision(self : SongSnapshot[A]) -> @identity.Revision {
  self.revision
}

///|
pub fn[A] SongSnapshot::layout_revision(
  self : SongSnapshot[A],
) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn[A] SongSnapshot::song(self : SongSnapshot[A]) -> Song[A] {
  self.song
}

///|
pub fn[A] SongSnapshot::section_id_for_occurrence(
  self : SongSnapshot[A],
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
fn[A] query_scoped_snapshot_layer(
  body : @pattern.Pat[A],
  scope : TimeScope,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[A]] {
  if scope.is_identity() {
    body.query(arc)
  } else {
    body.fast(scope.rate()).query(arc)
  }
}

///|
fn[A] push_song_snapshot_layer_events(
  result : Array[SongSnapshotEvent[A]],
  sourced : SourcedSongSnapshotOccurrence[A],
  layer : SourcedSongSnapshotLayer[A],
  local_arc : @pattern.TimeSpan,
) -> Unit {
  let occurrence = sourced.occurrence
  let events = query_scoped_snapshot_layer(
    layer.body,
    occurrence.section().scope(),
    local_arc,
  )
  for event in events {
    result.push({
      event: event.shift(occurrence.start()),
      origin: SongEventOrigin(
        occurrence=occurrence.id(),
        section=sourced.section,
        layer=layer.id,
      ),
    })
  }
}

///|
pub fn[A] SongSnapshot::query_sourced_events(
  self : SongSnapshot[A],
  arc : @pattern.TimeSpan,
) -> Array[SongSnapshotEvent[A]] {
  let result : Array[SongSnapshotEvent[A]] = []
  for sourced in self.sourced_occurrences {
    let occurrence = sourced.occurrence
    match occurrence.span().intersect(arc) {
      Some(global_arc) => {
        let local_arc = unshift_span(global_arc, occurrence.start())
        for layer in sourced.layers {
          push_song_snapshot_layer_events(result, sourced, layer, local_arc)
        }
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
pub fn[A] SongSnapshot::query_sourced_events_for_entry(
  self : SongSnapshot[A],
  source_index : Int,
  arc : @pattern.TimeSpan,
) -> Array[SongSnapshotEvent[A]] {
  let source = match self.sourced_entries.get(source_index) {
    Some(source) => source
    None => return []
  }
  match source.occurrence.span().intersect(arc) {
    None => []
    Some(global_arc) => {
      let local_arc = unshift_span(global_arc, source.occurrence.start())
      let events = query_scoped_snapshot_layer(
        source.body,
        source.occurrence.section().scope(),
        local_arc,
      )
      [
        for event in events => {
          {
            event: event.shift(source.occurrence.start()),
            origin: SongEventOrigin(
              occurrence=source.occurrence.id(),
              section=source.section,
              layer=source.layer,
            ),
          }
        }
      ]
    }
  }
}

///|
pub fn[A] SongSnapshot::query(
  self : SongSnapshot[A],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[A]] {
  self.song.query(arc)
}

///|
/// Identity-bearing song layout document for incremental occurrence edits.
///
/// This authoring layer keeps stable occurrence IDs across display renames,
/// insertion, removal, and reordering. It lowers back to the existing playback
/// song surface so scheduler/query semantics remain unchanged.
pub struct SongDoc[A] {
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
  priv parts : Array[SongOccurrenceDoc[A]]
}

///|
pub fn[A] SongDoc::SongDoc(
  parts~ : Array[SongOccurrenceDoc[A]],
) -> SongDoc[A] raise SongDocBuildError {
  validate_song_doc_parts(parts)
  {
    revision: aggregate_song_doc_revision(parts),
    layout_revision: aggregate_song_doc_layout_revision(parts),
    parts: copy_song_occurrence_docs(parts),
  }
}

///|
pub fn[A] SongDoc::revision(self : SongDoc[A]) -> @identity.Revision {
  self.revision
}

///|
pub fn[A] SongDoc::layout_revision(self : SongDoc[A]) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn[A] SongDoc::occurrence_count(self : SongDoc[A]) -> Int {
  self.parts.length()
}

///|
pub fn[A] SongDoc::occurrences(
  self : SongDoc[A],
) -> Array[SongOccurrenceDoc[A]] {
  copy_song_occurrence_docs(self.parts)
}

///|
pub fn[A] SongDoc::occurrence(
  self : SongDoc[A],
  index : Int,
) -> SongOccurrenceDoc[A]? {
  match self.parts.get(index) {
    Some(part) => Some(part)
    None => None
  }
}

///|
pub fn[A] SongDoc::get_occurrence(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
) -> SongOccurrenceDoc[A]? {
  match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => Some(self.parts[index])
    None => None
  }
}

///|
pub fn[A] SongDoc::rename_occurrence(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
  name~ : String,
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::replace_occurrence_section(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
  section~ : SectionDoc[A],
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::set_occurrence_start(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
  start~ : @pattern.Rational,
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::clear_occurrence_start(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::insert_occurrence(
  self : SongDoc[A],
  index~ : Int,
  occurrence~ : SongOccurrenceDoc[A],
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::remove_occurrence(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::move_occurrence(
  self : SongDoc[A],
  id : @identity.OccurrenceId,
  index~ : Int,
) -> SongDoc[A] raise SongDocEditError {
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
pub fn[A] SongDoc::to_song(self : SongDoc[A]) -> Song[A] raise SongBuildError {
  Song(parts=[ for part in self.parts => part.to_part() ])
}

///|
pub fn[A] SongDoc::lower(
  self : SongDoc[A],
) -> SongSnapshot[A] raise SongBuildError {
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
