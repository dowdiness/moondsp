///|
/// Shared graph-test constants reduce repetition, but a wrong edit here can
/// affect multiple test expectations at once. Keep values local when they only
/// matter to a single case.
const STANDARD_SAMPLE_RATE : Double = 48000.0

///|
const ADSR_TEST_SAMPLE_RATE : Double = 1000.0

///|
const SMALL_BLOCK_SIZE : Int = 4

///|
const LARGE_BLOCK_SIZE : Int = 8

///|
const OSCILLATOR_FREQ : Double = 440.0

///|
const NOISE_SEED : UInt = 123U

///|
const UNIT_SAMPLE : Double = 1.0

///|
const ZERO_SAMPLE : Double = 0.0

///|
const QUARTER_SAMPLE : Double = 0.25

///|
const NEGATIVE_MIX_SAMPLE : Double = -0.1

///|
const MIXED_SAMPLE : Double = 0.15

///|
const HALF_GAIN : Double = 0.5

///|
const CLIP_THRESHOLD : Double = 0.2

///|
const LOWPASS_CUTOFF : Double = 1000.0

///|
const LOWPASS_Q : Double = 0.707

///|
const INVALID_NYQUIST_CUTOFF : Double = 24000.0

///|
const ADSR_ATTACK_MS : Double = 1.0

///|
const ADSR_DECAY_MS : Double = 1.0

///|
const ADSR_SUSTAIN_LEVEL : Double = 0.25

///|
const ADSR_RELEASE_MS : Double = 2.0

///|
const DELAY_CAPACITY : Int = 4

///|
const DELAY_SAMPLES : Int = 2

///|
const DELAY_SAMPLES_DOUBLE : Double = 2.0

///|
test "compiled dsp renders a constant graph" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
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
  let context = DspContext::new(ADSR_TEST_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::output(1),
    DspNode::mul(3, 2),
    DspNode::adsr(
      ADSR_ATTACK_MS,
      ADSR_DECAY_MS,
      ADSR_SUSTAIN_LEVEL,
      ADSR_RELEASE_MS,
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
  let valid_context = DspContext::new(ADSR_TEST_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let invalid_context = DspContext::new(ZERO_SAMPLE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::output(1),
    DspNode::mul(3, 2),
    DspNode::adsr(
      ADSR_ATTACK_MS,
      ADSR_DECAY_MS,
      ADSR_SUSTAIN_LEVEL,
      ADSR_RELEASE_MS,
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::biquad(0, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
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
test "compiled dsp rejects invalid biquad parameters" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::biquad(0, BiquadMode::LowPass, INVALID_NYQUIST_CUTOFF, LOWPASS_Q),
    DspNode::output(1),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp topologically sorts declarative filter graph" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
  let nodes = [
    DspNode::output(1),
    DspNode::biquad(2, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
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
test "compiled dsp applies delay line in graph across blocks" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp delay node keeps zero-capacity default as passthrough" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp runtime param update changes gain output" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp runtime param update rejects unsupported or invalid values" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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

  compiled.process(context, output)

  assert_eq(output.get(0), UNIT_SAMPLE)
  assert_eq(output.get(1), UNIT_SAMPLE)
  assert_eq(output.get(2), UNIT_SAMPLE)
  assert_eq(output.get(3), UNIT_SAMPLE)
}

///|
test "compiled dsp runtime param update rejects invalid biquad values" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::biquad(0, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
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
  let context = DspContext::new(ADSR_TEST_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::output(1),
    DspNode::mul(3, 2),
    DspNode::adsr(
      ADSR_ATTACK_MS,
      ADSR_DECAY_MS,
      ADSR_SUSTAIN_LEVEL,
      ADSR_RELEASE_MS,
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
test "compiled dsp rejects non-finite adsr parameters" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::adsr(0.0 / 0.0, ADSR_DECAY_MS, HALF_GAIN, 10.0),
    DspNode::output(0),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects non-finite constants" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nan_nodes = [DspNode::constant(0.0 / 0.0), DspNode::output(0)]
  let inf_nodes = [DspNode::constant(1.0 / 0.0), DspNode::output(0)]

  assert_true(CompiledDsp::compile(nan_nodes, context) is None)
  assert_true(CompiledDsp::compile(inf_nodes, context) is None)
}

///|
test "compiled dsp silences when runtime block exceeds compiled capacity" {
  let compile_context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let runtime_context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
  let nodes = [DspNode::constant(QUARTER_SAMPLE), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, compile_context).unwrap()
  let output = AudioBuffer::filled(LARGE_BLOCK_SIZE, init=UNIT_SAMPLE)

  compiled.process(runtime_context, output)

  assert_true(output.as_fixed_array().every(sample => sample == ZERO_SAMPLE))
}

///|
test "compiled dsp topologically sorts declarative node order" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp rejects cycles" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [DspNode::output(1), DspNode::gain(0, HALF_GAIN)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects graphs without a final output node" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [DspNode::constant(QUARTER_SAMPLE)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp rejects multiple output nodes" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(QUARTER_SAMPLE),
    DspNode::output(0),
    DspNode::output(0),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}
