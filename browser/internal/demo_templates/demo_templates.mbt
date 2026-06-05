///|
pub fn bd_template() -> Array[@moondsp.DspNode] {
  // Kick drum: pitch sweep 240→60 Hz + amplitude envelope
  // [0] pitch ADSR: fast decay creates frequency sweep
  // [1] scale pitch envelope by 180 Hz range
  // [2] base frequency 60 Hz
  // [3] mix = 60 + env*180 → frequency sweeps 240→60
  // [4] FM sine oscillator reading frequency from mix
  // [5] amplitude ADSR
  // [6] envelope_gain: signal * amp envelope
  // [7] output
  [
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=40.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::gain(0, 180.0),
    @moondsp.DspNode::constant(60.0),
    @moondsp.DspNode::mix(1, 2),
    @moondsp.DspNode::oscillator_from(3, @moondsp.Waveform::Sine),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=120.0,
      sustain=0.0,
      release_ms=80.0,
    ),
    @moondsp.DspNode::envelope_gain(input=4, envelope=5, amount=1.0),
    @moondsp.DspNode::output(6),
  ]
}

///|
pub fn sd_template() -> Array[@moondsp.DspNode] {
  // Snare: bandpass noise + sine body, amplitude envelope
  // [0] noise source
  // [1] bandpass filter at 1.5 kHz (snare body)
  // [2] sine at 180 Hz (tonal body)
  // [3] mix noise + sine layers
  // [4] amplitude ADSR
  // [5] envelope_gain: signal * envelope
  // [6] output
  [
    @moondsp.DspNode::noise(12345U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::BandPass,
      cutoff_hz=1500.0,
      q=1.5,
    ),
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 180.0),
    @moondsp.DspNode::mix(1, 2),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=60.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::envelope_gain(input=3, envelope=4, amount=1.0),
    @moondsp.DspNode::output(5),
  ]
}

///|
pub fn hh_template() -> Array[@moondsp.DspNode] {
  // Hi-hat: high-pass filtered noise, short envelope
  // [0] noise source
  // [1] high-pass filter at 7 kHz
  // [2] amplitude ADSR (very short)
  // [3] envelope_gain: signal * envelope
  // [4] output
  [
    @moondsp.DspNode::noise(67890U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=7000.0,
      q=1.5,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=25.0,
      sustain=0.0,
      release_ms=15.0,
    ),
    @moondsp.DspNode::envelope_gain(input=1, envelope=2, amount=0.6),
    @moondsp.DspNode::output(3),
  ]
}

///|
pub fn oh_template() -> Array[@moondsp.DspNode] {
  // Open hi-hat: same shape as hh but longer decay + slightly lower
  // cutoff so it reads as "open" against the closed hh in patterns.
  // Different noise seed so layered hh + oh don't beat phase-coherently.
  [
    @moondsp.DspNode::noise(24680U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=6000.0,
      q=1.5,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=200.0,
      sustain=0.0,
      release_ms=100.0,
    ),
    @moondsp.DspNode::envelope_gain(input=1, envelope=2, amount=0.45),
    @moondsp.DspNode::output(3),
  ]
}

///|
pub fn cp_template() -> Array[@moondsp.DspNode] {
  // Clap: bandpass noise around 1.2 kHz with a sharp short envelope.
  // The classic 808 multi-burst texture would need a multi-tap envelope
  // primitive we don't have; a single sharp burst still reads as "clap"
  // distinct from sd (which has a tonal sine body and broader bandpass).
  [
    @moondsp.DspNode::noise(13579U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::BandPass,
      cutoff_hz=1200.0,
      q=2.0,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=40.0,
      sustain=0.0,
      release_ms=30.0,
    ),
    @moondsp.DspNode::envelope_gain(input=1, envelope=2, amount=0.7),
    @moondsp.DspNode::output(3),
  ]
}

///|
pub fn synth_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=10.0,
      decay_ms=100.0,
      sustain=0.7,
      release_ms=300.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}
