///|
test "low-pass coefficients are normalized and symmetric" {
  let biquad = Biquad::new()
  let context = DspContext::new(48000.0, 128)

  assert_true(biquad.update(context, BiquadMode::LowPass, 1000.0, 0.707))

  assert_true(biquad.configured)
  assert_approx_eq(biquad.b0, biquad.b2, 0.000000000001)
  assert_true(biquad.b0 > 0.0)
  assert_true(biquad.b1 > biquad.b0)
  assert_true(biquad.a1 < 0.0)
  assert_true(biquad.a2 > 0.0)
}

///|
test "high-pass coefficients are normalized and symmetric" {
  let biquad = Biquad::new()
  let context = DspContext::new(48000.0, 128)

  assert_true(biquad.update(context, BiquadMode::HighPass, 1000.0, 0.707))

  assert_true(biquad.configured)
  assert_approx_eq(biquad.b0, biquad.b2, 0.000000000001)
  assert_true(biquad.b0 > 0.0)
  assert_true(biquad.b1 < 0.0)
  assert_true(biquad.a1 < 0.0)
  assert_true(biquad.a2 > 0.0)
}

///|
test "band-pass coefficients keep zero center tap" {
  let biquad = Biquad::new()
  let context = DspContext::new(48000.0, 128)

  assert_true(biquad.update(context, BiquadMode::BandPass, 1000.0, 0.707))

  assert_true(biquad.configured)
  assert_approx_eq(biquad.b1, 0.0, 0.000000000001)
  assert_approx_eq(biquad.b0, -biquad.b2, 0.000000000001)
  assert_true(biquad.b0 > 0.0)
  assert_true(biquad.a1 < 0.0)
  assert_true(biquad.a2 > 0.0)
}

///|
test "invalid update clears coefficients and delay state" {
  let biquad = Biquad::new()
  let context = DspContext::new(48000.0, 128)

  assert_true(biquad.update(context, BiquadMode::LowPass, 1000.0, 0.707))
  ignore(biquad.tick(1.0))

  assert_true(biquad.z1 != 0.0 || biquad.z2 != 0.0)
  assert_eq(biquad.update(context, BiquadMode::LowPass, 24000.0, 0.707), false)

  assert_eq(biquad.configured, false)
  assert_eq(biquad.b0, 0.0)
  assert_eq(biquad.b1, 0.0)
  assert_eq(biquad.b2, 0.0)
  assert_eq(biquad.a1, 0.0)
  assert_eq(biquad.a2, 0.0)
  assert_eq(biquad.z1, 0.0)
  assert_eq(biquad.z2, 0.0)
}

///|
fn assert_approx_eq(
  actual : Double,
  expected : Double,
  epsilon : Double,
) -> Unit raise {
  assert_true((actual - expected).abs() <= epsilon)
}
