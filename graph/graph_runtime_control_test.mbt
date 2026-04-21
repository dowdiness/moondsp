///|
test "compiled dsp runtime param update changes gain output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::gain(0, QUARTER_SAMPLE),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  assert_eq(output.get(0), QUARTER_SAMPLE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
    ),
  )
  compiled.process(context, output)

  assert_eq(output.get(0), HALF_GAIN)
  assert_eq(output.get(1), HALF_GAIN)
  assert_eq(output.get(2), HALF_GAIN)
  assert_eq(output.get(3), HALF_GAIN)
}

///|
test "compiled dsp runtime param update changes delay length" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(ZERO_SAMPLE),
    DspNode::delay(0, DELAY_CAPACITY, delay_samples=0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_eq(output.get(3), ZERO_SAMPLE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(0, GraphParamSlot::Value0, UNIT_SAMPLE),
    ),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ),
  )
  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_eq(output.get(1), ZERO_SAMPLE)
  assert_eq(output.get(2), UNIT_SAMPLE)
  assert_eq(output.get(3), UNIT_SAMPLE)
}

///|
test "compiled dsp applies mixed control batches in order" {
  let context = DspContext::new(
    sample_rate=ADSR_TEST_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::output(1),
    DspNode::mul(3, 2),
    DspNode::adsr(
      attack_ms=ADSR_ATTACK_MS,
      decay_ms=ADSR_DECAY_MS,
      sustain=ADSR_SUSTAIN_LEVEL,
      release_ms=ADSR_RELEASE_MS,
    ),
    DspNode::constant(UNIT_SAMPLE),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(3, GraphParamSlot::Value0, HALF_GAIN),
      GraphControl::gate_on(2),
    ]),
  )
  compiled.process(context, output)

  assert_eq(output.get(0), HALF_GAIN)
  assert_eq(output.get(1), HALF_GAIN * ADSR_SUSTAIN_LEVEL)
  assert_eq(output.get(2), HALF_GAIN * ADSR_SUSTAIN_LEVEL)
  assert_eq(output.get(3), HALF_GAIN * ADSR_SUSTAIN_LEVEL)
}

///|
test "compiled dsp rejects invalid control batches without partial updates" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::gain(0, QUARTER_SAMPLE),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_false(
    compiled.apply_controls([
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ]),
  )

  compiled.process(context, output)

  assert_eq(output.get(0), QUARTER_SAMPLE)
  assert_eq(output.get(1), QUARTER_SAMPLE)
  assert_eq(output.get(2), QUARTER_SAMPLE)
  assert_eq(output.get(3), QUARTER_SAMPLE)
}

///|
test "compiled dsp runtime param update rejects unsupported or invalid values" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(0, DELAY_CAPACITY, delay_samples=0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_false(
    compiled.apply_control(
      GraphControl::set_param(
        0,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ),
  )
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 1.5),
    ),
  )
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 0.0 / 0.0),
    ),
  )
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, INVALID_DELAY_FEEDBACK),
    ),
  )
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::Value0,
        CLAMPED_HIGH_DELAY_FEEDBACK,
      ),
    ),
  )

  compiled.process(context, output)

  assert_eq(output.get(0), UNIT_SAMPLE)
  assert_eq(output.get(1), UNIT_SAMPLE)
  assert_eq(output.get(2), UNIT_SAMPLE)
  assert_eq(output.get(3), UNIT_SAMPLE)
}

///|
test "compiled dsp runtime param update rejects invalid biquad values" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=LOWPASS_CUTOFF,
      q=LOWPASS_Q,
    ),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, INVALID_NYQUIST_CUTOFF),
    ),
  )
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value1, ZERO_SAMPLE),
    ),
  )
  compiled.process(context, output)

  assert_true(output.get(0) > ZERO_SAMPLE)
  assert_true(output.get(0) < UNIT_SAMPLE)
  assert_true(output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
}

///|
test "compiled dsp legacy wrappers match apply_control" {
  let context = DspContext::new(
    sample_rate=ADSR_TEST_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::output(1),
    DspNode::mul(3, 2),
    DspNode::adsr(
      attack_ms=ADSR_ATTACK_MS,
      decay_ms=ADSR_DECAY_MS,
      sustain=ADSR_SUSTAIN_LEVEL,
      release_ms=ADSR_RELEASE_MS,
    ),
    DspNode::constant(UNIT_SAMPLE),
  ]
  let wrapper_compiled = CompiledDsp::compile(nodes, context).unwrap()
  let unified_compiled = CompiledDsp::compile(nodes, context).unwrap()
  let wrapper_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let unified_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(wrapper_compiled.gate_on(2))
  assert_true(unified_compiled.apply_control(GraphControl::gate_on(2)))

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(wrapper_output.get(index), unified_output.get(index))
  }

  assert_true(wrapper_compiled.gate_off(2))
  assert_true(unified_compiled.apply_control(GraphControl::gate_off(2)))

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(wrapper_output.get(index), unified_output.get(index))
  }
}

///|
test "compiled dsp set_param wrapper matches apply_control" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::gain(0, QUARTER_SAMPLE),
    DspNode::output(1),
  ]
  let wrapper_compiled = CompiledDsp::compile(nodes, context).unwrap()
  let unified_compiled = CompiledDsp::compile(nodes, context).unwrap()
  let wrapper_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let unified_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(wrapper_compiled.set_param(1, GraphParamSlot::Value0, HALF_GAIN))
  assert_true(
    unified_compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
    ),
  )

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_eq(wrapper_output.get(index), unified_output.get(index))
  }
}

///|
test "compiled dsp rejects negative delay_samples via set_param" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(0, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()

  // Negative delay_samples must be rejected
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, -1.0),
    ),
  )
  // Verify the node still works with the original valid delay_samples
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  assert_eq(output.get(0), ZERO_SAMPLE)
}

///|
test "compiled dsp rejects delay_samples exceeding delay_max_samples via set_param" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(0, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()

  // delay_samples > delay_max_samples (DELAY_CAPACITY=4) must be rejected
  assert_false(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        5.0, // exceeds DELAY_CAPACITY of 4
      ),
    ),
  )
}

///|
test "compiled dsp accepts valid delay_samples within bounds via set_param" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(0, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()

  // delay_samples == 0 (lower bound) is valid
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 0.0),
    ),
  )
  // delay_samples == delay_max_samples (upper bound) is valid
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        4.0, // equals DELAY_CAPACITY
      ),
    ),
  )
  // delay_samples == 3 (mid-range) is valid
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 3.0),
    ),
  )
}
