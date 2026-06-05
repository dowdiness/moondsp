///|
/// Per-sound pool state retained in the browser facade interface for
/// source compatibility. Runtime playback state now lives in
/// `browser/internal/playback_host`.
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
/// Keep the legacy facade-only scheduler route shells live without routing
/// playback through them. This preserves `browser/pkg.generated.mbti` exactly
/// while the real host state lives in `@playback_host`.
fn facade_selector_from_host(
  selector : @playback_host.SchedulerRouteSelector,
) -> SchedulerRouteSelector {
  match selector {
    @playback_host.SchedulerRouteSelector::RouteSound(sound_code) =>
      RouteSound(sound_code)
    @playback_host.SchedulerRouteSelector::RouteSynth => RouteSynth
  }
}

///|
fn touch_scheduler_facade_route(
  selector : @playback_host.SchedulerRouteSelector,
  bound_pool : @moondsp.BoundVoicePool,
  scheduler : @scheduler.PatternScheduler,
  tmp_left : @moondsp.AudioBuffer,
  tmp_right : @moondsp.AudioBuffer,
) -> Unit {
  let pool : SoundPool = { pool: bound_pool, scheduler, tmp_left, tmp_right }
  let facade_route : SchedulerRoute = {
    selector: facade_selector_from_host(selector),
    pool,
  }
  match facade_route.selector {
    RouteSound(sound_code) => ignore(sound_code)
    RouteSynth => ()
  }
  ignore(facade_route.pool.pool)
  ignore(facade_route.pool.scheduler)
  ignore(facade_route.pool.tmp_left)
  ignore(facade_route.pool.tmp_right)
}

///|
fn touch_scheduler_facade_types() -> Unit {
  @playback_host.for_each_route(touch_scheduler_facade_route)
}

///|
fn bd_template() -> Array[@moondsp.DspNode] {
  @demo_templates.bd_template()
}

///|
fn sd_template() -> Array[@moondsp.DspNode] {
  @demo_templates.sd_template()
}

///|
fn hh_template() -> Array[@moondsp.DspNode] {
  @demo_templates.hh_template()
}

///|
fn oh_template() -> Array[@moondsp.DspNode] {
  @demo_templates.oh_template()
}

///|
fn cp_template() -> Array[@moondsp.DspNode] {
  @demo_templates.cp_template()
}

///|
fn synth_template() -> Array[@moondsp.DspNode] {
  @demo_templates.synth_template()
}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  let ready = @playback_host.init_scheduler_graph_with_templates(
    sample_rate,
    block_size,
    bd_template(),
    sd_template(),
    hh_template(),
    cp_template(),
    oh_template(),
    synth_template(),
  )
  if ready {
    touch_scheduler_facade_types()
  }
  ready
}

///|
fn reset_scheduler_graph() -> Unit {
  @playback_host.reset_scheduler_graph()
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  @playback_host.scheduler_left_sample(index)
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  @playback_host.scheduler_right_sample(index)
}

///|
pub fn process_scheduler_block() -> Bool {
  @playback_host.process_scheduler_block()
}

///|
pub fn clear_pattern_input() -> Unit {
  @playback_host.clear_pattern_input()
}

///|
pub fn push_pattern_char(code : Int) -> Unit {
  @playback_host.push_pattern_char(code)
}

///|
pub fn eval_pattern_input() -> Int {
  @playback_host.eval_pattern_input()
}

///|
pub fn parse_and_set_pattern(text : String) -> Int {
  @playback_host.parse_and_set_pattern(text)
}

///|
pub fn clear_song_input() -> Unit {
  @playback_host.clear_song_input()
}

///|
pub fn push_song_char(code : Int) -> Unit {
  @playback_host.push_song_char(code)
}

///|
pub fn eval_song_input() -> Int {
  @playback_host.eval_song_input()
}

///|
pub fn parse_and_set_song(text : String) -> Int {
  @playback_host.parse_and_set_song(text)
}

///|
pub fn get_scheduler_parse_error() -> String {
  @playback_host.get_scheduler_parse_error()
}

///|
pub fn get_song_parse_error() -> String {
  @playback_host.get_song_parse_error()
}

///|
/// Length of the last parse-error message, in chars.
/// Char-by-char accessor companion to `get_pattern_error_char` for JS
/// consumers that can't receive MoonBit strings across the wasm-gc boundary.
pub fn get_pattern_error_length() -> Int {
  @playback_host.get_pattern_error_length()
}

///|
/// i-th character (UTF-16 code unit) of the last parse-error message.
/// Returns 0 if `i` is out of range; callers should respect
/// `get_pattern_error_length` first.
pub fn get_pattern_error_char(i : Int) -> Int {
  @playback_host.get_pattern_error_char(i)
}

///|
pub fn get_song_error_length() -> Int {
  @playback_host.get_song_error_length()
}

///|
pub fn get_song_error_char(i : Int) -> Int {
  @playback_host.get_song_error_char(i)
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  @playback_host.set_scheduler_bpm(bpm)
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  @playback_host.set_scheduler_gain(gain)
}
