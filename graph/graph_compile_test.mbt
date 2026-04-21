///|
test "compiled dsp rejects implicit stereo to mono output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::output(1),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects stereo-only nodes" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let stereo_gain_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::stereo_gain(0, HALF_GAIN),
    DspNode::output(1),
  ]
  let stereo_clip_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::stereo_clip(0, STEREO_CLIP_THRESHOLD),
    DspNode::output(1),
  ]
  let stereo_biquad_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::stereo_biquad(0, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
    DspNode::output(1),
  ]
  let stereo_delay_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::stereo_delay(0, DELAY_CAPACITY, delay_samples=DELAY_SAMPLES),
    DspNode::output(1),
  ]

  assert_true(CompiledDsp::compile(stereo_gain_nodes, context) is None)
  assert_true(CompiledDsp::compile(stereo_clip_nodes, context) is None)
  assert_true(CompiledDsp::compile(stereo_biquad_nodes, context) is None)
  assert_true(CompiledDsp::compile(stereo_delay_nodes, context) is None)
}

///|
test "compiled dsp rejects non-finite adsr parameters" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::adsr(
      attack_ms=0.0 / 0.0,
      decay_ms=ADSR_DECAY_MS,
      sustain=HALF_GAIN,
      release_ms=10.0,
    ),
    DspNode::output(0),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects non-finite constants" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nan_nodes = [DspNode::constant(0.0 / 0.0), DspNode::output(0)]
  let inf_nodes = [DspNode::constant(1.0 / 0.0), DspNode::output(0)]

  assert_true(CompiledDsp::compile(nan_nodes, context) is None)
  assert_true(CompiledDsp::compile(inf_nodes, context) is None)
}

///|
test "compiled dsp rejects graphs without a final output node" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::constant(QUARTER_SAMPLE)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects multiple output nodes" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(QUARTER_SAMPLE),
    DspNode::output(0),
    DspNode::output(0),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects invalid biquad parameters" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::biquad(
      input=0,
      mode=BiquadMode::LowPass,
      cutoff_hz=INVALID_NYQUIST_CUTOFF,
      q=LOWPASS_Q,
    ),
    DspNode::output(1),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp topologically sorts declarative filter graph" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::output(1),
    DspNode::biquad(
      input=2,
      mode=BiquadMode::LowPass,
      cutoff_hz=LOWPASS_CUTOFF,
      q=LOWPASS_Q,
    ),
    DspNode::constant(UNIT_SAMPLE),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true(output.get(0) > ZERO_SAMPLE)
  assert_true(output.get(0) < UNIT_SAMPLE)
  assert_true(output.get(7) < UNIT_SAMPLE)
}

///|
test "compiled dsp topologically sorts declarative node order" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::output(1),
    DspNode::gain(2, HALF_GAIN),
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_true(output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
  assert_true(
    output
    .as_fixed_array()
    .every(sample => sample >= -HALF_GAIN && sample <= HALF_GAIN),
  )
}

///|
test "compiled dsp optimizes constant subgraph during compilation" {
  // Build: Constant(3) * Constant(4) -> Output
  // After optimization: Constant(12) -> Output (only 2 nodes to compile)
  let nodes : Array[DspNode] = [
    DspNode::constant(3.0),
    DspNode::constant(4.0),
    DspNode::mul(0, 1),
    DspNode::output(2),
  ]
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled = CompiledDsp::compile(nodes, ctx)
  assert_true(compiled is Some(_))
  // Process and verify output = 12.0 (constant)
  let compiled = compiled.unwrap()
  let buf = AudioBuffer::filled(128)
  compiled.process(ctx, buf)
  assert_eq(buf.get(0), 12.0)
}

///|
test "compiled dsp delay node keeps zero-capacity default as passthrough" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(QUARTER_SAMPLE),
    DspNode::delay(0, 0),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), QUARTER_SAMPLE)
  assert_eq(output.get(1), QUARTER_SAMPLE)
  assert_eq(output.get(2), QUARTER_SAMPLE)
  assert_eq(output.get(3), QUARTER_SAMPLE)
}

///|
test "compiled graphs reject delay feedback outside live supported range" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let mono_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::delay(
      0,
      DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
      feedback=CLAMPED_HIGH_DELAY_FEEDBACK,
    ),
    DspNode::output(1),
  ]
  let stereo_nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_delay(
      1,
      DELAY_CAPACITY,
      delay_samples=DELAY_SAMPLES,
      feedback=CLAMPED_LOW_DELAY_FEEDBACK,
    ),
    DspNode::stereo_output(2),
  ]

  assert_true(CompiledDsp::compile(mono_nodes, context) is None)
  assert_true(CompiledStereoDsp::compile(stereo_nodes, context) is None)
}

///|
test "compiled stereo dsp rejects mono direct to stereo output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::constant(UNIT_SAMPLE), DspNode::stereo_output(0)]

  assert_true(CompiledStereoDsp::compile(nodes, context) is None)
}

///|
test "compiled stereo dsp rejects stereo post processing after pan" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_HARD_LEFT),
    DspNode::gain(1, HALF_GAIN),
    DspNode::stereo_output(2),
  ]

  assert_true(CompiledStereoDsp::compile(nodes, context) is None)
}

///|
test "compiled stereo dsp rejects stereo mixdown before stereo output" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_mixdown(1),
    DspNode::stereo_output(2),
  ]

  assert_true(CompiledStereoDsp::compile(nodes, context) is None)
}

///|
test "compiled stereo dsp rejects internal stereo mixdown roundtrip" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::stereo_mixdown(1),
    DspNode::gain(2, HALF_GAIN),
    DspNode::pan(3, PAN_CENTER),
    DspNode::stereo_output(4),
  ]

  assert_true(CompiledStereoDsp::compile(nodes, context) is None)
}
