// Pure musical-time contracts; these tests do not initialize an audio engine.

///|
fn cycle_span(begin : Int, end : Int) -> @pattern.TimeSpan {
  @pattern.TimeSpan(
    @pattern.Rational::from_int(begin),
    @pattern.Rational::from_int(end),
  )
}

///|
test "prepared song respects section boundaries differing periods and finite end" {
  let song = @mini.parse_song(
    "song(section(\"a\",3,stack(note(\"60\").slow(3),note(\"72 74\").slow(4))),section(\"b\",2,note(\"67\").slow(2)),part(\"a1\",\"a\"),part(\"b1\",\"b\"))",
  ).unwrap()
  let snapshot = song_update_snapshot(song)
  let span = cycle_span(0, 5)
  let events = snapshot.query(span)
  assert_eq(events.map(e => e.value.get("note")), [
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
  assert_eq(snapshot.query(cycle_span(5, 6)).length(), 0)
}

///|
test "snapshot thinning is deterministic across query partitions" {
  let song = @mini.parse_song(
    "song(section(\"a\",4,note(\"60*8\").degradeBy(0.5)),part(\"a1\",\"a\"))",
  ).unwrap()
  let snapshot = song_update_snapshot(song)
  let whole = snapshot.query(cycle_span(0, 4))
  let mut count = 0
  for cycle in 0..<4 {
    let events = snapshot.query(cycle_span(cycle, cycle + 1))
    for event in events {
      assert_eq(event.part, whole[count].part)
      assert_eq(event.value.get("note"), whole[count].value.get("note"))
      count = count + 1
    }
  }
  assert_eq(count, whole.length())
  assert_true(count > 0 && count < 32)
}
