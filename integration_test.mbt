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
  let context = DspContext::new(48000.0, 16)
  let osc = Oscillator::new()
  let env = Adsr::new(0.0, 0.0, 0.5, 5.0)
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
  let context = DspContext::new(48000.0, 16)
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
  let context = DspContext::new(48000.0, 16)
  let osc = Oscillator::new()
  let env = Adsr::new(0.0, 0.0, 0.6, 10.0)
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
test "compiled graph voice path stays coherent across gates and runtime updates" {
  let context = DspContext::new(GRAPH_VOICE_SAMPLE_RATE, GRAPH_VOICE_BLOCK_SIZE)
  let nodes = [
    DspNode::output(1),
    DspNode::clip(2, GRAPH_VOICE_CLIP),
    DspNode::delay(
      3,
      GRAPH_VOICE_DELAY_CAPACITY,
      delay_samples=GRAPH_VOICE_DELAY_SAMPLES,
    ),
    DspNode::gain(4, GRAPH_VOICE_GAIN),
    DspNode::biquad(5, BiquadMode::LowPass, GRAPH_VOICE_CUTOFF, GRAPH_VOICE_Q),
    DspNode::mul(7, 6),
    DspNode::adsr(0.0, 0.0, GRAPH_VOICE_SUSTAIN, GRAPH_VOICE_RELEASE_MS),
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
  let context = DspContext::new(GRAPH_VOICE_SAMPLE_RATE, GRAPH_VOICE_BLOCK_SIZE)
  let nodes = [
    DspNode::output(1),
    DspNode::clip(2, GRAPH_VOICE_CLIP),
    DspNode::delay(
      3,
      GRAPH_VOICE_DELAY_CAPACITY,
      delay_samples=GRAPH_VOICE_DELAY_SAMPLES,
    ),
    DspNode::gain(4, GRAPH_VOICE_GAIN),
    DspNode::biquad(5, BiquadMode::LowPass, GRAPH_VOICE_CUTOFF, GRAPH_VOICE_Q),
    DspNode::mul(7, 6),
    DspNode::adsr(0.0, 0.0, GRAPH_VOICE_SUSTAIN, GRAPH_VOICE_RELEASE_MS),
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
    GRAPH_MULTI_SOURCE_SAMPLE_RATE,
    GRAPH_MULTI_SOURCE_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Triangle, GRAPH_MULTI_SOURCE_OSC_FREQ),
    DspNode::noise(GRAPH_MULTI_SOURCE_NOISE_SEED),
    DspNode::gain(1, GRAPH_MULTI_SOURCE_NOISE_GAIN),
    DspNode::mix(0, 2),
    DspNode::biquad(
      3,
      BiquadMode::LowPass,
      GRAPH_MULTI_SOURCE_CUTOFF,
      GRAPH_MULTI_SOURCE_Q,
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
    GRAPH_HIGHPASS_SAMPLE_RATE,
    GRAPH_HIGHPASS_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, GRAPH_HIGHPASS_FREQ),
    DspNode::biquad(
      0,
      BiquadMode::HighPass,
      GRAPH_HIGHPASS_INITIAL_CUTOFF,
      GRAPH_HIGHPASS_Q,
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
    GRAPH_BANDPASS_SAMPLE_RATE,
    GRAPH_BANDPASS_BLOCK_SIZE,
  )
  let nodes = [
    DspNode::oscillator(Waveform::Sine, GRAPH_BANDPASS_FREQ),
    DspNode::biquad(
      0,
      BiquadMode::BandPass,
      GRAPH_BANDPASS_INITIAL_CUTOFF,
      GRAPH_BANDPASS_Q,
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
