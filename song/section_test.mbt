///|
test "Section::from_pattern wraps a pattern with identity scope" {
  let pat = @pattern.note(60.0)
  let section = Section::from_pattern(name="main", body=pat)
  assert_eq(section.name(), "main")
  assert_true(section.length_cycles() == @pattern.Rational::from_int(1))
  assert_true(section.scope().is_identity())
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
}

///|
test "Section::new rejects non-positive lengths" {
  let pat = @pattern.note(60.0)
  let zero = Section::new(
    name="bad",
    length_cycles=@pattern.Rational::from_int(0),
    scope=TimeScope::identity(),
    body=pat,
  )
  assert_true(zero is None)
}
