///|
#derive(Eq, Debug)
pub(all) suberror SongBuildError {
  EmptySong
  /// Two parts share this occurrence id.
  DuplicateOccurrence(String)
}

///|
/// A start before cycle 0, where every song begins: nothing can play there.
#derive(Eq, Debug)
pub(all) suberror NegativeStart

///|
/// One placement of a section in a song. A part without a start begins where
/// the parts before it end; one with a start may leave a gap or overlap.
pub struct SongPart[C] {
  priv id : @identity.OccurrenceId
  priv start : @pattern.Rational?
  priv section : Section[C]
}

///|
pub fn[C] SongPart::SongPart(
  id~ : @identity.OccurrenceId,
  section~ : Section[C],
) -> SongPart[C] {
  { id, start: None, section, }
}

///|
/// A part starting at `start`, or `NegativeStart` before the song begins.
pub fn[C] SongPart::at(
  id~ : @identity.OccurrenceId,
  start~ : @pattern.Rational,
  section~ : Section[C],
) -> SongPart[C] raise NegativeStart {
  guard start >= @pattern.Rational::from_int(0) else { raise NegativeStart }
  { id, start: Some(start), section, }
}

///|
/// Where a part landed: its section over a span of song time.
pub struct SectionOccurrence[C] {
  priv id : @identity.OccurrenceId
  priv section : Section[C]
  priv span : @pattern.TimeSpan
}

///|
pub fn[C] SectionOccurrence::id(
  self : SectionOccurrence[C],
) -> @identity.OccurrenceId {
  self.id
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
/// An arrangement of sections over song time, from cycle 0 to `duration`.
///
/// `Song` is generic over the section content `C` (ADR-0021); only
/// `entries` looks inside it.
pub struct Song[C] {
  priv occurrences : Array[SectionOccurrence[C]]
  priv duration : @pattern.Rational
}

///|
/// The song `parts` lay out in order, or `SongBuildError` when there is no
/// part or two parts share an id. A song ends after its beginning: it has a
/// part, every start is at or after 0, and every section lasts.
pub fn[C] Song::Song(
  parts~ : Array[SongPart[C]],
) -> Song[C] raise SongBuildError {
  guard !parts.is_empty() else { raise EmptySong }
  let occurrences : Array[SectionOccurrence[C]] = []
  let ids : Map[String, Bool] = Map([])
  let mut cursor = @pattern.Rational::from_int(0)
  for part in parts {
    let id = part.id.value()
    if ids.contains(id) {
      raise DuplicateOccurrence(id)
    }
    ids[id] = true
    let start = part.start.unwrap_or(cursor)
    let end_ = start + part.section.length_cycles()
    occurrences.push({
      id: part.id,
      section: part.section,
      span: @pattern.TimeSpan(start, end_),
    })
    if end_ > cursor {
      cursor = end_
    }
  }
  { occurrences, duration: cursor, }
}

///|
pub fn[C] Song::duration(self : Song[C]) -> @pattern.Rational {
  self.duration
}

///|
/// The occurrences in the order their parts were written.
pub fn[C] Song::occurrences(self : Song[C]) -> ArrayView[SectionOccurrence[C]] {
  self.occurrences[:]
}

///|
/// The song time no occurrence covers, earliest first.
pub fn[C] Song::gap_spans(self : Song[C]) -> Array[@pattern.TimeSpan] {
  let spans = self.occurrences.map(occurrence => occurrence.span)
  spans.sort_by((left, right) => left.begin.compare(right.begin))
  let result : Array[@pattern.TimeSpan] = []
  let mut cursor = @pattern.Rational::from_int(0)
  for span in spans {
    if cursor < span.begin {
      result.push(@pattern.TimeSpan(cursor, span.begin))
    }
    if span.end_ > cursor {
      cursor = span.end_
    }
  }
  result
}

///|
/// The canonical playback entries: every content entry of every layer of
/// every occurrence, in song order.
pub fn[C : SongContent] Song::entries(self : Song[C]) -> Array[SongEntry[C]] {
  let result : Array[SongEntry[C]] = []
  for occurrence in self.occurrences {
    let section = occurrence.section
    for layer in section.layers {
      let origin = SongEventOrigin(
        occurrence=occurrence.id,
        section=section.id,
        layer=layer.id,
      )
      let content = layer.content
      for index, body in content.pat().fast(section.rate).entries() {
        result.push({ occurrence, origin, content, index, body, })
      }
    }
  }
  result
}

///|
/// One canonical playback entry of a song: one `Pat::entries()` member of
/// one layer of one occurrence.
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
    rate=self.occurrence.section.rate,
  )
}

///|
pub fn[C] SongEntry::origin(self : SongEntry[C]) -> SongEventOrigin {
  self.origin
}

///|
/// The entry's pattern at its section's rate, in occurrence-local time.
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
/// Which occurrence, section and layer a song event comes from.
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
pub extend SongBuildError with Debug::{to_repr}

///|
pub extend SongBuildError with Eq::{not_equal, equal}

///|
pub extend NegativeStart with Eq::{not_equal, equal}

///|
pub extend NegativeStart with Debug::{to_repr}

///|
pub extend SongEventOrigin with Debug::{to_repr}

///|
pub extend SongEventOrigin with Eq::{not_equal, equal}
