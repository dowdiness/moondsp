///|
fn unwrap_parsed_song(
  result : Result[
    @mini.ParsedSong[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]],
    String,
  ],
) -> @song.Song[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]] {
  match result {
    Ok(parsed) => parsed.song()
    Err(msg) => abort("expected parsed song, got Err(\{msg})")
  }
}

///|
fn song_rat(n : Int64, d : Int64) -> @pattern.Rational {
  @pattern.Rational(n, d)
}

///|
fn song_span(
  begin_num : Int64,
  begin_den : Int64,
  end_num : Int64,
  end_den : Int64,
) -> @pattern.TimeSpan {
  @pattern.TimeSpan(song_rat(begin_num, begin_den), song_rat(end_num, end_den))
}

///|
fn song_occurrence_id(value : String) -> @identity.OccurrenceId {
  @identity.OccurrenceId::from_string(value) catch {
    _ => abort("expected valid occurrence id")
  }
}

///|
/// What `song` plays over `arc` on the song clock, as playback places it:
/// each entry's pattern, clipped to its occurrence.
fn[C : @song.SongContent] song_events(
  song : @song.Song[C],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  let result = []
  for entry in song.entries() {
    let occurrence = @pattern.TimeSpan(entry.start(), entry.end_())
    guard occurrence.intersect(arc) is Some(clipped) else { continue }
    let within = @pattern.TimeSpan(
      clipped.begin - entry.start(),
      clipped.end_ - entry.start(),
    )
    for event in entry.body().query(within) {
      result.push(event.shift(entry.start()))
    }
  }
  result
}

///|
/// The occurrence of `song` with id `id`.
fn[C] song_occurrence(
  song : @song.Song[C],
  id : String,
) -> @song.SectionOccurrence[C] {
  for occurrence in song.occurrences() {
    if occurrence.id().value() == id {
      return occurrence
    }
  }
  abort("expected occurrence '\{id}'")
}

///|
/// The ids of the occurrences playing at `time`, in written order.
fn[C] song_ids_at(
  song : @song.Song[C],
  time : @pattern.Rational,
) -> Array[String] {
  song
  .occurrences()
  .iter()
  .filter(occurrence => occurrence.span().contains(time))
  .map(occurrence => occurrence.id().value())
  .collect()
}

///|
test "parse_song builds sections and implicit parts" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"intro\",1,s(\"bd\")),section(\"verse\",2,note(\"60\")),part(\"intro1\",\"intro\"),part(\"verse1\",\"verse\"))",
    ),
  )
  @debug.assert_eq(song.occurrences().length(), 2)
  assert_true(song.duration() == @pattern.Rational::from_int(3))
  let occurrence = song_occurrence(song, "verse1")
  assert_true(occurrence.start() == @pattern.Rational::from_int(1))
  assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
  @debug.assert_eq(occurrence.section().id().value(), "section:verse")
  let events = song_events(song, song_span(0L, 1L, 3L, 1L))
  @debug.assert_eq(events.length(), 3)
  assert_true(drum_of(events[0].value) == Some("bd"))
  assert_true(pitch_of(events[1].value) == Some(60.0))
}

///|
test "parse_song captures optional tempo metadata" {
  let parsed = match
    @mini.parse_song(
      "song(bpm(72),section(\"intro\",1,s(\"bd\")),part(\"intro1\",\"intro\"))",
    ) {
    Ok(value) => value
    Err(msg) => abort("expected parsed song with bpm, got Err(\{msg})")
  }
  assert_true(parsed.bpm() == Some(72.0))
  @debug.assert_eq(parsed.song().occurrences().length(), 1)
}

///|
test "parse_song accepts multiline whitespace and notation newlines" {
  let input =
    #|song(
    #|  section(
    #|    "ode",
    #|    4,
    #|    stack(
    #|      s("bd")
    #|        .slow(4),
    #|      note("64
    #|64 65
    #|67")
    #|        .slow(4)
    #|    )
    #|  ),
    #|  part("ode1", "ode")
    #|)
    #|
  let song = unwrap_parsed_song(@mini.parse_song(input))
  let events = song_events(song, song_span(0L, 1L, 4L, 1L))
  @debug.assert_eq(events.length(), 5)
  assert_true(drum_of(events[0].value) == Some("bd"))
  assert_true(pitch_of(events[1].value) == Some(64.0))
  assert_true(pitch_of(events[3].value) == Some(65.0))
  assert_true(pitch_of(events[4].value) == Some(67.0))
}

///|
test "parse_song supports explicit rational starts and gaps" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"a\",1,s(\"bd\")),section(\"b\",1,s(\"sd\")),part(\"a1\",\"a\"),part(\"b1\",\"b\",3/2))",
    ),
  )
  assert_true(song.duration() == song_rat(5L, 2L))
  @debug.assert_eq(song_ids_at(song, song_rat(5L, 4L)), [])
  let gaps = song.gap_spans()
  @debug.assert_eq(gaps.length(), 1)
  assert_true(gaps[0] == song_span(1L, 1L, 3L, 2L))
}

///|
test "parse_song preserves authoring order for explicit overlaps" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"late\",2,s(\"bd\")),section(\"early\",2,s(\"sd\")),part(\"late1\",\"late\",1),part(\"early1\",\"early\",0))",
    ),
  )
  @debug.assert_eq(song_ids_at(song, song_rat(3L, 2L)), ["late1", "early1"])
  let events = song_events(song, song_span(1L, 1L, 2L, 1L))
  @debug.assert_eq(events.length(), 2)
  assert_true(drum_of(events[0].value) == Some("bd"))
  assert_true(drum_of(events[1].value) == Some("sd"))
}

///|
test "parse_song applies boundary fill directives" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"a\",1,s(\"bd\")),section(\"b\",1,s(\"sd\")),section(\"fill\",1,s(\"hh\")),part(\"a1\",\"a\"),part(\"b1\",\"b\",3),fill(\"fill\",\"fill\"))",
    ),
  )
  @debug.assert_eq(song.occurrences().length(), 3)
  let occurrence = song_occurrence(song, "fill:0")
  assert_true(occurrence.start() == @pattern.Rational::from_int(1))
  assert_true(occurrence.end_() == @pattern.Rational::from_int(3))
  assert_true(
    occurrence.section().length_cycles() == @pattern.Rational::from_int(2),
  )
  @debug.assert_eq(song.gap_spans().length(), 0)
  let events = song_events(song, song_span(1L, 1L, 3L, 1L))
  @debug.assert_eq(events.length(), 2)
  assert_true(drum_of(events[0].value) == Some("hh"))
  assert_true(drum_of(events[1].value) == Some("hh"))
}

///|
test "parse_song supports explicit occurrence IDs" {
  let song = unwrap_parsed_song(
    @mini.parse_song(
      "song(section(\"verse\",1,s(\"bd\")),part_id(\"verse:1\",\"Verse 1\",\"verse\"))",
    ),
  )
  assert_true(
    song_occurrence(song, "verse:1").id() == song_occurrence_id("verse:1"),
  )
}

///|
test "parse_song reports unknown section references" {
  let result = @mini.parse_song("song(part(\"a1\",\"missing\"))")
  match result {
    Err("position 15: unknown song section 'missing'") => ()
    _ => assert_true(false)
  }
}
