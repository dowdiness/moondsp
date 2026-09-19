///|
test "delay line delays impulse by delay_samples" {
  let delay = DelayLine::new(8, delay_samples=3)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
  assert_true(delay.tick(0.0) == 0.0)
}

///|
test "delay with zero delay_samples is passthrough" {
  let delay = DelayLine::new(8, delay_samples=0)
  assert_true(delay.tick(0.5) == 0.5)
  assert_true(delay.tick(0.7) == 0.7)
}

///|
test "delay with max delay_samples uses full buffer" {
  let delay = DelayLine::new(4, delay_samples=4)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
}

///|
test "delay feedback accumulates energy" {
  let delay = DelayLine::new(2, delay_samples=1, feedback=0.5)
  let first = delay.tick(1.0)
  assert_true(first == 0.0)
  let second = delay.tick(0.0)
  assert_true(second == 1.0)
  let third = delay.tick(0.0)
  assert_true((third - 0.5).abs() < 0.000001)
}

///|
test "delay set_delay_samples changes delay mid-stream" {
  let delay = DelayLine::new(8, delay_samples=2)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  assert_true(delay.tick(0.0) == 1.0)
  delay.set_delay_samples(1)
  ignore(delay.tick(0.5))
  assert_true(delay.tick(0.0) == 0.5)
}

///|
test "delay reset returns silence for unwritten samples" {
  let delay = DelayLine::new(4, delay_samples=1, feedback=0.5)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
}

///|
test "delay reset keeps configured delay and feedback" {
  let delay = DelayLine::new(8, delay_samples=3, feedback=0.25)
  ignore(delay.tick(1.0))
  delay.reset()
  assert_eq(delay.delay_samples(), 3)
  assert_eq(delay.feedback(), 0.25)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
}

///|
test "delay reset silences stale wrap-around content" {
  let delay = DelayLine::new(4, delay_samples=2, feedback=0.0)
  // Fill and wrap so every physical slot holds a non-zero value.
  ignore(delay.tick(1.0))
  ignore(delay.tick(2.0))
  ignore(delay.tick(3.0))
  ignore(delay.tick(4.0))
  ignore(delay.tick(5.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
}

///|
test "delay reset then length change still reads silence until written" {
  let delay = DelayLine::new(8, delay_samples=1, feedback=0.9)
  ignore(delay.tick(1.0))
  ignore(delay.tick(1.0))
  delay.reset()
  delay.set_delay_samples(4)
  assert_true(delay.tick(0.5) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.5)
}

///|
test "delay reset blocks feedback from stale samples" {
  let delay = DelayLine::new(4, delay_samples=1, feedback=0.9)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0)
  // Without valid-range guarding, feedback would recirculate the old impulse.
  assert_true(delay.tick(0.0) == 0.0)
}
