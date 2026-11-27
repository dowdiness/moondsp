///|
/// Kick: a pitch envelope sweeps a sine from 248 Hz to 48 Hz, then a gain and
/// a clip saturate it before the amplitude envelope.
fn kick_graph() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=45.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::gain(0, 200.0),
    @moondsp.DspNode::constant(48.0),
    @moondsp.DspNode::mix(1, 2),
    @moondsp.DspNode::oscillator_from(3, @moondsp.Waveform::Sine),
    @moondsp.DspNode::gain(4, 2.2),
    @moondsp.DspNode::clip(5, 0.9),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=260.0,
      sustain=0.0,
      release_ms=120.0,
    ),
    @moondsp.DspNode::envelope_gain(input=6, envelope=7, amount=0.65),
    @moondsp.DspNode::output(8),
  ]
}

///|
/// Snare: band-passed and high-passed noise over a triangle body.
fn snare_graph() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::noise(12345U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::BandPass,
      cutoff_hz=1800.0,
      q=1.2,
    ),
    @moondsp.DspNode::biquad(
      input=1,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=600.0,
      q=0.707,
    ),
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Triangle, 190.0),
    @moondsp.DspNode::gain(3, 0.6),
    @moondsp.DspNode::mix(2, 4),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=140.0,
      sustain=0.0,
      release_ms=60.0,
    ),
    @moondsp.DspNode::envelope_gain(input=5, envelope=6, amount=0.8),
    @moondsp.DspNode::output(7),
  ]
}

///|
/// Clap: a 12 ms noise burst repeated by a feedback delay (10 ms), the
/// multi-burst the browser's clap template says it lacks, plus a noise tail.
fn clap_graph() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::noise(13579U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::BandPass,
      cutoff_hz=1100.0,
      q=2.5,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=0.3,
      decay_ms=12.0,
      sustain=0.0,
      release_ms=8.0,
    ),
    @moondsp.DspNode::envelope_gain(input=1, envelope=2, amount=1.0),
    @moondsp.DspNode::delay(
      input=3,
      max_delay_samples=2048,
      delay_samples=480,
      feedback=0.45,
    ),
    @moondsp.DspNode::mix(3, 4),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=160.0,
      sustain=0.0,
      release_ms=80.0,
    ),
    @moondsp.DspNode::envelope_gain(input=1, envelope=6, amount=0.25),
    @moondsp.DspNode::mix(5, 7),
    @moondsp.DspNode::gain(8, 3.0),
    @moondsp.DspNode::output(9),
  ]
}

///|
/// Hats: high-passed noise ring-modulated (`mul`) by a square wave for a
/// metallic tone. `decay_ms` makes the closed and the open hat.
fn hat_graph(
  seed : UInt32,
  decay_ms : Double,
  amount : Double,
) -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::noise(seed),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=7500.0,
      q=1.0,
    ),
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Square, 5400.0),
    @moondsp.DspNode::mul(1, 2),
    @moondsp.DspNode::biquad(
      input=3,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=6000.0,
      q=0.707,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=0.3,
      decay_ms~,
      sustain=0.0,
      release_ms=decay_ms * 0.5,
    ),
    @moondsp.DspNode::envelope_gain(input=4, envelope=5, amount~),
    @moondsp.DspNode::output(6),
  ]
}

///|
fn drum_graph(drum : @score.Drum) -> Array[@moondsp.DspNode] {
  match drum {
    Bd => kick_graph()
    Sd => snare_graph()
    Cp => clap_graph()
    Hh => hat_graph(67890U, 35.0, 0.8)
    Oh => hat_graph(24680U, 260.0, 0.6)
  }
}

///|
/// The note instruments. Only the waveform, envelope, low-pass and level of
/// each can change: the player fixes the graph layout of every instrument.
fn instrument_voice(instrument : @score.Instrument) -> @player.NoteVoice {
  match instrument {
    Triangle =>
      {
        waveform: Triangle,
        attack_ms: 2.0,
        decay_ms: 600.0,
        sustain: 0.1,
        release_ms: 200.0,
        lpf_hz: 8000.0,
        lpf_q: 0.707,
        amount: 0.5,
        voices: 24,
      }
    Bass =>
      {
        waveform: Saw,
        attack_ms: 3.0,
        decay_ms: 250.0,
        sustain: 0.55,
        release_ms: 60.0,
        lpf_hz: 600.0,
        lpf_q: 1.5,
        amount: 0.5,
        voices: 8,
      }
    Pad =>
      {
        waveform: Saw,
        attack_ms: 400.0,
        decay_ms: 1500.0,
        sustain: 0.7,
        release_ms: 1200.0,
        lpf_hz: 1800.0,
        lpf_q: 0.707,
        amount: 0.16,
        voices: 16,
      }
    Pluck =>
      {
        waveform: Square,
        attack_ms: 1.0,
        decay_ms: 160.0,
        sustain: 0.0,
        release_ms: 120.0,
        lpf_hz: 2600.0,
        lpf_q: 0.9,
        amount: 0.28,
        voices: 16,
      }
    Sawtooth =>
      {
        waveform: Saw,
        attack_ms: 5.0,
        decay_ms: 300.0,
        sustain: 0.6,
        release_ms: 150.0,
        lpf_hz: 5000.0,
        lpf_q: 0.707,
        amount: 0.3,
        voices: 12,
      }
  }
}

///|
fn sampler_voice() -> @player.SamplerVoice {
  {
    attack_ms: 1.0,
    decay_ms: 0.0,
    sustain: 1.0,
    release_ms: 60.0,
    lpf_hz: 16000.0,
    lpf_q: 0.707,
    amount: 0.8,
    voices: 16,
  }
}

///|
/// Synthesize the built-in bank's two samples, as the browser host's
/// generated bank does, and register them at their bank numbers and roots.
fn register_samples(
  store : @moondsp.SampleStore,
  sample_rate : Double,
) -> Array[String] {
  let problems : Array[String] = []
  // ping: a decaying sine at the sample's root pitch (MIDI 69 = 440 Hz).
  let ping_len = (sample_rate * 1.0).to_int()
  let ping = FixedArray::make(ping_len, Float::from_int(0))
  for i in 0..<ping_len {
    let t = i.to_double() / sample_rate
    let env = @math.exp(-t * 5.0)
    let tone = @math.sin(2.0 * @math.PI * 440.0 * t) +
      0.3 * @math.sin(2.0 * @math.PI * 880.0 * t)
    ping[i] = Float::from_double(0.6 * env * tone)
  }
  // burst: a short decaying noise burst from a fixed LCG seed.
  let burst_len = (sample_rate * 0.4).to_int()
  let burst = FixedArray::make(burst_len, Float::from_int(0))
  let mut state : UInt32 = 2463534242U
  for i in 0..<burst_len {
    state = state * 1664525U + 1013904223U
    let white = (state >> 8).to_double() / 16777216.0 * 2.0 - 1.0
    let t = i.to_double() / sample_rate
    burst[i] = Float::from_double(0.7 * @math.exp(-t * 12.0) * white)
  }
  for
    entry in [(@score.Sample::all()[0], ping), (@score.Sample::all()[1], burst)] {
    let (sample, wave) = entry
    match
      store.register(sample.number(), wave, root_pitch=sample.root_pitch()) {
      None => ()
      Some(limit) =>
        problems.push("sample \{sample.name()}: \{limit.to_repr()}")
    }
  }
  problems
}
