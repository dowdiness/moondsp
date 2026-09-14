///|
fn assert_sine_phase_matches_core(phase : Double) -> Unit raise {
  assert_eq(
    sample_for_phase(Sine, phase).reinterpret_as_uint64(),
    @math.sin(phase * 2.0 * @math.PI).reinterpret_as_uint64(),
  )
}

///|
test "sine samples preserve core rounding across the complete phase range" {
  for i in 0..<=65536 {
    assert_sine_phase_matches_core(i.to_double() / 65536.0)
  }
  assert_sine_phase_matches_core(-0.0)
  assert_sine_phase_matches_core(1UL.reinterpret_as_double())
}

///|
test "sine samples preserve cancellation and reduction boundary rounding" {
  // Exact quadrant/octant boundaries and the high-word cutoffs used by core.
  let boundaries = [
    0.125,
    0.25,
    0.375,
    0.5,
    0.625,
    0.75,
    0.875,
    0x3fe921fb00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x3fe921fc00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x3ff921fb00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x3ff921fc00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x4002d97c00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x400921fb00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x400921fc00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x4012d97c00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x4012d97d00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
    0x401921fb00000000UL.reinterpret_as_double() / (2.0 * @math.PI),
  ]
  for phase in boundaries {
    let bits = phase.reinterpret_as_uint64()
    for offset in 0..<=16 {
      assert_sine_phase_matches_core(
        (bits - offset.to_uint64()).reinterpret_as_double(),
      )
      assert_sine_phase_matches_core(
        (bits + offset.to_uint64()).reinterpret_as_double(),
      )
    }
  }
  for offset in 0..<=16 {
    assert_sine_phase_matches_core(
      (1.0.reinterpret_as_uint64() - offset.to_uint64()).reinterpret_as_double(),
    )
  }
}

///|
test "sine retains rounded wrap and scalar overflow behavior" {
  let oscillator = Oscillator()
  let _ = oscillator.tick(freq_hz=-1UL.reinterpret_as_double(), sample_rate=1.0)
  assert_eq(oscillator.phase(), 1.0)
  assert_eq(
    oscillator.tick(freq_hz=0.0, sample_rate=1.0).reinterpret_as_uint64(),
    @math.sin(2.0 * @math.PI).reinterpret_as_uint64(),
  )
  oscillator.reset()
  let _ = oscillator.tick(freq_hz=1.0e308, sample_rate=1.0e-308)
  assert_true(oscillator.tick(freq_hz=1.0, sample_rate=48000.0).is_nan())
  oscillator.reset()
  assert_eq(oscillator.tick(freq_hz=440.0, sample_rate=48000.0), 0.0)
}
