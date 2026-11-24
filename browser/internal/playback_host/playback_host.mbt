///|
pub struct Player {
  priv scheduler : @scheduler.PatternScheduler
  priv onsets : @scheduler.OnsetBuffer
  priv context : @moondsp.DspContext
  priv left : @moondsp.AudioBuffer
  priv right : @moondsp.AudioBuffer
  priv reverb : @moondsp.StereoReverb
  priv send_left : @moondsp.AudioBuffer
  priv send_right : @moondsp.AudioBuffer
  priv wet_left : @moondsp.AudioBuffer
  priv wet_right : @moondsp.AudioBuffer
  priv mut gain : Double
  priv mut session : Session
}

///|
fn Player::Player(
  scheduler : @scheduler.PatternScheduler,
  context : @moondsp.DspContext,
) -> Player {
  let size = context.block_size()
  let onsets = @scheduler.OnsetBuffer()
  scheduler.attach_onset_buffer(onsets)
  {
    scheduler,
    onsets,
    context,
    left: @moondsp.AudioBuffer::filled(size),
    right: @moondsp.AudioBuffer::filled(size),
    reverb: @moondsp.StereoReverb::StereoReverb(context.sample_rate()),
    send_left: @moondsp.AudioBuffer::filled(size),
    send_right: @moondsp.AudioBuffer::filled(size),
    wet_left: @moondsp.AudioBuffer::filled(size),
    wet_right: @moondsp.AudioBuffer::filled(size),
    gain: 0.5,
    session: Empty,
  }
}

///|
let player : @ref.Ref[Player?] = Ref(None)

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
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool? {
  Some(
    // 8 voices = defensive headroom for .jux(f) patterns where f causes
    // same-sound overlap (e.g. the demo's hh*16? layer puts left's hh at
    // slot t and right's hh at slot 1-t — frequent coincidence at fine
    // subdivisions). Multi-sound patterns like s("bd sd hh sd").jux(rev)
    // do NOT need this headroom because per-pool pressure stays at 1.
    @moondsp.BoundVoicePool(
      @moondsp.AnalyzedGraph::analyze(template),
      ctx,
      voice_frame_bindings(),
      max_voices=8,
    ),
  ) catch {
    _ => None
  }
}

///|
/// The sound of a note instrument. The host builds its graph, so the graph
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
/// Give every drum and instrument a voice pool, built from `drum` and
/// `instrument`, and the samples one pool, built from `sampler`. Pools read
/// samples from the store `init_sample_store` made, if it made one.
pub fn init_scheduler_graph_with_sounds(
  sample_rate : Double,
  block_size : Int32,
  drum~ : (@score.Drum) -> Array[@moondsp.DspNode],
  instrument~ : (@score.Instrument) -> NoteVoice,
  sampler~ : SamplerVoice,
) -> Bool {
  // The scheduler and its voice pools refuse any format they cannot run.
  let ctx = sample_context(sample_rate, block_size)
  let drums = @score.Drum::all()
  let instruments = @score.Instrument::all()
  // No sound routes to the sampler pool, the last, until scores play
  // samples (ADR-0026 stage 4, after ADR-0023).
  let candidates = [
    ..drums.map(d => make_drum_pool(drum(d), ctx)),
    ..instruments.map(i => make_note_pool(instrument(i), ctx)),
    make_sample_pool(sampler, ctx),
  ]
  let pools : Array[@moondsp.BoundVoicePool] = []
  for candidate in candidates {
    guard candidate is Some(pool) else {
      reset_scheduler_graph()
      return false
    }
    pools.push(pool)
  }
  // `pools` holds the drums, then the instruments, each in `all()` order;
  // `all()` lists every constructor, so each search finds its sound.
  let route = (sound : @score.Sound) => {
    match sound {
      Hit(d) => drums.search(d).unwrap()
      Note(i, ..) => drums.length() + instruments.search(i).unwrap()
    }
  }
  let scheduler = @scheduler.PatternScheduler(
    bpm=@mini.DEFAULT_BPM,
    ctx~,
    pools~,
    route~,
  ) catch {
    _ => {
      reset_scheduler_graph()
      return false
    }
  }
  player.val = Some(Player(scheduler, ctx))
  playback_input_chars.clear()
  true
}

///|
pub fn reset_scheduler_graph() -> Unit {
  player.val = None
  playback_input_chars.clear()
}

///|
fn checked_sample(index : Int32, buffer : @moondsp.AudioBuffer) -> Double {
  guard index >= 0 && index < buffer.length() else { return 0.0 }
  buffer.get(index)
}

///|
pub fn scheduler_left_sample(index : Int32) -> Double {
  match player.val {
    Some(owner) => checked_sample(index, owner.left)
    None => 0.0
  }
}

///|
pub fn scheduler_right_sample(index : Int32) -> Double {
  match player.val {
    Some(owner) => checked_sample(index, owner.right)
    None => 0.0
  }
}

///|
pub fn process_scheduler_block() -> Bool {
  guard player.val is Some(owner) else {
    ignore(set_scheduler_parse_error("Player is not initialized"))
    return false
  }
  owner.process()
}

///|
fn Player::process(self : Player) -> Bool {
  self.left.fill(0.0)
  self.right.fill(0.0)
  match self.session {
    Empty | Ready(_) | Paused(_) => return true
    Fault(message) => {
      ignore(set_scheduler_parse_error(message))
      return false
    }
    Playing(_) | Ended(_, _, _) => ()
  }
  self.scheduler.render_block_with_send(
    self.left,
    self.right,
    self.send_left,
    self.send_right,
  )
  if self.scheduler.last_transport_error() is Some(_) {
    self.session = Fault("transport range exhausted")
    self.left.fill(0.0)
    self.right.fill(0.0)
    self.scheduler.kill_all_voices()
    ignore(set_scheduler_parse_error("transport range exhausted"))
    return false
  }
  self.reverb.process(
    self.context,
    self.send_left,
    self.send_right,
    self.wet_left,
    self.wet_right,
  )
  for i in 0..<self.context.block_size() {
    self.left.set(i, (self.left.get(i) + self.wet_left.get(i)) * self.gain)
    self.right.set(i, (self.right.get(i) + self.wet_right.get(i)) * self.gain)
  }
  if self.session is Playing(song) && song.finite_end() is Some(end_) {
    let scheduler = self.scheduler
    match scheduler.sample_at(end_) {
      Ok(end_sample) if scheduler.sample_counter() >= end_sample =>
        self.session = Ended(song, end_sample, end_.to_double())
      Ok(_) => ()
      Err(_) => {
        self.session = Fault("song end exceeds transport range")
        ignore(set_scheduler_parse_error("song end exceeds transport range"))
        return false
      }
    }
  }
  true
}

///|
const SCHEDULER_PARSE_STATUS_OK : Int32 = 0

///|
const SCHEDULER_PARSE_STATUS_ERROR : Int32 = 1

///|
let sched_last_error : @ref.Ref[String] = Ref("")

///|
fn set_scheduler_parse_success() -> Int32 {
  sched_last_error.val = ""
  SCHEDULER_PARSE_STATUS_OK
}

///|
fn set_scheduler_parse_error(message : String) -> Int32 {
  sched_last_error.val = message
  SCHEDULER_PARSE_STATUS_ERROR
}

///|
const MAX_PLAYBACK_INPUT_CODE_UNITS : Int32 = 2097152

///|
let playback_input_chars : Array[Int32] = []

///|
let playback_input_overflow : @ref.Ref[Bool] = Ref(false)

///|
fn input_chars_to_string(chars : Array[Int32]) -> Result[String, String] {
  let buf = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let code = chars[i]
    guard code >= 0 && code <= 0xffff else {
      return Err("invalid UTF-16 code unit")
    }
    if code >= 0xd800 && code <= 0xdbff {
      guard i + 1 < chars.length() else {
        return Err("invalid UTF-16 surrogate pair")
      }
      let next = chars[i + 1]
      guard next >= 0xdc00 && next <= 0xdfff else {
        return Err("invalid UTF-16 surrogate pair")
      }
      buf.write_char(code.unsafe_to_char())
      buf.write_char(next.unsafe_to_char())
      i += 2
    } else {
      guard code < 0xdc00 || code > 0xdfff else {
        return Err("invalid UTF-16 surrogate pair")
      }
      buf.write_char(code.unsafe_to_char())
      i += 1
    }
  }
  Ok(buf.to_string())
}

///|
pub fn clear_playback_input() -> Unit {
  playback_input_chars.clear()
  playback_input_overflow.val = false
}

///|
pub fn push_playback_char(code : Int32) -> Unit {
  if code < 0 ||
    code > 0xffff ||
    playback_input_chars.length() >= MAX_PLAYBACK_INPUT_CODE_UNITS {
    playback_input_overflow.val = true
  } else {
    playback_input_chars.push(code)
  }
}

///|
pub fn get_playback_error() -> String {
  sched_last_error.val
}

///|
pub fn get_playback_error_length() -> Int32 {
  sched_last_error.val.length()
}

///|
pub fn get_playback_error_char(i : Int32) -> Int32 {
  let s = sched_last_error.val
  if i < 0 || i >= s.length() {
    0
  } else {
    s[i].to_int()
  }
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Int32 {
  guard player.val is Some(owner) else {
    return set_scheduler_parse_error("Player is not initialized")
  }
  let tempo = match @scheduler.Tempo::from_bpm(bpm) {
    Ok(tempo) => tempo
    Err(_) => return set_scheduler_parse_error("tempo must be 0.001..1000 BPM")
  }
  if owner.session.song() is Some(song) {
    match owner.check_repeat_span(song.span, tempo) {
      Err(error) => return set_scheduler_parse_error(error.message())
      Ok(_) => ()
    }
    if song.finite_end() is Some(end_) {
      match
        tempo.sample_at_start(end_, sample_rate=owner.context.sample_rate()) {
        Err(_) =>
          return set_scheduler_parse_error("song end exceeds transport range")
        Ok(_) => ()
      }
    }
  }
  let end_ = match owner.session.song() {
    Some(song) => song.finite_end()
    None => None
  }
  match owner.scheduler.set_tempo(tempo, end_?) {
    Err(_) => set_scheduler_parse_error("tempo change exceeds transport range")
    Ok(_) => {
      if owner.session.song() is Some(song) {
        let next = { ..song, tempo, }
        owner.session = match owner.session {
          Ready(_) => Ready(next)
          Playing(_) => Playing(next)
          Paused(_) => Paused(next)
          Ended(_, position, cycle) => Ended(next, position, cycle)
          other => other
        }
      }
      set_scheduler_parse_success()
    }
  }
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  if player.val is Some(owner) {
    owner.gain = if gain.is_nan() || gain.is_inf() {
      0.5
    } else {
      Double::min(1.0, Double::max(0.0, gain))
    }
  }
}
