///|
test "pan center splits signal equally" {
  let pan = Pan::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::filled(4, init=1.0)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, 0.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true((left.get(i) - 0.7071067811865476).abs() < 0.0001)
    assert_true((right.get(i) - 0.7071067811865476).abs() < 0.0001)
  }
}

///|
test "pan hard left sends signal only to left" {
  let pan = Pan::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::filled(4, init=1.0)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, -1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.99)
    assert_true(right.get(i).abs() < 0.0001)
  }
}

///|
test "pan hard right sends signal only to right" {
  let pan = Pan::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::filled(4, init=1.0)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, 1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i).abs() < 0.0001)
    assert_true(right.get(i) > 0.99)
  }
}

///|
test "pan zero input produces zero output regardless of position" {
  let pan = Pan::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::filled(4)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, 0.5)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) == 0.0)
    assert_true(right.get(i) == 0.0)
  }
}

///|
test "prop: pan preserves energy (equal-power law)" {
  @qc.quick_check_fn(
    fn(raw_pan : Double) {
      let pan_pos = raw_pan * 2.0 - 1.0
      if pan_pos.is_nan() || pan_pos.is_inf() {
        return true
      }
      let pan = Pan::new()
      let ctx = DspContext::new(sample_rate=48000.0, block_size=1)
      let input = AudioBuffer::filled(1, init=1.0)
      let left = AudioBuffer::filled(1)
      let right = AudioBuffer::filled(1)
      pan.process(ctx, input, left, right, pan_pos)
      let l = left.get(0)
      let r = right.get(0)
      let energy = l * l + r * r
      (energy - 1.0).abs() < 0.01
    },
    max_success=200,
  )
}
