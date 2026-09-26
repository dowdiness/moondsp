///|
/// Kind of the latest accepted score, independent of the visible draft.
/// Constant-enum ABI values are None = 0, Pattern = 1, Song = 2.
/// Keep the constructor order stable for JS/wasm-gc callers.
pub(all) enum PlaybackMode {
  None
  Pattern
  Song
} derive(Eq, Debug)

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
pub fn player_update_input() -> Int {
  @playback_host.player_update_input()
}

///|
pub fn player_restart_input() -> Int {
  @playback_host.player_restart_input()
}

///|
pub fn player_play() -> Int {
  @playback_host.player_play()
}

///|
pub fn player_pause() -> Int {
  @playback_host.player_pause()
}

///|
/// Cycle arguments are exact thousandths of an accepted song cycle.
pub fn player_seek_cycle(cycle_milli : Int) -> Int {
  @playback_host.player_seek_cycle(cycle_milli)
}

///|
pub fn player_loop_cycles(begin_milli : Int, end_milli : Int) -> Int {
  @playback_host.player_loop_cycles(begin_milli, end_milli)
}

///|
/// Exact accepted occurrence boundaries, including fractional cycles.
pub fn player_seek_section(index : Int) -> Int {
  @playback_host.player_seek_section(index)
}

///|
pub fn player_loop_section(index : Int) -> Int {
  @playback_host.player_loop_section(index)
}

///|
pub fn player_whole_song() -> Int {
  @playback_host.player_whole_song()
}

///|
pub fn player_loop_begin() -> Double {
  @playback_host.player_loop_begin()
}

///|
pub fn player_loop_end() -> Double {
  @playback_host.player_loop_end()
}

///|
pub fn player_state() -> Int {
  @playback_host.player_state()
}

///|
/// Kind of the latest accepted score; Song includes finite and repeating songs.
/// Returns None before initialization and in Empty or Fault. This describes the
/// accepted score, not the visible draft or every currently sounding material.
/// JS/wasm-gc exports retain the constant-enum ABI: 0 none, 1 pattern, 2 song.
pub fn player_mode() -> PlaybackMode {
  match @playback_host.player_mode() {
    None => None
    Pattern => Pattern
    Song => Song
  }
}

///|
/// Song range preview reports the wrapped accepted-song coordinate; in normal
/// playback it reports the zero-based render position in cycles. This is a
/// floating-point observation, not an exact scheduling timestamp or an
/// estimate of audible position. Pause freezes it; tempo changes preserve
/// continuity. Ended retains the completed run's endpoint across updates.
/// Returns zero before initialization and in Empty, Ready, or Fault.
pub fn scheduler_cycle_position() -> Double {
  @playback_host.scheduler_cycle_position()
}

///|
pub fn player_pending_count() -> Int {
  @playback_host.player_pending_count()
}

///|
pub fn player_skipped_count() -> Int {
  @playback_host.player_skipped_count()
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

///|
/// Accepted song layout, indexed by occurrence. Empty in pattern mode.
pub fn player_section_count() -> Int {
  @playback_host.player_section_count()
}

///|
pub fn player_section_start(index : Int) -> Double {
  @playback_host.player_section_start(index)
}

///|
pub fn player_section_end(index : Int) -> Double {
  @playback_host.player_section_end(index)
}

///|
pub fn player_section_label_length(index : Int) -> Int {
  @playback_host.player_section_label_length(index)
}

///|
pub fn player_section_label_char(index : Int, char_index : Int) -> Int {
  @playback_host.player_section_label_char(index, char_index)
}
