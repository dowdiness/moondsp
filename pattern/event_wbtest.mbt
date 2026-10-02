///|
test "Event::shift by zero preserves a missing whole span" {
  let event : Event[Int] = {
    whole: None,
    part: TimeSpan::new(Rational::new(1L, 3L), Rational::new(2L, 3L)),
    value: 7,
  }
  let shifted = event.shift(Rational::from_int(0))
  assert_true(shifted.whole is None)
  assert_true(shifted.part == event.part)
  assert_eq(shifted.value, event.value)
}
