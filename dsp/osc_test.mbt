///|
test "sine oscillator accumulates phase correctly" {
  let osc = Oscillator::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let buf = AudioBuffer::filled(4)
  osc.process_waveform(ctx, buf, Waveform::Sine, 12000.0)
  // At 12 kHz / 48 kHz, phase advances 0.25 per sample (quarter cycle)
  // Sample 0 starts at phase 0.0 (output = sin(0) = 0), advances to 0.25
  // Sample 1 is at phase 0.25 = sin(2π * 0.25) = sin(π/2) ≈ 1.0
  inspect(buf.get(1) > 0.99 && buf.get(1) <= 1.0, content="true")
}

///|
test "saw oscillator produces distinct output from sine" {
  let osc_sine = Oscillator::new()
  let osc_saw = Oscillator::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let buf_sine = AudioBuffer::filled(4)
  let buf_saw = AudioBuffer::filled(4)
  osc_sine.process_waveform(ctx, buf_sine, Waveform::Sine, 440.0)
  osc_saw.process_waveform(ctx, buf_saw, Waveform::Saw, 440.0)
  assert_true(buf_sine.get(0) != buf_saw.get(0))
}

///|
test "oscillator tick matches process output" {
  let osc1 = Oscillator::new()
  let osc2 = Oscillator::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let buf = AudioBuffer::filled(4)
  osc1.process_waveform(ctx, buf, Waveform::Sine, 440.0)
  for i = 0; i < 4; i = i + 1 {
    let sample = osc2.tick_waveform(Waveform::Sine, 440.0, 48000.0)
    assert_true((buf.get(i) - sample).abs() < 0.000001)
  }
}

///|
test "oscillator reset returns phase to zero" {
  let osc = Oscillator::new()
  ignore(osc.tick(440.0, 48000.0))
  ignore(osc.tick(440.0, 48000.0))
  assert_true(osc.phase() > 0.0)
  osc.reset()
  assert_true(osc.phase() == 0.0)
}

///|
test "oscillator with zero frequency produces zero (sine)" {
  let osc = Oscillator::new()
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let buf = AudioBuffer::filled(4)
  osc.process_waveform(ctx, buf, Waveform::Sine, 0.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "prop: all waveforms output in [-1, 1]" {
  @qc.quick_check_fn(
    fn(raw_freq : Double) {
      let freq = raw_freq.abs() * 19999.0 + 1.0
      let osc = Oscillator::new()
      let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
      let waveforms : FixedArray[Waveform] = [
        Waveform::Sine,
        Waveform::Saw,
        Waveform::Square,
        Waveform::Triangle,
      ]
      for w = 0; w < waveforms.length(); w = w + 1 {
        osc.reset()
        let buf = AudioBuffer::filled(128)
        osc.process_waveform(ctx, buf, waveforms[w], freq)
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
