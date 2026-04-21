///|
test "tick returns silence for non-positive sample rate" {
  let osc = Oscillator::new()
  let first = osc.tick(440.0, 0.0)
  let second = osc.tick(440.0, -1.0)
  assert_eq(first, 0.0)
  assert_eq(second, 0.0)
  assert_eq(osc.phase(), 0.0)
}

///|
test "tick advances phase continuously" {
  let osc = Oscillator::new()
  let first = osc.tick(440.0, 48000.0)
  let second = osc.tick(440.0, 48000.0)

  assert_eq(first, 0.0)
  assert_true(second > first)
  assert_eq(osc.phase(), 880.0 / 48000.0)
}

///|
test "process fills a block with bounded samples" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  let buffer = AudioBuffer::filled(128)

  osc.process(context, buffer, freq_hz=440.0)

  assert_eq(buffer.length(), 128)
  assert_eq(buffer.get(0), 0.0)
  assert_true(buffer.as_fixed_array().any(sample => sample != 0.0))
  assert_true(
    buffer.as_fixed_array().every(sample => sample >= -1.0 && sample <= 1.0),
  )
}

///|
test "saw waveform ramps upward from negative values" {
  let osc = Oscillator::new()

  let first = osc.tick_waveform(Waveform::Saw, 440.0, 48000.0)
  let second = osc.tick_waveform(Waveform::Saw, 440.0, 48000.0)
  let third = osc.tick_waveform(Waveform::Saw, 440.0, 48000.0)

  assert_true(first < second)
  assert_true(second < third)
  assert_true(first >= -1.0 && third <= 1.0)
}

///|
test "square waveform toggles only between bipolar levels" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=8)
  let buffer = AudioBuffer::filled(8)

  osc.process_waveform(context, buffer, Waveform::Square, 440.0)

  assert_true(
    buffer.as_fixed_array().every(sample => sample == 1.0 || sample == -1.0),
  )
}

///|
test "triangle waveform stays bounded and changes smoothly" {
  let osc = Oscillator::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=8)
  let buffer = AudioBuffer::filled(8)

  osc.process_waveform(context, buffer, Waveform::Triangle, 440.0)

  assert_true(
    buffer.as_fixed_array().every(sample => sample >= -1.0 && sample <= 1.0),
  )
  assert_true((buffer.get(1) - buffer.get(0)).abs() < 0.1)
  assert_true((buffer.get(2) - buffer.get(1)).abs() < 0.1)
}

///|
test "audio buffer initializes and mutates samples" {
  let buffer = AudioBuffer::filled(4, init=0.25)

  assert_eq(buffer.length(), 4)
  assert_eq(buffer.get(0), 0.25)
  assert_eq(buffer.get(3), 0.25)

  buffer.set(1, -0.5)
  buffer.fill(0.75)

  assert_eq(buffer.get(0), 0.75)
  assert_eq(buffer.get(1), 0.75)
  assert_eq(buffer.get(3), 0.75)
}

///|
test "audio buffer can wrap an existing fixed array without copying" {
  let samples = FixedArray::make(4, 0.0)
  let buffer = AudioBuffer::new(samples)

  buffer.set(2, 0.5)

  assert_eq(samples[2], 0.5)
  samples[1] = -0.25
  assert_eq(buffer.get(1), -0.25)
}

///|
test "dsp context stores normalized runtime values" {
  let context = DspContext::new(sample_rate=48000.0, block_size=128)

  assert_eq(context.sample_rate(), 48000.0)
  assert_eq(context.block_size(), 128)
}

///|
test "dsp context normalizes invalid runtime values" {
  let context = DspContext::new(sample_rate=-1.0, block_size=-64)

  assert_eq(context.sample_rate(), 0.0)
  assert_eq(context.block_size(), 0)
}

///|
test "gain with unity amount preserves samples" {
  let gain = Gain::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_gain_test_samples())

  gain.process(context, buffer, 1.0)

  assert_eq(buffer.get(0), 0.25)
  assert_eq(buffer.get(1), -0.5)
  assert_eq(buffer.get(2), 1.0)
  assert_eq(buffer.get(3), -1.0)
}

///|
test "gain with zero amount silences samples" {
  let gain = Gain::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_gain_test_samples())

  gain.process(context, buffer, 0.0)

  assert_true(buffer.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "gain with negative amount inverts polarity" {
  let gain = Gain::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_gain_test_samples())

  gain.process(context, buffer, -2.0)

  assert_eq(buffer.get(0), -0.5)
  assert_eq(buffer.get(1), 1.0)
  assert_eq(buffer.get(2), -2.0)
  assert_eq(buffer.get(3), 2.0)
}

///|
fn make_gain_test_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 0.25
  samples[1] = -0.5
  samples[2] = 1.0
  samples[3] = -1.0
  samples
}

///|
test "mix sums two buffers in place" {
  let mix = Mix::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let output = AudioBuffer::new(make_mix_output_samples())
  let input = AudioBuffer::new(make_mix_input_samples())

  mix.process(context, output, input)

  assert_eq(output.get(0), 0.35)
  assert_eq(output.get(1), -0.3)
  assert_eq(output.get(2), 0.75)
  assert_eq(output.get(3), -0.375)
}

///|
test "mix does not implicitly clip summed output" {
  let mix = Mix::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let output = AudioBuffer::new(make_mix_hot_output_samples())
  let input = AudioBuffer::new(make_mix_hot_input_samples())

  mix.process(context, output, input)

  assert_eq(output.get(0), 1.25)
  assert_eq(output.get(1), -1.3)
}

///|
fn make_mix_output_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 0.25
  samples[1] = -0.5
  samples[2] = 0.5
  samples[3] = -0.25
  samples
}

///|
fn make_mix_input_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 0.1
  samples[1] = 0.2
  samples[2] = 0.25
  samples[3] = -0.125
  samples
}

///|
fn make_mix_hot_output_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(2, 0.0)
  samples[0] = 0.75
  samples[1] = -0.8
  samples
}

///|
fn make_mix_hot_input_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(2, 0.0)
  samples[0] = 0.5
  samples[1] = -0.5
  samples
}

///|
test "noise is deterministic from a seed" {
  let first = Noise::new(12345U)
  let second = Noise::new(12345U)

  assert_eq(first.tick(), second.tick())
  assert_eq(first.tick(), second.tick())
  assert_eq(first.tick(), second.tick())
}

///|
test "noise reset reproduces the same sequence" {
  let noise = Noise::new(99U)
  let first = noise.tick()
  let second = noise.tick()

  noise.reset(99U)

  assert_eq(noise.tick(), first)
  assert_eq(noise.tick(), second)
}

///|
test "noise process fills a block with bounded samples" {
  let noise = Noise::new(7U)
  let context = DspContext::new(sample_rate=48000.0, block_size=128)
  let buffer = AudioBuffer::filled(128)

  noise.process(context, buffer)

  assert_eq(buffer.length(), 128)
  assert_true(buffer.as_fixed_array().any(sample => sample != 0.0))
  assert_true(
    buffer.as_fixed_array().every(sample => sample >= -1.0 && sample <= 1.0),
  )
}

///|
test "clip limits positive and negative peaks symmetrically" {
  let clip = Clip::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_clip_test_samples())

  clip.process(context, buffer, 0.5)

  assert_eq(buffer.get(0), -0.5)
  assert_eq(buffer.get(1), -0.25)
  assert_eq(buffer.get(2), 0.25)
  assert_eq(buffer.get(3), 0.5)
}

///|
test "clip leaves in-range samples unchanged" {
  let clip = Clip::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = AudioBuffer::new(make_clip_in_range_samples())

  clip.process(context, buffer, 0.5)

  assert_eq(buffer.get(0), -0.4)
  assert_eq(buffer.get(1), -0.1)
  assert_eq(buffer.get(2), 0.1)
  assert_eq(buffer.get(3), 0.4)
}

///|
fn make_clip_test_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = -0.75
  samples[1] = -0.25
  samples[2] = 0.25
  samples[3] = 0.75
  samples
}

///|
fn make_clip_in_range_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = -0.4
  samples[1] = -0.1
  samples[2] = 0.1
  samples[3] = 0.4
  samples
}

///|
test "adsr attack reaches full scale then enters decay" {
  let env = Adsr::new(
    attack_ms=1.0,
    decay_ms=10.0,
    sustain=0.5,
    release_ms=10.0,
  )
  let context = DspContext::new(sample_rate=1000.0, block_size=8)

  env.gate_on()

  assert_eq(env.tick(context), 1.0)
  assert_true(env.stage() is EnvStage::Decay)
}

///|
test "adsr decay settles at sustain level" {
  let env = Adsr::new(
    attack_ms=0.0,
    decay_ms=2.0,
    sustain=0.25,
    release_ms=10.0,
  )
  let context = DspContext::new(sample_rate=1000.0, block_size=8)

  env.gate_on()
  ignore(env.tick(context))

  let first_decay = env.tick(context)
  let second_decay = env.tick(context)

  assert_true(first_decay < 1.0)
  assert_eq(second_decay, 0.25)
  assert_true(env.stage() is EnvStage::Sustain)
}

///|
test "adsr release falls from the current level to idle" {
  let env = Adsr::new(attack_ms=0.0, decay_ms=0.0, sustain=0.5, release_ms=2.0)
  let context = DspContext::new(sample_rate=1000.0, block_size=8)

  env.gate_on()
  assert_eq(env.tick(context), 0.5)
  env.gate_off()

  assert_eq(env.tick(context), 0.25)
  assert_eq(env.tick(context), 0.0)
  assert_true(env.stage() is EnvStage::Idle)
}

///|
test "adsr process fills a block of envelope values" {
  let env = Adsr::new(
    attack_ms=0.0,
    decay_ms=0.0,
    sustain=0.75,
    release_ms=10.0,
  )
  let context = DspContext::new(sample_rate=1000.0, block_size=4)
  let buffer = AudioBuffer::filled(4)

  env.gate_on()
  env.process(context, buffer)

  assert_eq(buffer.get(0), 0.75)
  assert_eq(buffer.get(1), 0.75)
  assert_eq(buffer.get(2), 0.75)
  assert_eq(buffer.get(3), 0.75)
}

///|
test "delay line outputs samples after the configured delay" {
  let delay = DelayLine::new(4, delay_samples=2)

  assert_eq(delay.tick(1.0), 0.0)
  assert_eq(delay.tick(2.0), 0.0)
  assert_eq(delay.tick(3.0), 1.0)
  assert_eq(delay.tick(4.0), 2.0)
}

///|
test "zero-delay line passes input through immediately" {
  let delay = DelayLine::new(4, delay_samples=0)

  assert_eq(delay.tick(0.25), 0.25)
  assert_eq(delay.tick(-0.5), -0.5)
}

///|
test "zero-capacity constructor defaults to passthrough delay" {
  let delay = DelayLine::new(0)

  assert_eq(delay.max_delay_samples(), 1)
  assert_eq(delay.delay_samples(), 0)
  assert_eq(delay.tick(0.75), 0.75)
}

///|
test "delay line wraps around its circular buffer" {
  let delay = DelayLine::new(3, delay_samples=3)

  assert_eq(delay.tick(1.0), 0.0)
  assert_eq(delay.tick(2.0), 0.0)
  assert_eq(delay.tick(3.0), 0.0)
  assert_eq(delay.tick(4.0), 1.0)
  assert_eq(delay.tick(5.0), 2.0)
}

///|
test "delay line recirculates echoes when feedback is enabled" {
  let delay = DelayLine::new(4, delay_samples=2, feedback=0.5)

  assert_eq(delay.tick(1.0), 0.0)
  assert_eq(delay.tick(0.0), 0.0)
  assert_eq(delay.tick(0.0), 1.0)
  assert_eq(delay.tick(0.0), 0.0)
  assert_eq(delay.tick(0.0), 0.5)
  assert_eq(delay.tick(0.0), 0.0)
}

///|
test "pan sends mono input fully left at -1 position" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::new(make_pan_test_samples())
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)

  pan.process(context, input, left, right, -1.0)

  assert_eq(left.get(0), 1.0)
  assert_eq(left.get(1), 0.5)
  assert_eq(left.get(2), -0.5)
  assert_eq(left.get(3), -1.0)
  assert_true(right.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "pan uses equal-power gains at center" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::new(make_pan_test_samples())
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)

  pan.process(context, input, left, right, 0.0)

  let center_gain = 0.5.sqrt()
  assert_true((left.get(0) - center_gain).abs() < 0.000000001)
  assert_true((right.get(0) - center_gain).abs() < 0.000000001)
  assert_true((left.get(3) + center_gain).abs() < 0.000000001)
  assert_true((right.get(3) + center_gain).abs() < 0.000000001)
}

///|
test "pan sends mono input fully right at +1 position" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=4)
  let input = AudioBuffer::new(make_pan_test_samples())
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)

  pan.process(context, input, left, right, 1.0)

  assert_true(left.as_fixed_array().every(sample => sample == 0.0))
  assert_eq(right.get(0), 1.0)
  assert_eq(right.get(1), 0.5)
  assert_eq(right.get(2), -0.5)
  assert_eq(right.get(3), -1.0)
}

///|
test "pan clamps finite positions outside the supported range" {
  let pan = Pan::new()
  let context = DspContext::new(sample_rate=48000.0, block_size=2)
  let input = AudioBuffer::new(make_pan_test_samples())
  let left = AudioBuffer::filled(2)
  let right = AudioBuffer::filled(2)

  pan.process(context, input, left, right, 2.0)

  assert_true(left.as_fixed_array().every(sample => sample == 0.0))
  assert_eq(right.get(0), 1.0)
  assert_eq(right.get(1), 0.5)
}

///|
fn make_pan_test_samples() -> FixedArray[Double] {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = 1.0
  samples[1] = 0.5
  samples[2] = -0.5
  samples[3] = -1.0
  samples
}
