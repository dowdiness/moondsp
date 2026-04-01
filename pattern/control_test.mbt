///|
test "note_name c3 = 48" {
  let pat = note_name("c3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(48.0))
}

///|
test "note_name e3 = 52" {
  let pat = note_name("e3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(52.0))
}

///|
test "note_name g3 = 55" {
  let pat = note_name("g3")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(55.0))
}

///|
test "note_name fs4 = 66" {
  let pat = note_name("fs4")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(66.0))
}

///|
test "note_name a4 = 69" {
  let pat = note_name("a4")
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(69.0))
}

///|
test "merge_control combines note and cutoff" {
  let merged = merge_control(note(60.0), s_cutoff(800.0))
  let events = merged.query(span(0, 1, 1, 1))
  assert_eq(events.length(), 1)
  assert_eq(events[0].value.0.get("note"), Some(60.0))
  assert_eq(events[0].value.0.get("cutoff"), Some(800.0))
}

///|
test "merge_control right-biased on conflict" {
  let a = note(60.0)
  let b = note(72.0)
  let merged = merge_control(a, b)
  let events = merged.query(span(0, 1, 1, 1))
  assert_eq(events[0].value.0.get("note"), Some(72.0))
}

///|
test "deliverable: sequence c3 e3 g3 fast 2 produces 6 events" {
  let pat = sequence([note_name("c3"), note_name("e3"), note_name("g3")]).fast(
    Rational::from_int(2),
  )
  let events = pat.query(span(0, 1, 1, 1))
  assert_eq(events.length(), 6)
  // First half: c3 e3 g3 in [0, 1/2)
  assert_eq(events[0].value.0.get("note"), Some(48.0))
  assert_eq(events[1].value.0.get("note"), Some(52.0))
  assert_eq(events[2].value.0.get("note"), Some(55.0))
  // Second half: c3 e3 g3 in [1/2, 1)
  assert_eq(events[3].value.0.get("note"), Some(48.0))
  assert_eq(events[4].value.0.get("note"), Some(52.0))
  assert_eq(events[5].value.0.get("note"), Some(55.0))
  // Verify rational time boundaries
  assert_eq(events[0].part.begin, Rational::new(0L, 1L))
  assert_eq(events[0].part.end_, Rational::new(1L, 6L))
  assert_eq(events[5].part.begin, Rational::new(5L, 6L))
  assert_eq(events[5].part.end_, Rational::new(1L, 1L))
}
