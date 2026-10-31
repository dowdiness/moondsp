///|
test "biquad rejects invalid parameters and writes silence" {
  let biquad = @dsp.Biquad()
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=4)
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
  let biquad = @dsp.Biquad()
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=8)
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
  let biquad = @dsp.Biquad()
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=64)
  let first = @dsp.AudioBuffer::filled(64, init=1.0)
  let second = @dsp.AudioBuffer::filled(64, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::HighPass, 4000.0, 0.707))

  biquad.process(context, first)
  biquad.process(context, second)

  assert_true(second.get(63).abs() < 0.001)
}

///|
test "band-pass filter rejects dc input" {
  let biquad = @dsp.Biquad()
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=64)
  let first = @dsp.AudioBuffer::filled(64, init=1.0)
  let second = @dsp.AudioBuffer::filled(64, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::BandPass, 4000.0, 0.707))

  biquad.process(context, first)
  biquad.process(context, second)

  assert_true(second.get(63).abs() < 0.001)
}

///|
test "biquad respects context block size" {
  let biquad = @dsp.Biquad()
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=2)
  let buffer = @dsp.AudioBuffer::filled(4, init=1.0)

  assert_true(biquad.update(context, @dsp.BiquadMode::LowPass, 1000.0, 0.707))

  biquad.process(context, buffer)

  assert_true(buffer.get(0) > 0.0)
  assert_true(buffer.get(1) > buffer.get(0))
  @debug.assert_eq(buffer.get(2), 0.0)
  @debug.assert_eq(buffer.get(3), 0.0)
}

///|
test "biquad impulse preserves core trigonometric rounding across cutoff range" {
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=1)
  let filter = @dsp.Biquad()
  let cutoffs = [ for i in 1..<4096 => i.to_double() * 24000.0 / 4096.0 ]
  // Both sides of reduction boundaries, including the near-Nyquist limit.
  for boundary in [6000.0, 12000.0, 18000.0, 23999.99999999999] {
    let bits = boundary.reinterpret_as_uint64()
    for offset in 0..<=8 {
      cutoffs.push((bits - offset.to_uint64()).reinterpret_as_double())
      let above = (bits + offset.to_uint64()).reinterpret_as_double()
      if above < 24000.0 {
        cutoffs.push(above)
      }
    }
  }
  for cutoff in cutoffs {
    let angle = 2.0 * @math.PI * cutoff / 48000.0
    let cosine = @math.cos(angle)
    let alpha = @math.sin(angle) / (2.0 * 0.73)
    let inverse = 1.0 / (1.0 + alpha)
    for mode in [@dsp.LowPass, @dsp.HighPass, @dsp.BandPass] {
      let numerator = match mode {
        LowPass => (1.0 - cosine) * 0.5
        HighPass => (1.0 + cosine) * 0.5
        BandPass => alpha
      }
      filter.reset()
      assert_true(filter.update(context, mode, cutoff, 0.73))
      assert_eq(filter.tick(1.0), numerator * inverse)
    }
  }
  let huge = @dsp.DspContext(sample_rate=1.0e308, block_size=1)
  assert_false(filter.update(huge, @dsp.LowPass, 4.0e307, 0.73))
  assert_eq(filter.tick(1.0), 0.0)
}
