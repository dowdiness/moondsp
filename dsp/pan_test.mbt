///|
test "pan center splits signal equally" {
  let pan = @dsp.Pan::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let input = @dsp.AudioBuffer::filled(4, init=1.0)
  let left = @dsp.AudioBuffer::filled(4)
  let right = @dsp.AudioBuffer::filled(4)
  pan.process(
    context=ctx,
    input~,
    left_output=left,
    right_output=right,
    position=0.0,
  )
  for i = 0; i < 4; i = i + 1 {
    assert_true((left.get(i) - 0.7071067811865476).abs() < 0.0001)
    assert_true((right.get(i) - 0.7071067811865476).abs() < 0.0001)
  }
}

///|
test "pan hard left sends signal only to left" {
  let pan = @dsp.Pan::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let input = @dsp.AudioBuffer::filled(4, init=1.0)
  let left = @dsp.AudioBuffer::filled(4)
  let right = @dsp.AudioBuffer::filled(4)
  pan.process(
    context=ctx,
    input~,
    left_output=left,
    right_output=right,
    position=-1.0,
  )
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.99)
    assert_true(right.get(i).abs() < 0.0001)
  }
}

///|
test "pan hard right sends signal only to right" {
  let pan = @dsp.Pan::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let input = @dsp.AudioBuffer::filled(4, init=1.0)
  let left = @dsp.AudioBuffer::filled(4)
  let right = @dsp.AudioBuffer::filled(4)
  pan.process(
    context=ctx,
    input~,
    left_output=left,
    right_output=right,
    position=1.0,
  )
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i).abs() < 0.0001)
    assert_true(right.get(i) > 0.99)
  }
}

///|
test "pan zero input produces zero output regardless of position" {
  let pan = @dsp.Pan::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let input = @dsp.AudioBuffer::filled(4)
  let left = @dsp.AudioBuffer::filled(4)
  let right = @dsp.AudioBuffer::filled(4)
  pan.process(
    context=ctx,
    input~,
    left_output=left,
    right_output=right,
    position=0.5,
  )
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
      let pan = @dsp.Pan::new()
      let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=1)
      let input = @dsp.AudioBuffer::filled(1, init=1.0)
      let left = @dsp.AudioBuffer::filled(1)
      let right = @dsp.AudioBuffer::filled(1)
      pan.process(
        context=ctx,
        input~,
        left_output=left,
        right_output=right,
        position=pan_pos,
      )
      let l = left.get(0)
      let r = right.get(0)
      let energy = l * l + r * r
      (energy - 1.0).abs() < 0.01
    },
    max_success=200,
  )
}
