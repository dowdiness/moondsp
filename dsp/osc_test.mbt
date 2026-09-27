///|
test "sine oscillator accumulates phase correctly" {
  let osc = @dsp.Oscillator::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let buf = @dsp.AudioBuffer::filled(4)
  osc.process_waveform(
    context=ctx,
    output=buf,
    waveform=@dsp.Waveform::Sine,
    freq_hz=12000.0,
  )
  // At 12 kHz / 48 kHz, phase advances 0.25 per sample (quarter cycle)
  // Sample 0 starts at phase 0.0 (output = sin(0) = 0), advances to 0.25
  // Sample 1 is at phase 0.25 = sin(2π * 0.25) = sin(π/2) ≈ 1.0
  inspect(buf.get(1) > 0.99 && buf.get(1) <= 1.0, content="true")
}

///|
test "saw oscillator produces distinct output from sine" {
  let osc_sine = @dsp.Oscillator::new()
  let osc_saw = @dsp.Oscillator::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let buf_sine = @dsp.AudioBuffer::filled(4)
  let buf_saw = @dsp.AudioBuffer::filled(4)
  osc_sine.process_waveform(
    context=ctx,
    output=buf_sine,
    waveform=@dsp.Waveform::Sine,
    freq_hz=440.0,
  )
  osc_saw.process_waveform(
    context=ctx,
    output=buf_saw,
    waveform=@dsp.Waveform::Saw,
    freq_hz=440.0,
  )
  assert_true(buf_sine.get(0) != buf_saw.get(0))
}

///|
test "oscillator tick matches process output" {
  let osc1 = @dsp.Oscillator::new()
  let osc2 = @dsp.Oscillator::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let buf = @dsp.AudioBuffer::filled(4)
  osc1.process_waveform(
    context=ctx,
    output=buf,
    waveform=@dsp.Waveform::Sine,
    freq_hz=440.0,
  )
  for i = 0; i < 4; i = i + 1 {
    let sample = osc2.tick_waveform(
      waveform=@dsp.Waveform::Sine,
      freq_hz=440.0,
      sample_rate=48000.0,
    )
    assert_true((buf.get(i) - sample).abs() < 0.000001)
  }
}

///|
test "oscillator reset returns phase to zero" {
  let osc = @dsp.Oscillator::new()
  ignore(osc.tick(freq_hz=440.0, sample_rate=48000.0))
  ignore(osc.tick(freq_hz=440.0, sample_rate=48000.0))
  assert_true(osc.phase() > 0.0)
  osc.reset()
  assert_true(osc.phase() == 0.0)
}

///|
test "oscillator with zero frequency produces zero (sine)" {
  let osc = @dsp.Oscillator::new()
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let buf = @dsp.AudioBuffer::filled(4)
  osc.process_waveform(
    context=ctx,
    output=buf,
    waveform=@dsp.Waveform::Sine,
    freq_hz=0.0,
  )
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "prop: all waveforms output in [-1, 1]" {
  @qc.quick_check_fn(
    fn(raw_freq : Double) {
      let freq = raw_freq.abs() * 19999.0 + 1.0
      let osc = @dsp.Oscillator::new()
      let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
      let waveforms : FixedArray[@dsp.Waveform] = [
        @dsp.Waveform::Sine,
        @dsp.Waveform::Saw,
        @dsp.Waveform::Square,
        @dsp.Waveform::Triangle,
      ]
      for w = 0; w < waveforms.length(); w = w + 1 {
        osc.reset()
        let buf = @dsp.AudioBuffer::filled(128)
        osc.process_waveform(
          context=ctx,
          output=buf,
          waveform=waveforms[w],
          freq_hz=freq,
        )
        for i = 0; i < 128; i = i + 1 {
          if buf.get(i) < -1.0 || buf.get(i) > 1.0 {
            return false
          }
        }
      }
      true
    },
    max_success=100,
  )
}
