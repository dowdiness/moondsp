///|
test "reset rewinds phase to zero" {
  let osc = Oscillator::new()

  ignore(osc.tick(440.0, 48000.0))
  ignore(osc.tick(440.0, 48000.0))
  assert_true(osc.phase() > 0.0)

  osc.reset()

  assert_eq(osc.phase(), 0.0)
  assert_eq(osc.tick(440.0, 48000.0), 0.0)
}

///|
test "process with invalid sample rate writes silence" {
  let osc = Oscillator::new()
  let buffer = FixedArray::make(8, 1.0)

  osc.process(buffer, 440.0, 0.0)

  assert_true(buffer.every(sample => sample == 0.0))
  assert_eq(osc.phase(), 0.0)
}
