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
