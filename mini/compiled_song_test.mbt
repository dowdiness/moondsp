// A compiled song keeps section boundaries and deterministic thinning.

///|
fn cycle_span(begin : Int32, end : Int32) -> @pattern.TimeSpan {
  @pattern.TimeSpan(
    @pattern.Rational::from_int(begin),
    @pattern.Rational::from_int(end),
  )
}

///|
fn compiled_song(
  source : String,
) -> @song.Song[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]] raise {
  guard @mini.PlaybackInput::text(source).compile().material()
    is UntrackedSong(song, _) else {
    fail("expected an untracked song")
  }
  song
}

///|
test "compiled song respects section boundaries differing periods and finite end" {
  let song = compiled_song(
    "song(section(\"a\",3,stack(note(\"60\").slow(3),note(\"72 74\").slow(4))),section(\"b\",2,note(\"67\").slow(2)),part(\"a1\",\"a\"),part(\"b1\",\"b\"))",
  )
  let events = song_events(song, cycle_span(0, 5))
  assert_eq(events.map(e => pitch_of(e.value)), [
    Some(60.0),
    Some(72.0),
    Some(74.0),
    Some(67.0),
  ])
  assert_eq(events.map(e => e.part.begin), [
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(2),
    @pattern.Rational::from_int(3),
  ])
  assert_eq(events[2].part.end_, @pattern.Rational::from_int(3))
  assert_eq(events[3].part.end_, @pattern.Rational::from_int(5))
  assert_eq(song_events(song, cycle_span(5, 6)).length(), 0)
  assert_eq(song.duration(), @pattern.Rational::from_int(5))
}

///|
test "song thinning is deterministic across query partitions" {
  let song = compiled_song(
    "song(section(\"a\",4,note(\"60*8\").degradeBy(0.5)),part(\"a1\",\"a\"))",
  )
  let whole = song_events(song, cycle_span(0, 4))
  let mut count = 0
  for cycle in 0..<4 {
    for event in song_events(song, cycle_span(cycle, cycle + 1)) {
      assert_eq(event.part, whole[count].part)
      assert_eq(event.value, whole[count].value)
      count = count + 1
    }
  }
  assert_eq(count, whole.length())
  assert_true(count > 0 && count < 32)
}

///|
test "parts of one section share its identity in the compiled song" {
  let snapshot = compiled_song(
    "song(section(\"a\",1,note(\"60\")),part(\"a1\",\"a\"),part(\"a2\",\"a\"))",
  )
  let entries = snapshot.entries()
  assert_eq(entries.length(), 2)
  assert_true(entries[0].origin().section() == entries[1].origin().section())
  assert_true(
    entries[0].origin().occurrence() != entries[1].origin().occurrence(),
  )
}

///|
test "a section name outside the identity alphabet compiles and stays distinct" {
  let snapshot = compiled_song(
    "song(section(\"my verse\",1,note(\"60\")),section(\"my.verse\",1,note(\"62\")),part(\"a1\",\"my verse\"),part(\"a2\",\"my.verse\"))",
  )
  let entries = snapshot.entries()
  assert_eq(entries.length(), 2)
  assert_true(entries[0].origin().section() != entries[1].origin().section())
}

///|
test "part names and fill prefixes outside the identity alphabet compile" {
  let song = compiled_song(
    "song(section(\"a\",1,note(\"60\")),section(\"rest\",1,note(\"62\")),part(\"my part\",\"a\"),part(\"my.part\",\"a\",2),fill(\"gap fill\",\"rest\"))",
  )
  let ids = song.occurrences().map(o => o.id().value())
  assert_eq(ids, ["my.20.part", "my.2e.part", "gap.20.fill:0"])
  assert_true(ids[0] != ids[1])
}

///|
test "a part name repeated by another part is reported where it repeats" {
  let source = "song(section(\"a\",1,note(\"60\")),part(\"my part\",\"a\"),part(\"my part\",\"a\",1))"
  let problem = try @mini.PlaybackInput::text(source).compile() catch {
    problem => Some(problem)
  } noraise {
    _ => None
  }
  guard problem is Some(Mistake(at, "duplicate song part 'my part'")) else {
    fail("expected a duplicate part mistake")
  }
  assert_true(source[at:].to_owned().has_prefix("part(\"my part\",\"a\",1)"))
}

///|
test "a part with an empty name is a mistake at that part" {
  let (message, at) = song_mistake_of(
    "song(section(\"a\",1,note(\"60\")),part(\"\",\"a\"))",
  )
  assert_eq(message, "song part requires a name")
  assert_true(at.has_prefix("part(\"\""))
}

///|
/// The mistake compiling `source` reports, and the source from its position.
fn song_mistake_of(source : String) -> (String, String) raise {
  let problem = try @mini.PlaybackInput::text(source).compile() catch {
    problem => Some(problem)
  } noraise {
    _ => None
  }
  guard problem is Some(Mistake(at, message)) else {
    fail("expected a mistake")
  }
  (message, source[at:].to_owned())
}

///|
test "a written part id and an encoded part name do not collide" {
  let snapshot = compiled_song(
    "song(section(\"s\",1,note(\"60\")),part(\"a.b\",\"s\"),part_id(\"a.2e.b\",\"X\",\"s\",1))",
  )
  assert_eq(snapshot.occurrences().length(), 2)
}

///|
test "repeated part identities name what the author repeated, where" {
  let (message, at) = song_mistake_of(
    "song(section(\"s\",1,note(\"60\")),part_id(\"a\",\"X\",\"s\"),part(\"a\",\"s\",1))",
  )
  assert_eq(message, "duplicate song part id 'a'")
  assert_true(at.has_prefix("part(\"a\""))
  let (message, at) = song_mistake_of(
    "song(section(\"s\",1,note(\"60\")),part(\"my fill:0\",\"s\",2),fill(\"my fill\",\"s\"))",
  )
  assert_eq(message, "duplicate song part 'my fill:0'")
  assert_true(at.has_prefix("fill("))
  let (message, _) = song_mistake_of(
    "song(section(\"s\",1,note(\"60\")),part_id(\"\",\"X\",\"s\"))",
  )
  assert_eq(message, "song part id cannot be empty")
}

///|
test "a part start before zero is a mistake where it is written" {
  for start in ["-4", "-1/2", "4/-1"] {
    let (message, at) = song_mistake_of(
      "song(section(\"a\",4,note(\"60\")),part(\"p\",\"a\",\{start}))",
    )
    assert_eq(message, "part start cannot be negative")
    assert_true(at.has_prefix(start), msg=start)
  }
  // Zero is the song's beginning.
  ignore(
    compiled_song("song(section(\"a\",4,note(\"60\")),part(\"p\",\"a\",0))"),
  )
}
