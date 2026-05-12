///|
pub(all) suberror SongBuildError {
  EmptySong
  DuplicateOccurrence(String)
  DuplicateOccurrenceId(String)
  InvalidOccurrenceId(String)
} derive(Eq, Debug)

///|
/// User-authored contiguous song part.
///
/// A `SongPart` names one placement of a reusable `Section`. Reusing the same
/// section body multiple times is allowed by giving each part a distinct name.
pub struct SongPart[A] {
  priv id : @identity.OccurrenceId?
  priv name : String
  priv section : Section[A]
}

///|
pub fn[A] SongPart::SongPart(
  name~ : String,
  section~ : Section[A],
) -> SongPart[A] {
  { id: None, name, section }
}

///|
pub fn[A] SongPart::with_id(
  id~ : @identity.OccurrenceId,
  name~ : String,
  section~ : Section[A],
) -> SongPart[A] {
  { id: Some(id), name, section }
}

///|
pub fn[A] SongPart::id(self : SongPart[A]) -> @identity.OccurrenceId? {
  self.id
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
/// Contiguous long-form arrangement of named section occurrences.
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
    let end_ = cursor + part.section.length_cycles()
    let index = occurrences.length()
    occurrence_index[id.value()] = index
    occurrence_names[part.name] = true
    occurrences.push({
      id,
      name: part.name,
      section: part.section,
      span: @pattern.TimeSpan::new(cursor, end_),
    })
    cursor = end_
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
        let events = occurrence.section.body().query(local_arc)
        for event in events {
          result.push(event.shift(occurrence.span.begin))
        }
      }
      None => ()
    }
  }
  result
}
