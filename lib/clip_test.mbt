///|
test "clip clamps values exceeding threshold" {
  let clip = Clip::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::new(FixedArray::from_array([2.0, -2.0, 0.5, -0.3]))
  clip.process(ctx, buf, 0.5)
  assert_true(buf.get(0) == 0.5)
  assert_true(buf.get(1) == -0.5)
  assert_true(buf.get(2) == 0.5)
  assert_true(buf.get(3) == -0.3)
}

///|
test "clip with threshold 1.0 clamps to standard range" {
  let clip = Clip::new()
  let ctx = DspContext::new(48000.0, 2)
  let buf = AudioBuffer::new(FixedArray::from_array([1.5, -1.5]))
  clip.process(ctx, buf, 1.0)
  assert_true(buf.get(0) == 1.0)
  assert_true(buf.get(1) == -1.0)
}

///|
test "clip with zero threshold produces silence" {
  let clip = Clip::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.5)
  clip.process(ctx, buf, 0.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "prop: clip output within threshold" {
  @qc.quick_check_fn(
    fn(pair : (Double, Double)) {
      let (input, raw_threshold) = pair
      if input.is_nan() ||
        input.is_inf() ||
        raw_threshold.is_nan() ||
        raw_threshold.is_inf() {
        return true
      }
      let threshold = raw_threshold.abs()
      let clip = Clip::new()
      let ctx = DspContext::new(48000.0, 1)
      let buf = AudioBuffer::filled(1, init=input)
      clip.process(ctx, buf, threshold)
      let out = buf.get(0)
      out >= -threshold && out <= threshold
    },
    max_success=200,
  )
}
