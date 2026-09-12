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
let sched_routes : @ref.Ref[Array[SchedulerRoute]] = @ref.new([])

///|
let sched_left : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_right : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_context : @ref.Ref[@moondsp.DspContext?] = @ref.new(None)

///|
let sched_reverb : @ref.Ref[@moondsp.StereoReverb?] = @ref.new(None)

///|
let sched_send_left : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_send_right : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_wet_left : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_wet_right : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_gain : @ref.Ref[Double] = @ref.new(0.5)

///|
/// Create a SoundPool for a drum template (no control bindings needed).
fn make_drum_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SoundPool? {
  let scheduler = match @scheduler.PatternScheduler::new(bpm=120.0, ctx~) {
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
      @moondsp.CompiledTemplate::analyze(template),
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
  let scheduler = match @scheduler.PatternScheduler::new(bpm=120.0, ctx~) {
    Ok(scheduler) => scheduler
    Err(_) => return None
  }
  // See make_drum_pool for the .jux headroom rationale.
  match
    @moondsp.BoundVoicePool::new(
      @moondsp.CompiledTemplate::analyze(template),
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
      .bind(key="release", node_index=1, slot=@moondsp.GraphParamSlot::Value3),
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
  sched_routes.val = routes
  sched_left.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_right.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_context.val = Some(ctx)
  sched_reverb.val = Some(@moondsp.StereoReverb::StereoReverb(sample_rate))
  sched_send_left.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_send_right.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_wet_left.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_wet_right.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_gain.val = 0.5
  reset_playback_state()
  true
}

///|
pub fn reset_scheduler_graph() -> Unit {
  sched_routes.val = []
  sched_left.val = None
  sched_right.val = None
  sched_context.val = None
  sched_reverb.val = None
  sched_send_left.val = None
  sched_send_right.val = None
  sched_wet_left.val = None
  sched_wet_right.val = None
  sched_gain.val = 0.5
  reset_playback_state()
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
fn route_patterns(
  pat : @pattern.Pat[@pattern.ControlMap],
  selectors : Array[SchedulerRouteSelector],
) -> Array[@pattern.Pat[@pattern.ControlMap]] {
  let route_patterns : Array[@pattern.Pat[@pattern.ControlMap]] = []
  for selector in selectors {
    route_patterns.push(filter_pat_for_route(selector, pat))
  }
  route_patterns
}

///|
fn route_songs(
  song : @song.Song[@pattern.ControlMap],
  selectors : Array[SchedulerRouteSelector],
) -> Result[Array[@song.Song[@pattern.ControlMap]], String] {
  let route_songs : Array[@song.Song[@pattern.ControlMap]] = []
  for selector in selectors {
    match filter_song_for_route(selector, song) {
      Ok(route_song) => route_songs.push(route_song)
      Err(msg) => return Err(msg)
    }
  }
  Ok(route_songs)
}

///|
pub fn process_scheduler_block() -> Bool {
  let left = match sched_left.val {
    Some(buffer) => buffer
    None => return false
  }
  let right = match sched_right.val {
    Some(buffer) => buffer
    None => return false
  }
  let context = match sched_context.val {
    Some(context) => context
    None => return false
  }
  let reverb = match sched_reverb.val {
    Some(reverb) => reverb
    None => return false
  }
  let send_left = match sched_send_left.val {
    Some(buffer) => buffer
    None => return false
  }
  let send_right = match sched_send_right.val {
    Some(buffer) => buffer
    None => return false
  }
  let wet_left = match sched_wet_left.val {
    Some(buffer) => buffer
    None => return false
  }
  let wet_right = match sched_wet_right.val {
    Some(buffer) => buffer
    None => return false
  }
  commit_playback_request()
  left.fill(0.0)
  right.fill(0.0)
  send_left.fill(0.0)
  send_right.fill(0.0)
  if playback_state.val.active is None {
    return true
  }
  process_snapshot_routes(left, right)
  reverb.process(context, send_left, send_right, wet_left, wet_right)
  let gain = sched_gain.val
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, (left.get(i) + wet_left.get(i)) * gain)
    right.set(i, (right.get(i) + wet_right.get(i)) * gain)
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
let playback_input_chars : Array[Int] = []

///|
fn input_chars_to_string(chars : Array[Int]) -> String {
  let buf = StringBuilder()
  for c in chars {
    buf.write_char(c.unsafe_to_char())
  }
  buf.to_string()
}

///|
pub fn clear_playback_input() -> Unit {
  playback_input_chars.clear()
}

///|
pub fn push_playback_char(code : Int) -> Unit {
  playback_input_chars.push(code)
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
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  for route in sched_routes.val {
    match route.pool.scheduler.validate_bpm(bpm) {
      Err(_) => {
        ignore(
          set_scheduler_parse_error(
            "tempo must be 0.001..1000 BPM and representable",
          ),
        )
        return
      }
      Ok(_) => ()
    }
  }
  for route in sched_routes.val {
    // Same audio-owner turn as preflight; no route can advance in between.
    route.pool.scheduler.set_bpm(bpm).unwrap()
  }
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  sched_gain.val = if gain.is_nan() || gain.is_inf() {
    0.5
  } else if gain < 0.0 {
    0.0
  } else if gain > 1.0 {
    1.0
  } else {
    gain
  }
}
