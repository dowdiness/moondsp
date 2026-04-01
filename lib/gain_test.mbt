///|
test "gain scales samples by gain value" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.5)
  gain.process(ctx, buf, 0.8)
  for i = 0; i < 4; i = i + 1 {
    assert_true((buf.get(i) - 0.4).abs() < 0.000001)
  }
}

///|
test "zero gain produces silence" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=1.0)
  gain.process(ctx, buf, 0.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "unity gain is passthrough" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.7)
  gain.process(ctx, buf, 1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true((buf.get(i) - 0.7).abs() < 0.000001)
  }
}

///|
test "negative gain inverts signal" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.5)
  gain.process(ctx, buf, -1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true((buf.get(i) - -0.5).abs() < 0.000001)
  }
}

///|
test "prop: gain is exact multiplication" {
  @qc.quick_check_fn(
    fn(pair : (Double, Double)) {
      let (input, gain_val) = pair
      if input.is_nan() ||
        input.is_inf() ||
        gain_val.is_nan() ||
        gain_val.is_inf() {
        return true
      }
      let gain = Gain::new()
      let ctx = DspContext::new(48000.0, 1)
      let buf = AudioBuffer::filled(1, init=input)
      gain.process(ctx, buf, gain_val)
      let expected = input * gain_val
      if expected.is_nan() || expected.is_inf() {
        return true
      }
      (buf.get(0) - expected).abs() < 0.000001
    },
    max_success=200,
  )
}
