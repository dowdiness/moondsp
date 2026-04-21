///|
test "compiled dsp renders a constant graph" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::constant(QUARTER_SAMPLE), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), QUARTER_SAMPLE)
  assert_eq(output.get(1), QUARTER_SAMPLE)
  assert_eq(output.get(2), QUARTER_SAMPLE)
  assert_eq(output.get(3), QUARTER_SAMPLE)
}

///|
test "compiled dsp renders an oscillator gain clip chain" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::gain(0, HALF_GAIN),
    DspNode::clip(1, CLIP_THRESHOLD),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_true(output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
  assert_true(
    output
    .as_fixed_array()
    .every(sample => sample >= -CLIP_THRESHOLD && sample <= CLIP_THRESHOLD),
  )
}

///|
test "compiled dsp mixes two constants" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(QUARTER_SAMPLE),
    DspNode::constant(NEGATIVE_MIX_SAMPLE),
    DspNode::mix(0, 1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), MIXED_SAMPLE)
  assert_eq(output.get(1), MIXED_SAMPLE)
  assert_eq(output.get(2), MIXED_SAMPLE)
  assert_eq(output.get(3), MIXED_SAMPLE)
}

///|
test "compiled dsp noise graph stays bounded and non-zero" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [DspNode::noise(NOISE_SEED), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true(output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
  assert_true(
    output
    .as_fixed_array()
    .every(sample => sample >= -UNIT_SAMPLE && sample <= UNIT_SAMPLE),
  )
}

///|
test "compiled dsp applies adsr envelope through multiply" {
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

  assert_true(compiled.apply_control(GraphControl::gate_on(2)))
  compiled.process(context, output)

  assert_eq(output.get(0), UNIT_SAMPLE)
  assert_eq(output.get(1), ADSR_SUSTAIN_LEVEL)
  assert_eq(output.get(2), ADSR_SUSTAIN_LEVEL)
  assert_eq(output.get(3), ADSR_SUSTAIN_LEVEL)

  assert_true(compiled.apply_control(GraphControl::gate_off(2)))
  compiled.process(context, output)

  assert_eq(output.get(0), 0.125)
  assert_eq(output.get(1), ZERO_SAMPLE)
  assert_eq(output.get(2), ZERO_SAMPLE)
  assert_eq(output.get(3), ZERO_SAMPLE)
}

///|
test "compiled dsp resets adsr state on invalid context" {
  let valid_context = DspContext::new(
    sample_rate=ADSR_TEST_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let invalid_context = DspContext::new(
    sample_rate=ZERO_SAMPLE,
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
  let compiled = CompiledDsp::compile(nodes, valid_context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  assert_true(compiled.apply_control(GraphControl::gate_on(2)))
  compiled.process(valid_context, output)
  compiled.process(invalid_context, output)
  compiled.process(valid_context, output)

  assert_true(output.as_fixed_array().every(sample => sample == ZERO_SAMPLE))
}

///|
test "compiled dsp applies low-pass biquad in graph" {
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

  assert_true(output.get(0) > ZERO_SAMPLE)
  assert_true(output.get(0) < UNIT_SAMPLE)
  assert_true(output.get(1) > output.get(0))
  assert_true(output.get(2) > output.get(1))
  assert_true(output.get(7) < UNIT_SAMPLE)
}

///|
test "compiled dsp applies delay line in graph across blocks" {
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
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_eq(output.get(1), ZERO_SAMPLE)
  assert_eq(output.get(2), UNIT_SAMPLE)
  assert_eq(output.get(3), UNIT_SAMPLE)

  compiled.process(context, output)

  assert_eq(output.get(0), UNIT_SAMPLE)
  assert_eq(output.get(1), UNIT_SAMPLE)
  assert_eq(output.get(2), UNIT_SAMPLE)
  assert_eq(output.get(3), UNIT_SAMPLE)
}

///|
test "compiled dsp silences when runtime block exceeds compiled capacity" {
  let compile_context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let runtime_context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [DspNode::constant(QUARTER_SAMPLE), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, compile_context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE, init=UNIT_SAMPLE)

  compiled.process(runtime_context, output)

  assert_true(output.as_fixed_array().every(sample => sample == ZERO_SAMPLE))
}

///|
test "compiled dsp: oscillator reads frequency from input buffer" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(OSCILLATOR_FREQ),
    DspNode::oscillator_from(0, Waveform::Sine),
    DspNode::output(1),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)

  compiled.process(context, output)

  assert_eq(output.get(0), ZERO_SAMPLE)
  assert_true(output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
}

///|
test "compiled dsp: FM oscillator with modulated frequency" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=LARGE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 2.0),
    DspNode::constant(300.0),
    DspNode::gain(0, 100.0),
    DspNode::mix(2, 1),
    DspNode::oscillator_from(3, Waveform::Sine),
    DspNode::output(4),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE)

  compiled.process(context, output)

  assert_true(output.as_fixed_array().any(sample => sample != ZERO_SAMPLE))
}

///|
test "process: clean graph has zero sanitized count" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::output(0),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  assert_eq(compiled.last_sanitized_count(), 0)
}

///|
test "process: NaN constant is rejected at compile time" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::constant(@double.not_a_number), DspNode::output(0)]
  // NaN constants are caught by validation — compile returns None
  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "process: last_sanitized_count resets each call" {
  let context = DspContext::new(
    sample_rate=STANDARD_SAMPLE_RATE,
    block_size=SMALL_BLOCK_SIZE,
  )
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(SMALL_BLOCK_SIZE)
  compiled.process(context, output)
  assert_eq(compiled.last_sanitized_count(), 0)
  // Second call also returns 0
  compiled.process(context, output)
  assert_eq(compiled.last_sanitized_count(), 0)
}
