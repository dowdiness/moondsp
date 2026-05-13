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
  priv occurrence_index : Map[String, Int]
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
fn[A] sorted_occurrences_by_start(
  occurrences : Array[SectionOccurrence[A]],
) -> Array[SectionOccurrence[A]] {
  let result : Array[SectionOccurrence[A]] = []
  for occurrence in occurrences {
    result.push(occurrence.snapshot())
    let mut index = result.length() - 1
    while index > 0 && result[index].start() < result[index - 1].start() {
      let previous = result[index - 1]
      result[index - 1] = result[index]
      result[index] = previous
      index = index - 1
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
  if parts.length() == 0 {
    raise EmptySong
  }
  let occurrences : Array[SectionOccurrence[A]] = []
  let occurrence_index : Map[String, Int] = {}
  let occurrence_names : Map[String, Bool] = {}
  let mut cursor = @pattern.Rational::from_int(0)
  for part in parts {
    if occurrence_names.contains(part.name) {
      raise DuplicateOccurrence(part.name)
    }
    let id = occurrence_id_for_part(part)
    if occurrence_index.contains(id.value()) {
      raise DuplicateOccurrenceId(id.value())
    }
    let start = part.start.unwrap_or(cursor)
    let end_ = start + part.section.length_cycles()
    let index = occurrences.length()
    occurrence_index[id.value()] = index
    occurrence_names[part.name] = true
    occurrences.push({
      id,
      name: part.name,
      section: part.section,
      span: @pattern.TimeSpan::new(start, end_),
    })
    cursor = max_rational(cursor, end_)
  }
  { occurrences, occurrence_index, duration: cursor }
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
  for occurrence in self.occurrences {
    if occurrence.span.contains(time) {
      return Some(occurrence.snapshot())
    }
  }
  None
}

///|
pub fn[A] Song::occurrences_at(
  self : Song[A],
  time : @pattern.Rational,
) -> Array[SectionOccurrence[A]] {
  let result : Array[SectionOccurrence[A]] = []
  for occurrence in self.occurrences {
    if occurrence.span.contains(time) {
      result.push(occurrence.snapshot())
    }
  }
  result
}

///|
pub fn[A] Song::occurrences_intersecting(
  self : Song[A],
  arc : @pattern.TimeSpan,
) -> Array[SectionOccurrence[A]] {
  let result : Array[SectionOccurrence[A]] = []
  for occurrence in self.occurrences {
    if occurrence.span.intersect(arc) is Some(_) {
      result.push(occurrence.snapshot())
    }
  }
  result
}

///|
pub fn[A] Song::gap_spans(self : Song[A]) -> Array[@pattern.TimeSpan] {
  let result : Array[@pattern.TimeSpan] = []
  let mut cursor = @pattern.Rational::from_int(0)
  let sorted = sorted_occurrences_by_start(self.occurrences)
  for occurrence in sorted {
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
  for occurrence in self.occurrences {
    if occurrence.name == name {
      return Some(occurrence.snapshot())
    }
  }
  None
}

///|
pub fn[A] Song::get_occurrence_by_id(
  self : Song[A],
  id : @identity.OccurrenceId,
) -> SectionOccurrence[A]? {
  match self.occurrence_index.get(id.value()) {
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
  for occurrence in self.occurrences {
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
