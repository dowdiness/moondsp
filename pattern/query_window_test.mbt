///|
test "a query window is always a positive span" {
  assert_true(
    @pattern.QueryWindow::from_span(@pattern.Rational(1L, 8L)) is Some(_),
  )
  assert_true(
    @pattern.QueryWindow::from_span(@pattern.Rational::from_int(0)) is None,
  )
  assert_true(
    @pattern.QueryWindow::from_span(@pattern.Rational(-1L, 8L)) is None,
  )
}
