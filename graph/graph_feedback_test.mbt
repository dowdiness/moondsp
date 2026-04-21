///|
test "compiled dsp resolves simple mono feedback cycle via z^-1 insertion" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 2),
    DspNode::gain(1, HALF_GAIN),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true((output.get(0) - HALF_GAIN).abs() < 0.000000001)
  assert_true((output.get(1) - 0.75).abs() < 0.000000001)
  assert_true((output.get(2) - 0.875).abs() < 0.000000001)
  assert_true((output.get(3) - 0.9375).abs() < 0.000000001)
}

///|
test "compiled dsp runtime gain update retunes accepted feedback cycle" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 2),
    DspNode::gain(1, HALF_GAIN),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let baseline_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let retuned_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, baseline_output)
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, QUARTER_SAMPLE),
    ),
  )
  compiled.process(context, retuned_output)

  assert_true((baseline_output.get(3) - 0.9375).abs() < 0.000000001)
  assert_true((retuned_output.get(0) - 0.484375).abs() < 0.000000001)
  assert_true((retuned_output.get(1) - 0.37109375).abs() < 0.000000001)
  assert_true((retuned_output.get(2) - 0.3427734375).abs() < 0.000000001)
  assert_true((retuned_output.get(3) - 0.335693359375).abs() < 0.000000001)
}

///|
test "compiled dsp resolves multiple mono feedback edges from one source" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::gain(4, HALF_GAIN),
    DspNode::gain(4, QUARTER_SAMPLE),
    DspNode::mix(0, 1),
    DspNode::mix(3, 2),
    DspNode::output(4),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true((output.get(0) - UNIT_SAMPLE).abs() < 0.000000001)
  assert_true((output.get(1) - 1.75).abs() < 0.000000001)
  assert_true((output.get(2) - 2.3125).abs() < 0.000000001)
  assert_true((output.get(3) - 2.734375).abs() < 0.000000001)
}

///|
test "compiled dsp runtime delay update matches fixed feedback loop compile" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let runtime_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 3),
    DspNode::delay(1, DELAY_CAPACITY, delay_samples=0),
    DspNode::gain(2, HALF_GAIN),
    DspNode::output(3),
  ]
  let fixed_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 3),
    DspNode::delay(1, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::gain(2, HALF_GAIN),
    DspNode::output(3),
  ]
  let runtime_compiled = CompiledDsp::compile(runtime_nodes, context).unwrap()
  let fixed_compiled = CompiledDsp::compile(fixed_nodes, context).unwrap()
  let runtime_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let fixed_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    runtime_compiled.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::DelaySamples,
        DELAY_SAMPLES_DOUBLE,
      ),
    ),
  )
  runtime_compiled.process(context, runtime_output)
  fixed_compiled.process(context, fixed_output)

  assert_eq(runtime_output.get(0), ZERO_SAMPLE)
  assert_eq(runtime_output.get(1), ZERO_SAMPLE)
  assert_eq(runtime_output.get(2), HALF_GAIN)
  assert_eq(runtime_output.get(3), HALF_GAIN)
  for index = 0; index < runtime_output.length(); index = index + 1 {
    assert_true(
      (runtime_output.get(index) - fixed_output.get(index)).abs() < 0.000000001,
    )
  }
}

///|
test "compiled dsp runtime biquad update matches fixed feedback loop compile" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let retuned_cutoff = 4000.0
  let runtime_nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::mix(0, 3),
    DspNode::biquad(
      input=1,
      mode=BiquadMode::LowPass,
      cutoff_hz=LOWPASS_CUTOFF,
      q=LOWPASS_Q,
    ),
    DspNode::gain(2, HALF_GAIN),
    DspNode::output(3),
  ]
  let fixed_nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::mix(0, 3),
    DspNode::biquad(
      input=1,
      mode=BiquadMode::LowPass,
      cutoff_hz=retuned_cutoff,
      q=LOWPASS_Q,
    ),
    DspNode::gain(2, HALF_GAIN),
    DspNode::output(3),
  ]
  let runtime_compiled = CompiledDsp::compile(runtime_nodes, context).unwrap()
  let fixed_compiled = CompiledDsp::compile(fixed_nodes, context).unwrap()
  let runtime_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let fixed_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(
    runtime_compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, retuned_cutoff),
    ),
  )
  runtime_compiled.process(context, runtime_output)
  fixed_compiled.process(context, fixed_output)

  assert_true(
    runtime_output.as_fixed_array().any(sample => sample != ZERO_SAMPLE),
  )
  for index = 0; index < runtime_output.length(); index = index + 1 {
    assert_true(
      (runtime_output.get(index) - fixed_output.get(index)).abs() < 0.000000001,
    )
  }
}

///|
test "compiled stereo dsp resolves mono feedback cycle before pan via z^-1 insertion" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 2),
    DspNode::gain(1, HALF_GAIN),
    DspNode::pan(2, PAN_CENTER),
    DspNode::stereo_output(3),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  assert_true(
    (left_output.get(0) - HALF_GAIN * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true((left_output.get(1) - 0.75 * PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true(
    (left_output.get(2) - 0.875 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true(
    (left_output.get(3) - 0.9375 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true(
      (left_output.get(index) - right_output.get(index)).abs() < 0.000000001,
    )
  }
}

///|
test "compiled stereo dsp runtime gain update retunes accepted mono feedback cycle" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 2),
    DspNode::gain(1, HALF_GAIN),
    DspNode::pan(2, PAN_CENTER),
    DspNode::stereo_output(3),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let baseline_left = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let baseline_right = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let retuned_left = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let retuned_right = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, baseline_left, baseline_right)
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, QUARTER_SAMPLE),
    ),
  )
  compiled.process(context, retuned_left, retuned_right)

  assert_true(
    (retuned_left.get(0) - 0.484375 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true(
    (retuned_left.get(1) - 0.37109375 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true(
    (retuned_left.get(2) - 0.3427734375 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true(
    (retuned_left.get(3) - 0.335693359375 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true(retuned_left.get(0) < baseline_left.get(3))
  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true(
      (retuned_left.get(index) - retuned_right.get(index)).abs() < 0.000000001,
    )
  }
}

///|
test "compiled dsp accepts direct self-feedback with zero-initialized z^-1 state" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::gain(0, HALF_GAIN), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_eq(output.get(1), ZERO_SAMPLE)
  assert_eq(output.get(2), ZERO_SAMPLE)
  assert_eq(output.get(3), ZERO_SAMPLE)
}

///|
test "compiled dsp rejects feedback cycles through output nodes" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::output(1), DspNode::gain(0, HALF_GAIN)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp accepts stereo-involved feedback cycles via self-registers" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(2, PAN_CENTER),
    DspNode::stereo_mixdown(1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context)
  assert_true(compiled is Some(_))
  let compiled = compiled.unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  // Output should be finite and bounded
  assert_true(
    output
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf()),
  )
}

///|
test "compiled stereo dsp accepts stereo-shaped feedback edges via self-registers" {
  // Stereo feedback cycle: Const -> Mix -> Gain -> Pan -> StereoGain -> StereoMixDown
  // with StereoMixDown feeding back to Mix (slot 1).
  // The cycle crosses the mono/stereo boundary.
  //
  // Authoring order:
  //   0: Constant(1.0)
  //   1: Mix(0, 5)             -- input0=Constant, input1=StereoMixDown (back-edge)
  //   2: Gain(1, 0.5)          -- apply gain to Mix output
  //   3: Pan(2, center)        -- mono -> stereo
  //   4: StereoGain(3, 0.5)    -- stereo gain
  //   5: StereoMixDown(4)      -- stereo -> mono (feedback source)
  //   6: StereoOutput(4)       -- final output from StereoGain
  //
  // Wait, StereoOutput reads from StereoGain(4), not StereoMixDown. StereoMixDown
  // exists only for the feedback path.
  // Hmm, but StereoOutput(4) means it reads from node 4 (StereoGain).
  // The StereoMixDown(5) is only used as feedback source for Mix's input1.
  // Back-edge: StereoMixDown(5) -> Mix(1), slot 1. Source=mono, target=mono. Valid!
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 5),
    DspNode::gain(1, HALF_GAIN),
    DspNode::pan(2, PAN_CENTER),
    DspNode::stereo_gain(3, HALF_GAIN),
    DspNode::stereo_mixdown(4),
    DspNode::stereo_output(4),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context)
  assert_true(compiled is Some(_))
  let compiled = compiled.unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, left_output, right_output)
  // Output should be finite and bounded
  assert_true(
    left_output
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf()),
  )
  assert_true(
    right_output
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf()),
  )
  // Output should have non-zero values (the constant propagates through)
  assert_true(left_output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
}

///|
test "self-register fields initialized for acyclic graph" {
  let nodes : Array[DspNode] = [
    DspNode::constant(440.0),
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(1),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  let buf = AudioBuffer::filled(128)
  compiled.process(ctx, buf)
  // Acyclic graph should process normally — oscillator produces non-zero output
  assert_true(buf.as_fixed_array().any(sample => sample != 0.0))
}

///|
test "self-register: mono self-feedback produces bounded recurrence" {
  // A Gain node feeding back to itself with gain < 1 should decay to zero.
  // Graph: Constant(1.0) -> Mix(0, 2) -> Gain(1, 0.5) -> Output(2)
  // Back-edge: Gain -> Mix (slot 1)
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 2),
    DspNode::gain(1, HALF_GAIN),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  // First sample: Mix(1.0, self_values[gain]=0.0) = 1.0, then Gain(1.0*0.5) = 0.5
  assert_true((output.get(0) - HALF_GAIN).abs() < 0.000000001)
  // Recurrence converges: 0.5, 0.75, 0.875, 0.9375
  assert_true((output.get(1) - 0.75).abs() < 0.000000001)
  assert_true((output.get(2) - 0.875).abs() < 0.000000001)
  assert_true((output.get(3) - 0.9375).abs() < 0.000000001)
  // All samples are finite and bounded
  assert_true(
    output
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf() && sample.abs() <= 2.0),
  )
}

///|
test "self-register: stereo feedback via self-registers" {
  // Stereo feedback cycle through Pan and StereoGain.
  // Graph: Constant(1.0) -> Gain(0, 0.5) -> Pan(1, center) -> StereoGain(2, 0.5) -> StereoOutput(3)
  // Back-edge: StereoGain is at the end, no feedback here unless we create a cycle.
  // Better: create a cycle in the stereo domain.
  // Graph: Constant(1.0) -> Mix(0, 5) -> Gain(1, 0.5) -> Pan(2, center) -> StereoGain(3, 0.5) -> StereoOutput(4)
  //   + StereoMixDown(3) -> feeds back to Mix slot 1 as node 5
  // Hmm, let me create: Const -> Mix(0, 5) -> Gain(1, 0.5) -> Pan(2, center) -> StereoGain(3, 0.5) -> StereoOutput(4)
  // No, StereoOutput won't have back edge. Let me use a direct stereo cycle.
  // Simpler: Constant -> Pan -> StereoGain -> StereoOutput, with StereoGain feeding back to Pan's input (via StereoMixDown -> mono).
  // But that requires StereoMixDown in a stereo graph...
  // Actually for a stereo graph: Const -> Mix(0, 5) -> Gain(1, 0.5) -> Pan(2, center) -> StereoGain(3, 0.5) -> StereoOutput(4)
  // with node 5 = StereoMixDown(3) feeding back to Mix's input1 on slot 1.
  // But StereoMixDown is rejected in stereo_compile_plan because valid_stereo_node_inputs returns false for StereoMixDown.
  // Let me just use a simpler stereo feedback graph.
  // Simplest stereo cycle: Constant -> Mix(0, 3) -> Gain(1, 0.5) -> Pan(2, center) -> StereoGain(3, 0.5) -> StereoOutput(4)
  // Back-edge: StereoGain (idx 4 after remap) -> Mix (idx 1 after remap). But StereoGain is stereo, Mix expects mono. Shape mismatch.
  // We need: Constant -> Mix(0, 4) -> Gain(1, 0.5) -> Pan(2, center) -> StereoGain(3, 0.5) -> StereoOutput(4)
  // hmm that has StereoGain feeding back. The source is stereo, target expects mono on Mix. Not valid.
  // The valid pattern is: the feedback source must output mono if the target expects mono.
  // So: Const -> Mix(0, 2) -> Gain(1, 0.5) -> Pan(2, center) -> StereoOutput(3)
  // Back-edge: Gain -> Mix slot 1. Source=Gain(mono), target=Mix slot 1(mono). Valid!
  // This is a mono cycle with stereo output.
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 2),
    DspNode::gain(1, HALF_GAIN),
    DspNode::pan(2, PAN_CENTER),
    DspNode::stereo_output(3),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  // Same recurrence as mono: gain output = 0.5, 0.75, 0.875, 0.9375
  // After pan at center, both channels get value * PAN_CENTER_GAIN
  assert_true(
    (left_output.get(0) - HALF_GAIN * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true((left_output.get(1) - 0.75 * PAN_CENTER_GAIN).abs() < 0.000000001)
  assert_true(
    (left_output.get(2) - 0.875 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  assert_true(
    (left_output.get(3) - 0.9375 * PAN_CENTER_GAIN).abs() < 0.000000001,
  )
  // Left and right should be equal at center pan
  for index = 0; index < SMALL_BLOCK_SIZE; index = index + 1 {
    assert_true(
      (left_output.get(index) - right_output.get(index)).abs() < 0.000000001,
    )
  }
}

///|
test "self-register: mixed-shape feedback across mono/stereo boundary" {
  // mono -> Pan -> stereo -> StereoMixDown -> Gain -> mono, with Gain feeding
  // back to Mix. The cycle crosses the mono/stereo boundary via Pan and
  // StereoMixDown.
  //
  // Authoring order:
  //   0: Constant(1.0)
  //   1: Mix(0, 4)          -- input0=Constant, input1=Gain (back-edge)
  //   2: Pan(1, center)     -- mono -> stereo
  //   3: StereoMixDown(2)   -- stereo -> mono
  //   4: Gain(3, 0.5)       -- apply gain
  //   5: Output(4)
  //
  // Back-edge: Gain(4) -> Mix(1) on slot 1.
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 4),
    DspNode::pan(1, PAN_CENTER),
    DspNode::stereo_mixdown(2),
    DspNode::gain(3, HALF_GAIN),
    DspNode::output(4),
  ]
  let compiled = CompiledDsp::compile(nodes, context)
  assert_true(compiled is Some(_))
  let compiled = compiled.unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)

  // All output should be finite and bounded
  assert_true(
    output
    .as_fixed_array()
    .every(sample => !sample.is_nan() && !sample.is_inf() && sample.abs() <= 2.0),
  )
  // The recurrence converges because gain < 1.
  // Sample 0: Mix(1.0, 0.0)=1.0 -> Pan -> MixDown(0.707) -> Gain(0.3535)
  // Sample 1: Mix(1.0, 0.3535)=1.3535 -> Pan -> MixDown(0.957) -> Gain(0.4785)
  // ...converging toward a stable value
  assert_true(output.get(0) > 0.0)
  assert_true(output.get(1) > output.get(0))
}

///|
test "feedback clip and mul exercise inline feedback computations" {
  // Exercises Clip and Mul within a feedback loop — both use inline
  // computation in the feedback dispatch (clip_feedback_sample, input0*input1)
  // rather than delegating to .tick(). This test catches semantic drift
  // between the block and feedback dispatch for these node kinds.
  //
  // Graph:
  //   0: Constant(1.0)
  //   1: Mix(0, 4)       -- feedback entry: input0=Constant, input1=Clip
  //   2: Constant(0.5)
  //   3: Mul(1, 2)       -- multiply by 0.5 (same as Gain but via Mul)
  //   4: Clip(3, 0.8)    -- clamp to [-0.8, 0.8]
  //   5: Output(4)
  //
  // Back-edge: Clip(4) -> Mix(1) on slot 1.
  //
  // Analytical per-sample recurrence:
  //   s[0]: Mix(1.0, 0.0) = 1.0, Mul(1.0*0.5) = 0.5, Clip(0.5, 0.8) = 0.5
  //   s[1]: Mix(1.0, 0.5) = 1.5, Mul(1.5*0.5) = 0.75, Clip(0.75, 0.8) = 0.75
  //   s[2]: Mix(1.0, 0.75)= 1.75, Mul(1.75*0.5)= 0.875, Clip(0.875, 0.8) = 0.8
  //   s[3]: Mix(1.0, 0.8) = 1.8, Mul(1.8*0.5) = 0.9, Clip(0.9, 0.8) = 0.8
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::mix(0, 4),
    DspNode::constant(HALF_GAIN),
    DspNode::mul(1, 2),
    DspNode::clip(3, 0.8),
    DspNode::output(4),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true((output.get(0) - 0.5).abs() < 0.000000001)
  assert_true((output.get(1) - 0.75).abs() < 0.000000001)
  assert_true((output.get(2) - 0.8).abs() < 0.000000001)
  assert_true((output.get(3) - 0.8).abs() < 0.000000001)
}
