///|
#derive(Eq, Debug)
pub(all) suberror SongBuildError {
  EmptySong
  DuplicateOccurrence(String)
  DuplicateOccurrenceId(String)
  InvalidOccurrenceId(String)
}

///|
/// User-authored song part.
///
/// A `SongPart` names one placement of a reusable `Section`. Reusing the same
/// section body multiple times is allowed by giving each part a distinct name.
/// Parts without an explicit start are placed at the current layout cursor;
/// parts with an explicit start may create gaps or overlaps.
pub struct SongPart {
  priv id : @identity.OccurrenceId?
  priv start : @pattern.Rational?
  priv name : String
  priv section : Section
}

///|
pub fn SongPart::SongPart(name~ : String, section~ : Section) -> SongPart {
  { id: None, start: None, name, section, }
}

///|
pub fn SongPart::with_id(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : Section,
) -> SongPart {
  { id: Some(id), start: None, name, section, }
}

///|
pub fn SongPart::at(
  start~ : @pattern.Rational,
  name~ : String,
  section~ : Section,
) -> SongPart {
  { id: None, start: Some(start), name, section, }
}

///|
pub fn SongPart::with_id_at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  name~ : String,
  section~ : Section,
) -> SongPart {
  { id: Some(id), start: Some(start), name, section, }
}

///|
pub fn SongPart::id(self : SongPart) -> @identity.OccurrenceId? {
  self.id
}

///|
pub fn SongPart::start(self : SongPart) -> @pattern.Rational? {
  self.start
}

///|
pub fn SongPart::name(self : SongPart) -> String {
  self.name
}

///|
pub fn SongPart::section(self : SongPart) -> Section {
  self.section
}

///|
/// Computed placement of a section in song-global logical time.
pub struct SectionOccurrence {
  priv id : @identity.OccurrenceId
  priv name : String
  priv section : Section
  priv span : @pattern.TimeSpan
}

///|
fn SectionOccurrence::snapshot(self : SectionOccurrence) -> SectionOccurrence {
  { id: self.id, name: self.name, section: self.section, span: self.span, }
}

///|
pub fn SectionOccurrence::id(
  self : SectionOccurrence,
) -> @identity.OccurrenceId {
  self.id
}

///|
pub fn SectionOccurrence::name(self : SectionOccurrence) -> String {
  self.name
}

///|
pub fn SectionOccurrence::section(self : SectionOccurrence) -> Section {
  self.section
}

///|
pub fn SectionOccurrence::span(self : SectionOccurrence) -> @pattern.TimeSpan {
  self.span
}

///|
pub fn SectionOccurrence::start(self : SectionOccurrence) -> @pattern.Rational {
  self.span.begin
}

///|
pub fn SectionOccurrence::end_(self : SectionOccurrence) -> @pattern.Rational {
  self.span.end_
}

///|
/// Long-form arrangement of named section occurrences.
pub struct Song {
  priv occurrences : Array[SectionOccurrence]
  priv occurrence_by_id : Map[String, Int32]
  priv occurrence_by_name : Map[String, Int32]
  priv occurrence_by_start : Array[Int32]
  priv occurrence_by_end : Array[Int32]
  priv duration : @pattern.Rational
}

///|
fn occurrence_id_for_part(
  part : SongPart,
) -> @identity.OccurrenceId raise SongBuildError {
  match part.id {
    Some(id) => id
    None =>
      @identity.OccurrenceId::from_string(part.name) catch {
        _ => raise InvalidOccurrenceId(part.name)
      }
  }
}

///|
fn copy_occurrences(
  occurrences : Array[SectionOccurrence],
) -> Array[SectionOccurrence] {
  occurrences.map(occurrence => occurrence.snapshot())
}

///|
fn sorted_occurrence_indexes_by_start(
  occurrences : Array[SectionOccurrence],
) -> Array[Int32] {
  let result : Array[Int32] = []
  for occurrence_index in 0..<occurrences.length() {
    result.push(occurrence_index)
    let mut index = result.length() - 1
    while index > 0 &&
          occurrences[result[index]].start() <
          occurrences[result[index - 1]].start() {
      let previous = result[index - 1]
      result[index - 1] = result[index]
      result[index] = previous
      index = index - 1
    }
  }
  result
}

///|
fn sorted_occurrence_indexes_by_end(
  occurrences : Array[SectionOccurrence],
) -> Array[Int32] {
  let result : Array[Int32] = []
  for occurrence_index in 0..<occurrences.length() {
    result.push(occurrence_index)
    let mut index = result.length() - 1
    while index > 0 &&
          occurrences[result[index]].end_() <
          occurrences[result[index - 1]].end_() {
      let previous = result[index - 1]
      result[index - 1] = result[index]
      result[index] = previous
      index = index - 1
    }
  }
  result
}

///|
fn first_start_not_before(
  occurrences : Array[SectionOccurrence],
  indexes : Array[Int32],
  time : @pattern.Rational,
) -> Int32 {
  let mut low = 0
  let mut high = indexes.length()
  while low < high {
    let middle = (low + high) / 2
    if occurrences[indexes[middle]].start() < time {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn first_start_after(
  occurrences : Array[SectionOccurrence],
  indexes : Array[Int32],
  time : @pattern.Rational,
) -> Int32 {
  let mut low = 0
  let mut high = indexes.length()
  while low < high {
    let middle = (low + high) / 2
    if occurrences[indexes[middle]].start() <= time {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn first_end_after(
  occurrences : Array[SectionOccurrence],
  indexes : Array[Int32],
  time : @pattern.Rational,
) -> Int32 {
  let mut low = 0
  let mut high = indexes.length()
  while low < high {
    let middle = (low + high) / 2
    if occurrences[indexes[middle]].end_() <= time {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn push_index_in_authoring_order(
  indexes : Array[Int32],
  occurrence_index : Int32,
) -> Unit {
  let mut insert_at = indexes.length()
  let mut cursor = 0
  let mut searching = true
  let mut duplicate = false
  while cursor < indexes.length() && searching {
    if indexes[cursor] == occurrence_index {
      duplicate = true
      searching = false
    } else if occurrence_index < indexes[cursor] {
      insert_at = cursor
      searching = false
    } else {
      cursor = cursor + 1
    }
  }
  if !duplicate {
    indexes.push(occurrence_index)
    let mut index = indexes.length() - 1
    while index > insert_at {
      indexes[index] = indexes[index - 1]
      index = index - 1
    }
    indexes[insert_at] = occurrence_index
  }
}

///|
fn Song::occurrence_indexes_at(
  self : Song,
  time : @pattern.Rational,
) -> Array[Int32] {
  let result : Array[Int32] = []
  let start_limit = first_start_after(
    self.occurrences,
    self.occurrence_by_start,
    time,
  )
  let end_begin = first_end_after(
    self.occurrences,
    self.occurrence_by_end,
    time,
  )
  let end_count = self.occurrence_by_end.length() - end_begin
  if start_limit <= end_count {
    for index in 0..<start_limit {
      let occurrence_index = self.occurrence_by_start[index]
      if self.occurrences[occurrence_index].span.contains(time) {
        push_index_in_authoring_order(result, occurrence_index)
      }
    }
  } else {
    for index in end_begin..<self.occurrence_by_end.length() {
      let occurrence_index = self.occurrence_by_end[index]
      if self.occurrences[occurrence_index].span.contains(time) {
        push_index_in_authoring_order(result, occurrence_index)
      }
    }
  }
  result
}

///|
fn Song::occurrence_indexes_intersecting(
  self : Song,
  arc : @pattern.TimeSpan,
) -> Array[Int32] {
  let result : Array[Int32] = []
  let start_limit = first_start_not_before(
    self.occurrences,
    self.occurrence_by_start,
    arc.end_,
  )
  let end_begin = first_end_after(
    self.occurrences,
    self.occurrence_by_end,
    arc.begin,
  )
  let end_count = self.occurrence_by_end.length() - end_begin
  if start_limit <= end_count {
    for index in 0..<start_limit {
      let occurrence_index = self.occurrence_by_start[index]
      if self.occurrences[occurrence_index].span.intersect(arc) is Some(_) {
        push_index_in_authoring_order(result, occurrence_index)
      }
    }
  } else {
    for index in end_begin..<self.occurrence_by_end.length() {
      let occurrence_index = self.occurrence_by_end[index]
      if self.occurrences[occurrence_index].span.intersect(arc) is Some(_) {
        push_index_in_authoring_order(result, occurrence_index)
      }
    }
  }
  result
}

///|
fn max_rational(
  left : @pattern.Rational,
  right : @pattern.Rational,
) -> @pattern.Rational {
  if left >= right {
    left
  } else {
    right
  }
}

///|
pub fn Song::Song(parts~ : Array[SongPart]) -> Song raise SongBuildError {
  if parts.is_empty() {
    raise EmptySong
  }
  let occurrences : Array[SectionOccurrence] = []
  let by_id : Map[String, Int32] = Map([])
  let by_name : Map[String, Int32] = Map([])
  let mut cursor = @pattern.Rational::from_int(0)
  for part in parts {
    if by_name.contains(part.name) {
      raise DuplicateOccurrence(part.name)
    }
    let id = occurrence_id_for_part(part)
    if by_id.contains(id.value()) {
      raise DuplicateOccurrenceId(id.value())
    }
    let start = part.start.unwrap_or(cursor)
    let end_ = start + part.section.length_cycles()
    let index = occurrences.length()
    by_id[id.value()] = index
    by_name[part.name] = index
    occurrences.push({
      id,
      name: part.name,
      section: part.section,
      span: @pattern.TimeSpan(start, end_),
    })
    cursor = max_rational(cursor, end_)
  }
  {
    occurrences,
    occurrence_by_id: by_id,
    occurrence_by_name: by_name,
    occurrence_by_start: sorted_occurrence_indexes_by_start(occurrences),
    occurrence_by_end: sorted_occurrence_indexes_by_end(occurrences),
    duration: cursor,
  }
}

///|
pub fn Song::from_sections(
  sections : Array[Section],
) -> Song raise SongBuildError {
  Song(parts=sections.map(section => SongPart(name=section.name(), section~)))
}

///|
pub fn Song::duration(self : Song) -> @pattern.Rational {
  self.duration
}

///|
pub fn Song::occurrence_count(self : Song) -> Int32 {
  self.occurrences.length()
}

///|
pub fn Song::occurrences(self : Song) -> Array[SectionOccurrence] {
  copy_occurrences(self.occurrences)
}

///|
pub fn Song::occurrence(self : Song, index : Int32) -> SectionOccurrence? {
  match self.occurrences.get(index) {
    Some(occurrence) => Some(occurrence.snapshot())
    None => None
  }
}

///|
pub fn Song::occurrence_at(
  self : Song,
  time : @pattern.Rational,
) -> SectionOccurrence? {
  let indexes = self.occurrence_indexes_at(time)
  match indexes.get(0) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
pub fn Song::occurrences_at(
  self : Song,
  time : @pattern.Rational,
) -> Array[SectionOccurrence] {
  self
  .occurrence_indexes_at(time)
  .map(index => self.occurrences[index].snapshot())
}

///|
pub fn Song::occurrences_intersecting(
  self : Song,
  arc : @pattern.TimeSpan,
) -> Array[SectionOccurrence] {
  self
  .occurrence_indexes_intersecting(arc)
  .map(index => self.occurrences[index].snapshot())
}

///|
pub fn Song::gap_spans(self : Song) -> Array[@pattern.TimeSpan] {
  let result : Array[@pattern.TimeSpan] = []
  let mut cursor = @pattern.Rational::from_int(0)
  for index in self.occurrence_by_start {
    let occurrence = self.occurrences[index]
    if cursor < occurrence.start() {
      result.push(@pattern.TimeSpan(cursor, occurrence.start()))
    }
    cursor = max_rational(cursor, occurrence.end_())
  }
  result
}

///|
fn section_with_length(
  section : Section,
  length_cycles : @pattern.Rational,
) -> Section {
  {
    name: section.name(),
    length_cycles,
    scope: section.scope(),
    body: section.section_body(),
    source_snapshot: section.source_snapshot(),
  }
}

///|
fn fill_occurrence_name(prefix : String, index : Int32) -> String {
  "\{prefix}:\{index}"
}

///|
fn occurrence_to_part(occurrence : SectionOccurrence) -> SongPart {
  SongPart::with_id_at(
    id=occurrence.id(),
    start=occurrence.start(),
    name=occurrence.name(),
    section=occurrence.section(),
  )
}

///|
/// Return a derived song where uncovered time between occurrences is filled.
///
/// Existing occurrences keep their stable IDs and authoring order. Generated
/// fill names use deterministic `prefix:index` values in song-time gap order.
/// Each fill occurrence reuses the supplied section body/scope with its length
/// adjusted to the uncovered span.
pub fn Song::fill_gaps(
  self : Song,
  prefix~ : String,
  section~ : Section,
) -> Song raise SongBuildError {
  let parts = self.occurrences.map(occurrence_to_part)
  for index, gap in self.gap_spans() {
    parts.push(
      SongPart::at(
        start=gap.begin,
        name=fill_occurrence_name(prefix, index),
        section=section_with_length(section, gap.duration()),
      ),
    )
  }
  Song(parts~)
}

///|
pub fn Song::get_occurrence(self : Song, name : String) -> SectionOccurrence? {
  match self.occurrence_by_name.get(name) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
pub fn Song::get_occurrence_by_id(
  self : Song,
  id : @identity.OccurrenceId,
) -> SectionOccurrence? {
  match self.occurrence_by_id.get(id.value()) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
fn unshift_span(
  span : @pattern.TimeSpan,
  offset : @pattern.Rational,
) -> @pattern.TimeSpan {
  @pattern.TimeSpan(span.begin - offset, span.end_ - offset)
}

///|
/// Query song-global logical time.
///
/// Each intersecting occurrence is queried in section-local time, then returned
/// events are shifted back into song-global time. Event `part` remains clipped
/// to the query/occurrence intersection; event `whole` preserves the pattern's
/// intended duration and is shifted without clipping. This intentionally lets
/// notes sustain past section boundaries; clipping `whole` here would force
/// abrupt note-offs at layout boundaries.
pub fn Song::query(
  self : Song,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  let result : Array[@pattern.Event[@pattern.ControlMap]] = []
  let indexes = self.occurrence_indexes_intersecting(arc)
  for index in indexes {
    let occurrence = self.occurrences[index]
    match occurrence.span.intersect(arc) {
      Some(global_arc) => {
        let local_arc = unshift_span(global_arc, occurrence.span.begin)
        let events = occurrence.section.query(local_arc)
        for event in events {
          result.push(event.shift(occurrence.span.begin))
        }
      }
      None => ()
    }
  }
  result
}

///|
pub extend SongBuildError with Debug::{to_repr}

///|
pub extend SongBuildError with Eq::{not_equal, equal}
