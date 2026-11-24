///|
fn assert_sine_phase_matches_core(phase : Double) -> Unit raise {
  assert_eq(
    sine_of_turns(phase).reinterpret_as_uint64(),
    @math.sin(phase * 2.0 * @math.PI).reinterpret_as_uint64(),
  )
}

///|
test "sine and cosine of turns preserve core rounding across one turn" {
  for i in 0..<=65536 {
    let turns = i.to_double() / 65536.0
    assert_sine_phase_matches_core(turns)
    assert_eq(
      cosine_of_turns(turns).reinterpret_as_uint64(),
      @math.cos(turns * 2.0 * @math.PI).reinterpret_as_uint64(),
    )
  }
  assert_sine_phase_matches_core(-0.0)
  assert_sine_phase_matches_core(1UL.reinterpret_as_double())
}

///|
test "sine of turns preserves cancellation and reduction boundary rounding" {
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
