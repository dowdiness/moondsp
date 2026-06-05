///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  @playback_host.init_scheduler_graph_with_templates(
    sample_rate,
    block_size,
    @demo_templates.bd_template(),
    @demo_templates.sd_template(),
    @demo_templates.hh_template(),
    @demo_templates.cp_template(),
    @demo_templates.oh_template(),
    @demo_templates.synth_template(),
  )
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
