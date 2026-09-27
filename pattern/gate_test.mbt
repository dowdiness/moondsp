///|
test "gate shortens notes without moving onsets or pattern period" {
  let pat = @pattern.sequence([@pattern.Pat::pure(1), @pattern.Pat::pure(2)]).gate(
    @pattern.Rational::new(2L, 5L),
  )
  let events = pat.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  assert_eq(events.length(), 2)
  assert_eq(events[0].whole.unwrap().begin, @pattern.Rational::new(0L, 1L))
  assert_eq(events[0].whole.unwrap().end_, @pattern.Rational::new(1L, 5L))
  assert_eq(events[1].whole.unwrap().begin, @pattern.Rational::new(1L, 2L))
  assert_eq(events[1].whole.unwrap().end_, @pattern.Rational::new(7L, 10L))
  assert_eq(pat.entry_period(), @pattern.Rational::from_int(1))
}

///|
test "gate removes the silent tail from later queries" {
  let pat = @pattern.Pat::pure(1).gate(@pattern.Rational::new(2L, 5L))
  let tail = pat.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::new(1L, 2L),
      @pattern.Rational::from_int(1),
    ),
  )
  assert_eq(tail.length(), 0)
}

///|
test "gate keeps high-precision events valid in later cycles" {
  let pat = @pattern.Pat::pure(1).gate(
    @pattern.Rational::new(123456789012345679L, 1000000000000000000L),
  )
  let events = pat.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(10),
      @pattern.Rational::from_int(11),
    ),
  )
  assert_eq(events.length(), 1)
  let whole = events[0].whole.unwrap()
  assert_eq(whole.end_, @pattern.Rational::new(10123456789L, 1000000000L))
}

///|
test "gate clamps fractions to the closed unit interval" {
  let source = @pattern.Pat::pure(1)
  assert_eq(
    source
    .gate(@pattern.Rational::new(-1L, 2L))
    .query(
      @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(1),
      ),
    )
    .length(),
    0,
  )
  let full = source
    .gate(@pattern.Rational::from_int(2))
    .query(
      @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(1),
      ),
    )
  assert_eq(full[0].whole.unwrap().end_, @pattern.Rational::from_int(1))
}
