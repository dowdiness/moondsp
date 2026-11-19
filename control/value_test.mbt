///|
test "absent values are equal and NaN is absent" {
  let absent = @control.ControlValue::absent()
  assert_true(absent == @control.ControlValue::absent())
  assert_true(@control.ControlValue::of(@double.not_a_number) == absent)
  assert_true(@control.ControlValue::of(0.0) != absent)
  assert_true(absent != @control.ControlValue::of(0.0))
  assert_true(@control.ControlValue::of(0.5) == @control.ControlValue::of(0.5))
  assert_true(@control.ControlValue::of(0.5) != @control.ControlValue::of(0.25))
}
