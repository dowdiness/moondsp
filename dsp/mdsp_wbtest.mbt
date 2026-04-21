///|
test "reset rewinds phase to zero" {
  let osc = Oscillator::new()

  ignore(osc.tick(440.0, 48000.0))
  ignore(osc.tick(440.0, 48000.0))
  assert_true(osc.phase() > 0.0)

  osc.reset()

  assert_eq(osc.phase(), 0.0)
  assert_eq(osc.tick(440.0, 48000.0), 0.0)
}

///|
test "process with invalid sample rate writes silence" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=0.0, block_size=8)
  let buffer = AudioBuffer::filled(8, init=1.0)

  osc.process(context, buffer, freq_hz=440.0)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
  assert_eq(osc.phase(), 0.0)
}

///|
test "process_waveform respects context block size" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = AudioBuffer::filled(4, init=1.0)

  osc.process_waveform(context, buffer, Waveform::Saw, 440.0)

  assert_true(buffer.get(0) != 1.0)
  assert_true(buffer.get(1) != 1.0)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
test "waveform selection preserves shared phase progression" {
  let osc = Oscillator::new()

  ignore(osc.tick_waveform(Waveform::Saw, 440.0, 48000.0))
  let phase_after_saw = osc.phase()
  ignore(osc.tick_waveform(Waveform::Triangle, 440.0, 48000.0))

  assert_true(phase_after_saw > 0.0)
  assert_eq(osc.phase(), 880.0 / 48000.0)
}

///|
test "tick_waveform rejects non-finite parameters without poisoning phase" {
  let osc = Oscillator::new()

  assert_eq(osc.tick_waveform(Waveform::Saw, 0.0 / 0.0, 48000.0), 0.0)
  assert_eq(osc.tick_waveform(Waveform::Square, 440.0, 1.0 / 0.0), 0.0)
  assert_eq(osc.phase(), 0.0)
  assert_eq(osc.tick_waveform(Waveform::Triangle, 440.0, 48000.0), -1.0)
}

///|
test "process_waveform rejects non-finite frequency without advancing phase" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::filled(4, init=1.0)

  osc.process_waveform(context, buffer, Waveform::Saw, 0.0 / 0.0)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
  assert_eq(osc.phase(), 0.0)
}

///|
test "process respects context block size" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = AudioBuffer::filled(4, init=1.0)

  osc.process(context, buffer, freq_hz=440.0)

  assert_eq(buffer.get(0), 0.0)
  assert_true(buffer.get(1) != 0.0)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
test "gain with invalid context writes silence" {
  let gain = Gain::new()
  let context = DspContext::new(sample_rate=0.0, block_size=4)
  let buffer = AudioBuffer::new(make_gain_test_samples_wb())

  gain.process(context, buffer, 0.5)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "gain with invalid amount writes silence" {
  let gain = Gain::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_gain_test_samples_wb())

  gain.process(context, buffer, 0.0 / 0.0)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "gain respects context block size" {
  let gain = Gain::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = AudioBuffer::new(make_gain_block_samples_wb())

  gain.process(context, buffer, 0.5)

  assert_eq(buffer.get(0), 0.5)
  assert_eq(buffer.get(1), -0.5)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
fn make_gain_test_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 0.25
  samples[1] = -0.5
  samples[2] = 1.0
  samples[3] = -1.0
  samples
}

///|
fn make_gain_block_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 1.0
  samples[1] = -1.0
  samples[2] = 1.0
  samples[3] = -1.0
  samples
}

///|
test "mix with invalid context writes silence" {
  let mix = Mix::new()
  let context = DspContext::new(sample_rate=0.0, block_size=4)
  let output = AudioBuffer::new(make_mix_output_samples_wb())
  let input = AudioBuffer::new(make_mix_input_samples_wb())

  mix.process(context, output, input)

  assert_true(output.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "mix respects context block size" {
  let mix = Mix::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let output = AudioBuffer::new(make_mix_output_samples_wb())
  let input = AudioBuffer::new(make_mix_input_samples_wb())

  mix.process(context, output, input)

  assert_eq(output.get(0), 0.35)
  assert_eq(output.get(1), -0.3)
  assert_eq(output.get(2), 0.0)
  assert_eq(output.get(3), 0.0)
}

///|
test "mix stops at the shorter input length" {
  let mix = Mix::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let output = AudioBuffer::new(make_mix_output_samples_wb())
  let input = AudioBuffer::new(make_short_mix_input_samples_wb())

  mix.process(context, output, input)

  assert_eq(output.get(0), 0.35)
  assert_eq(output.get(1), -0.3)
  assert_eq(output.get(2), 0.0)
  assert_eq(output.get(3), 0.0)
}

///|
fn make_mix_output_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 0.25
  samples[1] = -0.5
  samples[2] = 0.5
  samples[3] = -0.25
  samples
}

///|
fn make_mix_input_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 0.1
  samples[1] = 0.2
  samples[2] = 0.25
  samples[3] = -0.125
  samples
}

///|
fn make_short_mix_input_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(2, 0.0)
  samples[0] = 0.1
  samples[1] = 0.2
  samples
}

///|
test "noise normalizes zero seed to a usable internal state" {
  let noise = Noise::new(0U)

  assert_true(noise.seed() != 0U)
  assert_true(noise.tick() >= -1.0)
}

///|
test "noise with invalid context writes silence without advancing state" {
  let noise = Noise::new(42U)
  let state_before = noise.seed()
  let context = DspContext::new(sample_rate=0.0, block_size=4)
  let buffer = AudioBuffer::filled(4, init=1.0)

  noise.process(context, buffer)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
  assert_eq(noise.seed(), state_before)
}

///|
test "noise respects context block size and zeros the tail" {
  let noise = Noise::new(17U)
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = AudioBuffer::filled(4, init=1.0)

  noise.process(context, buffer)

  assert_true(buffer.get(0) != 0.0)
  assert_true(buffer.get(1) != 0.0)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
test "clip with invalid context writes silence" {
  let clip = Clip::new()
  let context = DspContext::new(sample_rate=0.0, block_size=4)
  let buffer = AudioBuffer::new(make_clip_test_samples_wb())

  clip.process(context, buffer, 0.5)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "clip with invalid threshold writes silence" {
  let clip = Clip::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_clip_test_samples_wb())

  clip.process(context, buffer, 0.0)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "clip respects context block size" {
  let clip = Clip::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = AudioBuffer::new(make_clip_test_samples_wb())

  clip.process(context, buffer, 0.5)

  assert_eq(buffer.get(0), -0.5)
  assert_eq(buffer.get(1), -0.25)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
fn make_clip_test_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = -0.75
  samples[1] = -0.25
  samples[2] = 0.25
  samples[3] = 0.75
  samples
}

///|
test "adsr invalid context resets to idle silence" {
  let env = Adsr::new(
    attack_ms=10.0,
    decay_ms=10.0,
    sustain=0.5,
    release_ms=10.0,
  )
  let context = DspContext::new(sample_rate=0.0, block_size=4)
  let buffer = AudioBuffer::filled(4, init=1.0)

  env.gate_on()
  env.process(context, buffer)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
  assert_true(env.stage() is EnvStage::Idle)
  assert_eq(env.level(), 0.0)
}

///|
test "adsr zero times transition immediately" {
  let env = Adsr::new(attack_ms=0.0, decay_ms=0.0, sustain=0.25, release_ms=0.0)
  let context = DspContext::new(sample_rate=1000.0, block_size=4)

  env.gate_on()
  assert_eq(env.tick(context), 0.25)
  assert_true(env.stage() is EnvStage::Sustain)

  env.gate_off()
  assert_eq(env.tick(context), 0.0)
  assert_true(env.stage() is EnvStage::Idle)
}

///|
test "adsr process respects context block size" {
  let env = Adsr::new(attack_ms=0.0, decay_ms=0.0, sustain=0.5, release_ms=10.0)
  let context = DspContext::new(sample_rate=1000.0, block_size=2)
  let buffer = AudioBuffer::filled(4, init=1.0)

  env.gate_on()
  env.process(context, buffer)

  assert_eq(buffer.get(0), 0.5)
  assert_eq(buffer.get(1), 0.5)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
test "adsr zero-sample process preserves state" {
  let env = Adsr::new(
    attack_ms=10.0,
    decay_ms=10.0,
    sustain=0.5,
    release_ms=10.0,
  )
  let context = DspContext::new(sample_rate=1000.0, block_size=0)
  let buffer = AudioBuffer::filled(4, init=1.0)

  env.gate_on()
  ignore(env.tick(DspContext::new(sample_rate=1000.0, block_size=4)))
  let level_before = env.level()

  env.process(context, buffer)

  assert_true(env.stage() is EnvStage::Attack)
  assert_eq(env.level(), level_before)
  assert_eq(buffer.get(0), 1.0)
  assert_eq(buffer.get(1), 1.0)
  assert_eq(buffer.get(2), 1.0)
  assert_eq(buffer.get(3), 1.0)
}

///|
test "adsr non-finite sample rate resets to idle silence" {
  let env = Adsr::new(
    attack_ms=10.0,
    decay_ms=10.0,
    sustain=0.5,
    release_ms=10.0,
  )
  let context = DspContext::new(sample_rate=1.0 / 0.0, block_size=4)
  let buffer = AudioBuffer::filled(4, init=1.0)

  env.gate_on()
  env.process(context, buffer)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
  assert_true(env.stage() is EnvStage::Idle)
  assert_eq(env.level(), 0.0)
}

///|
test "delay line clamps invalid delay lengths deterministically" {
  let delay = DelayLine::new(4, delay_samples=99)
  assert_eq(delay.delay_samples(), 4)

  delay.set_delay_samples(-3)
  assert_eq(delay.delay_samples(), 0)
}

///|
test "delay line clamps invalid feedback deterministically" {
  let delay = DelayLine::new(4, feedback=99.0)
  assert_eq(delay.feedback(), 0.99)

  delay.set_feedback(-2.0)
  assert_eq(delay.feedback(), -0.99)
  delay.set_feedback(0.0 / 0.0)
  assert_eq(delay.feedback(), 0.0)
}

///|
test "delay line process respects context block size" {
  let delay = DelayLine::new(4, delay_samples=1)
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = AudioBuffer::new(make_delay_process_samples())

  delay.process(context, buffer)

  assert_eq(buffer.get(0), 0.0)
  assert_eq(buffer.get(1), 1.0)
  assert_eq(buffer.get(2), 0.0)
  assert_eq(buffer.get(3), 0.0)
}

///|
test "delay line zero-sample process writes silence" {
  let delay = DelayLine::new(4, delay_samples=1)
  let context = DspContext::new(sample_rate=48000.0, block_size=0)
  let buffer = AudioBuffer::new(make_delay_process_samples())

  delay.process(context, buffer)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "delay line invalid context writes silence without resetting state" {
  let delay = DelayLine::new(4, delay_samples=2)
  let invalid_context = DspContext::new(sample_rate=0.0, block_size=4)
  let valid_context = DspContext::new(sample_rate=48000.0, block_size=4)
  let invalid_buffer = AudioBuffer::new(make_delay_process_samples())
  let valid_buffer = AudioBuffer::new(make_delay_followup_samples())

  ignore(delay.tick(1.0))
  ignore(delay.tick(2.0))
  delay.process(invalid_context, invalid_buffer)
  delay.process(valid_context, valid_buffer)

  assert_true(invalid_buffer.as_fixed_array().every(sample => sample == 0.0))
  assert_eq(valid_buffer.get(0), 1.0)
}

///|
fn make_delay_process_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 1.0
  samples[1] = 2.0
  samples[2] = 3.0
  samples[3] = 4.0
  samples
}

///|
fn make_delay_followup_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 5.0
  samples[1] = 6.0
  samples[2] = 7.0
  samples[3] = 8.0
  samples
}

///|
test "pan invalid context writes silence to both outputs" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=0.0, block_size=4)
  let input = AudioBuffer::new(make_pan_test_samples_wb())
  let left = AudioBuffer::filled(4, init=1.0)
  let right = AudioBuffer::filled(4, init=1.0)

  pan.process(context, input, left, right, 0.0)

  assert_true(left.as_fixed_array().every(sample => sample == 0.0))
  assert_true(right.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "pan invalid position writes silence to both outputs" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::new(make_pan_test_samples_wb())
  let left = AudioBuffer::filled(4, init=1.0)
  let right = AudioBuffer::filled(4, init=1.0)

  pan.process(context, input, left, right, 0.0 / 0.0)

  assert_true(left.as_fixed_array().every(sample => sample == 0.0))
  assert_true(right.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "pan respects context block size and zeros both tails" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let input = AudioBuffer::new(make_pan_test_samples_wb())
  let left = AudioBuffer::filled(4, init=1.0)
  let right = AudioBuffer::filled(4, init=1.0)

  pan.process(context, input, left, right, -1.0)

  assert_eq(left.get(0), 1.0)
  assert_eq(left.get(1), 0.5)
  assert_eq(left.get(2), 0.0)
  assert_eq(left.get(3), 0.0)
  assert_true(right.as_fixed_array().every(sample => sample == 0.0))
}

///|
fn make_pan_test_samples_wb() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 1.0
  samples[1] = 0.5
  samples[2] = -0.5
  samples[3] = -1.0
  samples
}
