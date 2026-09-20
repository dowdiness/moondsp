///|
test "copied envelope history retains destination timing" {
  let context = @dsp.DspContext::new(sample_rate=1000.0, block_size=16)
  let old = @dsp.Adsr::new(
    attack_ms=100.0,
    decay_ms=100.0,
    sustain=0.5,
    release_ms=100.0,
  )
  let next = @dsp.Adsr::new(
    attack_ms=200.0,
    decay_ms=200.0,
    sustain=0.25,
    release_ms=200.0,
  )
  old.gate_on()
  for _ in 0..<10 {
    ignore(old.tick(context))
  }
  next.copy_state_from(old)
  let before = next.level()
  ignore(old.tick(context))
  assert_true((next.tick(context) - (before + 0.005)).abs() < 0.000000000001)
  old.gate_off()
  assert_true(next.stage() is @dsp.EnvStage::Attack)
}

///|
test "copied delay history retains destination settings and storage ownership" {
  let old = @dsp.DelayLine::new(8, delay_samples=1, feedback=0.0)
  let next = @dsp.DelayLine::new(8, delay_samples=3, feedback=0.5)
  for sample in [1.0, 2.0, 3.0, 4.0] {
    ignore(old.tick(sample))
  }
  assert_true(next.copy_state_from(old))
  // Old graph writes must not alter the destination ring.
  for _ in 0..<16 {
    ignore(old.tick(99.0))
  }
  assert_eq(next.tick(0.0), 2.0)
  assert_eq(next.tick(0.0), 3.0)
  assert_eq(next.tick(0.0), 4.0)
  assert_eq(next.tick(0.0), 1.0)
  let incompatible = @dsp.DelayLine::new(4, delay_samples=1)
  assert_false(incompatible.copy_state_from(next))
  assert_eq(incompatible.tick(0.0), 0.0)
}
