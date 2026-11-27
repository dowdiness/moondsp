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
) -> @song.SongSnapshot[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]] raise {
  guard @mini.PlaybackInput::text(source).compile().material()
    is UntrackedSong(snapshot, _) else {
    fail("expected an untracked song")
  }
  snapshot
}

///|
test "compiled song respects section boundaries differing periods and finite end" {
  let snapshot = compiled_song(
    "song(section(\"a\",3,stack(note(\"60\").slow(3),note(\"72 74\").slow(4))),section(\"b\",2,note(\"67\").slow(2)),part(\"a1\",\"a\"),part(\"b1\",\"b\"))",
  )
  let span = cycle_span(0, 5)
  let events = snapshot.song().query(span)
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
  assert_eq(snapshot.song().query(cycle_span(5, 6)).length(), 0)
}

///|
test "snapshot thinning is deterministic across query partitions" {
  let snapshot = compiled_song(
    "song(section(\"a\",4,note(\"60*8\").degradeBy(0.5)),part(\"a1\",\"a\"))",
  )
  let whole = snapshot.song().query(cycle_span(0, 4))
  let mut count = 0
  for cycle in 0..<4 {
    let events = snapshot.song().query(cycle_span(cycle, cycle + 1))
    for event in events {
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
  let snapshot = compiled_song(
    "song(section(\"a\",1,note(\"60\")),section(\"rest\",1,note(\"62\")),part(\"my part\",\"a\"),part(\"my.part\",\"a\",2),fill(\"gap fill\",\"rest\"))",
  )
  let names = snapshot.song().occurrences().map(o => o.name())
  assert_eq(names, ["my part", "my.part", "gap fill:0"])
  let ids = snapshot.song().occurrences().map(o => o.id().value())
  // Distinct names keep distinct identities.
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
