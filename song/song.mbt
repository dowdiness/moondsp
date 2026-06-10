///|
pub(all) suberror SongBuildError {
  EmptySong
  DuplicateOccurrence(String)
  DuplicateOccurrenceId(String)
  InvalidOccurrenceId(String)
} derive(Eq, Debug)

///|
/// User-authored song part.
///
/// A `SongPart` names one placement of a reusable `Section`. Reusing the same
/// section body multiple times is allowed by giving each part a distinct name.
/// Parts without an explicit start are placed at the current layout cursor;
/// parts with an explicit start may create gaps or overlaps.
pub struct SongPart[A] {
  priv id : @identity.OccurrenceId?
  priv start : @pattern.Rational?
  priv name : String
  priv section : Section[A]
}

///|
pub fn[A] SongPart::SongPart(
  name~ : String,
  section~ : Section[A],
) -> SongPart[A] {
  { id: None, start: None, name, section }
}

///|
pub fn[A] SongPart::with_id(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : Section[A],
) -> SongPart[A] {
  { id: Some(id), start: None, name, section }
}

///|
pub fn[A] SongPart::at(
  start~ : @pattern.Rational,
  name~ : String,
  section~ : Section[A],
) -> SongPart[A] {
  { id: None, start: Some(start), name, section }
}

///|
pub fn[A] SongPart::with_id_at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  name~ : String,
  section~ : Section[A],
) -> SongPart[A] {
  { id: Some(id), start: Some(start), name, section }
}

///|
pub fn[A] SongPart::id(self : SongPart[A]) -> @identity.OccurrenceId? {
  self.id
}

///|
pub fn[A] SongPart::start(self : SongPart[A]) -> @pattern.Rational? {
  self.start
}

///|
pub fn[A] SongPart::name(self : SongPart[A]) -> String {
  self.name
}

///|
pub fn[A] SongPart::section(self : SongPart[A]) -> Section[A] {
  self.section
}

///|
/// Computed placement of a section in song-global logical time.
pub struct SectionOccurrence[A] {
  priv id : @identity.OccurrenceId
  priv name : String
  priv section : Section[A]
  priv span : @pattern.TimeSpan
}

///|
fn[A] SectionOccurrence::snapshot(
  self : SectionOccurrence[A],
) -> SectionOccurrence[A] {
  { id: self.id, name: self.name, section: self.section, span: self.span }
}

///|
pub fn[A] SectionOccurrence::id(
  self : SectionOccurrence[A],
) -> @identity.OccurrenceId {
  self.id
}

///|
pub fn[A] SectionOccurrence::name(self : SectionOccurrence[A]) -> String {
  self.name
}

///|
pub fn[A] SectionOccurrence::section(self : SectionOccurrence[A]) -> Section[A] {
  self.section
}

///|
pub fn[A] SectionOccurrence::span(
  self : SectionOccurrence[A],
) -> @pattern.TimeSpan {
  self.span
}

///|
pub fn[A] SectionOccurrence::start(
  self : SectionOccurrence[A],
) -> @pattern.Rational {
  self.span.begin
}

///|
pub fn[A] SectionOccurrence::end_(
  self : SectionOccurrence[A],
) -> @pattern.Rational {
  self.span.end_
}

///|
/// Long-form arrangement of named section occurrences.
///
/// `Song` is intentionally polymorphic in the same payload type as `Section`
/// and `Pat`. Scheduler integration specializes it to `Song[ControlMap]`.
pub struct Song[A] {
  priv occurrences : Array[SectionOccurrence[A]]
  priv occurrence_by_id : Map[String, Int]
  priv occurrence_by_name : Map[String, Int]
  priv occurrence_by_start : Array[Int]
  priv occurrence_by_end : Array[Int]
  priv duration : @pattern.Rational
}

///|
fn[A] occurrence_id_for_part(
  part : SongPart[A],
) -> @identity.OccurrenceId raise SongBuildError {
  match part.id {
    Some(id) => id
    None => {
      let result = try? @identity.OccurrenceId::from_string(part.name)
      match result {
        Ok(id) => id
        Err(_) => raise InvalidOccurrenceId(part.name)
      }
    }
  }
}

///|
fn[A] copy_occurrences(
  occurrences : Array[SectionOccurrence[A]],
) -> Array[SectionOccurrence[A]] {
  let result : Array[SectionOccurrence[A]] = []
  for occurrence in occurrences {
    result.push(occurrence.snapshot())
  }
  result
}

///|
fn[A] sorted_occurrence_indexes_by_start(
  occurrences : Array[SectionOccurrence[A]],
) -> Array[Int] {
  let result : Array[Int] = []
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
fn[A] sorted_occurrence_indexes_by_end(
  occurrences : Array[SectionOccurrence[A]],
) -> Array[Int] {
  let result : Array[Int] = []
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
fn[A] first_start_not_before(
  occurrences : Array[SectionOccurrence[A]],
  indexes : Array[Int],
  time : @pattern.Rational,
) -> Int {
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
fn[A] first_start_after(
  occurrences : Array[SectionOccurrence[A]],
  indexes : Array[Int],
  time : @pattern.Rational,
) -> Int {
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
fn[A] first_end_after(
  occurrences : Array[SectionOccurrence[A]],
  indexes : Array[Int],
  time : @pattern.Rational,
) -> Int {
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
  indexes : Array[Int],
  occurrence_index : Int,
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
fn[A] Song::occurrence_indexes_at(
  self : Song[A],
  time : @pattern.Rational,
) -> Array[Int] {
  let result : Array[Int] = []
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
fn[A] Song::occurrence_indexes_intersecting(
  self : Song[A],
  arc : @pattern.TimeSpan,
) -> Array[Int] {
  let result : Array[Int] = []
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
pub fn[A] Song::Song(
  parts~ : Array[SongPart[A]],
) -> Song[A] raise SongBuildError {
  if parts.is_empty() {
    raise EmptySong
  }
  let occurrences : Array[SectionOccurrence[A]] = []
  let by_id : Map[String, Int] = {}
  let by_name : Map[String, Int] = {}
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
      span: @pattern.TimeSpan::new(start, end_),
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
pub fn[A] Song::from_sections(
  sections : Array[Section[A]],
) -> Song[A] raise SongBuildError {
  let parts : Array[SongPart[A]] = []
  for section in sections {
    parts.push(SongPart(name=section.name(), section~))
  }
  Song(parts~)
}

///|
pub fn[A] Song::duration(self : Song[A]) -> @pattern.Rational {
  self.duration
}

///|
pub fn[A] Song::occurrence_count(self : Song[A]) -> Int {
  self.occurrences.length()
}

///|
pub fn[A] Song::occurrences(self : Song[A]) -> Array[SectionOccurrence[A]] {
  copy_occurrences(self.occurrences)
}

///|
pub fn[A] Song::occurrence(
  self : Song[A],
  index : Int,
) -> SectionOccurrence[A]? {
  match self.occurrences.get(index) {
    Some(occurrence) => Some(occurrence.snapshot())
    None => None
  }
}

///|
pub fn[A] Song::occurrence_at(
  self : Song[A],
  time : @pattern.Rational,
) -> SectionOccurrence[A]? {
  let indexes = self.occurrence_indexes_at(time)
  match indexes.get(0) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
pub fn[A] Song::occurrences_at(
  self : Song[A],
  time : @pattern.Rational,
) -> Array[SectionOccurrence[A]] {
  let result : Array[SectionOccurrence[A]] = []
  let indexes = self.occurrence_indexes_at(time)
  for index in indexes {
    result.push(self.occurrences[index].snapshot())
  }
  result
}

///|
pub fn[A] Song::occurrences_intersecting(
  self : Song[A],
  arc : @pattern.TimeSpan,
) -> Array[SectionOccurrence[A]] {
  let result : Array[SectionOccurrence[A]] = []
  let indexes = self.occurrence_indexes_intersecting(arc)
  for index in indexes {
    result.push(self.occurrences[index].snapshot())
  }
  result
}

///|
pub fn[A] Song::gap_spans(self : Song[A]) -> Array[@pattern.TimeSpan] {
  let result : Array[@pattern.TimeSpan] = []
  let mut cursor = @pattern.Rational::from_int(0)
  for index in self.occurrence_by_start {
    let occurrence = self.occurrences[index]
    if cursor < occurrence.start() {
      result.push(@pattern.TimeSpan::new(cursor, occurrence.start()))
    }
    cursor = max_rational(cursor, occurrence.end_())
  }
  result
}

///|
fn[A] section_with_length(
  section : Section[A],
  length_cycles : @pattern.Rational,
) -> Section[A] {
  {
    name: section.name(),
    length_cycles,
    scope: section.scope(),
    body: section.section_body(),
  }
}

///|
fn fill_occurrence_name(prefix : String, index : Int) -> String {
  "\{prefix}:\{index}"
}

///|
fn[A] occurrence_to_part(occurrence : SectionOccurrence[A]) -> SongPart[A] {
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
pub fn[A] Song::fill_gaps(
  self : Song[A],
  prefix~ : String,
  section~ : Section[A],
) -> Song[A] raise SongBuildError {
  let parts : Array[SongPart[A]] = []
  for occurrence in self.occurrences {
    parts.push(occurrence_to_part(occurrence))
  }
  let gaps = self.gap_spans()
  for index in 0..<gaps.length() {
    let gap = gaps[index]
    let fill_name = fill_occurrence_name(prefix, index)
    parts.push(
      SongPart::at(
        start=gap.begin,
        name=fill_name,
        section=section_with_length(section, gap.duration()),
      ),
    )
  }
  Song(parts~)
}

///|
pub fn[A] Song::get_occurrence(
  self : Song[A],
  name : String,
) -> SectionOccurrence[A]? {
  match self.occurrence_by_name.get(name) {
    Some(index) => self.occurrence(index)
    None => None
  }
}

///|
pub fn[A] Song::get_occurrence_by_id(
  self : Song[A],
  id : @identity.OccurrenceId,
) -> SectionOccurrence[A]? {
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
  @pattern.TimeSpan::new(span.begin - offset, span.end_ - offset)
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
pub fn[A] Song::query(
  self : Song[A],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[A]] {
  let result : Array[@pattern.Event[A]] = []
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
