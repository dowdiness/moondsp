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
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  @debug.assert_eq(output.get(0), QUARTER_SAMPLE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
    )
    is Ok(_),
  )
  compiled.process(context, output)

  @debug.assert_eq(output.get(0), HALF_GAIN)
  @debug.assert_eq(output.get(1), HALF_GAIN)
  @debug.assert_eq(output.get(2), HALF_GAIN)
  @debug.assert_eq(output.get(3), HALF_GAIN)
}

///|
test "compiled dsp runtime param update changes delay length" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(ZERO_SAMPLE),
    DspNode::delay(input=0, max_delay_samples=DELAY_CAPACITY, delay_samples=0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  @debug.assert_eq(output.get(0), ZERO_SAMPLE)
  @debug.assert_eq(output.get(3), ZERO_SAMPLE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(0, GraphParamSlot::Value0, UNIT_SAMPLE),
    )
    is Ok(_),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    )
    is Ok(_),
  )
  compiled.process(context, output)

  @debug.assert_eq(output.get(0), ZERO_SAMPLE)
  @debug.assert_eq(output.get(1), ZERO_SAMPLE)
  @debug.assert_eq(output.get(2), UNIT_SAMPLE)
  @debug.assert_eq(output.get(3), UNIT_SAMPLE)
}

///|
test "compiled dsp reset restores runtime delay parameters" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(input=0, max_delay_samples=DELAY_CAPACITY, delay_samples=0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    )
    is Ok(_),
  )
  compiled.reset_runtime_state()
  compiled.process(context, output)

  @debug.assert_eq(output.get(0), UNIT_SAMPLE)
  @debug.assert_eq(output.get(1), UNIT_SAMPLE)
  @debug.assert_eq(output.get(2), UNIT_SAMPLE)
  @debug.assert_eq(output.get(3), UNIT_SAMPLE)
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
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(3, GraphParamSlot::Value0, HALF_GAIN),
      GraphControl::gate_on(2),
    ])
    is Ok(_),
  )
  compiled.process(context, output)

  @debug.assert_eq(output.get(0), HALF_GAIN)
  @debug.assert_eq(output.get(1), HALF_GAIN * ADSR_SUSTAIN_LEVEL)
  @debug.assert_eq(output.get(2), HALF_GAIN * ADSR_SUSTAIN_LEVEL)
  @debug.assert_eq(output.get(3), HALF_GAIN * ADSR_SUSTAIN_LEVEL)
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
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ])
    is Err(_),
  )

  compiled.process(context, output)

  @debug.assert_eq(output.get(0), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(1), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(2), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(3), QUARTER_SAMPLE)
}

///|
test "compiled dsp apply_control reports invalid node index" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::gain(0, QUARTER_SAMPLE),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()

  match
    compiled.apply_control(
      GraphControl::set_param(99, GraphParamSlot::Value0, HALF_GAIN),
    ) {
    Err(GraphControlError::InvalidNodeIndex(99)) => ()
    other => fail("expected InvalidNodeIndex, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp apply_control reports orphan optimized node" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::constant(HALF_GAIN),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()

  match
    compiled.apply_control(
      GraphControl::set_param(0, GraphParamSlot::Value0, QUARTER_SAMPLE),
    ) {
    Err(GraphControlError::OrphanNode(0)) => ()
    other => fail("expected OrphanNode, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp apply_control reports invalid slot and value" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(input=0, max_delay_samples=DELAY_CAPACITY, delay_samples=0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()

  match
    compiled.apply_control(
      GraphControl::set_param(0, GraphParamSlot::DelaySamples, 1.0),
    ) {
    Err(
      GraphControlError::InvalidSlotForNode(
        0,
        DspNodeKind::Constant,
        GraphParamSlot::DelaySamples
      )
    ) => ()
    other => fail("expected InvalidSlotForNode, got \{@debug.to_string(other)}")
  }

  match
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 1.5),
    ) {
    Err(
      GraphControlError::InvalidParamValue(
        1,
        DspNodeKind::Delay,
        GraphParamSlot::DelaySamples,
        1.5
      )
    ) => ()
    other => fail("expected InvalidParamValue, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp apply_controls is transactional" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::gain(0, QUARTER_SAMPLE),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  match
    compiled.apply_controls([
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ]) {
    Err(
      GraphControlError::InvalidSlotForNode(
        1,
        DspNodeKind::Constant,
        GraphParamSlot::DelaySamples
      )
    ) => ()
    other => fail("expected InvalidSlotForNode, got \{@debug.to_string(other)}")
  }

  compiled.process(context, output)

  @debug.assert_eq(output.get(0), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(1), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(2), QUARTER_SAMPLE)
  @debug.assert_eq(output.get(3), QUARTER_SAMPLE)
}

///|
test "compiled stereo dsp apply_control reports invalid gate target" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, 0.0),
    DspNode::stereo_output(1),
  ]
  let compiled = CompiledStereoDsp::compile(
    CompiledTemplate::analyze(nodes),
    context,
  ).unwrap()

  match compiled.apply_control(GraphControl::gate_on(1)) {
    Err(GraphControlError::InvalidGateNode(1, DspNodeKind::Pan)) => ()
    other => fail("expected InvalidGateNode, got \{@debug.to_string(other)}")
  }
}

///|
test "compiled dsp runtime param update rejects unsupported or invalid values" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(input=0, max_delay_samples=DELAY_CAPACITY, delay_samples=0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        0,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 1.5),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 0.0 / 0.0),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, INVALID_DELAY_FEEDBACK),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::Value0,
        CLAMPED_HIGH_DELAY_FEEDBACK,
      ),
    )
    is Err(_),
  )

  compiled.process(context, output)

  @debug.assert_eq(output.get(0), UNIT_SAMPLE)
  @debug.assert_eq(output.get(1), UNIT_SAMPLE)
  @debug.assert_eq(output.get(2), UNIT_SAMPLE)
  @debug.assert_eq(output.get(3), UNIT_SAMPLE)
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
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, INVALID_NYQUIST_CUTOFF),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value1, ZERO_SAMPLE),
    )
    is Err(_),
  )
  compiled.process(context, output)

  assert_true(output.get(0) > ZERO_SAMPLE)
  assert_true(output.get(0) < UNIT_SAMPLE)
  assert_true(output.any(sample => sample != ZERO_SAMPLE))
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
  let wrapper_compiled = CompiledDsp::compile(
    CompiledTemplate::analyze(nodes),
    context,
  ).unwrap()
  let unified_compiled = CompiledDsp::compile(
    CompiledTemplate::analyze(nodes),
    context,
  ).unwrap()
  let wrapper_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let unified_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(wrapper_compiled.gate_on(2) is Ok(_))
  assert_true(unified_compiled.apply_control(GraphControl::gate_on(2)) is Ok(_))

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    @debug.assert_eq(wrapper_output.get(index), unified_output.get(index))
  }

  assert_true(wrapper_compiled.gate_off(2) is Ok(_))
  assert_true(
    unified_compiled.apply_control(GraphControl::gate_off(2)) is Ok(_),
  )

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    @debug.assert_eq(wrapper_output.get(index), unified_output.get(index))
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
  let wrapper_compiled = CompiledDsp::compile(
    CompiledTemplate::analyze(nodes),
    context,
  ).unwrap()
  let unified_compiled = CompiledDsp::compile(
    CompiledTemplate::analyze(nodes),
    context,
  ).unwrap()
  let wrapper_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let unified_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    wrapper_compiled.set_param(1, GraphParamSlot::Value0, HALF_GAIN) is Ok(_),
  )
  assert_true(
    unified_compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
    )
    is Ok(_),
  )

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    @debug.assert_eq(wrapper_output.get(index), unified_output.get(index))
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
    DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()

  // Negative delay_samples must be rejected
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, -1.0),
    )
    is Err(_),
  )
  // Verify the node still works with the original valid delay_samples
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  @debug.assert_eq(output.get(0), ZERO_SAMPLE)
}

///|
test "compiled dsp rejects delay_samples exceeding delay_max_samples via set_param" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()

  // delay_samples > delay_max_samples (DELAY_CAPACITY=4) must be rejected
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        5.0, // exceeds DELAY_CAPACITY of 4
      ),
    )
    is Err(_),
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
    DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(CompiledTemplate::analyze(nodes), context).unwrap()

  // delay_samples == 0 (lower bound) is valid
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 0.0),
    )
    is Ok(_),
  )
  // delay_samples == delay_max_samples (upper bound) is valid
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::DelaySamples,
        4.0, // equals DELAY_CAPACITY
      ),
    )
    is Ok(_),
  )
  // delay_samples == 3 (mid-range) is valid
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(1, GraphParamSlot::DelaySamples, 3.0),
    )
    is Ok(_),
  )
}
