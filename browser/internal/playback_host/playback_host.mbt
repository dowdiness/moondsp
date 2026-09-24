///|
/// Per-sound pool state: voice pool + scheduler + tmp buffers.
priv struct SoundPool {
  pool : @moondsp.BoundVoicePool
  scheduler : @scheduler.PatternScheduler
  tmp_left : @moondsp.AudioBuffer
  tmp_right : @moondsp.AudioBuffer
  tmp_send_left : @moondsp.AudioBuffer
  tmp_send_right : @moondsp.AudioBuffer
}

///|
priv enum SchedulerRouteSelector {
  RouteSound(Double)
  RouteSynth
}

///|
priv struct SchedulerRoute {
  selector : SchedulerRouteSelector
  pool : SoundPool
}

///|
pub struct Player {
  priv routes : Array[SchedulerRoute]
  priv schedulers : Array[@scheduler.PatternScheduler]
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
  routes : Array[SchedulerRoute],
  context : @moondsp.DspContext,
) -> Player {
  let size = context.block_size()
  {
    routes,
    schedulers: routes.map(route => route.pool.scheduler),
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
/// Create a SoundPool for a drum template (no control bindings needed).
fn make_drum_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SoundPool? {
  let scheduler = match @scheduler.PatternScheduler::new(bpm=60.0, ctx~) {
    Ok(scheduler) => scheduler
    Err(_) => return None
  }
  // 8 voices = defensive headroom for .jux(f) patterns where f causes
  // same-sound overlap (e.g. the demo's hh*16? layer puts left's hh at
  // slot t and right's hh at slot 1-t — frequent coincidence at fine
  // subdivisions). Multi-sound patterns like s("bd sd hh sd").jux(rev)
  // do NOT need this headroom because per-pool pressure stays at 1.
  match
    @moondsp.BoundVoicePool::new(
      @moondsp.AnalyzedGraph::analyze(template),
      ctx,
      @moondsp.ControlBindingBuilder::new(),
      max_voices=8,
    ) {
    Err(_) => None
    Ok(pool) =>
      Some({
        pool,
        scheduler,
        tmp_left: @moondsp.AudioBuffer::filled(block_size),
        tmp_right: @moondsp.AudioBuffer::filled(block_size),
        tmp_send_left: @moondsp.AudioBuffer::filled(block_size),
        tmp_send_right: @moondsp.AudioBuffer::filled(block_size),
      })
  }
}

///|
/// Create a SoundPool for the synth template (with note->freq binding).
fn make_synth_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SoundPool? {
  let scheduler = match @scheduler.PatternScheduler::new(bpm=60.0, ctx~) {
    Ok(scheduler) => scheduler
    Err(_) => return None
  }
  // See make_drum_pool for the .jux headroom rationale.
  match
    @moondsp.BoundVoicePool::new(
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
      )
      .bind(key="gain", node_index=5, slot=@moondsp.GraphParamSlot::Value0),
      // 24 voices for chords: a 5-note chord × 4 layers of jux/stereo
      // needs up to 20 voices. Fewer steals → fewer clicks.
      max_voices=24,
    ) {
    Err(_) => None
    Ok(pool) =>
      Some({
        pool,
        scheduler,
        tmp_left: @moondsp.AudioBuffer::filled(block_size),
        tmp_right: @moondsp.AudioBuffer::filled(block_size),
        tmp_send_left: @moondsp.AudioBuffer::filled(block_size),
        tmp_send_right: @moondsp.AudioBuffer::filled(block_size),
      })
  }
}

///|
fn make_drum_route(
  sound_code : Double,
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SchedulerRoute? {
  match make_drum_pool(template, ctx, block_size) {
    Some(pool) => Some({ selector: RouteSound(sound_code), pool, })
    None => None
  }
}

///|
fn make_synth_route(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SchedulerRoute? {
  match make_synth_pool(template, ctx, block_size) {
    Some(pool) => Some({ selector: RouteSynth, pool, })
    None => None
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
  let route_candidates = [
    make_drum_route(36.0, bd_template, ctx, block_size),
    make_drum_route(38.0, sd_template, ctx, block_size),
    make_drum_route(42.0, hh_template, ctx, block_size),
    make_drum_route(39.0, cp_template, ctx, block_size),
    make_drum_route(46.0, oh_template, ctx, block_size),
    make_synth_route(synth_template, ctx, block_size),
  ]
  let routes : Array[SchedulerRoute] = []
  for candidate in route_candidates {
    match candidate {
      Some(route) => routes.push(route)
      None => {
        reset_scheduler_graph()
        return false
      }
    }
  }
  player.val = Some(Player(routes, ctx))
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
/// Accumulate one sub-pool's rendered tmp buffers into main buffers.
fn accumulate_sub_pool(
  sp : SoundPool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) + sp.tmp_left.get(i))
    right.set(i, right.get(i) + sp.tmp_right.get(i))
  }
}

///|
fn filter_pat_for_route(
  selector : SchedulerRouteSelector,
  pat : @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] {
  match selector {
    RouteSynth => pat.select_control("note")
    RouteSound(code) => pat.select_control("sound", value=code)
  }
}

///|
fn filter_section_for_route(
  selector : SchedulerRouteSelector,
  section : @song.Section[@pattern.ControlMap],
) -> Result[@song.Section[@pattern.ControlMap], String] {
  let body = @song.SectionBody::single(
    filter_pat_for_route(selector, section.body()),
  )
  let filtered = @song.Section(
    name=section.name(),
    length_cycles=section.length_cycles(),
    scope=section.scope(),
    body~,
  ) catch {
    _ => return Err("internal song routing error: invalid section length")
  }
  Ok(filtered)
}

///|
fn filter_song_for_route(
  selector : SchedulerRouteSelector,
  song : @song.Song[@pattern.ControlMap],
) -> Result[@song.Song[@pattern.ControlMap], String] {
  let parts : Array[@song.SongPart[@pattern.ControlMap]] = []
  for occurrence in song.occurrences() {
    match filter_section_for_route(selector, occurrence.section()) {
      Ok(section) =>
        parts.push(
          @song.SongPart::with_id_at(
            id=occurrence.id(),
            start=occurrence.start(),
            name=occurrence.name(),
            section~,
          ),
        )
      Err(msg) => return Err(msg)
    }
  }
  let filtered = @song.Song(parts~) catch {
    _ => return Err("internal song routing error: invalid song layout")
  }
  Ok(filtered)
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
  self.send_left.fill(0.0)
  self.send_right.fill(0.0)
  for route in self.routes {
    let sp = route.pool
    sp.scheduler.render_block_with_send(
      sp.pool,
      sp.tmp_left,
      sp.tmp_right,
      sp.tmp_send_left,
      sp.tmp_send_right,
    )
    if sp.scheduler.last_transport_error() is Some(_) {
      self.session = Fault("transport range exhausted")
      self.left.fill(0.0)
      self.right.fill(0.0)
      for route in self.routes {
        route.pool.pool.kill_all()
      }
      ignore(set_scheduler_parse_error("transport range exhausted"))
      return false
    }
    for i in 0..<self.context.block_size() {
      self.send_left.set(i, self.send_left.get(i) + sp.tmp_send_left.get(i))
      self.send_right.set(i, self.send_right.get(i) + sp.tmp_send_right.get(i))
    }
    accumulate_sub_pool(sp, self.left, self.right)
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
    let scheduler = self.schedulers[0]
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
  match @scheduler.set_tempo_all(owner.schedulers, tempo, end_?) {
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
