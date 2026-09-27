///|
test "compiled dsp preserves constant-fed gain controls and reset" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(3.0),
    @graph.DspNode::gain(0, 0.5),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  @debug.assert_eq(output.get(0), 1.5)

  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 2.0),
    )
    is Ok(_),
  )
  compiled.process(context, output)

  for index in 0..<SMALL_BLOCK_SIZE {
    @debug.assert_eq(output.get(index), 6.0)
  }

  compiled.reset_runtime_state()
  compiled.process(context, output)

  for index in 0..<SMALL_BLOCK_SIZE {
    @debug.assert_eq(output.get(index), 1.5)
  }
}

///|
test "compiled dsp preserves constant-fed clip controls" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(10.0),
    @graph.DspNode::clip(0, 3.0),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  @debug.assert_eq(output.get(0), 3.0)

  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(1, @graph.GraphParamSlot::Value0, 7.0),
    )
    is Ok(_),
  )
  compiled.process(context, output)

  for index in 0..<SMALL_BLOCK_SIZE {
    @debug.assert_eq(output.get(index), 7.0)
  }
}

///|
test "compiled dsp runtime param update changes delay length" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    @graph.DspNode::constant(ZERO_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=0,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)
  @debug.assert_eq(output.get(0), ZERO_SAMPLE)
  @debug.assert_eq(output.get(3), ZERO_SAMPLE)

  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        0,
        @graph.GraphParamSlot::Value0,
        UNIT_SAMPLE,
      ),
    )
    is Ok(_),
  )
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=0,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
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
    @graph.DspNode::output(1),
    @graph.DspNode::mul(3, 2),
    @graph.DspNode::adsr(
      attack_ms=ADSR_ATTACK_MS,
      decay_ms=ADSR_DECAY_MS,
      sustain=ADSR_SUSTAIN_LEVEL,
      release_ms=ADSR_RELEASE_MS,
    ),
    @graph.DspNode::constant(UNIT_SAMPLE),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      @graph.GraphControl::set_param(
        3,
        @graph.GraphParamSlot::Value0,
        HALF_GAIN,
      ),
      @graph.GraphControl::gate_on(2),
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::gain(0, QUARTER_SAMPLE),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value0,
        HALF_GAIN,
      ),
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::gain(0, QUARTER_SAMPLE),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  match
    compiled.apply_control(
      @graph.GraphControl::set_param(
        99,
        @graph.GraphParamSlot::Value0,
        HALF_GAIN,
      ),
    ) {
    Err(@graph.GraphControlError::InvalidNodeIndex(99)) => ()
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::constant(HALF_GAIN),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  match
    compiled.apply_control(
      @graph.GraphControl::set_param(
        0,
        @graph.GraphParamSlot::Value0,
        QUARTER_SAMPLE,
      ),
    ) {
    Err(@graph.GraphControlError::OrphanNode(0)) => ()
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=0,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  match
    compiled.apply_control(
      @graph.GraphControl::set_param(
        0,
        @graph.GraphParamSlot::DelaySamples,
        1.0,
      ),
    ) {
    Err(
      @graph.GraphControlError::InvalidSlotForNode(
        0,
        @graph.DspNodeKind::Constant,
        @graph.GraphParamSlot::DelaySamples
      )
    ) => ()
    other => fail("expected InvalidSlotForNode, got \{@debug.to_string(other)}")
  }

  match
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        1.5,
      ),
    ) {
    Err(
      @graph.GraphControlError::InvalidParamValue(
        1,
        @graph.DspNodeKind::Delay,
        @graph.GraphParamSlot::DelaySamples,
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::gain(0, QUARTER_SAMPLE),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  match
    compiled.apply_controls([
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value0,
        HALF_GAIN,
      ),
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ]) {
    Err(
      @graph.GraphControlError::InvalidSlotForNode(
        1,
        @graph.DspNodeKind::Gain,
        @graph.GraphParamSlot::DelaySamples
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::pan(0, 0.0),
    @graph.DspNode::stereo_output(1),
  ]
  let compiled = @graph.StereoDsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  match compiled.apply_control(@graph.GraphControl::gate_on(1)) {
    Err(@graph.GraphControlError::InvalidGateNode(1, @graph.DspNodeKind::Pan)) =>
      ()
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=0,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        0,
        @graph.GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        1.5,
      ),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        0.0 / 0.0,
      ),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value0,
        INVALID_DELAY_FEEDBACK,
      ),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value0,
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=LOWPASS_CUTOFF,
      q=LOWPASS_Q,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value0,
        INVALID_NYQUIST_CUTOFF,
      ),
    )
    is Err(_),
  )
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value1,
        ZERO_SAMPLE,
      ),
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
    @graph.DspNode::output(1),
    @graph.DspNode::mul(3, 2),
    @graph.DspNode::adsr(
      attack_ms=ADSR_ATTACK_MS,
      decay_ms=ADSR_DECAY_MS,
      sustain=ADSR_SUSTAIN_LEVEL,
      release_ms=ADSR_RELEASE_MS,
    ),
    @graph.DspNode::constant(UNIT_SAMPLE),
  ]
  let wrapper_compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let unified_compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let wrapper_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let unified_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(wrapper_compiled.gate_on(2) is Ok(_))
  assert_true(
    unified_compiled.apply_control(@graph.GraphControl::gate_on(2)) is Ok(_),
  )

  wrapper_compiled.process(context, wrapper_output)
  unified_compiled.process(context, unified_output)

  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    @debug.assert_eq(wrapper_output.get(index), unified_output.get(index))
  }

  assert_true(wrapper_compiled.gate_off(2) is Ok(_))
  assert_true(
    unified_compiled.apply_control(@graph.GraphControl::gate_off(2)) is Ok(_),
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::gain(0, QUARTER_SAMPLE),
    @graph.DspNode::output(1),
  ]
  let wrapper_compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let unified_compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()
  let wrapper_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let unified_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    wrapper_compiled.set_param(1, @graph.GraphParamSlot::Value0, HALF_GAIN)
    is Ok(_),
  )
  assert_true(
    unified_compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::Value0,
        HALF_GAIN,
      ),
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  // Negative delay_samples must be rejected
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        -1.0,
      ),
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  // delay_samples > delay_max_samples (DELAY_CAPACITY=4) must be rejected
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
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
    @graph.DspNode::constant(UNIT_SAMPLE),
    @graph.DspNode::delay(
      input=0,
      max_delay_samples=DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
    ),
    @graph.DspNode::output(1),
  ]
  let compiled = @graph.Dsp::compile(
    @graph.AnalyzedGraph::analyze(nodes),
    context,
  ).unwrap()

  // delay_samples == 0 (lower bound) is valid
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        0.0,
      ),
    )
    is Ok(_),
  )
  // delay_samples == delay_max_samples (upper bound) is valid
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        4.0, // equals DELAY_CAPACITY
      ),
    )
    is Ok(_),
  )
  // delay_samples == 3 (mid-range) is valid
  assert_true(
    compiled.apply_control(
      @graph.GraphControl::set_param(
        1,
        @graph.GraphParamSlot::DelaySamples,
        3.0,
      ),
    )
    is Ok(_),
  )
}
