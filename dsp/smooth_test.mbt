///|
test "param smoother approaches the target monotonically" {
  let smoother = ParamSmoother::new(0.0, 10.0, 48000.0)
  smoother.set_target(1.0)

  let mut previous = smoother.tick()
  assert_true(previous > 0.0)
  assert_true(previous < 1.0)

  for index = 0; index < 255; index = index + 1 {
    let next = smoother.tick()
    assert_true(next >= previous)
    assert_true(next <= 1.0)
    previous = next
  }

  for index = 0; index < 8192; index = index + 1 {
    previous = smoother.tick()
  }

  assert_true(1.0 - previous < 0.000001)
}

///|
test "shorter smoothing times move faster than longer ones" {
  let fast = ParamSmoother::new(0.0, 1.0, 48000.0)
  let slow = ParamSmoother::new(0.0, 20.0, 48000.0)

  fast.set_target(1.0)
  slow.set_target(1.0)

  for index = 0; index < 64; index = index + 1 {
    ignore(fast.tick())
    ignore(slow.tick())
  }

  assert_true(fast.current() > slow.current())
  assert_true(slow.current() > 0.0)
}

///|
test "context-based setup matches explicit sample rate setup" {
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  let from_rate = ParamSmoother::new(0.0, 5.0, 48000.0)
  let from_context = ParamSmoother::from_context(0.0, 5.0, context)

  from_rate.set_target(1.0)
  from_context.set_target(1.0)

  for index = 0; index < 128; index = index + 1 {
    ignore(from_rate.tick())
    ignore(from_context.tick())
  }

  assert_true(
    (from_rate.current() - from_context.current()).abs() < 0.000000001,
  )
}

///|
test "invalid smoothing parameters snap immediately" {
  let smoother = ParamSmoother::new(0.0, 0.0, 48000.0)
  smoother.set_target(1.0)
  assert_eq(smoother.tick(), 1.0)

  smoother.reset(0.0)
  smoother.set_smoothing_time(5.0, 0.0)
  smoother.set_target(0.5)
  assert_eq(smoother.tick(), 0.5)

  let context = DspContext::new(sample_rate=0.0, block_size=128)
  smoother.reset(0.0)
  smoother.set_smoothing_time_from_context(5.0, context)
  smoother.set_target(-0.25)
  assert_eq(smoother.tick(), -0.25)
}

///|
test "invalid values are normalized or ignored deterministically" {
  let smoother = ParamSmoother::new(0.0 / 0.0, 10.0, 48000.0)
  assert_eq(smoother.current(), 0.0)
  assert_eq(smoother.target(), 0.0)

  smoother.set_target(1.0 / 0.0)
  assert_eq(smoother.target(), 0.0)
  assert_eq(smoother.tick(), 0.0)

  smoother.reset(0.75)
  smoother.set_target(-0.5)
  assert_true(smoother.tick() < 0.75)
}
