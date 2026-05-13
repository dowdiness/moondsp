///|
fn unwrap_parsed_song(
  result : Result[@song.Song[@pattern.ControlMap], String],
) -> @song.Song[@pattern.ControlMap] {
  match result {
    Ok(song) => song
    Err(msg) => abort("expected parsed song, got Err(\{msg})")
  }
}

///|
fn song_rat(n : Int64, d : Int64) -> @pattern.Rational {
  @pattern.Rational::new(n, d)
}

///|
fn song_span(
  begin_num : Int64,
  begin_den : Int64,
  end_num : Int64,
  end_den : Int64,
) -> @pattern.TimeSpan {
  @pattern.TimeSpan::new(
    song_rat(begin_num, begin_den),
    song_rat(end_num, end_den),
  )
}

///|
fn song_occurrence_id(value : String) -> @identity.OccurrenceId {
  let result = try? @identity.OccurrenceId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid occurrence id")
  }
}

///|
test "parse_song builds sections and implicit parts" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"intro\",1,s(\"bd\")),section(\"verse\",2,note(\"60\")),part(\"intro1\",\"intro\"),part(\"verse1\",\"verse\"))",
    ),
  )
  assert_eq(song.occurrence_count(), 2)
  assert_true(song.duration() == @pattern.Rational::from_int(3))
  match song.get_occurrence("verse1") {
    Some(occurrence) => {
      assert_true(occurrence.start() == @pattern.Rational::from_int(1))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
      assert_eq(occurrence.section().name(), "verse")
    }
    None => abort("expected verse occurrence")
  }
  let events = song.query(song_span(0L, 1L, 3L, 1L))
  assert_eq(events.length(), 3)
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[1].value.get("note") == Some(60.0))
}

///|
test "parse_song supports explicit rational starts and gaps" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"a\",1,s(\"bd\")),section(\"b\",1,s(\"sd\")),part(\"a1\",\"a\"),part(\"b1\",\"b\",3/2))",
    ),
  )
  assert_true(song.duration() == song_rat(5L, 2L))
  match song.occurrence_at(song_rat(5L, 4L)) {
    None => ()
    Some(_) => abort("expected explicit gap")
  }
  let gaps = song.gap_spans()
  assert_eq(gaps.length(), 1)
  assert_true(gaps[0] == song_span(1L, 1L, 3L, 2L))
}

///|
test "parse_song preserves authoring order for explicit overlaps" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"late\",2,s(\"bd\")),section(\"early\",2,s(\"sd\")),part(\"late1\",\"late\",1),part(\"early1\",\"early\",0))",
    ),
  )
  let hits = song.occurrences_at(song_rat(3L, 2L))
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].name(), "late1")
  assert_eq(hits[1].name(), "early1")
  let events = song.query(song_span(1L, 1L, 2L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[1].value.get("sound") == Some(38.0))
}

///|
test "parse_song applies boundary fill directives" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"a\",1,s(\"bd\")),section(\"b\",1,s(\"sd\")),section(\"fill\",1,s(\"hh\")),part(\"a1\",\"a\"),part(\"b1\",\"b\",3),fill(\"fill\",\"fill\"))",
    ),
  )
  assert_eq(song.occurrence_count(), 3)
  match song.get_occurrence("fill:0") {
    Some(occurrence) => {
      assert_true(occurrence.start() == @pattern.Rational::from_int(1))
      assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
      assert_true(
        occurrence.section().length_cycles() == @pattern.Rational::from_int(2),
      )
    }
    None => abort("expected generated fill occurrence")
  }
  assert_eq(song.gap_spans().length(), 0)
  let events = song.query(song_span(1L, 1L, 3L, 1L))
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("sound") == Some(42.0))
  assert_true(events[1].value.get("sound") == Some(42.0))
}

///|
test "parse_song supports explicit occurrence IDs and display names" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"verse\",1,s(\"bd\")),part_id(\"verse:1\",\"Verse 1\",\"verse\"))",
    ),
  )
  let id = song_occurrence_id("verse:1")
  match song.get_occurrence_by_id(id) {
    Some(occurrence) => {
      assert_eq(occurrence.name(), "Verse 1")
      assert_eq(occurrence.id().value(), "verse:1")
    }
    None => abort("expected occurrence by explicit ID")
  }
}

///|
test "parse_song reports unknown section references" {
  let result = @mini.parse_song("song(part(\"a1\",\"missing\"))")
  match result {
    Err("unknown song section 'missing'") => ()
    _ => assert_true(false)
  }
}
