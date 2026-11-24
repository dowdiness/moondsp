///|
/// The sample store of the browser host (ADR-0026 Decision 6): 64 sample
/// numbers, waveforms up to 30 s at 48 kHz, and 32 MiB of samples in all.
pub const SAMPLE_ENTRIES : Int32 = 64

///|
pub const SAMPLE_MAX_LENGTH : Int32 = 1440000

///|
pub const SAMPLE_CAPACITY : Int32 = 8388608

///|
/// Made once by `init_sample_store`. Making it takes 15–20 ms, so the host
/// makes it before the first render, not while one runs.
let sample_store : @ref.Ref[@moondsp.SampleStore?] = Ref(None)

///|
/// Make the browser's sample store if there is none yet. Players built after
/// it read their samples from it. Returns its capacity.
pub fn init_sample_store() -> Int32 {
  match sample_store.val {
    Some(store) => store.capacity()
    None => {
      let store = @moondsp.SampleStore(
        entries=SAMPLE_ENTRIES,
        max_length=SAMPLE_MAX_LENGTH,
        capacity=SAMPLE_CAPACITY,
      )
      sample_store.val = Some(store)
      store.capacity()
    }
  }
}

///|
/// A context of this format that compiles graphs over the sample store, or
/// over an empty store before `init_sample_store`.
fn sample_context(
  sample_rate : Double,
  block_size : Int32,
) -> @moondsp.DspContext {
  match sample_store.val {
    Some(samples) => @moondsp.DspContext(sample_rate~, block_size~, samples~)
    None => @moondsp.DspContext(sample_rate~, block_size~)
  }
}

///|
/// The number of samples in the built-in bank; sample number `n` is
/// `@score.Sample::all()[n]`.
pub fn sample_bank_count() -> Int32 {
  @score.Sample::all().length()
}

///|
/// The name of bank sample `entry`, or "" outside the bank.
pub fn sample_bank_name(entry : Int32) -> String {
  let bank = @score.Sample::all()
  if entry >= 0 && entry < bank.length() {
    bank[entry].name()
  } else {
    ""
  }
}

///|
/// Begin loading a waveform of `length` samples into sample number `entry`.
/// Returns 0, or what refused it: 1 the sample number, 2 the length, 3 the
/// store's memory (ADR-0026 Decision 6), 4 no store yet.
pub fn sample_load_begin(
  entry : Int32,
  length : Int32,
  root_pitch : Double,
) -> Int32 {
  guard sample_store.val is Some(store) else { return 4 }
  match store.begin(entry, length, root_pitch~) {
    None => 0
    Some(Entries) => 1
    Some(Length) => 2
    Some(Memory) => 3
  }
}

///|
/// Write sample `offset` of the waveform being loaded.
pub fn sample_load_write(offset : Int32, value : Float) -> Unit {
  if sample_store.val is Some(store) {
    store.write(offset, value)
  }
}

///|
/// Finish loading, so new notes on the sample number play the waveform.
/// Returns false when nothing was being loaded.
pub fn sample_load_commit() -> Bool {
  match sample_store.val {
    Some(store) => store.commit()
    None => false
  }
}

///|
/// Whether sample number `entry` has a waveform.
pub fn sample_loaded(entry : Int32) -> Bool {
  match sample_store.val {
    Some(store) => store.has(entry)
    None => false
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
/// The one pool every sample plays on (ADR-0026). A note's pitch is the
/// player's MIDI pitch. Its sample number reaches the player once scores
/// play samples (ADR-0026 stage 4, after ADR-0023).
fn make_sample_pool(
  voice : SamplerVoice,
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool? {
  Some(
    @moondsp.BoundVoicePool(
      @moondsp.AnalyzedGraph::analyze(voice.graph()),
      ctx,
      instrument_bindings().bind(
        key=Note,
        node_index=0,
        slot=@moondsp.GraphParamSlot::Value1,
      ),
      max_voices=voice.voices,
    ),
  ) catch {
    _ => None
  }
}
