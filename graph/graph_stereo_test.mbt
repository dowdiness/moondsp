///|
test "compiled stereo dsp pans mono input to stereo output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true((left_output.get(index) - PAN_CENTER_GAIN).abs() < 0.000000001)
    assert_true((right_output.get(index) - PAN_CENTER_GAIN).abs() < 0.000000001)
  }
}

///|
test "compiled stereo dsp applies stereo gain after pan" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_gain(1, HALF_GAIN),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true(
      (left_output.get(index) - HALF_GAIN * PAN_CENTER_GAIN).abs() < 0.000000001,
    )
    assert_true(
      (right_output.get(index) - HALF_GAIN * PAN_CENTER_GAIN).abs() <
      0.000000001,
    )
  }
}

///|
test "compiled stereo dsp applies stereo clip after pan" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_clip(1, STEREO_CLIP_THRESHOLD),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(left_output.get(index), STEREO_CLIP_THRESHOLD)
    assert_eq(right_output.get(index), STEREO_CLIP_THRESHOLD)
  }
}

///|
test "compiled stereo dsp applies stereo biquad after pan" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_biquad(1, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(LARGE_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  assert_true(left_output.get(0) > ZERO_SAMPLE)
  assert_true(left_output.get(0) < PAN_CENTER_GAIN)
  assert_true(left_output.get(1) > left_output.get(0))
  assert_true(right_output.get(0) > ZERO_SAMPLE)
  assert_true((left_output.get(0) - right_output.get(0)).abs() < 0.000000001)
  assert_true((left_output.get(1) - right_output.get(1)).abs() < 0.000000001)
}

///|
test "compiled stereo dsp applies stereo delay after pan" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  assert_eq(left_output.get(0), ZERO_SAMPLE)
  assert_eq(left_output.get(1), ZERO_SAMPLE)
  assert_true((left_output.get(2) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((left_output.get(3) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_eq(right_output.get(0), ZERO_SAMPLE)
  assert_eq(right_output.get(1), ZERO_SAMPLE)
  assert_true((right_output.get(2) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((right_output.get(3) - PAN_CENTER_GAIN).abs() < 0.000000001)
}

///|
test "compiled stereo dsp apply_control updates pan position" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, PAN_HARD_RIGHT),
    ),
  )
  compiled.process(context, left_output, right_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(left_output.get(index), ZERO_SAMPLE)
    assert_eq(right_output.get(index), UNIT_SAMPLE)
  }
}

///|
test "compiled stereo dsp runtime params update stereo gain and clip" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_gain(1, UNIT_SAMPLE),
    DspNode::stereo_clip(2, UNIT_SAMPLE),
    DspNode::stereo_output(3),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, HALF_GAIN),
    ),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(3, GraphParamSlot::Value0, STEREO_CLIP_THRESHOLD),
    ),
  )
  compiled.process(context, left_output, right_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(left_output.get(index), STEREO_CLIP_THRESHOLD)
    assert_eq(right_output.get(index), STEREO_CLIP_THRESHOLD)
  }
}

///|
test "compiled stereo dsp runtime params update stereo biquad" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_biquad(1, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let baseline_left = AudioBuffer::filled(LARGE_BLOCK_SIZE)
  let baseline_right = AudioBuffer::filled(LARGE_BLOCK_SIZE)
  let retuned_left = AudioBuffer::filled(LARGE_BLOCK_SIZE)
  let retuned_right = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, baseline_left, baseline_right)
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        HALF_GAIN * LOWPASS_CUTOFF,
      ),
    ),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value1, 1.2),
    ),
  )
  compiled.process(context, retuned_left, retuned_right)

  assert_true(retuned_left.get(0) != baseline_left.get(0))
  assert_true(retuned_right.get(0) != baseline_right.get(0))
}

///|
test "compiled stereo dsp runtime params update stereo delay" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=0),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ),
  )
  compiled.process(context, left_output, right_output)

  assert_eq(left_output.get(0), ZERO_SAMPLE)
  assert_eq(left_output.get(1), ZERO_SAMPLE)
  assert_true((left_output.get(2) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((left_output.get(3) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_eq(right_output.get(0), ZERO_SAMPLE)
  assert_eq(right_output.get(1), ZERO_SAMPLE)
  assert_true((right_output.get(2) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((right_output.get(3) - PAN_CENTER_GAIN).abs() < 0.000000001)
}

///|
test "compiled stereo dsp runtime params update stereo delay feedback" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::stereo_output(2),
  ]
  let baseline = CompiledStereoDsp::compile(nodes, context).unwrap()
  let retuned = CompiledStereoDsp::compile(nodes, context).unwrap()
  let baseline_left = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let baseline_right = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let retuned_left = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let retuned_right = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  baseline.process(context, baseline_left, baseline_right)
  retuned.process(context, retuned_left, retuned_right)
  assert_true(
    retuned.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, DELAY_FEEDBACK),
    ),
  )
  baseline.process(context, baseline_left, baseline_right)
  retuned.process(context, retuned_left, retuned_right)

  assert_true((retuned_left.get(0) - baseline_left.get(0)).abs() < 0.000000001)
  assert_true(
    (retuned_right.get(0) - baseline_right.get(0)).abs() < 0.000000001,
  )
  assert_true(retuned_left.get(2) > baseline_left.get(2))
  assert_true(retuned_right.get(2) > baseline_right.get(2))
}

///|
test "compiled stereo dsp apply_controls updates pan and source together" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_HARD_LEFT),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(0, GraphParamSlot::Value0, HALF_GAIN),
      GraphControl::set_param(1, GraphParamSlot::Value0, PAN_CENTER),
    ]),
  )
  compiled.process(context, left_output, right_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true(
      (left_output.get(index) - HALF_GAIN * PAN_CENTER_GAIN).abs() < 0.000000001,
    )
    assert_true(
      (right_output.get(index) - HALF_GAIN * PAN_CENTER_GAIN).abs() <
      0.000000001,
    )
  }
}

///|
test "compiled stereo dsp rejects out-of-bounds delay_samples via set_param" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, ZERO_SAMPLE),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::stereo_output(2),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()

  // Negative delay_samples must be rejected
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::DelaySamples, -1.0),
    ),
  )
  // Exceeding max must be rejected
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::DelaySamples, 5.0),
    ),
  )
  // Valid value must be accepted
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::DelaySamples, 3.0),
    ),
  )
}

///|
test "compiled dsp folds stereo graph back to mono output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_mixdown(1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true((output.get(index) - PAN_CENTER_GAIN).abs() < 0.000000001)
  }
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, 1.0),
    ),
  )
}

///|
test "compiled dsp runtime params update stereo nodes before mixdown" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_gain(1, UNIT_SAMPLE),
    DspNode::stereo_clip(2, UNIT_SAMPLE),
    DspNode::stereo_mixdown(3),
    DspNode::output(4),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, HALF_GAIN),
    ),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(3, GraphParamSlot::Value0, STEREO_CLIP_THRESHOLD),
    ),
  )
  compiled.process(context, output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(output.get(index), STEREO_CLIP_THRESHOLD)
  }
  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(2, GraphParamSlot::Value0, UNIT_SAMPLE),
      GraphControl::set_param(3, GraphParamSlot::Value0, UNIT_SAMPLE),
    ]),
  )
}

///|
test "compiled dsp runtime params update stereo biquad before mixdown" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_biquad(1, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
    DspNode::stereo_mixdown(2),
    DspNode::output(3),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        HALF_GAIN * LOWPASS_CUTOFF,
      ),
    ),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value1, 1.2),
    ),
  )
  compiled.process(context, output)

  assert_true(output.get(0) > ZERO_SAMPLE)
  assert_true(output.get(0) < PAN_CENTER_GAIN)
  assert_true(output.get(1) > output.get(0))
}

///|
test "compiled dsp applies stereo delay before mixdown" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::stereo_mixdown(2),
    DspNode::output(3),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_eq(output.get(1), ZERO_SAMPLE)
  assert_true((output.get(2) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((output.get(3) - PAN_CENTER_GAIN).abs() < 0.000000001)
}

///|
test "compiled dsp runtime params update stereo delay before mixdown" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=0),
    DspNode::stereo_mixdown(2),
    DspNode::output(3),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ),
  )
  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_eq(output.get(1), ZERO_SAMPLE)
  assert_true((output.get(2) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((output.get(3) - PAN_CENTER_GAIN).abs() < 0.000000001)
}

///|
test "compiled dsp runtime params update stereo delay feedback before mixdown" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(1, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::stereo_mixdown(2),
    DspNode::output(3),
  ]
  let baseline = CompiledDsp::compile(nodes, context).unwrap()
  let retuned = CompiledDsp::compile(nodes, context).unwrap()
  let baseline_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let retuned_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)
  assert_true(
    retuned.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, DELAY_FEEDBACK),
    ),
  )
  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true((baseline_output.get(0) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true((baseline_output.get(1) - PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true(
    (retuned_output.get(0) - baseline_output.get(0)).abs() < 0.000000001,
  )
  assert_true(
    (retuned_output.get(1) - baseline_output.get(1)).abs() < 0.000000001,
  )
  assert_true(retuned_output.get(2) > baseline_output.get(2))
  assert_true(retuned_output.get(3) > baseline_output.get(3))
}

///|
test "stereo process: clean graph has zero sanitized count" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::pan(0, 0.0),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, left, right)
  assert_eq(compiled.last_sanitized_count(), 0)
}
