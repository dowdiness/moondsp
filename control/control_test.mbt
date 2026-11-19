///|
test "all lists every control once, in declaration order" {
  let all = @control.Control::all()
  for i, control in all {
    assert_eq(Hash::hash(control), i)
  }
  // A variant left out of the list leaves a hash past its end.
  assert_eq(all.length(), Hash::hash(@control.Control::Release) + 1)
}
