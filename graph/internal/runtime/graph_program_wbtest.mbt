///|
fn assert_same_audio(
  actual : AudioBuffer,
  expected : AudioBuffer,
) -> Unit raise {
  for i in 0..<actual.length() {
    assert_true((actual.get(i) - expected.get(i)).abs() < 0.000000000001)
  }
}

///|
test "program instances own parameters reset and oscillator history" {
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  let program = DspProgram(
    build_graph_program(
      [
        DspNode::constant(440.0),
        DspNode::oscillator_from(0, @dsp.Waveform::Sine),
        DspNode::output(1),
      ],
      context,
      DspNodeKind::Output,
    ).unwrap(),
  )
  let changed = program.instantiate()
  let untouched = program.instantiate()
  let reference = program.instantiate()
  let actual = AudioBuffer::filled(128)
  let expected = AudioBuffer::filled(128)
  changed
  .apply_control(GraphControl::set_param(0, GraphParamSlot::Value0, 880.0))
  .unwrap()
  changed.process(context, actual)
  changed.reset_runtime_state()
  for _ in 0..<3 {
    changed.process(context, actual)
    untouched.process(context, actual)
    reference.process(context, expected)
    assert_same_audio(actual, expected)
  }
  let fresh = program.instantiate()
  changed.reset_runtime_state()
  changed.process(context, actual)
  fresh.process(context, expected)
  assert_same_audio(actual, expected)
}

///|
test "transferred mono histories are independent of the old graph" {
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  let sources = [
    [DspNode::oscillator(@dsp.Waveform::Sine, 440.0), DspNode::output(0)],
    [DspNode::noise(42U), DspNode::output(0)],
    [
      DspNode::adsr(attack_ms=20.0, decay_ms=30.0, sustain=0.5, release_ms=40.0),
      DspNode::output(0),
    ],
    [
      DspNode::noise(42U),
      DspNode::biquad(
        input=0,
        mode=@dsp.BiquadMode::LowPass,
        cutoff_hz=1000.0,
        q=0.7,
      ),
      DspNode::output(1),
    ],
    [
      DspNode::noise(42U),
      DspNode::delay(
        input=0,
        max_delay_samples=512,
        delay_samples=200,
        feedback=0.4,
      ),
      DspNode::output(1),
    ],
  ]
  let actual = AudioBuffer::filled(128)
  let expected = AudioBuffer::filled(128)
  for nodes in sources {
    let old = Dsp::compile_raw(nodes, context).unwrap()
    let next = Dsp::compile_raw(nodes, context).unwrap()
    let reference = Dsp::compile_raw(nodes, context).unwrap()
    if nodes[0].kind() is Adsr {
      old.apply_control(GraphControl::gate_on(0)).unwrap()
      reference.apply_control(GraphControl::gate_on(0)).unwrap()
    }
    for _ in 0..<3 {
      old.process(context, actual)
      reference.process(context, expected)
    }
    next.raw_graph().copy_compatible_runtime_state_from(old.raw_graph())
    for _ in 0..<4 {
      old.process(context, actual)
      next.process(context, actual)
      reference.process(context, expected)
      assert_same_audio(actual, expected)
    }
  }
}

///|
test "transferred stereo filter and delay histories remain independent" {
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  let nodes = [
    DspNode::noise(42U),
    DspNode::pan(0, -0.3),
    DspNode::stereo_biquad(
      input=1,
      mode=@dsp.BiquadMode::LowPass,
      cutoff_hz=1000.0,
      q=0.7,
    ),
    DspNode::stereo_delay(
      input=2,
      max_delay_samples=512,
      delay_samples=200,
      feedback=0.4,
    ),
    DspNode::stereo_output(3),
  ]
  let old = StereoDsp::compile_raw(nodes, context).unwrap()
  let next = StereoDsp::compile_raw(nodes, context).unwrap()
  let reference = StereoDsp::compile_raw(nodes, context).unwrap()
  let left = AudioBuffer::filled(128)
  let right = AudioBuffer::filled(128)
  let expected_left = AudioBuffer::filled(128)
  let expected_right = AudioBuffer::filled(128)
  for _ in 0..<3 {
    old.process(context, left, right)
    reference.process(context, expected_left, expected_right)
  }
  next.raw_graph().copy_compatible_runtime_state_from(old.raw_graph())
  for _ in 0..<4 {
    old.process(context, left, right)
    next.process(context, left, right)
    reference.process(context, expected_left, expected_right)
    assert_same_audio(left, expected_left)
    assert_same_audio(right, expected_right)
  }
}
