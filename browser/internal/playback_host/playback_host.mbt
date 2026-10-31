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
let player : @ref.Ref[Player?] = @ref.new(None)

///|
/// Create a drum instrument pool (no control bindings needed).
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
      @moondsp.ControlBindingBuilder::new(),
      max_voices=8,
    ),
  ) catch {
    _ => None
  }
}

///|
/// Create the synth instrument pool (with note->freq binding).
fn make_synth_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool? {
  Some(
    // See make_drum_pool for the .jux headroom rationale.
    @moondsp.BoundVoicePool(
      @moondsp.AnalyzedGraph::analyze(template),
      ctx,
      @moondsp.ControlBindingBuilder::new()
      .bind(
        key="note",
        node_index=0, // oscillator(Value0) frequency placeholder
        slot=@moondsp.GraphParamSlot::Value0,
      )
      .bind(key="attack", node_index=1, slot=@moondsp.GraphParamSlot::Value0)
      .bind(
        key="envelope_decay",
        node_index=1,
        slot=@moondsp.GraphParamSlot::Value1,
      )
      .bind(
        key="envelope_sustain",
        node_index=1,
        slot=@moondsp.GraphParamSlot::Value2,
      )
      .bind(key="release", node_index=1, slot=@moondsp.GraphParamSlot::Value3)
      .bind(key="lpf", node_index=2, slot=@moondsp.GraphParamSlot::Value0)
      .bind(
        key="lpf_resonance",
        node_index=2,
        slot=@moondsp.GraphParamSlot::Value1,
      )
      .bind(key="hpf", node_index=3, slot=@moondsp.GraphParamSlot::Value0)
      .bind(
        key="hpf_resonance",
        node_index=3,
        slot=@moondsp.GraphParamSlot::Value1,
      ),
      // 24 voices for chords: a 5-note chord × 4 layers of jux/stereo
      // needs up to 20 voices. Fewer steals → fewer clicks.
      max_voices=24,
    ),
  ) catch {
    _ => None
  }
}

///|
pub fn init_scheduler_graph_with_templates(
  sample_rate : Double,
  block_size : Int,
  bd_template : Array[@moondsp.DspNode],
  sd_template : Array[@moondsp.DspNode],
  hh_template : Array[@moondsp.DspNode],
  cp_template : Array[@moondsp.DspNode],
  oh_template : Array[@moondsp.DspNode],
  synth_template : Array[@moondsp.DspNode],
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_graph()
    return false
  }
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size~)
  let candidates = [
    (@scheduler.ControlEquals("sound", 36.0), make_drum_pool(bd_template, ctx)),
    (@scheduler.ControlEquals("sound", 38.0), make_drum_pool(sd_template, ctx)),
    (@scheduler.ControlEquals("sound", 42.0), make_drum_pool(hh_template, ctx)),
    (@scheduler.ControlEquals("sound", 39.0), make_drum_pool(cp_template, ctx)),
    (@scheduler.ControlEquals("sound", 46.0), make_drum_pool(oh_template, ctx)),
    (@scheduler.HasControl("note"), make_synth_pool(synth_template, ctx)),
  ]
  let instruments : Array[
    (@scheduler.InstrumentSelector, @moondsp.BoundVoicePool),
  ] = []
  for candidate in candidates {
    match candidate {
      (selector, Some(pool)) => instruments.push((selector, pool))
      (_, None) => {
        reset_scheduler_graph()
        return false
      }
    }
  }
  let scheduler = @scheduler.PatternScheduler(bpm=60.0, ctx~, instruments~) catch {
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
fn checked_sample(index : Int, buffer : @moondsp.AudioBuffer) -> Double {
  guard index >= 0 && index < buffer.length() else { return 0.0 }
  buffer.get(index)
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  match player.val {
    Some(owner) => checked_sample(index, owner.left)
    None => 0.0
  }
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
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
const SCHEDULER_PARSE_STATUS_OK : Int = 0

///|
const SCHEDULER_PARSE_STATUS_ERROR : Int = 1

///|
let sched_last_error : @ref.Ref[String] = @ref.new("")

///|
fn set_scheduler_parse_success() -> Int {
  sched_last_error.val = ""
  SCHEDULER_PARSE_STATUS_OK
}

///|
fn set_scheduler_parse_error(message : String) -> Int {
  sched_last_error.val = message
  SCHEDULER_PARSE_STATUS_ERROR
}

///|
const MAX_PLAYBACK_INPUT_CODE_UNITS : Int = 2097152

///|
let playback_input_chars : Array[Int] = []

///|
let playback_input_overflow : @ref.Ref[Bool] = @ref.new(false)

///|
fn input_chars_to_string(chars : Array[Int]) -> Result[String, String] {
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
pub fn push_playback_char(code : Int) -> Unit {
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
pub fn get_playback_error_length() -> Int {
  sched_last_error.val.length()
}

///|
pub fn get_playback_error_char(i : Int) -> Int {
  let s = sched_last_error.val
  if i < 0 || i >= s.length() {
    0
  } else {
    s[i].to_int()
  }
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Int {
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
