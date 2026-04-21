///|
const GRAPH_VOICE_SAMPLE_RATE : Double = 1000.0

///|
const GRAPH_VOICE_BLOCK_SIZE : Int = 8

///|
const GRAPH_VOICE_FREQ : Double = 125.0

///|
const GRAPH_VOICE_CUTOFF : Double = 120.0

///|
const GRAPH_VOICE_Q : Double = 0.707

///|
const GRAPH_VOICE_GAIN : Double = 0.8

///|
const GRAPH_VOICE_CLIP : Double = 0.35

///|
const GRAPH_VOICE_SUSTAIN : Double = 0.5

///|
const GRAPH_VOICE_RELEASE_MS : Double = 2.0

///|
const GRAPH_VOICE_DELAY_CAPACITY : Int = 4

///|
const GRAPH_VOICE_DELAY_SAMPLES : Int = 2

///|
const GRAPH_VOICE_DELAY_SAMPLES_DOUBLE : Double = 2.0

///|
const GRAPH_VOICE_RELEASE_TAIL_LIMIT : Double = 0.001

///|
const GRAPH_FEEDBACK_SAMPLE_RATE : Double = 1000.0

///|
const GRAPH_FEEDBACK_BLOCK_SIZE : Int = 8

///|
const GRAPH_FEEDBACK_GAIN : Double = 0.5

///|
const GRAPH_FEEDBACK_RETUNED_GAIN : Double = 0.25

///|
const GRAPH_FEEDBACK_RETUNED_CONSTANT : Double = 2.0

///|
const GRAPH_MULTI_SOURCE_SAMPLE_RATE : Double = 48000.0

///|
const GRAPH_MULTI_SOURCE_BLOCK_SIZE : Int = 16

///|
const GRAPH_MULTI_SOURCE_OSC_FREQ : Double = 220.0

///|
const GRAPH_MULTI_SOURCE_NOISE_SEED : UInt = 456U

///|
const GRAPH_MULTI_SOURCE_NOISE_GAIN : Double = 0.2

///|
const GRAPH_MULTI_SOURCE_CUTOFF : Double = 500.0

///|
const GRAPH_MULTI_SOURCE_RETUNED_CUTOFF : Double = 4000.0

///|
const GRAPH_MULTI_SOURCE_Q : Double = 0.707

///|
const GRAPH_MULTI_SOURCE_OUTPUT_GAIN : Double = 0.6

///|
const GRAPH_MULTI_SOURCE_CLIP : Double = 0.5

///|
const GRAPH_STEREO_SAMPLE_RATE : Double = 48000.0

///|
const GRAPH_STEREO_BLOCK_SIZE : Int = 16

///|
const GRAPH_STEREO_FREQ : Double = 330.0

///|
const GRAPH_STEREO_GAIN : Double = 0.6

///|
const GRAPH_STEREO_BATCH_GAIN : Double = 0.3

///|
const GRAPH_STEREO_POST_GAIN : Double = 0.8

///|
const GRAPH_STEREO_CLIP : Double = 0.2

///|
const GRAPH_STEREO_CENTER : Double = 0.0

///|
const GRAPH_STEREO_HARD_LEFT : Double = -1.0

///|
const GRAPH_STEREO_HARD_RIGHT : Double = 1.0

///|
const GRAPH_STEREO_FILTER_INITIAL_CUTOFF : Double = 180.0

///|
const GRAPH_STEREO_FILTER_RETUNED_CUTOFF : Double = 4000.0

///|
const GRAPH_STEREO_FILTER_Q : Double = 0.707

///|
const GRAPH_STEREO_DELAY_CAPACITY : Int = 8

///|
const GRAPH_STEREO_DELAY_SAMPLES : Int = 4

///|
const GRAPH_STEREO_DELAY_FEEDBACK : Double = 0.5

///|
const GRAPH_STEREO_CENTER_GAIN : Double = 0.7071067811865476

///|
const INTEGRATION_BUFFER_EPSILON : Double = 0.000000000001

///|
const GRAPH_HIGHPASS_SAMPLE_RATE : Double = 48000.0

///|
const GRAPH_HIGHPASS_BLOCK_SIZE : Int = 32

///|
const GRAPH_HIGHPASS_FREQ : Double = 220.0

///|
const GRAPH_HIGHPASS_INITIAL_CUTOFF : Double = 2000.0

///|
const GRAPH_HIGHPASS_RETUNED_CUTOFF : Double = 100.0

///|
const GRAPH_HIGHPASS_Q : Double = 0.707

///|
const GRAPH_HIGHPASS_CLIP : Double = 0.9

///|
const GRAPH_BANDPASS_SAMPLE_RATE : Double = 48000.0

///|
const GRAPH_BANDPASS_BLOCK_SIZE : Int = 32

///|
const GRAPH_BANDPASS_FREQ : Double = 440.0

///|
const GRAPH_BANDPASS_INITIAL_CUTOFF : Double = 2000.0

///|
const GRAPH_BANDPASS_RETUNED_CUTOFF : Double = 440.0

///|
const GRAPH_BANDPASS_Q : Double = 1.2

///|
const GRAPH_BANDPASS_CLIP : Double = 0.9

///|
test "voice chain stays bounded across note on and release" {
  let context = DspContext::new(sample_rate=48000.0, block_size=16)
  let osc = Oscillator::new()
  let env = Adsr::new(attack_ms=0.0, decay_ms=0.0, sustain=0.5, release_ms=5.0)
  let filter = Biquad::new()
  let gain = Gain::new()
  let delay = DelayLine::new(4, delay_samples=2)
  let clip = Clip::new()
  let signal = AudioBuffer::filled(16)
  let envelope = AudioBuffer::filled(16)

  assert_true(filter.update(context, BiquadMode::LowPass, 1200.0, 0.707))

  env.gate_on()
  osc.process_waveform(context, signal, Waveform::Saw, 220.0)
  env.process(context, envelope)
  integration_apply_modulation(signal, envelope)
  filter.process(context, signal)
  gain.process(context, signal, 0.8)

  assert_true(integration_buffer_is_finite_and_bounded(signal, 1.0))
  assert_true(integration_any_non_zero(signal))

  delay.process(context, signal)

  assert_true(integration_buffer_is_finite_and_bounded(signal, 1.0))
  clip.process(context, signal, 0.35)

  assert_true(integration_buffer_is_finite_and_bounded(signal, 0.35))
  assert_true(integration_any_non_zero(signal))
  assert_true(env.stage() is EnvStage::Sustain)

  env.gate_off()
  osc.process_waveform(context, signal, Waveform::Saw, 220.0)
  env.process(context, envelope)
  integration_apply_modulation(signal, envelope)
  filter.process(context, signal)
  gain.process(context, signal, 0.8)

  assert_true(integration_buffer_is_finite_and_bounded(signal, 1.0))
  assert_true(integration_any_non_zero(signal))

  delay.process(context, signal)

  assert_true(integration_buffer_is_finite_and_bounded(signal, 1.0))
  clip.process(context, signal, 0.35)

  assert_true(integration_buffer_is_finite_and_bounded(signal, 0.35))
  assert_true(env.stage() is EnvStage::Release)
}

///|
test "mixed oscillator and noise buses remain finite and bounded" {
  let context = DspContext::new(sample_rate=48000.0, block_size=16)
  let osc = Oscillator::new()
  let noise = Noise::new(123U)
  let smoother = ParamSmoother::from_context(0.0, 1.0, context)
  let mix = Mix::new()
  let clip = Clip::new()
  let filter = Biquad::new()
  let tone = AudioBuffer::filled(16)
  let noise_bus = AudioBuffer::filled(16)

  assert_true(filter.update(context, BiquadMode::HighPass, 800.0, 0.707))

  osc.process_waveform(context, tone, Waveform::Triangle, 110.0)
  let tone_before_mix = integration_copy_samples(tone)
  noise.process(context, noise_bus)
  filter.process(context, noise_bus)

  smoother.set_target(0.5)
  integration_apply_smoothed_gain(noise_bus, smoother)

  assert_true(integration_buffer_is_finite_and_bounded(noise_bus, 1.0))
  assert_true(integration_any_non_zero(noise_bus))

  mix.process(context, tone, noise_bus)
  assert_true(integration_buffer_is_finite_and_bounded(tone, 2.0))
  assert_true(
    integration_buffer_differs_from_fixed_array(tone, tone_before_mix),
  )
  clip.process(context, tone, 0.75)

  assert_true(integration_buffer_is_finite_and_bounded(tone, 0.75))
  assert_true(integration_any_non_zero(tone))
  assert_true(smoother.current() > 0.0)
  assert_true(smoother.current() < 0.5)
}

///|
test "stereo voice path with pan stays balanced and bounded" {
  let context = DspContext::new(sample_rate=48000.0, block_size=16)
  let osc = Oscillator::new()
  let env = Adsr::new(attack_ms=0.0, decay_ms=0.0, sustain=0.6, release_ms=10.0)
  let filter = Biquad::new()
  let gain = Gain::new()
  let pan = Pan::new()
  let left_clip = Clip::new()
  let right_clip = Clip::new()
  let mono = AudioBuffer::filled(16)
  let envelope = AudioBuffer::filled(16)
  let left = AudioBuffer::filled(16)
  let right = AudioBuffer::filled(16)

  assert_true(filter.update(context, BiquadMode::BandPass, 900.0, 0.9))

  env.gate_on()
  osc.process_waveform(context, mono, Waveform::Triangle, 330.0)
  env.process(context, envelope)
  integration_apply_modulation(mono, envelope)
  filter.process(context, mono)
  gain.process(context, mono, 0.8)

  assert_true(integration_buffer_is_finite_and_bounded(mono, 1.0))
  assert_true(integration_any_non_zero(mono))

  pan.process(context, mono, left, right, 0.0)

  assert_true(integration_buffer_is_finite_and_bounded(left, 1.0))
  assert_true(integration_buffer_is_finite_and_bounded(right, 1.0))
  assert_true(integration_any_non_zero(left))
  assert_true(integration_any_non_zero(right))
  assert_true(integration_buffers_close(left, right, 0.000000001))

  left_clip.process(context, left, 0.4)
  right_clip.process(context, right, 0.4)

  assert_true(integration_buffer_is_finite_and_bounded(left, 0.4))
  assert_true(integration_buffer_is_finite_and_bounded(right, 0.4))
}

///|
test "compiled stereo graph voice path responds to runtime pan updates" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_STEREO_FREQ),
    DspNode::gain(0, GRAPH_STEREO_GAIN),
    DspNode::pan(1, GRAPH_STEREO_CENTER),
    DspNode::stereo_gain(2, GRAPH_STEREO_POST_GAIN),
    DspNode::stereo_clip(3, GRAPH_STEREO_CLIP),
    DspNode::stereo_output(4),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  compiled.process(context, left_output, right_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(left_output, GRAPH_STEREO_CLIP),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(right_output, GRAPH_STEREO_CLIP),
  )
  assert_true(integration_any_non_zero(left_output))
  assert_true(integration_any_non_zero(right_output))
  assert_true(
    integration_buffers_close(
      left_output,
      right_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(2, GraphParamSlot::Value0, GRAPH_STEREO_HARD_LEFT),
    ),
  )
  compiled.process(context, left_output, right_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(left_output, GRAPH_STEREO_CLIP),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(right_output, GRAPH_STEREO_CLIP),
  )
  assert_true(integration_any_non_zero(left_output))
  assert_true(right_output.as_fixed_array().every(sample => sample == 0.0))
  assert_true(
    integration_abs_sum(left_output) > integration_abs_sum(right_output),
  )
}

///|
test "compiled stereo graph applies batched control frames" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_STEREO_FREQ),
    DspNode::gain(0, GRAPH_STEREO_GAIN),
    DspNode::pan(1, GRAPH_STEREO_CENTER),
    DspNode::stereo_gain(2, GRAPH_STEREO_POST_GAIN),
    DspNode::stereo_clip(3, GRAPH_STEREO_CLIP),
    DspNode::stereo_output(4),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let left_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let right_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(
        1,
        GraphParamSlot::Value0,
        GRAPH_STEREO_BATCH_GAIN,
      ),
      GraphControl::set_param(2, GraphParamSlot::Value0, GRAPH_STEREO_HARD_LEFT),
      GraphControl::set_param(3, GraphParamSlot::Value0, HALF_GAIN),
    ]),
  )
  compiled.process(context, left_output, right_output)

  assert_true(integration_buffer_is_finite_and_bounded(left_output, HALF_GAIN))
  assert_true(integration_buffer_is_finite_and_bounded(right_output, HALF_GAIN))
  assert_true(integration_any_non_zero(left_output))
  assert_true(right_output.as_fixed_array().every(sample => sample == 0.0))
  assert_true(
    integration_abs_sum(left_output) > integration_abs_sum(right_output),
  )

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(2, GraphParamSlot::Value0, GRAPH_STEREO_CENTER),
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        GRAPH_STEREO_HARD_RIGHT,
      ),
      GraphControl::set_param(4, GraphParamSlot::Value0, GRAPH_STEREO_CLIP),
    ]),
  )
  compiled.process(context, left_output, right_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(left_output, GRAPH_STEREO_CLIP),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(right_output, GRAPH_STEREO_CLIP),
  )
  assert_true(left_output.as_fixed_array().every(sample => sample == 0.0))
  assert_true(integration_any_non_zero(right_output))
  assert_true(
    integration_abs_sum(right_output) > integration_abs_sum(left_output),
  )
}

///|
test "compiled stereo graph stereo biquad retune changes output" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let baseline_nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_STEREO_FREQ),
    DspNode::pan(0, GRAPH_STEREO_CENTER),
    DspNode::stereo_biquad(
      1,
      BiquadMode::LowPass,
      GRAPH_STEREO_FILTER_INITIAL_CUTOFF,
      GRAPH_STEREO_FILTER_Q,
    ),
    DspNode::stereo_gain(2, GRAPH_STEREO_POST_GAIN),
    DspNode::stereo_clip(3, GRAPH_STEREO_CLIP),
    DspNode::stereo_output(4),
  ]
  let baseline = CompiledStereoDsp::compile(baseline_nodes, context).unwrap()
  let retuned = CompiledStereoDsp::compile(baseline_nodes, context).unwrap()
  let baseline_left = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let baseline_right = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let retuned_left = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let retuned_right = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  baseline.process(context, baseline_left, baseline_right)
  retuned.process(context, retuned_left, retuned_right)

  assert_true(integration_any_non_zero(baseline_left))
  assert_true(integration_any_non_zero(retuned_left))
  assert_true(
    integration_buffers_close(
      baseline_left,
      baseline_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_buffers_close(
      retuned_left,
      retuned_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )

  assert_true(
    retuned.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        GRAPH_STEREO_FILTER_RETUNED_CUTOFF,
      ),
    ),
  )
  retuned.process(context, retuned_left, retuned_right)

  assert_true(
    integration_buffer_is_finite_and_bounded(baseline_left, GRAPH_STEREO_CLIP),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(retuned_left, GRAPH_STEREO_CLIP),
  )
  assert_false(
    integration_buffers_close(
      baseline_left,
      retuned_left,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_abs_sum(retuned_left) > integration_abs_sum(baseline_left),
  )
}

///|
test "compiled stereo graph stereo delay retune changes output" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::pan(0, GRAPH_STEREO_CENTER),
    DspNode::stereo_delay(
      1,
      GRAPH_STEREO_DELAY_CAPACITY,
      delay_samples=GRAPH_STEREO_DELAY_SAMPLES,
    ),
    DspNode::stereo_output(2),
  ]
  let baseline = CompiledStereoDsp::compile(nodes, context).unwrap()
  let retuned = CompiledStereoDsp::compile(nodes, context).unwrap()
  let baseline_left = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let baseline_right = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let retuned_left = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let retuned_right = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  baseline.process(context, baseline_left, baseline_right)
  assert_true(
    retuned.apply_control(
      GraphControl::set_param(2, GraphParamSlot::DelaySamples, 0.0),
    ),
  )
  retuned.process(context, retuned_left, retuned_right)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      baseline_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      retuned_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffers_close(
      baseline_left,
      baseline_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_buffers_close(
      retuned_left,
      retuned_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_false(
    integration_buffers_close(
      baseline_left,
      retuned_left,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_abs_sum(retuned_left) > integration_abs_sum(baseline_left),
  )
}

///|
test "compiled stereo graph stereo delay feedback increases tail energy" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::pan(0, GRAPH_STEREO_CENTER),
    DspNode::stereo_delay(
      1,
      GRAPH_STEREO_DELAY_CAPACITY,
      delay_samples=GRAPH_STEREO_DELAY_SAMPLES,
    ),
    DspNode::stereo_output(2),
  ]
  let baseline = CompiledStereoDsp::compile(nodes, context).unwrap()
  let retuned = CompiledStereoDsp::compile(nodes, context).unwrap()
  let baseline_left = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let baseline_right = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let retuned_left = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let retuned_right = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  baseline.process(context, baseline_left, baseline_right)
  retuned.process(context, retuned_left, retuned_right)
  assert_true(
    retuned.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        GRAPH_STEREO_DELAY_FEEDBACK,
      ),
    ),
  )
  baseline.process(context, baseline_left, baseline_right)
  retuned.process(context, retuned_left, retuned_right)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      baseline_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(integration_buffer_is_finite_and_bounded(retuned_left, 2.0))
  assert_true(
    integration_buffers_close(
      baseline_left,
      baseline_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_buffers_close(
      retuned_left,
      retuned_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_abs_sum(retuned_left) > integration_abs_sum(baseline_left),
  )
}

///|
test "compiled graph stereo delay mixdown matches equivalent mono delay path" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let stereo_nodes = [
    DspNode::constant(1.0),
    DspNode::pan(0, GRAPH_STEREO_CENTER),
    DspNode::stereo_delay(
      1,
      GRAPH_STEREO_DELAY_CAPACITY,
      delay_samples=GRAPH_STEREO_DELAY_SAMPLES,
    ),
    DspNode::stereo_mixdown(2),
    DspNode::output(3),
  ]
  let mono_nodes = [
    DspNode::constant(GRAPH_STEREO_CENTER_GAIN),
    DspNode::delay(
      0,
      GRAPH_STEREO_DELAY_CAPACITY,
      delay_samples=GRAPH_STEREO_DELAY_SAMPLES,
    ),
    DspNode::output(1),
  ]
  let stereo_mixdown = CompiledDsp::compile(stereo_nodes, context).unwrap()
  let mono = CompiledDsp::compile(mono_nodes, context).unwrap()
  let stereo_mixdown_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let mono_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  stereo_mixdown.process(context, stereo_mixdown_output)
  mono.process(context, mono_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      stereo_mixdown_output,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffers_close(
      stereo_mixdown_output,
      mono_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
}

///|
test "compiled graph stereo mixdown matches equivalent mono gain path" {
  let context = DspContext::new(
    sample_rate=GRAPH_STEREO_SAMPLE_RATE,
    block_size=GRAPH_STEREO_BLOCK_SIZE,
  )
  let mono_gain = GRAPH_STEREO_GAIN *
    GRAPH_STEREO_POST_GAIN *
    0.7071067811865476
  let stereo_nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_STEREO_FREQ),
    DspNode::gain(0, GRAPH_STEREO_GAIN),
    DspNode::pan(1, GRAPH_STEREO_CENTER),
    DspNode::stereo_gain(2, GRAPH_STEREO_POST_GAIN),
    DspNode::stereo_clip(3, 1.0),
    DspNode::stereo_mixdown(4),
    DspNode::output(5),
  ]
  let mono_nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_STEREO_FREQ),
    DspNode::gain(0, mono_gain),
    DspNode::clip(1, 1.0),
    DspNode::output(2),
  ]
  let stereo_mixdown = CompiledDsp::compile(stereo_nodes, context).unwrap()
  let mono = CompiledDsp::compile(mono_nodes, context).unwrap()
  let stereo_mixdown_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)
  let mono_output = AudioBuffer::filled(GRAPH_STEREO_BLOCK_SIZE)

  stereo_mixdown.process(context, stereo_mixdown_output)
  mono.process(context, mono_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(stereo_mixdown_output, 1.0),
  )
  assert_true(integration_any_non_zero(stereo_mixdown_output))
  assert_true(
    integration_buffers_close(
      stereo_mixdown_output,
      mono_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
}

///|
test "compiled graph z^-1 feedback cycle persists across blocks and stays bounded" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::mix(0, 2),
    DspNode::gain(1, GRAPH_FEEDBACK_GAIN),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  compiled.process(context, first_block)
  compiled.process(context, second_block)

  assert_true(integration_buffer_is_finite_and_bounded(first_block, 1.0))
  assert_true(integration_buffer_is_finite_and_bounded(second_block, 1.0))
  assert_true(
    (first_block.get(0) - GRAPH_FEEDBACK_GAIN).abs() <
    INTEGRATION_BUFFER_EPSILON,
  )
  assert_true((first_block.get(1) - 0.75).abs() < INTEGRATION_BUFFER_EPSILON)
  assert_true(
    (second_block.get(0) - 0.998046875).abs() < INTEGRATION_BUFFER_EPSILON,
  )
  assert_true(second_block.get(0) > first_block.get(first_block.length() - 1))
}

///|
test "compiled graph z^-1 feedback cycle applies batched runtime changes" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::mix(0, 2),
    DspNode::gain(1, GRAPH_FEEDBACK_GAIN),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  compiled.process(context, first_block)
  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(
        0,
        GraphParamSlot::Value0,
        GRAPH_FEEDBACK_RETUNED_CONSTANT,
      ),
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        GRAPH_FEEDBACK_RETUNED_GAIN,
      ),
    ]),
  )
  compiled.process(context, second_block)

  assert_true(integration_buffer_is_finite_and_bounded(second_block, 0.75))
  assert_true(
    (second_block.get(0) - 0.7490234375).abs() < INTEGRATION_BUFFER_EPSILON,
  )
  assert_true(
    (second_block.get(1) - 0.687255859375).abs() < INTEGRATION_BUFFER_EPSILON,
  )
  assert_true(second_block.get(second_block.length() - 1) < second_block.get(0))
}

///|
test "compiled stereo graph mono z^-1 feedback cycle persists across blocks" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::mix(0, 2),
    DspNode::gain(1, GRAPH_FEEDBACK_GAIN),
    DspNode::pan(2, GRAPH_STEREO_CENTER),
    DspNode::stereo_output(3),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let first_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  compiled.process(context, first_left, first_right)
  compiled.process(context, second_left, second_right)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      first_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      second_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffers_close(
      first_left,
      first_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_buffers_close(
      second_left,
      second_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    (first_left.get(0) - GRAPH_FEEDBACK_GAIN * GRAPH_STEREO_CENTER_GAIN).abs() <
    INTEGRATION_BUFFER_EPSILON,
  )
  assert_true(
    (second_left.get(0) - 0.998046875 * GRAPH_STEREO_CENTER_GAIN).abs() <
    INTEGRATION_BUFFER_EPSILON,
  )
  assert_true(second_left.get(0) > first_left.get(first_left.length() - 1))
}

///|
test "compiled stereo graph mono z^-1 feedback cycle applies batched runtime changes" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::constant(1.0),
    DspNode::mix(0, 2),
    DspNode::gain(1, GRAPH_FEEDBACK_GAIN),
    DspNode::pan(2, GRAPH_STEREO_CENTER),
    DspNode::stereo_output(3),
  ]
  let compiled = CompiledStereoDsp::compile(nodes, context).unwrap()
  let first_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  compiled.process(context, first_left, first_right)
  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(
        2,
        GraphParamSlot::Value0,
        GRAPH_FEEDBACK_RETUNED_GAIN,
      ),
      GraphControl::set_param(3, GraphParamSlot::Value0, GRAPH_STEREO_HARD_LEFT),
    ]),
  )
  compiled.process(context, second_left, second_right)

  assert_true(integration_buffer_is_finite_and_bounded(second_left, 1.0))
  assert_true(integration_buffer_is_finite_and_bounded(second_right, 0.0))
  assert_true(
    (second_left.get(0) - 0.4990234375).abs() < INTEGRATION_BUFFER_EPSILON,
  )
  assert_true(
    second_right
    .as_fixed_array()
    .all(sample => sample.abs() < INTEGRATION_BUFFER_EPSILON),
  )
  assert_true(second_left.get(second_left.length() - 1) < second_left.get(0))
}

///|
test "compiled graph hot swap crossfades between bounded mono graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let active = CompiledDsp::compile(
    [DspNode::constant(0.25), DspNode::output(0)],
    context,
  ).unwrap()
  let replacement = CompiledDsp::compile(
    [DspNode::constant(0.75), DspNode::output(0)],
    context,
  ).unwrap()
  let hot_swap = CompiledDspHotSwap::from_graph(active, crossfade_samples=8)
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(replacement))
  hot_swap.process(context, first_block)
  hot_swap.process(context, second_block)
  hot_swap.process(context, settled_block)

  assert_true(integration_buffer_is_finite_and_bounded(first_block, 0.8))
  assert_true(integration_buffer_is_finite_and_bounded(second_block, 0.8))
  assert_true(integration_buffer_is_finite_and_bounded(settled_block, 0.75))
  assert_true(first_block.get(0) == 0.25)
  assert_true(first_block.get(1) > first_block.get(0))
  assert_true(first_block.get(2) > first_block.get(1))
  assert_true(first_block.get(3) > first_block.get(2))
  assert_true(second_block.as_fixed_array().every(sample => sample == 0.75))
  assert_true(settled_block.as_fixed_array().every(sample => sample == 0.75))
}

///|
test "compiled graph topology edit crossfades rebuilt mono graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::gain(0, 0.25), DspNode::output(1)],
    context,
    crossfade_samples=8,
  ).unwrap()
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::replace_node(1, DspNode::gain(0, 0.75)),
    ),
  )
  assert_true(
    topology.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, HALF_GAIN),
    ),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  assert_true(
    integration_buffer_is_finite_and_bounded(first_block, HALF_GAIN * 1.5),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(second_block, HALF_GAIN * 1.5),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(settled_block, HALF_GAIN),
  )
  assert_true(first_block.get(0) == HALF_GAIN)
  assert_true(second_block.get(0) >= HALF_GAIN)
  assert_true(
    settled_block.as_fixed_array().every(sample => sample == HALF_GAIN),
  )
}

///|
test "compiled graph topology edit rewires rebuilt mono graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let topology = CompiledDspTopologyController::from_nodes(
    [
      DspNode::constant(2.0),
      DspNode::constant(1.0),
      DspNode::gain(0, HALF_GAIN),
      DspNode::gain(1, HALF_GAIN),
      DspNode::mix(2, 3),
      DspNode::mix(4, 3),
      DspNode::output(5),
    ],
    context,
    crossfade_samples=8,
  ).unwrap()
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::rewire_input(4, GraphTopologyInputSlot::Input1, 0),
    ),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  assert_true(integration_buffer_is_finite_and_bounded(first_block, 4.1))
  assert_true(integration_buffer_is_finite_and_bounded(second_block, 4.1))
  assert_true(integration_buffer_is_finite_and_bounded(settled_block, 3.5))
  assert_true(first_block.get(0) == 2.0)
  assert_true(second_block.get(0) >= 2.0)
  assert_true(settled_block.as_fixed_array().every(sample => sample == 3.5))
}

///|
test "compiled graph topology edit inserts rebuilt mono graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::output(0)],
    context,
    crossfade_samples=8,
  ).unwrap()
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::insert_node(
        1,
        GraphTopologyInputSlot::Input0,
        DspNode::gain(0, HALF_GAIN),
      ),
    ),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  assert_true(integration_buffer_is_finite_and_bounded(first_block, 1.2))
  assert_true(integration_buffer_is_finite_and_bounded(second_block, 1.2))
  assert_true(
    integration_buffer_is_finite_and_bounded(settled_block, HALF_GAIN),
  )
  assert_true(first_block.get(0) == 1.0)
  assert_true(second_block.get(0) >= HALF_GAIN)
  assert_true(
    settled_block.as_fixed_array().every(sample => sample == HALF_GAIN),
  )
}

///|
test "compiled graph topology edit deletes rebuilt mono graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::gain(0, HALF_GAIN), DspNode::output(1)],
    context,
    crossfade_samples=8,
  ).unwrap()
  let first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::delete_node(1, 2, GraphTopologyInputSlot::Input0, 1),
    ),
  )
  topology.process(context, first_block)
  topology.process(context, second_block)
  topology.process(context, settled_block)

  assert_true(integration_buffer_is_finite_and_bounded(first_block, 1.2))
  assert_true(integration_buffer_is_finite_and_bounded(second_block, 1.2))
  assert_true(integration_buffer_is_finite_and_bounded(settled_block, 1.0))
  assert_true(first_block.get(0) == HALF_GAIN)
  assert_true(second_block.get(0) >= HALF_GAIN)
  assert_true(settled_block.as_fixed_array().every(sample => sample == 1.0))
}

///|
test "compiled graph topology edit insert delete roundtrip restores rebuilt mono graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let topology = CompiledDspTopologyController::from_nodes(
    [DspNode::constant(1.0), DspNode::output(0)],
    context,
    crossfade_samples=8,
  ).unwrap()
  let insert_first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let insert_second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let inserted_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let delete_first_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let delete_second_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let restored_block = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::insert_node(
        1,
        GraphTopologyInputSlot::Input0,
        DspNode::gain(0, HALF_GAIN),
      ),
    ),
  )
  topology.process(context, insert_first_block)
  topology.process(context, insert_second_block)
  topology.process(context, inserted_block)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::delete_node(2, 1, GraphTopologyInputSlot::Input0, 2),
    ),
  )
  topology.process(context, delete_first_block)
  topology.process(context, delete_second_block)
  topology.process(context, restored_block)

  assert_true(integration_buffer_is_finite_and_bounded(insert_first_block, 1.2))
  assert_true(
    integration_buffer_is_finite_and_bounded(insert_second_block, 1.2),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(inserted_block, HALF_GAIN),
  )
  assert_true(integration_buffer_is_finite_and_bounded(delete_first_block, 1.2))
  assert_true(
    integration_buffer_is_finite_and_bounded(delete_second_block, 1.2),
  )
  assert_true(integration_buffer_is_finite_and_bounded(restored_block, 1.0))
  assert_true(insert_first_block.get(0) == 1.0)
  assert_true(
    inserted_block.as_fixed_array().every(sample => sample == HALF_GAIN),
  )
  assert_true(delete_first_block.get(0) == HALF_GAIN)
  assert_true(restored_block.as_fixed_array().every(sample => sample == 1.0))
}

///|
test "compiled stereo graph hot swap preserves bounded stereo output" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let active = CompiledStereoDsp::compile(
    [
      DspNode::constant(0.25),
      DspNode::pan(0, GRAPH_STEREO_CENTER),
      DspNode::stereo_output(1),
    ],
    context,
  ).unwrap()
  let replacement = CompiledStereoDsp::compile(
    [
      DspNode::constant(0.75),
      DspNode::pan(0, GRAPH_STEREO_CENTER),
      DspNode::stereo_output(1),
    ],
    context,
  ).unwrap()
  let hot_swap = CompiledStereoDspHotSwap::from_graph(
    active,
    crossfade_samples=8,
  )
  let first_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(hot_swap.queue_swap(replacement))
  hot_swap.process(context, first_left, first_right)
  hot_swap.process(context, second_left, second_right)
  hot_swap.process(context, settled_left, settled_right)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      first_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      second_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      settled_left,
      GRAPH_STEREO_CENTER_GAIN,
    ),
  )
  assert_true(
    integration_buffers_close(
      first_left,
      first_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_buffers_close(
      second_left,
      second_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_buffers_close(
      settled_left,
      settled_right,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(first_left.get(0) == 0.25 * GRAPH_STEREO_CENTER_GAIN)
  assert_true(
    second_left
    .as_fixed_array()
    .every(sample => {
      (sample - 0.75 * GRAPH_STEREO_CENTER_GAIN).abs() <
      INTEGRATION_BUFFER_EPSILON
    }),
  )
  assert_true(
    settled_left
    .as_fixed_array()
    .every(sample => {
      (sample - 0.75 * GRAPH_STEREO_CENTER_GAIN).abs() <
      INTEGRATION_BUFFER_EPSILON
    }),
  )
}

///|
test "compiled stereo graph topology edit crossfades rebuilt stereo graphs" {
  let context = DspContext::new(
    sample_rate=GRAPH_FEEDBACK_SAMPLE_RATE,
    block_size=GRAPH_FEEDBACK_BLOCK_SIZE,
  )
  let topology = CompiledStereoDspTopologyController::from_nodes(
    [
      DspNode::constant(1.0),
      DspNode::pan(0, GRAPH_STEREO_CENTER),
      DspNode::stereo_output(1),
    ],
    context,
    crossfade_samples=8,
  ).unwrap()
  let first_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let first_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let second_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_left = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)
  let settled_right = AudioBuffer::filled(GRAPH_FEEDBACK_BLOCK_SIZE)

  assert_true(
    topology.queue_topology_edit(
      GraphTopologyEdit::replace_node(
        1,
        DspNode::pan(0, GRAPH_STEREO_HARD_RIGHT),
      ),
    ),
  )
  assert_true(
    topology.apply_control(
      GraphControl::set_param(1, GraphParamSlot::Value0, GRAPH_STEREO_HARD_LEFT),
    ),
  )
  topology.process(context, first_left, first_right)
  topology.process(context, second_left, second_right)
  topology.process(context, settled_left, settled_right)

  assert_true(integration_buffer_is_finite_and_bounded(first_left, 1.5))
  assert_true(integration_buffer_is_finite_and_bounded(second_left, 1.5))
  assert_true(integration_buffer_is_finite_and_bounded(settled_left, 1.0))
  assert_true(integration_buffer_is_finite_and_bounded(first_right, 1.0))
  assert_true(integration_buffer_is_finite_and_bounded(second_right, 1.0))
  assert_true(integration_buffer_is_finite_and_bounded(settled_right, 0.0))
  assert_true(first_left.get(0) == 1.0)
  assert_true(second_left.get(0) >= 1.0)
  assert_true(
    first_right
    .as_fixed_array()
    .every(sample => sample.abs() < INTEGRATION_BUFFER_EPSILON),
  )
  assert_true(
    second_right
    .as_fixed_array()
    .every(sample => sample.abs() < INTEGRATION_BUFFER_EPSILON),
  )
  assert_true(settled_left.as_fixed_array().every(sample => sample == 1.0))
  assert_true(
    settled_right
    .as_fixed_array()
    .every(sample => sample.abs() < INTEGRATION_BUFFER_EPSILON),
  )
}

///|
test "compiled graph voice path stays coherent across gates and runtime updates" {
  let context = DspContext::new(
    sample_rate=GRAPH_VOICE_SAMPLE_RATE,
    block_size=GRAPH_VOICE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::output(1),
    DspNode::clip(2, GRAPH_VOICE_CLIP),
    DspNode::delay(
      3,
      GRAPH_VOICE_DELAY_CAPACITY,
      delay_samples=GRAPH_VOICE_DELAY_SAMPLES,
    ),
    DspNode::gain(4, GRAPH_VOICE_GAIN),
    DspNode::biquad(
      input=5,
      mode=BiquadMode::LowPass,
      cutoff_hz=GRAPH_VOICE_CUTOFF,
      q=GRAPH_VOICE_Q,
    ),
    DspNode::mul(7, 6),
    DspNode::adsr(
      attack_ms=0.0,
      decay_ms=0.0,
      sustain=GRAPH_VOICE_SUSTAIN,
      release_ms=GRAPH_VOICE_RELEASE_MS,
    ),
    DspNode::oscillator(Waveform::Square, GRAPH_VOICE_FREQ),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(GRAPH_VOICE_BLOCK_SIZE)

  assert_true(compiled.apply_control(GraphControl::gate_on(6)))
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )
  assert_true(integration_any_non_zero(output))

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(3, GraphParamSlot::Value0, 0.0),
    ),
  )
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )
  assert_true(integration_any_non_zero(output))
  assert_true(integration_all_zero_from(output, GRAPH_VOICE_DELAY_SAMPLES))

  assert_true(
    compiled.apply_control(
      GraphControl::set_param(3, GraphParamSlot::Value0, GRAPH_VOICE_GAIN),
    ),
  )
  assert_true(
    compiled.apply_control(
      GraphControl::set_param(
        2,
        GraphParamSlot::DelaySamples,
        GRAPH_VOICE_DELAY_SAMPLES_DOUBLE,
      ),
    ),
  )
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )
  assert_true(integration_any_non_zero(output))

  assert_true(compiled.apply_control(GraphControl::gate_off(6)))
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )

  for repeat = 0; repeat < 6; repeat = repeat + 1 {
    compiled.process(context, output)
  }

  assert_true(
    integration_buffer_is_finite_and_bounded(
      output,
      GRAPH_VOICE_RELEASE_TAIL_LIMIT,
    ),
  )
}

///|
test "compiled graph control frames apply batched runtime changes per block" {
  let context = DspContext::new(
    sample_rate=GRAPH_VOICE_SAMPLE_RATE,
    block_size=GRAPH_VOICE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::output(1),
    DspNode::clip(2, GRAPH_VOICE_CLIP),
    DspNode::delay(
      3,
      GRAPH_VOICE_DELAY_CAPACITY,
      delay_samples=GRAPH_VOICE_DELAY_SAMPLES,
    ),
    DspNode::gain(4, GRAPH_VOICE_GAIN),
    DspNode::biquad(
      input=5,
      mode=BiquadMode::LowPass,
      cutoff_hz=GRAPH_VOICE_CUTOFF,
      q=GRAPH_VOICE_Q,
    ),
    DspNode::mul(7, 6),
    DspNode::adsr(
      attack_ms=0.0,
      decay_ms=0.0,
      sustain=GRAPH_VOICE_SUSTAIN,
      release_ms=GRAPH_VOICE_RELEASE_MS,
    ),
    DspNode::oscillator(Waveform::Square, GRAPH_VOICE_FREQ),
  ]
  let compiled = CompiledDsp::compile(nodes, context).unwrap()
  let output = AudioBuffer::filled(GRAPH_VOICE_BLOCK_SIZE)

  assert_true(
    compiled.apply_controls([
      GraphControl::gate_on(6),
      GraphControl::set_param(3, GraphParamSlot::Value0, 0.0),
    ]),
  )
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )
  assert_true(output.as_fixed_array().every(sample => sample == 0.0))

  assert_true(
    compiled.apply_controls([
      GraphControl::set_param(3, GraphParamSlot::Value0, GRAPH_VOICE_GAIN),
      GraphControl::set_param(2, GraphParamSlot::DelaySamples, 0.0),
    ]),
  )
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )
  assert_true(integration_any_non_zero(output))

  assert_true(compiled.apply_controls([GraphControl::gate_off(6)]))
  compiled.process(context, output)

  assert_true(
    integration_buffer_is_finite_and_bounded(output, GRAPH_VOICE_CLIP),
  )
  assert_true(integration_any_non_zero(output))

  for repeat = 0; repeat < 6; repeat = repeat + 1 {
    compiled.process(context, output)
  }

  assert_true(
    integration_buffer_is_finite_and_bounded(
      output,
      GRAPH_VOICE_RELEASE_TAIL_LIMIT,
    ),
  )
}

///|
test "compiled graph multi-source path responds to runtime biquad retune" {
  let context = DspContext::new(
    sample_rate=GRAPH_MULTI_SOURCE_SAMPLE_RATE,
    block_size=GRAPH_MULTI_SOURCE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_MULTI_SOURCE_OSC_FREQ),
    DspNode::noise(GRAPH_MULTI_SOURCE_NOISE_SEED),
    DspNode::gain(1, GRAPH_MULTI_SOURCE_NOISE_GAIN),
    DspNode::mix(0, 2),
    DspNode::biquad(
      input=3,
      mode=BiquadMode::LowPass,
      cutoff_hz=GRAPH_MULTI_SOURCE_CUTOFF,
      q=GRAPH_MULTI_SOURCE_Q,
    ),
    DspNode::gain(4, GRAPH_MULTI_SOURCE_OUTPUT_GAIN),
    DspNode::clip(5, GRAPH_MULTI_SOURCE_CLIP),
    DspNode::output(6),
  ]
  let baseline = CompiledDsp::compile(nodes, context).unwrap()
  let retuned = CompiledDsp::compile(nodes, context).unwrap()
  let baseline_output = AudioBuffer::filled(GRAPH_MULTI_SOURCE_BLOCK_SIZE)
  let retuned_output = AudioBuffer::filled(GRAPH_MULTI_SOURCE_BLOCK_SIZE)

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      baseline_output,
      GRAPH_MULTI_SOURCE_CLIP,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      retuned_output,
      GRAPH_MULTI_SOURCE_CLIP,
    ),
  )
  assert_true(integration_any_non_zero(baseline_output))
  assert_true(integration_any_non_zero(retuned_output))
  assert_true(
    integration_buffers_close(
      baseline_output,
      retuned_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )

  assert_true(
    retuned.apply_control(
      GraphControl::set_param(
        4,
        GraphParamSlot::Value0,
        GRAPH_MULTI_SOURCE_RETUNED_CUTOFF,
      ),
    ),
  )

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      baseline_output,
      GRAPH_MULTI_SOURCE_CLIP,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      retuned_output,
      GRAPH_MULTI_SOURCE_CLIP,
    ),
  )
  assert_true(integration_any_non_zero(baseline_output))
  assert_true(integration_any_non_zero(retuned_output))
  assert_false(
    integration_buffers_close(
      baseline_output,
      retuned_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
}

///|
test "compiled graph runtime high-pass retune changes output directionally" {
  let context = DspContext::new(
    sample_rate=GRAPH_HIGHPASS_SAMPLE_RATE,
    block_size=GRAPH_HIGHPASS_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, GRAPH_HIGHPASS_FREQ),
    DspNode::biquad(
      input=0,
      mode=BiquadMode::HighPass,
      cutoff_hz=GRAPH_HIGHPASS_INITIAL_CUTOFF,
      q=GRAPH_HIGHPASS_Q,
    ),
    DspNode::clip(1, GRAPH_HIGHPASS_CLIP),
    DspNode::output(2),
  ]
  let baseline = CompiledDsp::compile(nodes, context).unwrap()
  let retuned = CompiledDsp::compile(nodes, context).unwrap()
  let baseline_output = AudioBuffer::filled(GRAPH_HIGHPASS_BLOCK_SIZE)
  let retuned_output = AudioBuffer::filled(GRAPH_HIGHPASS_BLOCK_SIZE)

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true(
    retuned.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::Value0,
        GRAPH_HIGHPASS_RETUNED_CUTOFF,
      ),
    ),
  )

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      baseline_output,
      GRAPH_HIGHPASS_CLIP,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      retuned_output,
      GRAPH_HIGHPASS_CLIP,
    ),
  )
  assert_true(integration_any_non_zero(baseline_output))
  assert_true(integration_any_non_zero(retuned_output))
  assert_false(
    integration_buffers_close(
      baseline_output,
      retuned_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_abs_sum(retuned_output) > integration_abs_sum(baseline_output),
  )
}

///|
test "compiled graph runtime band-pass retune changes output" {
  let context = DspContext::new(
    sample_rate=GRAPH_BANDPASS_SAMPLE_RATE,
    block_size=GRAPH_BANDPASS_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, GRAPH_BANDPASS_FREQ),
    DspNode::biquad(
      input=0,
      mode=BiquadMode::BandPass,
      cutoff_hz=GRAPH_BANDPASS_INITIAL_CUTOFF,
      q=GRAPH_BANDPASS_Q,
    ),
    DspNode::clip(1, GRAPH_BANDPASS_CLIP),
    DspNode::output(2),
  ]
  let baseline = CompiledDsp::compile(nodes, context).unwrap()
  let retuned = CompiledDsp::compile(nodes, context).unwrap()
  let baseline_output = AudioBuffer::filled(GRAPH_BANDPASS_BLOCK_SIZE)
  let retuned_output = AudioBuffer::filled(GRAPH_BANDPASS_BLOCK_SIZE)

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true(
    retuned.apply_control(
      GraphControl::set_param(
        1,
        GraphParamSlot::Value0,
        GRAPH_BANDPASS_RETUNED_CUTOFF,
      ),
    ),
  )

  baseline.process(context, baseline_output)
  retuned.process(context, retuned_output)

  assert_true(
    integration_buffer_is_finite_and_bounded(
      baseline_output,
      GRAPH_BANDPASS_CLIP,
    ),
  )
  assert_true(
    integration_buffer_is_finite_and_bounded(
      retuned_output,
      GRAPH_BANDPASS_CLIP,
    ),
  )
  assert_true(integration_any_non_zero(baseline_output))
  assert_true(integration_any_non_zero(retuned_output))
  assert_false(
    integration_buffers_close(
      baseline_output,
      retuned_output,
      INTEGRATION_BUFFER_EPSILON,
    ),
  )
  assert_true(
    integration_abs_sum(retuned_output) > integration_abs_sum(baseline_output),
  )
}

///|
test "exit deliverable compiles and produces non-zero output" {
  let graph : GraphBuilder = exit_deliverable()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled = CompiledDsp::compile(graph.nodes(), ctx)
  assert_true(compiled is Some(_))
  let compiled = compiled.unwrap()
  let buf = AudioBuffer::filled(128)
  compiled.process(ctx, buf)
  let mut has_nonzero = false
  for i = 0; i < 128; i = i + 1 {
    if buf.get(i) != 0.0 {
      has_nonzero = true
      break
    }
  }
  assert_true(has_nonzero)
}

///|
fn integration_apply_modulation(
  signal : AudioBuffer,
  modulation : AudioBuffer,
) -> Unit {
  let sample_count = if signal.length() < modulation.length() {
    signal.length()
  } else {
    modulation.length()
  }

  for index = 0; index < sample_count; index = index + 1 {
    signal.set(index, signal.get(index) * modulation.get(index))
  }
}

///|
fn integration_apply_smoothed_gain(
  signal : AudioBuffer,
  smoother : ParamSmoother,
) -> Unit {
  for index = 0; index < signal.length(); index = index + 1 {
    signal.set(index, signal.get(index) * smoother.tick())
  }
}

///|
fn integration_any_non_zero(buffer : AudioBuffer) -> Bool {
  buffer.as_fixed_array().any(sample => sample != 0.0)
}

///|
fn integration_copy_samples(buffer : AudioBuffer) -> FixedArray[Double] {
  let copy = FixedArray::make(buffer.length(), 0.0)
  for index = 0; index < buffer.length(); index = index + 1 {
    copy[index] = buffer.get(index)
  }
  copy
}

///|
fn integration_buffer_differs_from_fixed_array(
  buffer : AudioBuffer,
  baseline : FixedArray[Double],
) -> Bool {
  let sample_count = if buffer.length() < baseline.length() {
    buffer.length()
  } else {
    baseline.length()
  }

  for index = 0; index < sample_count; index = index + 1 {
    if buffer.get(index) != baseline[index] {
      return true
    }
  }

  buffer.length() != baseline.length()
}

///|
fn integration_buffers_close(
  left : AudioBuffer,
  right : AudioBuffer,
  epsilon : Double,
) -> Bool {
  let sample_count = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }

  for index = 0; index < sample_count; index = index + 1 {
    if (left.get(index) - right.get(index)).abs() > epsilon {
      return false
    }
  }

  left.length() == right.length()
}

///|
fn integration_all_zero_from(buffer : AudioBuffer, start : Int) -> Bool {
  let bounded_start = if start < 0 {
    0
  } else if start > buffer.length() {
    buffer.length()
  } else {
    start
  }

  for index = bounded_start; index < buffer.length(); index = index + 1 {
    if buffer.get(index) != 0.0 {
      return false
    }
  }

  true
}

///|
fn integration_buffer_is_finite_and_bounded(
  buffer : AudioBuffer,
  limit : Double,
) -> Bool {
  buffer
  .as_fixed_array()
  .every(sample => {
    !sample.is_nan() && !sample.is_inf() && sample >= -limit && sample <= limit
  })
}

///|
fn integration_abs_sum(buffer : AudioBuffer) -> Double {
  let mut total = 0.0

  for index = 0; index < buffer.length(); index = index + 1 {
    total = total + buffer.get(index).abs()
  }

  total
}
