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
pub fn clear_playback_input() -> Unit {
  @playback_host.clear_playback_input()
}

///|
pub fn push_playback_char(code : Int) -> Unit {
  @playback_host.push_playback_char(code)
}

///|
pub fn prepare_pattern_input() -> Int {
  @playback_host.prepare_pattern_input()
}

///|
pub fn prepare_song_input() -> Int {
  @playback_host.prepare_song_input()
}

///|
/// Return 0 when queued, 1 for an invalid/unrepresentable request, or 2 when
/// starting/restarting is required. A rejected valid token is not consumed.
pub fn apply_prepared_playback(token : Int, restart : Bool) -> Int {
  @playback_host.apply_prepared_playback(token, restart)
}

///|
pub fn discard_prepared_playback(token : Int) -> Bool {
  @playback_host.discard_prepared_playback(token)
}

///|
pub fn restart_playback() -> Int {
  @playback_host.restart_playback()
}

///|
pub fn get_playback_error() -> String {
  @playback_host.get_playback_error()
}

///|
pub fn get_playback_error_length() -> Int {
  @playback_host.get_playback_error_length()
}

///|
pub fn get_playback_error_char(i : Int) -> Int {
  @playback_host.get_playback_error_char(i)
}

///|
/// Return 0 after an accepted tempo change, or 1 with a playback diagnostic.
pub fn set_scheduler_bpm(bpm : Double) -> Int {
  @playback_host.set_scheduler_bpm(bpm)
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  @playback_host.set_scheduler_gain(gain)
}

///|
pub fn scheduler_bpm() -> Double {
  @playback_host.scheduler_bpm()
}

///|
pub fn scheduler_sample_position() -> Double {
  @playback_host.scheduler_sample_position()
}
