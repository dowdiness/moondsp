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
const DELAY_FEEDBACK : Double = 0.5

///|
const CLAMPED_HIGH_DELAY_FEEDBACK : Double = 0.995

///|
const CLAMPED_LOW_DELAY_FEEDBACK : Double = -0.995

///|
const INVALID_DELAY_FEEDBACK : Double = 1.0

///|
const PAN_HARD_LEFT : Double = -1.0

///|
const PAN_CENTER : Double = 0.0

///|
const PAN_HARD_RIGHT : Double = 1.0

///|
const PAN_CENTER_GAIN : Double = 0.7071067811865476

///|
const STEREO_CLIP_THRESHOLD : Double = 0.25

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
test "compiled dsp rejects implicit stereo to mono output" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [
    DspNode::constant(UNIT_SAMPLE),
    DspNode::pan(0, PAN_CENTER),
    DspNode::output(1),
  ]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp folds stereo graph back to mono output" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled stereo dsp pans mono input to stereo output" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled stereo dsp rejects mono direct to stereo output" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [DspNode::constant(UNIT_SAMPLE), DspNode::stereo_output(0)]

  assert_true(CompiledStereoDsp::compile(nodes, context) is None)
}

///|
test "compiled stereo dsp rejects stereo post processing after pan" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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

///|
test "compiled stereo dsp applies stereo gain after pan" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp rejects stereo-only nodes" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled graphs reject delay feedback outside live supported range" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled stereo dsp apply_control updates pan position" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp applies mixed control batches in order" {
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp set_param wrapper matches apply_control" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp resolves simple mono feedback cycle via z^-1 insertion" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let retuned_cutoff = 4000.0
  let runtime_nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::mix(0, 3),
    DspNode::biquad(1, BiquadMode::LowPass, LOWPASS_CUTOFF, LOWPASS_Q),
    DspNode::gain(2, HALF_GAIN),
    DspNode::output(3),
  ]
  let fixed_nodes = [
    DspNode::oscillator(Waveform::Sine, OSCILLATOR_FREQ),
    DspNode::mix(0, 3),
    DspNode::biquad(1, BiquadMode::LowPass, retuned_cutoff, LOWPASS_Q),
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [DspNode::output(1), DspNode::gain(0, HALF_GAIN)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
}

///|
test "compiled dsp accepts stereo-involved feedback cycles via self-registers" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp: oscillator reads frequency from input buffer" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, LARGE_BLOCK_SIZE)
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
test "compiled dsp rejects graphs without a final output node" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
  let nodes = [DspNode::constant(QUARTER_SAMPLE)]

  assert_true(CompiledDsp::compile(nodes, context) is None)
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
  let ctx = DspContext::new(48000.0, 128)
  let compiled = CompiledDsp::compile(nodes, ctx)
  assert_true(compiled is Some(_))
  // Process and verify output = 12.0 (constant)
  let compiled = compiled.unwrap()
  let buf = AudioBuffer::filled(128)
  compiled.process(ctx, buf)
  assert_eq(buf.get(0), 12.0)
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

///|
test "self-register fields initialized for acyclic graph" {
  let nodes : Array[DspNode] = [
    DspNode::constant(440.0),
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(1),
  ]
  let ctx = DspContext::new(48000.0, 128)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "compiled dsp rejects negative delay_samples via set_param" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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

///|
test "compiled stereo dsp rejects out-of-bounds delay_samples via set_param" {
  let context = DspContext::new(STANDARD_SAMPLE_RATE, SMALL_BLOCK_SIZE)
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
test "node_accepts_slot: Constant accepts Value0" {
  let node = DspNode::constant(1.0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: Constant rejects Value1" {
  let node = DspNode::constant(1.0)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Biquad accepts Value0 and Value1" {
  let node = DspNode::biquad(0, BiquadMode::LowPass, 1000.0, 0.707)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_true(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Delay accepts Value0 and DelaySamples" {
  let node = DspNode::delay(0, 128, delay_samples=0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_true(node_accepts_slot(node, GraphParamSlot::DelaySamples))
  assert_false(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Output rejects all slots" {
  let node = DspNode::output(0)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_false(node_accepts_slot(node, GraphParamSlot::DelaySamples))
}

///|
test "node_accepts_slot: FM oscillator rejects Value0" {
  let node = DspNode::oscillator_from(0, Waveform::Sine)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: non-FM oscillator accepts Value0" {
  let node = DspNode::oscillator(Waveform::Sine, 440.0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
}
