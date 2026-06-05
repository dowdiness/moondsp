///|
/// Active playback source parsed from the explicit browser protocol.
priv enum SchedulerActivePlayback {
  ActivePattern(@pattern.Pat[@pattern.ControlMap])
  ActiveSong(Array[@song.Song[@pattern.ControlMap]])
}

///|
let sched_active_playback : @ref.Ref[SchedulerActivePlayback?] = @ref.new(None)

///|
/// Per-sound pool state: voice pool + scheduler + tmp buffers.
priv struct SoundPool {
  pool : @moondsp.BoundVoicePool
  scheduler : @scheduler.PatternScheduler
  tmp_left : @moondsp.AudioBuffer
  tmp_right : @moondsp.AudioBuffer
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
let sched_routes : @ref.Ref[Array[SchedulerRoute]] = @ref.new([])

///|
let sched_left : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_right : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
/// Create a SoundPool for a drum template (no control bindings needed).
fn make_drum_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SoundPool? {
  // 8 voices = defensive headroom for .jux(f) patterns where f causes
  // same-sound overlap (e.g. the demo's hh*16? layer puts left's hh at
  // slot t and right's hh at slot 1-t — frequent coincidence at fine
  // subdivisions). Multi-sound patterns like s("bd sd hh sd").jux(rev)
  // do NOT need this headroom because per-pool pressure stays at 1.
  match
    @moondsp.BoundVoicePool::new(
      @moondsp.CompiledTemplate::analyze(template),
      ctx,
      @moondsp.ControlBindingBuilder::new(),
      max_voices=8,
    ) {
    Err(_) => None
    Ok(pool) => {
      let scheduler = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
      Some({
        pool,
        scheduler,
        tmp_left: @moondsp.AudioBuffer::filled(block_size),
        tmp_right: @moondsp.AudioBuffer::filled(block_size),
      })
    }
  }
}

///|
/// Create a SoundPool for the synth template (with note->freq binding).
fn make_synth_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SoundPool? {
  // See make_drum_pool for the .jux headroom rationale.
  match
    @moondsp.BoundVoicePool::new(
      @moondsp.CompiledTemplate::analyze(template),
      ctx,
      @moondsp.ControlBindingBuilder::new().bind(
        key="note",
        node_index=0,
        slot=@moondsp.GraphParamSlot::Value0,
      ),
      max_voices=16,
    ) {
    Err(_) => None
    Ok(pool) => {
      let scheduler = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
      Some({
        pool,
        scheduler,
        tmp_left: @moondsp.AudioBuffer::filled(block_size),
        tmp_right: @moondsp.AudioBuffer::filled(block_size),
      })
    }
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
    Some(pool) => Some({ selector: RouteSound(sound_code), pool })
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
    Some(pool) => Some({ selector: RouteSynth, pool })
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
  sched_routes.val = routes
  sched_left.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_right.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_gain.val = 0.3
  sched_active_playback.val = None
  true
}

///|
pub fn reset_scheduler_graph() -> Unit {
  sched_routes.val = []
  sched_left.val = None
  sched_right.val = None
  sched_gain.val = 0.3
  sched_active_playback.val = None
}

///|
/// Visit initialized route kinds for the browser facade's legacy route type
/// compatibility shell. This intentionally exposes only route tags, not the
/// host-owned selector enum, pools, schedulers, or buffers.
pub fn for_each_route_kind(
  on_sound : (Double) -> Unit,
  on_synth : () -> Unit,
) -> Unit {
  for route in sched_routes.val {
    match route.selector {
      RouteSound(sound_code) => on_sound(sound_code)
      RouteSynth => on_synth()
    }
  }
}

///|
fn checked_sample(index : Int, output : @moondsp.AudioBuffer?) -> Double {
  match output {
    Some(buffer) =>
      if index >= 0 && index < buffer.length() {
        buffer.get(index)
      } else {
        0.0
      }
    None => 0.0
  }
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  checked_sample(index, sched_left.val)
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  checked_sample(index, sched_right.val)
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
fn process_sub_pool(
  sp : SoundPool,
  sub_pat : @pattern.Pat[@pattern.ControlMap],
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  sp.tmp_left.fill(0.0)
  sp.tmp_right.fill(0.0)
  sp.scheduler.process_block(sub_pat, sp.pool, sp.tmp_left, sp.tmp_right)
  accumulate_sub_pool(sp, left, right)
}

///|
fn process_sub_song_pool(
  sp : SoundPool,
  song : @song.Song[@pattern.ControlMap],
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  sp.tmp_left.fill(0.0)
  sp.tmp_right.fill(0.0)
  sp.scheduler.process_song_block(song, sp.pool, sp.tmp_left, sp.tmp_right)
  accumulate_sub_pool(sp, left, right)
}

///|
fn route_matches(
  selector : SchedulerRouteSelector,
  cm : @pattern.ControlMap,
) -> Bool {
  match selector {
    RouteSound(sound_code) =>
      match cm.get("sound") {
        Some(v) => v == sound_code
        None => false
      }
    RouteSynth =>
      match cm.get("note") {
        Some(_) => true
        None => false
      }
  }
}

///|
fn control_map_for_route(
  selector : SchedulerRouteSelector,
  cm : @pattern.ControlMap,
) -> @pattern.ControlMap? {
  if route_matches(selector, cm) {
    Some(cm)
  } else {
    None
  }
}

///|
fn filter_pat_for_route(
  selector : SchedulerRouteSelector,
  pat : @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] {
  pat.filter_map(fn(cm) { control_map_for_route(selector, cm) })
}

///|
fn filter_section_for_route(
  selector : SchedulerRouteSelector,
  section : @song.Section[@pattern.ControlMap],
) -> Result[@song.Section[@pattern.ControlMap], String] {
  let body = @song.SectionBody::single(
    filter_pat_for_route(selector, section.body()),
  )
  let result = try? @song.Section(
    name=section.name(),
    length_cycles=section.length_cycles(),
    scope=section.scope(),
    body~,
  )
  match result {
    Ok(filtered) => Ok(filtered)
    Err(_) => Err("internal song routing error: invalid section length")
  }
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
  let result = try? @song.Song(parts~)
  match result {
    Ok(filtered) => Ok(filtered)
    Err(_) => Err("internal song routing error: invalid song layout")
  }
}

///|
fn route_songs_for_current_routes(
  song : @song.Song[@pattern.ControlMap],
) -> Result[Array[@song.Song[@pattern.ControlMap]], String] {
  let route_songs : Array[@song.Song[@pattern.ControlMap]] = []
  for route in sched_routes.val {
    match filter_song_for_route(route.selector, song) {
      Ok(route_song) => route_songs.push(route_song)
      Err(msg) => return Err(msg)
    }
  }
  Ok(route_songs)
}

///|
fn reset_route_transports_for_song_start() -> Unit {
  for route in sched_routes.val {
    route.pool.scheduler.reset_transport_and_kill_notes(route.pool.pool)
  }
}

///|
fn process_pattern_routes(
  pat : @pattern.Pat[@pattern.ControlMap],
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  for route in sched_routes.val {
    let sub = filter_pat_for_route(route.selector, pat)
    process_sub_pool(route.pool, sub, left, right)
  }
}

///|
fn process_song_routes(
  route_songs : Array[@song.Song[@pattern.ControlMap]],
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  for i in 0..<sched_routes.val.length() {
    match route_songs.get(i) {
      Some(song) =>
        process_sub_song_pool(sched_routes.val[i].pool, song, left, right)
      None => ()
    }
  }
}

///|
pub fn process_scheduler_block() -> Bool {
  let left = match sched_left.val {
    Some(b) => b
    None => return false
  }
  let right = match sched_right.val {
    Some(b) => b
    None => return false
  }
  // Clear main output buffers
  left.fill(0.0)
  right.fill(0.0)
  // Get active playback; if none set, output silence.
  match sched_active_playback.val {
    Some(ActivePattern(pat)) => process_pattern_routes(pat, left, right)
    Some(ActiveSong(route_songs)) =>
      process_song_routes(route_songs, left, right)
    None => return true
  }
  // Apply master gain
  let gain = sched_gain.val
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) * gain)
    right.set(i, right.get(i) * gain)
  }
  true
}

///|
let sched_last_error : @ref.Ref[String] = @ref.new("")

///|
let sched_pattern_input_chars : Array[Int] = []

///|
let sched_song_input_chars : Array[Int] = []

///|
fn input_chars_to_string(chars : Array[Int]) -> String {
  let buf = StringBuilder::new()
  for c in chars {
    buf.write_char(c.unsafe_to_char())
  }
  buf.to_string()
}

///|
fn set_active_pattern_text(text : String) -> Int {
  match @mini.parse(text) {
    Ok(pat) => {
      sched_active_playback.val = Some(ActivePattern(pat))
      sched_last_error.val = ""
      0
    }
    Err(msg) => {
      sched_last_error.val = msg
      1
    }
  }
}

///|
fn set_active_song_text(text : String) -> Int {
  match @mini.parse_song_with_bpm(text) {
    Ok(parsed) =>
      match route_songs_for_current_routes(parsed.song()) {
        Ok(route_songs) => {
          match parsed.bpm() {
            Some(bpm) => set_scheduler_bpm(bpm)
            None => ()
          }
          reset_route_transports_for_song_start()
          sched_active_playback.val = Some(ActiveSong(route_songs))
          sched_last_error.val = ""
          0
        }
        Err(msg) => {
          sched_last_error.val = msg
          1
        }
      }
    Err(msg) => {
      sched_last_error.val = msg
      1
    }
  }
}

///|
pub fn clear_pattern_input() -> Unit {
  sched_pattern_input_chars.clear()
}

///|
pub fn push_pattern_char(code : Int) -> Unit {
  sched_pattern_input_chars.push(code)
}

///|
pub fn eval_pattern_input() -> Int {
  let text = input_chars_to_string(sched_pattern_input_chars)
  sched_pattern_input_chars.clear()
  set_active_pattern_text(text)
}

///|
pub fn parse_and_set_pattern(text : String) -> Int {
  set_active_pattern_text(text)
}

///|
pub fn clear_song_input() -> Unit {
  sched_song_input_chars.clear()
}

///|
pub fn push_song_char(code : Int) -> Unit {
  sched_song_input_chars.push(code)
}

///|
pub fn eval_song_input() -> Int {
  let text = input_chars_to_string(sched_song_input_chars)
  sched_song_input_chars.clear()
  set_active_song_text(text)
}

///|
pub fn parse_and_set_song(text : String) -> Int {
  set_active_song_text(text)
}

///|
pub fn get_scheduler_parse_error() -> String {
  sched_last_error.val
}

///|
pub fn get_song_parse_error() -> String {
  sched_last_error.val
}

///|
/// Length of the last parse-error message, in chars.
/// Char-by-char accessor companion to `get_pattern_error_char` for JS
/// consumers that can't receive MoonBit strings across the wasm-gc boundary.
pub fn get_pattern_error_length() -> Int {
  sched_last_error.val.length()
}

///|
/// i-th character (UTF-16 code unit) of the last parse-error message.
/// Returns 0 if `i` is out of range; callers should respect
/// `get_pattern_error_length` first.
pub fn get_pattern_error_char(i : Int) -> Int {
  let s = sched_last_error.val
  if i < 0 || i >= s.length() {
    0
  } else {
    s[i].to_int()
  }
}

///|
pub fn get_song_error_length() -> Int {
  sched_last_error.val.length()
}

///|
pub fn get_song_error_char(i : Int) -> Int {
  get_pattern_error_char(i)
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  for route in sched_routes.val {
    route.pool.scheduler.set_bpm(bpm)
  }
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  sched_gain.val = if gain < 0.0 {
    0.0
  } else if gain > 1.0 {
    1.0
  } else {
    gain
  }
}
