///|
test "mix adds two buffers sample-wise" {
  let mix = Mix::new()
  let ctx = DspContext::new(48000.0, 4)
  let dst = AudioBuffer::new(FixedArray::from_array([1.0, 2.0, 3.0, 4.0]))
  let src = AudioBuffer::new(FixedArray::from_array([0.1, 0.2, 0.3, 0.4]))
  mix.process(ctx, dst, src)
  assert_true((dst.get(0) - 1.1).abs() < 0.000001)
  assert_true((dst.get(1) - 2.2).abs() < 0.000001)
  assert_true((dst.get(2) - 3.3).abs() < 0.000001)
  assert_true((dst.get(3) - 4.4).abs() < 0.000001)
}

///|
test "mix with silence is identity" {
  let mix = Mix::new()
  let ctx = DspContext::new(48000.0, 4)
  let dst = AudioBuffer::new(FixedArray::from_array([1.0, 2.0, 3.0, 4.0]))
  let silent = AudioBuffer::filled(4)
  mix.process(ctx, dst, silent)
  assert_true(dst.get(0) == 1.0)
  assert_true(dst.get(3) == 4.0)
}

///|
test "prop: mix is additive" {
  @qc.quick_check_fn(
    fn(pair : (Double, Double)) {
      let (a, b) = pair
      if a.is_nan() || a.is_inf() || b.is_nan() || b.is_inf() {
        return true
      }
      let mix = Mix::new()
      let ctx = DspContext::new(48000.0, 1)
      let dst = AudioBuffer::filled(1, init=a)
      let src = AudioBuffer::filled(1, init=b)
      mix.process(ctx, dst, src)
      let expected = a + b
      if expected.is_nan() || expected.is_inf() {
        return true
      }
      (dst.get(0) - expected).abs() < 0.000001
    },
    max_success=200,
  )
}
