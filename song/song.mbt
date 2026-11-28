///|
#derive(Eq, Debug)
pub(all) suberror SongBuildError {
  EmptySong
  /// The named part starts before the song's beginning, cycle 0.
  NegativeStart(String)
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
pub struct SongPart[C] {
  priv id : @identity.OccurrenceId?
  priv start : @pattern.Rational?
  priv name : String
  priv section : Section[C]
}

///|
pub fn[C] SongPart::SongPart(
  name~ : String,
  section~ : Section[C],
) -> SongPart[C] {
  { id: None, start: None, name, section, }
}

///|
pub fn[C] SongPart::with_id(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : Section[C],
) -> SongPart[C] {
  { id: Some(id), start: None, name, section, }
}

///|
pub fn[C] SongPart::at(
  start~ : @pattern.Rational,
  name~ : String,
  section~ : Section[C],
) -> SongPart[C] {
  { id: None, start: Some(start), name, section, }
}

///|
pub fn[C] SongPart::with_id_at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  name~ : String,
  section~ : Section[C],
) -> SongPart[C] {
  { id: Some(id), start: Some(start), name, section, }
}

///|
pub fn[C] SongPart::id(self : SongPart[C]) -> @identity.OccurrenceId? {
  self.id
}

///|
pub fn[C] SongPart::start(self : SongPart[C]) -> @pattern.Rational? {
  self.start
}

///|
pub fn[C] SongPart::name(self : SongPart[C]) -> String {
  self.name
}

///|
pub fn[C] SongPart::section(self : SongPart[C]) -> Section[C] {
  self.section
}

///|
/// Computed placement of a section in song-global logical time.
pub struct SectionOccurrence[C] {
  priv id : @identity.OccurrenceId
  priv name : String
  priv section : Section[C]
  priv span : @pattern.TimeSpan
}

///|
fn[C] SectionOccurrence::snapshot(
  self : SectionOccurrence[C],
) -> SectionOccurrence[C] {
  { id: self.id, name: self.name, section: self.section, span: self.span, }
}

///|
pub fn[C] SectionOccurrence::id(
  self : SectionOccurrence[C],
) -> @identity.OccurrenceId {
  self.id
}

///|
pub fn[C] SectionOccurrence::name(self : SectionOccurrence[C]) -> String {
  self.name
}

///|
pub fn[C] SectionOccurrence::section(self : SectionOccurrence[C]) -> Section[C] {
  self.section
}

///|
pub fn[C] SectionOccurrence::span(
  self : SectionOccurrence[C],
) -> @pattern.TimeSpan {
  self.span
}

///|
pub fn[C] SectionOccurrence::start(
  self : SectionOccurrence[C],
) -> @pattern.Rational {
  self.span.begin
}

///|
pub fn[C] SectionOccurrence::end_(
  self : SectionOccurrence[C],
) -> @pattern.Rational {
  self.span.end_
}

///|
/// Long-form arrangement of named section occurrences.
///
/// `Song` is generic over the same section content `C` as `Section`
/// (ADR-0021).
pub struct Song[C] {
  priv occurrences : Array[SectionOccurrence[C]]
  priv occurrence_by_id : Map[String, Int32]
  priv occurrence_by_name : Map[String, Int32]
  priv occurrence_by_start : Array[Int32]
  priv occurrence_by_end : Array[Int32]
  priv duration : @pattern.Rational
}

///|
fn[C] occurrence_id_for_part(
  part : SongPart[C],
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
fn[C] copy_occurrences(
  occurrences : Array[SectionOccurrence[C]],
) -> Array[SectionOccurrence[C]] {
  occurrences.map(occurrence => occurrence.snapshot())
}

///|
fn[C] sorted_occurrence_indexes_by_start(
  occurrences : Array[SectionOccurrence[C]],
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
fn[C] sorted_occurrence_indexes_by_end(
  occurrences : Array[SectionOccurrence[C]],
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
fn[C] first_start_not_before(
  occurrences : Array[SectionOccurrence[C]],
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
fn[C] first_start_after(
  occurrences : Array[SectionOccurrence[C]],
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
fn[C] first_end_after(
  occurrences : Array[SectionOccurrence[C]],
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
fn[C] Song::occurrence_indexes_at(
  self : Song[C],
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
fn[C] Song::occurrence_indexes_intersecting(
  self : Song[C],
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
pub fn[C] Song::Song(
  parts~ : Array[SongPart[C]],
) -> Song[C] raise SongBuildError {
  if parts.is_empty() {
    raise EmptySong
  }
  let occurrences : Array[SectionOccurrence[C]] = []
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
    if start < @pattern.Rational::from_int(0) {
      raise NegativeStart(part.name)
    }
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
pub fn[C] Song::from_sections(
  sections : Array[Section[C]],
) -> Song[C] raise SongBuildError {
  Song(parts=sections.map(section => SongPart(name=section.name(), section~)))
}

///|
pub fn[C] Song::duration(self : Song[C]) -> @pattern.Rational {
  self.duration
}

///|
pub fn[C] Song::occurrence_count(self : Song[C]) -> Int32 {
  self.occurrences.length()
}

///|
pub fn[C] Song::occurrences(self : Song[C]) -> Array[SectionOccurrence[C]] {
  copy_occurrences(self.occurrences)
}

///|
pub fn[C] Song::occurrence(
  self : Song[C],
  index : Int32,
) -> SectionOccurrence[C]? {
  match self.occurrences.get(index) {
    Some(occurrence) => Some(occurrence.snapshot())
    None => None
  }
}

///|
pub fn[C] Song::occurrence_at(
  self : Song[C],
  time : @pattern.Rational,
) -> SectionOccurrence[C]? {
  let indexes = self.occurrence_indexes_at(time)
  match indexes.get(0) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
pub fn[C] Song::occurrences_at(
  self : Song[C],
  time : @pattern.Rational,
) -> Array[SectionOccurrence[C]] {
  self
  .occurrence_indexes_at(time)
  .map(index => self.occurrences[index].snapshot())
}

///|
pub fn[C] Song::occurrences_intersecting(
  self : Song[C],
  arc : @pattern.TimeSpan,
) -> Array[SectionOccurrence[C]] {
  self
  .occurrence_indexes_intersecting(arc)
  .map(index => self.occurrences[index].snapshot())
}

///|
pub fn[C] Song::gap_spans(self : Song[C]) -> Array[@pattern.TimeSpan] {
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
fn[C] section_with_length(
  section : Section[C],
  length_cycles : @pattern.Rational,
) -> Section[C] {
  {
    name: section.name(),
    length_cycles,
    scope: section.scope(),
    body: section.section_body(),
  }
}

///|
fn fill_occurrence_name(prefix : String, index : Int32) -> String {
  "\{prefix}:\{index}"
}

///|
fn[C] occurrence_to_part(occurrence : SectionOccurrence[C]) -> SongPart[C] {
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
pub fn[C] Song::fill_gaps(
  self : Song[C],
  prefix~ : String,
  section~ : Section[C],
) -> Song[C] raise SongBuildError {
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
pub fn[C] Song::get_occurrence(
  self : Song[C],
  name : String,
) -> SectionOccurrence[C]? {
  match self.occurrence_by_name.get(name) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
pub fn[C] Song::get_occurrence_by_id(
  self : Song[C],
  id : @identity.OccurrenceId,
) -> SectionOccurrence[C]? {
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
pub fn[C : SongContent] Song::query(
  self : Song[C],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  let result : Array[@pattern.Event[@score.ScoreEvent]] = []
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
