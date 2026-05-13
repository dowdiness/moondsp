///|
using @identity {type OccurrenceId}

///|
using @song {type Song, type SongBuildError, type SongPart}

///|
fn rat(n : Int64, d : Int64) -> @pattern.Rational {
  @pattern.Rational::new(n, d)
}

///|
fn span(
  begin_num : Int64,
  begin_den : Int64,
  end_num : Int64,
  end_den : Int64,
) -> @pattern.TimeSpan {
  @pattern.TimeSpan::new(rat(begin_num, begin_den), rat(end_num, end_den))
}

///|
fn make_section(
  name : String,
  length : @pattern.Rational,
  midi : Double,
) -> @song.Section[@pattern.ControlMap] {
  let result = try? @song.Section(
    name~,
    length_cycles=length,
    scope=@song.TimeScope::identity(),
    body=@song.SectionBody::single(@pattern.note(midi)),
  )
  match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
}

///|
fn make_scoped_section(
  name : String,
  length : @pattern.Rational,
  scope : @song.TimeScope,
  midi : Double,
) -> @song.Section[@pattern.ControlMap] {
  let result = try? @song.Section(
    name~,
    length_cycles=length,
    scope~,
    body=@song.SectionBody::single(@pattern.note(midi)),
  )
  match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
}

///|
fn fast_scope(n : Int) -> @song.TimeScope {
  let result = try? @song.TimeScope::fast(factor=@pattern.Rational::from_int(n))
  match result {
    Ok(scope) => scope
    Err(_) => abort("time scope creation failed")
  }
}

///|
fn make_song(
  parts : Array[SongPart[@pattern.ControlMap]],
) -> Song[@pattern.ControlMap] {
  let result = try? Song(parts~)
  match result {
    Ok(song) => song
    Err(_) => abort("song creation failed")
  }
}

///|
fn occurrence_id(value : String) -> OccurrenceId {
  let result = try? OccurrenceId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("occurrence id creation failed")
  }
}

///|
test "Song constructor computes contiguous duration and occurrences" {
  let intro = make_section("intro", @pattern.Rational::from_int(1), 60.0)
  let verse = make_section("verse", @pattern.Rational::from_int(2), 62.0)
  let song = make_song([
    SongPart(name="intro", section=intro),
    SongPart(name="verse1", section=verse),
  ])
  assert_true(song.duration() == @pattern.Rational::from_int(3))
  assert_eq(song.occurrence_count(), 2)
  match song.get_occurrence("verse1") {
    Some(occurrence) => {
      assert_true(occurrence.start() == @pattern.Rational::from_int(1))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
      assert_eq(occurrence.section().name(), "verse")
      assert_eq(occurrence.id().value(), "verse1")
    }
    None => abort("expected verse1 occurrence")
  }
}

///|
test "Song constructor rejects empty layout" {
  let parts : Array[SongPart[@pattern.ControlMap]] = []
  let result = try? Song(parts~)
  match result {
    Err(SongBuildError::EmptySong) => ()
    _ => assert_true(false)
  }
}

///|
test "Song constructor rejects duplicate occurrence names" {
  let section = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let result = try? Song(parts=[
    SongPart(name="verse1", section~),
    SongPart(name="verse1", section~),
  ])
  match result {
    Err(SongBuildError::DuplicateOccurrence("verse1")) => ()
    _ => assert_true(false)
  }
}

///|
test "Song constructor rejects occurrence names that cannot seed IDs" {
  let section = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let result = try? Song(parts=[SongPart(name="verse one", section~)])
  match result {
    Err(SongBuildError::InvalidOccurrenceId("verse one")) => ()
    _ => assert_true(false)
  }
}

///|
test "Song constructor rejects duplicate explicit occurrence IDs" {
  let section = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let id = occurrence_id("verse:shared")
  let result = try? Song(parts=[
    SongPart::with_id(id~, name="verse one", section~),
    SongPart::with_id(id~, name="verse two", section~),
  ])
  match result {
    Err(SongBuildError::DuplicateOccurrenceId("verse:shared")) => ()
    _ => assert_true(false)
  }
}

///|
test "Song::from_sections uses section names as occurrence names" {
  let intro = make_section("intro", @pattern.Rational::from_int(1), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(1), 64.0)
  let result = try? Song::from_sections([intro, chorus])
  let song = match result {
    Ok(song) => song
    Err(_) => abort("song creation failed")
  }
  assert_true(song.duration() == @pattern.Rational::from_int(2))
  assert_true(song.get_occurrence("intro") is Some(_))
  assert_true(song.get_occurrence("chorus") is Some(_))
}

///|
test "Song supports occurrence lookup by stable ID" {
  let verse = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let id = occurrence_id("verse:1")
  let song = make_song([SongPart::with_id(id~, name="Verse 1", section=verse)])
  match song.get_occurrence_by_id(id) {
    Some(occurrence) => {
      assert_eq(occurrence.id().value(), "verse:1")
      assert_eq(occurrence.name(), "Verse 1")
    }
    None => abort("expected occurrence by ID")
  }
}

///|
test "Song::occurrence_at uses half-open occurrence boundaries" {
  let verse = make_section("verse", @pattern.Rational::from_int(2), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(1), 64.0)
  let song = make_song([
    SongPart(name="verse1", section=verse),
    SongPart(name="chorus1", section=chorus),
  ])
  match song.occurrence_at(@pattern.Rational::from_int(0)) {
    Some(occurrence) => assert_eq(occurrence.name(), "verse1")
    None => abort("expected verse1 at song start")
  }
  match song.occurrence_at(@pattern.Rational::from_int(2)) {
    Some(occurrence) => assert_eq(occurrence.name(), "chorus1")
    None => abort("expected chorus1 at boundary")
  }
  match song.occurrence_at(@pattern.Rational::from_int(3)) {
    None => ()
    Some(_) => assert_true(false)
  }
}

///|
test "SongPart explicit starts create gaps and set duration to latest end" {
  let intro = make_section("intro", @pattern.Rational::from_int(1), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(1), 64.0)
  let song = make_song([
    SongPart(name="intro", section=intro),
    SongPart::at(
      start=@pattern.Rational::from_int(2),
      name="chorus1",
      section=chorus,
    ),
  ])
  assert_true(song.duration() == @pattern.Rational::from_int(3))
  match song.occurrence_at(rat(3L, 2L)) {
    None => ()
    Some(_) => abort("expected gap between explicit occurrences")
  }
  match song.get_occurrence("chorus1") {
    Some(occurrence) => {
      assert_true(occurrence.start() == @pattern.Rational::from_int(2))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
    }
    None => abort("expected explicitly placed occurrence")
  }
  let events = song.query(span(1L, 1L, 2L, 1L))
  assert_eq(events.length(), 0)
}

///|
test "SongPart explicit starts can overlap and range lookup returns all hits" {
  let verse = make_section("verse", @pattern.Rational::from_int(2), 60.0)
  let pad = make_section("pad", @pattern.Rational::from_int(2), 64.0)
  let song = make_song([
    SongPart(name="verse1", section=verse),
    SongPart::at(start=@pattern.Rational::from_int(1), name="pad1", section=pad),
  ])
  assert_true(song.duration() == @pattern.Rational::from_int(3))
  let at_overlap = song.occurrences_at(rat(3L, 2L))
  assert_eq(at_overlap.length(), 2)
  assert_eq(at_overlap[0].name(), "verse1")
  assert_eq(at_overlap[1].name(), "pad1")
  let range_hits = song.occurrences_intersecting(span(1L, 1L, 2L, 1L))
  assert_eq(range_hits.length(), 2)
  let events = song.query(span(1L, 1L, 2L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[1].value.get("note") == Some(64.0))
}

///|
test "indexed occurrence lookups preserve authoring order for timeline-sorted overlaps" {
  let late = make_section("late", @pattern.Rational::from_int(3), 60.0)
  let early = make_section("early", @pattern.Rational::from_int(3), 64.0)
  let song = make_song([
    SongPart::at(
      start=@pattern.Rational::from_int(1),
      name="late1",
      section=late,
    ),
    SongPart::at(
      start=@pattern.Rational::from_int(0),
      name="early1",
      section=early,
    ),
  ])
  match song.occurrence_at(rat(3L, 2L)) {
    Some(occurrence) => assert_eq(occurrence.name(), "late1")
    None => abort("expected first authored occurrence at overlap")
  }
  let at_hits = song.occurrences_at(rat(3L, 2L))
  assert_eq(at_hits.length(), 2)
  assert_eq(at_hits[0].name(), "late1")
  assert_eq(at_hits[1].name(), "early1")
  let range_hits = song.occurrences_intersecting(span(2L, 1L, 3L, 1L))
  assert_eq(range_hits.length(), 2)
  assert_eq(range_hits[0].name(), "late1")
  assert_eq(range_hits[1].name(), "early1")
}

///|
test "implicit parts continue after latest explicit occurrence end" {
  let a = make_section("a", @pattern.Rational::from_int(1), 60.0)
  let b = make_section("b", @pattern.Rational::from_int(1), 62.0)
  let c = make_section("c", @pattern.Rational::from_int(1), 64.0)
  let song = make_song([
    SongPart(name="a1", section=a),
    SongPart::at(start=rat(1L, 2L), name="b1", section=b),
    SongPart(name="c1", section=c),
  ])
  assert_true(song.duration() == rat(5L, 2L))
  match song.get_occurrence("c1") {
    Some(occurrence) => {
      assert_true(occurrence.start() == rat(3L, 2L))
      assert_true(occurrence.end_() == rat(5L, 2L))
    }
    None => abort("expected implicit occurrence after overlap")
  }
}

///|
test "Song::occurrences_intersecting uses half-open range boundaries" {
  let a = make_section("a", @pattern.Rational::from_int(1), 60.0)
  let b = make_section("b", @pattern.Rational::from_int(1), 62.0)
  let song = make_song([
    SongPart(name="a1", section=a),
    SongPart::at(start=@pattern.Rational::from_int(2), name="b1", section=b),
  ])
  let gap_hits = song.occurrences_intersecting(span(1L, 1L, 2L, 1L))
  assert_eq(gap_hits.length(), 0)
  let boundary_hits = song.occurrences_intersecting(span(1L, 1L, 3L, 1L))
  assert_eq(boundary_hits.length(), 1)
  assert_eq(boundary_hits[0].name(), "b1")
}

///|
test "Song::gap_spans reports uncovered boundary ranges" {
  let a = make_section("a", @pattern.Rational::from_int(1), 60.0)
  let b = make_section("b", @pattern.Rational::from_int(1), 62.0)
  let c = make_section("c", @pattern.Rational::from_int(1), 64.0)
  let song = make_song([
    SongPart(name="a1", section=a),
    SongPart::at(start=@pattern.Rational::from_int(3), name="b1", section=b),
    SongPart::at(start=@pattern.Rational::from_int(5), name="c1", section=c),
  ])
  let gaps = song.gap_spans()
  assert_eq(gaps.length(), 2)
  assert_true(gaps[0] == span(1L, 1L, 3L, 1L))
  assert_true(gaps[1] == span(4L, 1L, 5L, 1L))
}

///|
test "Song::fill_gaps inserts sized fill occurrences in uncovered ranges" {
  let a = make_section("a", @pattern.Rational::from_int(1), 60.0)
  let b = make_section("b", @pattern.Rational::from_int(1), 62.0)
  let fill = make_section("fill", @pattern.Rational::from_int(1), 70.0)
  let song = make_song([
    SongPart(name="a1", section=a),
    SongPart::at(start=@pattern.Rational::from_int(3), name="b1", section=b),
  ])
  let result = try? song.fill_gaps(prefix="fill", section=fill)
  let filled = match result {
    Ok(song) => song
    Err(_) => abort("expected filled song")
  }
  assert_eq(filled.occurrence_count(), 3)
  match filled.get_occurrence("fill:0") {
    Some(occurrence) => {
      assert_eq(occurrence.id().value(), "fill:0")
      assert_true(occurrence.start() == @pattern.Rational::from_int(1))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
      assert_true(
        occurrence.section().length_cycles() == @pattern.Rational::from_int(2),
      )
    }
    None => abort("expected generated fill occurrence")
  }
  assert_eq(filled.gap_spans().length(), 0)
  let events = filled.query(span(1L, 1L, 3L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(70.0))
  assert_true(events[1].value.get("note") == Some(70.0))
}

///|
test "Song::fill_gaps preserves existing IDs and ignores covered overlap" {
  let a = make_section("a", @pattern.Rational::from_int(2), 60.0)
  let b = make_section("b", @pattern.Rational::from_int(2), 62.0)
  let c = make_section("c", @pattern.Rational::from_int(1), 64.0)
  let fill = make_section("fill", @pattern.Rational::from_int(1), 70.0)
  let a_id = occurrence_id("a:1")
  let b_id = occurrence_id("b:1")
  let c_id = occurrence_id("c:1")
  let song = make_song([
    SongPart::with_id(id=a_id, name="A", section=a),
    SongPart::with_id_at(
      id=b_id,
      start=@pattern.Rational::from_int(1),
      name="B",
      section=b,
    ),
    SongPart::with_id_at(
      id=c_id,
      start=@pattern.Rational::from_int(4),
      name="C",
      section=c,
    ),
  ])
  let gaps = song.gap_spans()
  assert_eq(gaps.length(), 1)
  assert_true(gaps[0] == span(3L, 1L, 4L, 1L))
  let result = try? song.fill_gaps(prefix="fill", section=fill)
  let filled = match result {
    Ok(song) => song
    Err(_) => abort("expected filled song")
  }
  assert_eq(filled.occurrence_count(), 4)
  assert_true(filled.get_occurrence_by_id(a_id) is Some(_))
  assert_true(filled.get_occurrence_by_id(b_id) is Some(_))
  assert_true(filled.get_occurrence_by_id(c_id) is Some(_))
  match filled.get_occurrence("fill:0") {
    Some(occurrence) => {
      assert_true(occurrence.start() == @pattern.Rational::from_int(3))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(4))
    }
    None => abort("expected generated overlap fill")
  }
}

///|
test "Song::fill_gaps preserves authoring order for out-of-order overlaps" {
  let late = make_section("late", @pattern.Rational::from_int(2), 60.0)
  let early = make_section("early", @pattern.Rational::from_int(2), 64.0)
  let fill = make_section("fill", @pattern.Rational::from_int(1), 70.0)
  let song = make_song([
    SongPart::at(
      start=@pattern.Rational::from_int(1),
      name="late1",
      section=late,
    ),
    SongPart::at(
      start=@pattern.Rational::from_int(0),
      name="early1",
      section=early,
    ),
  ])
  let result = try? song.fill_gaps(prefix="fill", section=fill)
  let filled = match result {
    Ok(song) => song
    Err(_) => abort("expected filled song")
  }
  assert_eq(filled.occurrence_count(), 2)
  let overlap_hits = filled.occurrences_at(rat(3L, 2L))
  assert_eq(overlap_hits.length(), 2)
  assert_eq(overlap_hits[0].name(), "late1")
  assert_eq(overlap_hits[1].name(), "early1")
  let events = filled.query(span(1L, 1L, 2L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[1].value.get("note") == Some(64.0))
}

///|
test "Song::fill_gaps rejects generated occurrence name collisions" {
  let a = make_section("a", @pattern.Rational::from_int(1), 60.0)
  let existing_fill = make_section(
    "existing_fill",
    @pattern.Rational::from_int(1),
    62.0,
  )
  let fill = make_section("fill", @pattern.Rational::from_int(1), 70.0)
  let song = make_song([
    SongPart(name="a1", section=a),
    SongPart::at(
      start=@pattern.Rational::from_int(2),
      name="fill:0",
      section=existing_fill,
    ),
  ])
  let result = try? song.fill_gaps(prefix="fill", section=fill)
  match result {
    Err(SongBuildError::DuplicateOccurrence("fill:0")) => ()
    _ => assert_true(false)
  }
}

///|
test "Song keeps explicit occurrence IDs across reordering" {
  let verse = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(1), 64.0)
  let verse_id = occurrence_id("verse:1")
  let chorus_id = occurrence_id("chorus:1")
  let original = make_song([
    SongPart::with_id(id=verse_id, name="Verse 1", section=verse),
    SongPart::with_id(id=chorus_id, name="Chorus 1", section=chorus),
  ])
  let reordered = make_song([
    SongPart::with_id(id=chorus_id, name="Chorus 1", section=chorus),
    SongPart::with_id(id=verse_id, name="Verse 1", section=verse),
  ])
  match
    (
      original.get_occurrence_by_id(verse_id),
      reordered.get_occurrence_by_id(verse_id),
    ) {
    (Some(before), Some(after)) => {
      assert_eq(before.id().value(), after.id().value())
      assert_true(before.start() == @pattern.Rational::from_int(0))
      assert_true(after.start() == @pattern.Rational::from_int(1))
    }
    _ => abort("expected verse occurrence by ID")
  }
}

///|
test "Song keeps explicit occurrence IDs across section length changes" {
  let verse_short = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let verse_long = make_section("verse", @pattern.Rational::from_int(2), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(1), 64.0)
  let verse_id = occurrence_id("verse:1")
  let chorus_id = occurrence_id("chorus:1")
  let short_layout = make_song([
    SongPart::with_id(id=verse_id, name="Verse 1", section=verse_short),
    SongPart::with_id(id=chorus_id, name="Chorus 1", section=chorus),
  ])
  let long_layout = make_song([
    SongPart::with_id(id=verse_id, name="Verse 1", section=verse_long),
    SongPart::with_id(id=chorus_id, name="Chorus 1", section=chorus),
  ])
  match
    (
      short_layout.get_occurrence_by_id(chorus_id),
      long_layout.get_occurrence_by_id(chorus_id),
    ) {
    (Some(before), Some(after)) => {
      assert_eq(before.id().value(), after.id().value())
      assert_true(before.start() == @pattern.Rational::from_int(1))
      assert_true(after.start() == @pattern.Rational::from_int(2))
    }
    _ => abort("expected chorus occurrence by ID")
  }
}

///|
test "Song allows repeated sections with distinct occurrence names" {
  let verse = make_section("verse", @pattern.Rational::from_int(1), 60.0)
  let song = make_song([
    SongPart(name="verse1", section=verse),
    SongPart(name="verse2", section=verse),
  ])
  let events = song.query(span(0L, 1L, 2L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[0].whole.unwrap().begin == @pattern.Rational::from_int(0))
  assert_true(events[1].value.get("note") == Some(60.0))
  assert_true(events[1].whole.unwrap().begin == @pattern.Rational::from_int(1))
}

///|
test "Song::query shifts event whole and part into song time" {
  let intro = make_section("intro", @pattern.Rational::from_int(1), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(2), 64.0)
  let song = make_song([
    SongPart(name="intro", section=intro),
    SongPart(name="chorus1", section=chorus),
  ])
  let events = song.query(span(0L, 1L, 3L, 1L))
  assert_eq(events.length(), 3)
  assert_true(events[0].whole.unwrap().begin == @pattern.Rational::from_int(0))
  assert_true(events[0].part.begin == @pattern.Rational::from_int(0))
  assert_true(events[1].whole.unwrap().begin == @pattern.Rational::from_int(1))
  assert_true(events[1].part.begin == @pattern.Rational::from_int(1))
  assert_true(events[2].whole.unwrap().begin == @pattern.Rational::from_int(2))
  assert_true(events[2].part.begin == @pattern.Rational::from_int(2))
  assert_true(events[2].value.get("note") == Some(64.0))
}

///|
test "Song::query applies section TimeScope without changing occurrence span" {
  let section = make_scoped_section(
    "riff",
    @pattern.Rational::from_int(1),
    fast_scope(2),
    60.0,
  )
  let song = make_song([
    SongPart::at(start=@pattern.Rational::from_int(1), name="riff1", section~),
  ])
  match song.get_occurrence("riff1") {
    Some(occurrence) => {
      assert_true(occurrence.start() == @pattern.Rational::from_int(1))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(2))
    }
    None => abort("expected scoped occurrence")
  }
  let events = song.query(span(1L, 1L, 2L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].whole.unwrap().begin == @pattern.Rational::from_int(1))
  assert_true(events[0].part.begin == @pattern.Rational::from_int(1))
  assert_true(events[1].whole.unwrap().begin == rat(3L, 2L))
  assert_true(events[1].part.begin == rat(3L, 2L))
}

///|
test "Song::query clips parts at occurrence boundaries without clipping whole" {
  let intro = make_section("intro", @pattern.Rational::from_int(1), 60.0)
  let chorus = make_section("chorus", @pattern.Rational::from_int(1), 64.0)
  let song = make_song([
    SongPart(name="intro", section=intro),
    SongPart(name="chorus1", section=chorus),
  ])
  let events = song.query(span(1L, 2L, 3L, 2L))
  assert_eq(events.length(), 2)
  assert_true(events[0].whole.unwrap().begin == @pattern.Rational::from_int(0))
  assert_true(events[0].whole.unwrap().end_ == @pattern.Rational::from_int(1))
  assert_true(events[0].part.begin == rat(1L, 2L))
  assert_true(events[0].part.end_ == @pattern.Rational::from_int(1))
  assert_true(events[1].whole.unwrap().begin == @pattern.Rational::from_int(1))
  assert_true(events[1].whole.unwrap().end_ == @pattern.Rational::from_int(2))
  assert_true(events[1].part.begin == @pattern.Rational::from_int(1))
  assert_true(events[1].part.end_ == rat(3L, 2L))
}
