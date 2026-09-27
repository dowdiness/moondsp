///|
test "biquad rejects invalid parameters and writes silence" {
  let biquad = @dsp.Biquad::new()
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = @dsp.AudioBuffer::filled(4, init=1.0)

  @debug.assert_eq(
    biquad.update(context, @dsp.BiquadMode::LowPass, 0.0, 0.707),
    false,
  )

  biquad.process(context, buffer)

  assert_true(buffer.all(sample => sample == 0.0))
}

///|
test "low-pass filter smooths a step input" {
  let biquad = @dsp.Biquad::new()
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=8)
  let buffer = @dsp.AudioBuffer::filled(8, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::LowPass, 1000.0, 0.707))

  biquad.process(context, buffer)

  assert_true(buffer.get(0) > 0.0)
  assert_true(buffer.get(0) < 1.0)
  assert_true(buffer.get(1) > buffer.get(0))
  assert_true(buffer.get(2) > buffer.get(1))
  assert_true(buffer.get(7) < 1.0)
}

///|
test "high-pass filter attenuates dc across successive blocks" {
  let biquad = @dsp.Biquad::new()
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=64)
  let first = @dsp.AudioBuffer::filled(64, init=1.0)
  let second = @dsp.AudioBuffer::filled(64, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::HighPass, 4000.0, 0.707))

  biquad.process(context, first)
  biquad.process(context, second)

  assert_true(second.get(63).abs() < 0.001)
}

///|
test "band-pass filter rejects dc input" {
  let biquad = @dsp.Biquad::new()
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=64)
  let first = @dsp.AudioBuffer::filled(64, init=1.0)
  let second = @dsp.AudioBuffer::filled(64, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::BandPass, 4000.0, 0.707))

  biquad.process(context, first)
  biquad.process(context, second)

  assert_true(second.get(63).abs() < 0.001)
}

///|
test "biquad respects context block size" {
  let biquad = @dsp.Biquad::new()
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=2)
  let buffer = @dsp.AudioBuffer::filled(4, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::LowPass, 1000.0, 0.707))

  biquad.process(context, buffer)

  assert_true(buffer.get(0) > 0.0)
  assert_true(buffer.get(1) > buffer.get(0))
  @debug.assert_eq(buffer.get(2), 0.0)
  @debug.assert_eq(buffer.get(3), 0.0)
}
