///|
/// Active pattern parsed from mini-notation text.
let sched_active_pattern : @ref.Ref[@pattern.Pat[@pattern.ControlMap]?] = @ref.new(
  None,
)

///|
/// Per-sound pool state: voice pool + scheduler + tmp buffers.
struct SoundPool {
  pool : @moondsp.BoundVoicePool
  scheduler : @scheduler.PatternScheduler
  tmp_left : @moondsp.AudioBuffer
  tmp_right : @moondsp.AudioBuffer
}

///|
enum SchedulerRouteSelector {
  RouteSound(Double)
  RouteSynth
}

///|
struct SchedulerRoute {
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
fn synth_template() -> Array[@moondsp.DspNode] {
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
fn make_synth_pool(ctx : @moondsp.DspContext, block_size : Int) -> SoundPool? {
  let template = synth_template()
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
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SchedulerRoute? {
  match make_synth_pool(ctx, block_size) {
    Some(pool) => Some({ selector: RouteSynth, pool })
    None => None
  }
}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_graph()
    return false
  }
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size~)
  let route_candidates = [
    make_drum_route(36.0, bd_template(), ctx, block_size),
    make_drum_route(38.0, sd_template(), ctx, block_size),
    make_drum_route(42.0, hh_template(), ctx, block_size),
    make_drum_route(39.0, cp_template(), ctx, block_size),
    make_drum_route(46.0, oh_template(), ctx, block_size),
    make_synth_route(ctx, block_size),
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
  sched_active_pattern.val = None
  true
}

///|
fn reset_scheduler_graph() -> Unit {
  sched_routes.val = []
  sched_left.val = None
  sched_right.val = None
  sched_gain.val = 0.3
  sched_active_pattern.val = None
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
/// Process one sub-pattern through its sound pool, accumulating into main buffers.
fn process_sub_pool(
  sp : SoundPool,
  sub_pat : @pattern.Pat[@pattern.ControlMap],
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  sp.tmp_left.fill(0.0)
  sp.tmp_right.fill(0.0)
  sp.scheduler.process_block(sub_pat, sp.pool, sp.tmp_left, sp.tmp_right)
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) + sp.tmp_left.get(i))
    right.set(i, right.get(i) + sp.tmp_right.get(i))
  }
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
  // Get active pattern; if none set, output silence
  let pat = match sched_active_pattern.val {
    Some(p) => p
    None => return true
  }
  // Route drum events to their pools, note events to synth.
  for route in sched_routes.val {
    let selector = route.selector
    let sub = pat.filter_map(fn(cm) {
      if route_matches(selector, cm) {
        Some(cm)
      } else {
        None
      }
    })
    process_sub_pool(route.pool, sub, left, right)
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
let sched_input_chars : Array[Int] = []

///|
pub fn clear_pattern_input() -> Unit {
  sched_input_chars.clear()
}

///|
pub fn push_pattern_char(code : Int) -> Unit {
  sched_input_chars.push(code)
}

///|
pub fn eval_pattern_input() -> Int {
  let buf = StringBuilder::new()
  for c in sched_input_chars {
    buf.write_char(c.unsafe_to_char())
  }
  let text = buf.to_string()
  sched_input_chars.clear()
  match @mini.parse(text) {
    Ok(pat) => {
      sched_active_pattern.val = Some(pat)
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
pub fn parse_and_set_pattern(text : String) -> Int {
  match @mini.parse(text) {
    Ok(pat) => {
      sched_active_pattern.val = Some(pat)
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
pub fn get_scheduler_parse_error() -> String {
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
