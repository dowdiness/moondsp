///|
test "all lists every control once, in declaration order" {
  let all = @control.Control::all()
  for i, control in all {
    assert_eq(Hash::hash(control), i)
  }
  // A variant left out of the list leaves a hash past its end.
  assert_eq(all.length(), Hash::hash(@control.Control::Release) + 1)
}

///|
test "admits states each control's domain at its boundaries" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  assert_true(@control.Control::Hold.admits(0.0))
  assert_true(@control.Control::Hold.admits(@control.MAX_SECONDS))
  assert_false(@control.Control::Hold.admits(@control.MAX_SECONDS + 0.001))
  assert_false(@control.Control::Attack.admits(-0.001))
  assert_false(@control.Control::Release.admits(inf))
  assert_false(@control.Control::Hold.admits(nan))
  assert_true(@control.Control::Room.admits(1.0))
  assert_false(@control.Control::Room.admits(1.001))
  assert_false(@control.Control::LpfResonance.admits(0.0))
  assert_true(@control.Control::HpfResonance.admits(0.001))
  assert_false(@control.Control::LpfResonance.admits(inf))
  assert_true(@control.Control::Gain.admits(-3.0))
  assert_false(@control.Control::Note.admits(nan))
}
