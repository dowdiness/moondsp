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
pub struct SongOccurrenceDoc[C] {
  priv id : @identity.OccurrenceId
  priv name : String
  priv start : @pattern.Rational?
  priv section : SectionDoc[C]
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
}

///|
pub fn[C] SongOccurrenceDoc::SongOccurrenceDoc(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : SectionDoc[C],
) -> SongOccurrenceDoc[C] {
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
pub fn[C] SongOccurrenceDoc::at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  name~ : String,
  section~ : SectionDoc[C],
) -> SongOccurrenceDoc[C] {
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
pub fn[C] SongOccurrenceDoc::id(
  self : SongOccurrenceDoc[C],
) -> @identity.OccurrenceId {
  self.id
}

///|
pub fn[C] SongOccurrenceDoc::name(self : SongOccurrenceDoc[C]) -> String {
  self.name
}

///|
pub fn[C] SongOccurrenceDoc::start(
  self : SongOccurrenceDoc[C],
) -> @pattern.Rational? {
  self.start
}

///|
pub fn[C] SongOccurrenceDoc::section(
  self : SongOccurrenceDoc[C],
) -> SectionDoc[C] {
  self.section
}

///|
pub fn[C] SongOccurrenceDoc::revision(
  self : SongOccurrenceDoc[C],
) -> @identity.Revision {
  self.revision.combine(self.section.revision())
}

///|
pub fn[C] SongOccurrenceDoc::layout_revision(
  self : SongOccurrenceDoc[C],
) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn[C] SongOccurrenceDoc::rename(
  self : SongOccurrenceDoc[C],
  name~ : String,
) -> SongOccurrenceDoc[C] {
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
pub fn[C] SongOccurrenceDoc::with_start(
  self : SongOccurrenceDoc[C],
  start~ : @pattern.Rational,
) -> SongOccurrenceDoc[C] {
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
pub fn[C] SongOccurrenceDoc::clear_start(
  self : SongOccurrenceDoc[C],
) -> SongOccurrenceDoc[C] {
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
pub fn[C] SongOccurrenceDoc::replace_section(
  self : SongOccurrenceDoc[C],
  section~ : SectionDoc[C],
) -> SongOccurrenceDoc[C] {
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
fn[C] SongOccurrenceDoc::to_part(self : SongOccurrenceDoc[C]) -> SongPart[C] {
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
fn[C] copy_song_occurrence_docs(
  parts : Array[SongOccurrenceDoc[C]],
) -> Array[SongOccurrenceDoc[C]] {
  parts.copy()
}

///|
fn[C] song_doc_find_occurrence_index(
  parts : Array[SongOccurrenceDoc[C]],
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
fn[C] song_doc_has_occurrence_id(
  parts : Array[SongOccurrenceDoc[C]],
  id : @identity.OccurrenceId,
) -> Bool {
  song_doc_find_occurrence_index(parts, id) is Some(_)
}

///|
fn[C] song_doc_has_occurrence_name_except(
  parts : Array[SongOccurrenceDoc[C]],
  name : String,
  id : @identity.OccurrenceId,
) -> Bool {
  parts.iter().any(part => part.id() != id && part.name() == name)
}

///|
fn[C] validate_song_doc_parts(
  parts : Array[SongOccurrenceDoc[C]],
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
fn[C] aggregate_song_doc_revision(
  parts : Array[SongOccurrenceDoc[C]],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for part in parts {
    revision = revision.combine(part.revision())
  }
  revision.next()
}

///|
fn[C] aggregate_song_doc_layout_revision(
  parts : Array[SongOccurrenceDoc[C]],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for part in parts {
    revision = revision.combine(part.layout_revision())
  }
  revision.next()
}

///|
fn[C] insert_song_doc_occurrence_at(
  parts : Array[SongOccurrenceDoc[C]],
  index : Int32,
  occurrence : SongOccurrenceDoc[C],
) -> Array[SongOccurrenceDoc[C]] {
  [..parts[0:index], occurrence, ..parts[index:]]
}

///|
fn[C] move_song_doc_occurrence_to(
  parts : Array[SongOccurrenceDoc[C]],
  current_index : Int32,
  target_index : Int32,
) -> Array[SongOccurrenceDoc[C]] {
  let moving = parts[current_index]
  let without = [ for index, part in parts if index != current_index => part ]
  [..without[0:target_index], moving, ..without[target_index:]]
}

///|
/// One canonical playback entry of a lowered song: one `Pat::entries()`
/// member of one layer of one occurrence.
pub struct SongEntry[C] {
  priv occurrence : SectionOccurrence[C]
  priv origin : SongEventOrigin
  priv content : C
  priv index : Int32
  priv body : @pattern.Pat[@score.ScoreEvent]
}

///|
/// The section content this entry plays.
pub fn[C] SongEntry::content(self : SongEntry[C]) -> C {
  self.content
}

///|
/// Which of the content's canonical entries this entry plays.
pub fn[C] SongEntry::content_entry(self : SongEntry[C]) -> Int32 {
  self.index
}

///|
/// Where the content's time sits in song time: the occurrence's start and
/// its section's rate.
pub fn[C] SongEntry::placement(self : SongEntry[C]) -> @pattern.Placement {
  @pattern.Placement(
    origin=self.occurrence.start(),
    rate=self.occurrence.section().scope().rate(),
  )
}

///|
pub fn[C] SongEntry::origin(self : SongEntry[C]) -> SongEventOrigin {
  self.origin
}

///|
/// The entry's pattern with its section scope applied, in occurrence-local
/// time.
pub fn[C] SongEntry::body(
  self : SongEntry[C],
) -> @pattern.Pat[@score.ScoreEvent] {
  self.body
}

///|
pub fn[C] SongEntry::start(self : SongEntry[C]) -> @pattern.Rational {
  self.occurrence.start()
}

///|
pub fn[C] SongEntry::end_(self : SongEntry[C]) -> @pattern.Rational {
  self.occurrence.end_()
}

///|
/// The entry's share of a song-clock query, or `None` when its occurrence
/// misses `arc`.
pub fn[C] SongEntry::slice(
  self : SongEntry[C],
  arc : @pattern.TimeSpan,
) -> SongSlice[C]? {
  guard self.occurrence.span().intersect(arc) is Some(arc) else { return None }
  let placement = self.placement()
  Some({
    content: self.content,
    entry: self.index,
    arc: placement.local_span(arc),
    placement,
    origin: self.origin,
  })
}

///|
fn[C : SongContent] song_entries(
  song : Song[C],
  authored : Array[SongOccurrenceDoc[C]],
) -> Array[SongEntry[C]] {
  let occurrences = song.occurrences()
  guard occurrences.length() == authored.length() else {
    abort("lowered song occurrence provenance is incomplete")
  }
  let result : Array[SongEntry[C]] = []
  for index, part in authored {
    let occurrence = occurrences[index]
    let section = part.section()
    let layers = match section.body() {
      Single(layer) => [layer]
      Layers(layers) => layers
    }
    let rate = section.scope().rate()
    for layer in layers {
      let origin = SongEventOrigin(
        occurrence=occurrence.id(),
        section=section.id(),
        layer=layer.id(),
      )
      let content = layer.body()
      for entry, body in content.pat().fast(rate).entries() {
        result.push({ occurrence, origin, content, index: entry, body, })
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
/// One song entry's share of a song-clock query: which content entry to
/// query, over which content-local arc, and how to place its events back on
/// the song clock. Querying the content is the caller's job, so song structure
/// stays independent of what the content's events carry.
pub struct SongSlice[C] {
  priv content : C
  priv entry : Int32
  priv arc : @pattern.TimeSpan
  priv placement : @pattern.Placement
  priv origin : SongEventOrigin
}

///|
pub fn[C] SongSlice::content(self : SongSlice[C]) -> C {
  self.content
}

///|
/// The content's canonical entry index.
pub fn[C] SongSlice::entry(self : SongSlice[C]) -> Int32 {
  self.entry
}

///|
/// The query arc in the content's own time.
pub fn[C] SongSlice::arc(self : SongSlice[C]) -> @pattern.TimeSpan {
  self.arc
}

///|
/// Maps content time back to the song clock; apply it to events and controls.
pub fn[C] SongSlice::placement(self : SongSlice[C]) -> @pattern.Placement {
  self.placement
}

///|
pub fn[C] SongSlice::origin(self : SongSlice[C]) -> SongEventOrigin {
  self.origin
}

///|
/// Lowered song snapshot for scheduler/runtime consumers.
///
/// `revision` tracks any authoring content change. `layout_revision` advances
/// only when occurrence placement or section length can change computed song
/// spans, giving schedulers a stable boundary for layout-sensitive commits.
pub struct SongSnapshot[C] {
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
  priv song : Song[C]
  priv entries : Array[SongEntry[C]]
}

///|
pub fn[C] SongSnapshot::revision(self : SongSnapshot[C]) -> @identity.Revision {
  self.revision
}

///|
pub fn[C] SongSnapshot::layout_revision(
  self : SongSnapshot[C],
) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn[C] SongSnapshot::song(self : SongSnapshot[C]) -> Song[C] {
  self.song
}

///|
/// The canonical playback entries: every content entry of every layer of
/// every occurrence, in song order.
pub fn[C] SongSnapshot::entries(
  self : SongSnapshot[C],
) -> ArrayView[SongEntry[C]] {
  self.entries[:]
}

///|
/// Every entry's slice that sounds within `arc`, in song order.
pub fn[C] SongSnapshot::slices(
  self : SongSnapshot[C],
  arc : @pattern.TimeSpan,
) -> Array[SongSlice[C]] {
  [
    for entry in self.entries if entry.slice(arc) is Some(slice) => slice
  ]
}

///|
/// Identity-bearing song layout document for incremental occurrence edits.
///
/// This authoring layer keeps stable occurrence IDs across display renames,
/// insertion, removal, and reordering. It lowers back to the existing playback
/// song surface so scheduler/query semantics remain unchanged.
pub struct SongDoc[C] {
  priv revision : @identity.Revision
  priv layout_revision : @identity.Revision
  priv parts : Array[SongOccurrenceDoc[C]]
}

///|
pub fn[C] SongDoc::SongDoc(
  parts~ : Array[SongOccurrenceDoc[C]],
) -> SongDoc[C] raise SongDocBuildError {
  validate_song_doc_parts(parts)
  {
    revision: aggregate_song_doc_revision(parts),
    layout_revision: aggregate_song_doc_layout_revision(parts),
    parts: copy_song_occurrence_docs(parts),
  }
}

///|
pub fn[C] SongDoc::revision(self : SongDoc[C]) -> @identity.Revision {
  self.revision
}

///|
pub fn[C] SongDoc::layout_revision(self : SongDoc[C]) -> @identity.Revision {
  self.layout_revision
}

///|
pub fn[C] SongDoc::occurrence_count(self : SongDoc[C]) -> Int32 {
  self.parts.length()
}

///|
pub fn[C] SongDoc::occurrences(
  self : SongDoc[C],
) -> Array[SongOccurrenceDoc[C]] {
  copy_song_occurrence_docs(self.parts)
}

///|
pub fn[C] SongDoc::occurrence(
  self : SongDoc[C],
  index : Int32,
) -> SongOccurrenceDoc[C]? {
  match self.parts.get(index) {
    Some(part) => Some(part)
    None => None
  }
}

///|
pub fn[C] SongDoc::get_occurrence(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
) -> SongOccurrenceDoc[C]? {
  match song_doc_find_occurrence_index(self.parts, id) {
    Some(index) => Some(self.parts[index])
    None => None
  }
}

///|
pub fn[C] SongDoc::rename_occurrence(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
  name~ : String,
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::replace_occurrence_section(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
  section~ : SectionDoc[C],
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::set_occurrence_start(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
  start~ : @pattern.Rational,
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::clear_occurrence_start(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::insert_occurrence(
  self : SongDoc[C],
  index~ : Int32,
  occurrence~ : SongOccurrenceDoc[C],
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::remove_occurrence(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::move_occurrence(
  self : SongDoc[C],
  id : @identity.OccurrenceId,
  index~ : Int32,
) -> SongDoc[C] raise SongDocEditError {
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
pub fn[C] SongDoc::to_song(self : SongDoc[C]) -> Song[C] raise SongBuildError {
  Song(parts=[ for part in self.parts => part.to_part() ])
}

///|
pub fn[C : SongContent] SongDoc::lower(
  self : SongDoc[C],
) -> SongSnapshot[C] raise SongBuildError {
  let song = self.to_song()
  {
    revision: self.revision,
    layout_revision: self.layout_revision,
    song,
    entries: song_entries(song, self.parts),
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
