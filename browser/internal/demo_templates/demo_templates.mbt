///|
fn bd_template() -> Array[@moondsp.DspNode] {
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
fn sd_template() -> Array[@moondsp.DspNode] {
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
fn hh_template() -> Array[@moondsp.DspNode] {
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
fn oh_template() -> Array[@moondsp.DspNode] {
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
fn cp_template() -> Array[@moondsp.DspNode] {
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
/// The sound of each drum.
pub fn drum_template(drum : @score.Drum) -> Array[@moondsp.DspNode] {
  match drum {
    Bd => bd_template()
    Sd => sd_template()
    Cp => cp_template()
    Hh => hh_template()
    Oh => oh_template()
  }
}

///|
/// The sound of each instrument. The oscillators are not band-limited, so
/// the brighter waveforms sit behind a low-pass default. Triangle, the
/// default, has 24 voices for a 5-note chord × 4 layers of jux/stereo, so
/// fewer steals click; the others have 12, a 5-note chord under `.jux`.
pub fn instrument_voice(
  instrument : @score.Instrument,
) -> @playback_host.NoteVoice {
  match instrument {
    // The default instrument is Triangle for now: Dsp Sine still crackles
    // in AudioWorklet probes, while JS sine and direct wasm tick-block are
    // clean. Follow-ups:
    // https://github.com/dowdiness/moondsp/issues/211
    // https://github.com/dowdiness/moondsp/issues/212
    Triangle =>
      {
        waveform: Triangle,
        attack_ms: 2.0,
        decay_ms: 800.0,
        sustain: 0.08,
        release_ms: 20.0,
        lpf_hz: 8000.0,
        lpf_q: 0.707,
        amount: 0.5,
        voices: 24,
      }
    Bass =>
      {
        waveform: Saw,
        attack_ms: 3.0,
        decay_ms: 300.0,
        sustain: 0.6,
        release_ms: 80.0,
        lpf_hz: 700.0,
        lpf_q: 1.2,
        amount: 0.45,
        voices: 12,
      }
    Pad =>
      {
        waveform: Saw,
        attack_ms: 400.0,
        decay_ms: 1200.0,
        sustain: 0.7,
        release_ms: 900.0,
        lpf_hz: 1800.0,
        lpf_q: 0.707,
        amount: 0.22,
        voices: 12,
      }
    Pluck =>
      {
        waveform: Square,
        attack_ms: 1.0,
        decay_ms: 180.0,
        sustain: 0.0,
        release_ms: 120.0,
        lpf_hz: 3000.0,
        lpf_q: 0.707,
        amount: 0.3,
        voices: 12,
      }
    Sawtooth =>
      {
        waveform: Saw,
        attack_ms: 5.0,
        decay_ms: 200.0,
        sustain: 0.7,
        release_ms: 120.0,
        lpf_hz: 6000.0,
        lpf_q: 0.707,
        amount: 0.3,
        voices: 12,
      }
  }
}
