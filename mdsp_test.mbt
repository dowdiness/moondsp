///|
test "tick returns silence for non-positive sample rate" {
  let osc = Oscillator::new()
  let first = osc.tick(440.0, 0.0)
  let second = osc.tick(440.0, -1.0)
  assert_eq(first, 0.0)
  assert_eq(second, 0.0)
  assert_eq(osc.phase(), 0.0)
}

///|
test "tick advances phase continuously" {
  let osc = Oscillator::new()
  let first = osc.tick(440.0, 48000.0)
  let second = osc.tick(440.0, 48000.0)

  assert_eq(first, 0.0)
  assert_true(second > first)
  assert_eq(osc.phase(), 880.0 / 48000.0)
}

///|
test "process fills a block with bounded samples" {
  let osc = Oscillator::new()
  let buffer = FixedArray::make(128, 0.0)

  osc.process(buffer, 440.0, 48000.0)

  assert_eq(buffer.length(), 128)
  assert_eq(buffer[0], 0.0)
  assert_true(buffer.any(sample => sample != 0.0))
  assert_true(buffer.every(sample => sample >= -1.0 && sample <= 1.0))
}
