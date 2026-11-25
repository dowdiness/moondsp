///|
/// Mini's voice-frame keys, which every instrument receives.
fn voice_frame_bindings() -> @moondsp.ControlBindingBuilder[@moondsp.Control] {
  let bindings : @moondsp.ControlBindingBuilder[@moondsp.Control] = @moondsp.ControlBindingBuilder()
  bindings
  .bind_voice(key=Gain, param=Gain)
  .bind_voice(key=Pan, param=Pan)
  .bind_voice(key=Room, param=Send)
}

///|
/// Create a drum instrument pool (voice-frame bindings only).
fn make_drum_pool(
  graph : @moondsp.AnalyzedGraph,
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool? {
  Some(
    // 8 voices = defensive headroom for .jux(f) patterns where f causes
    // same-sound overlap (e.g. the demo's hh*16? layer puts left's hh at
    // slot t and right's hh at slot 1-t — frequent coincidence at fine
    // subdivisions). Multi-sound patterns like s("bd sd hh sd").jux(rev)
    // do NOT need this headroom because per-pool pressure stays at 1.
    @moondsp.BoundVoicePool(graph, ctx, voice_frame_bindings(), max_voices=8),
  ) catch {
    _ => None
  }
}

///|
/// The sound of a note instrument. The player builds its graph, so the graph
/// always has the node layout that `make_note_pool` binds controls to.
pub(all) struct NoteVoice {
  waveform : @moondsp.Waveform
  attack_ms : Double
  decay_ms : Double
  sustain : Double
  release_ms : Double
  lpf_hz : Double
  lpf_q : Double
  /// Envelope depth, which sets the voice's level.
  amount : Double
  /// How many notes the instrument sounds at once.
  voices : Int32
}

///|
/// [0] oscillator, [1] adsr, [2] low-pass, [3] high-pass: the indices
/// `make_note_pool` binds. `note` binds directly to oscillator Value0: a
/// constant -> oscillator_from path crackled on sustained browser notes.
fn NoteVoice::graph(self : NoteVoice) -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(self.waveform, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=self.attack_ms,
      decay_ms=self.decay_ms,
      sustain=self.sustain,
      release_ms=self.release_ms,
    ),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=self.lpf_hz,
      q=self.lpf_q,
    ),
    @moondsp.DspNode::biquad(
      input=2,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=20.0,
      q=0.707,
    ),
    @moondsp.DspNode::envelope_gain(input=3, envelope=1, amount=self.amount),
    @moondsp.DspNode::gain(4, 1.0),
    @moondsp.DspNode::output(5),
  ]
}

///|
/// The voice-frame keys and the envelope and filters of the `NoteVoice`
/// layout: [1] adsr, [2] low-pass, [3] high-pass. Every pitched pool binds
/// them; each binds `Note` to its own source.
fn instrument_bindings() -> @moondsp.ControlBindingBuilder[@moondsp.Control] {
  voice_frame_bindings()
  .bind(
    key=Attack,
    node_index=1,
    slot=@moondsp.GraphParamSlot::Value0,
    unit=SecondsToMs,
  )
  .bind(key=Decay, node_index=1, slot=@moondsp.GraphParamSlot::Value1)
  .bind(key=Sustain, node_index=1, slot=@moondsp.GraphParamSlot::Value2)
  .bind(
    key=Release,
    node_index=1,
    slot=@moondsp.GraphParamSlot::Value3,
    unit=SecondsToMs,
  )
  .bind(key=Lpf, node_index=2, slot=@moondsp.GraphParamSlot::Value0)
  .bind(key=LpfResonance, node_index=2, slot=@moondsp.GraphParamSlot::Value1)
  .bind(key=Hpf, node_index=3, slot=@moondsp.GraphParamSlot::Value0)
  .bind(key=HpfResonance, node_index=3, slot=@moondsp.GraphParamSlot::Value1)
}

///|
/// Create a note instrument pool (with note->freq binding).
fn make_note_pool(
  voice : NoteVoice,
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool? {
  Some(
    // See make_drum_pool for the .jux headroom rationale.
    @moondsp.BoundVoicePool(
      @moondsp.AnalyzedGraph::analyze(voice.graph()),
      ctx,
      instrument_bindings().bind(
        key=Note,
        node_index=0, // oscillator(Value0) frequency placeholder
        slot=@moondsp.GraphParamSlot::Value0,
        unit=MidiToHz,
      ),
      max_voices=voice.voices,
    ),
  ) catch {
    _ => None
  }
}

///|
/// The sound of the sampler, which plays every sample: the envelope and
/// filters of an instrument over a sample player.
pub(all) struct SamplerVoice {
  attack_ms : Double
  decay_ms : Double
  sustain : Double
  release_ms : Double
  lpf_hz : Double
  lpf_q : Double
  /// Envelope depth, which sets the voice's level.
  amount : Double
  /// How many samples the sampler sounds at once.
  voices : Int32
}

///|
/// The `NoteVoice` layout with a sample player at [0]: [1] adsr, [2]
/// low-pass, [3] high-pass, so the instrument bindings apply unchanged. The
/// player starts on no sample, which is silence.
fn SamplerVoice::graph(self : SamplerVoice) -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::sample_player(number=-1.0, pitch=60.0, speed=1.0),
    @moondsp.DspNode::adsr(
      attack_ms=self.attack_ms,
      decay_ms=self.decay_ms,
      sustain=self.sustain,
      release_ms=self.release_ms,
    ),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=self.lpf_hz,
      q=self.lpf_q,
    ),
    @moondsp.DspNode::biquad(
      input=2,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=20.0,
      q=0.707,
    ),
    @moondsp.DspNode::envelope_gain(input=3, envelope=1, amount=self.amount),
    @moondsp.DspNode::gain(4, 1.0),
    @moondsp.DspNode::output(5),
  ]
}

///|
/// The one pool every sample plays on (ADR-0026). A note's sample number
/// and MIDI pitch, which the scheduler sets from its `Play` sound, are the
/// player's sample and pitch.
fn make_sample_pool(
  voice : SamplerVoice,
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool? {
  Some(
    @moondsp.BoundVoicePool(
      @moondsp.AnalyzedGraph::analyze(voice.graph()),
      ctx,
      instrument_bindings()
      .bind(
        key=SampleNumber,
        node_index=0,
        slot=@moondsp.GraphParamSlot::Value0,
      )
      .bind(key=Note, node_index=0, slot=@moondsp.GraphParamSlot::Value1)
      .bind(key=Speed, node_index=0, slot=@moondsp.GraphParamSlot::Value2)
      .bind(key=Begin, node_index=0, slot=@moondsp.GraphParamSlot::Value3)
      .bind(key=End, node_index=0, slot=@moondsp.GraphParamSlot::Value4),
      max_voices=voice.voices,
    ),
  ) catch {
    _ => None
  }
}

///|
/// A scheduler with a voice pool for every drum and instrument, built from
/// `drum` and `instrument`, and one for every sample, built from `sampler`.
/// Pools read samples from `ctx`'s sample store. `None` when a pool or the
/// scheduler refuses `ctx`'s format.
fn scheduler_with_sounds(
  ctx : @moondsp.DspContext,
  drum : (@score.Drum) -> @moondsp.AnalyzedGraph,
  instrument : (@score.Instrument) -> NoteVoice,
  sampler : SamplerVoice,
) -> @scheduler.PatternScheduler? {
  let drums = @score.Drum::all()
  let instruments = @score.Instrument::all()
  // Every sample plays on the sampler pool, the last.
  let candidates = [
    ..drums.map(d => make_drum_pool(drum(d), ctx)),
    ..instruments.map(i => make_note_pool(instrument(i), ctx)),
    make_sample_pool(sampler, ctx),
  ]
  let pools : Array[@moondsp.BoundVoicePool] = []
  for candidate in candidates {
    guard candidate is Some(pool) else { return None }
    pools.push(pool)
  }
  // `pools` holds the drums, then the instruments, each in `all()` order;
  // `all()` lists every constructor, so each search finds its sound.
  let route = (sound : @score.Sound) => {
    match sound {
      Hit(d) => drums.search(d).unwrap()
      Note(i, ..) => drums.length() + instruments.search(i).unwrap()
      Play(_, ..) => drums.length() + instruments.length()
    }
  }
  Some(@scheduler.PatternScheduler(bpm=@mini.DEFAULT_BPM, ctx~, pools~, route~)) catch {
    _ => None
  }
}
