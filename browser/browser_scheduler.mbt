///|
/// Kind of the latest accepted score, independent of the visible draft.
/// Constant-enum ABI values are None = 0, Pattern = 1, Song = 2.
/// Keep the constructor order stable for JS/wasm-gc callers.
#derive(Eq, Debug)
pub(all) enum PlaybackMode {
  None
  Pattern
  Song
}

///|
pub extend PlaybackMode with Eq::{not_equal, equal}

///|
pub extend PlaybackMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int32) -> Bool {
  @playback_host.init_scheduler_graph_with_sounds(
    sample_rate,
    block_size,
    drum=@demo_templates.drum_template,
    instrument=@demo_templates.instrument_voice,
    sampler=@demo_templates.sampler_voice(),
  )
}

///|
fn reset_scheduler_graph() -> Unit {
  @playback_host.reset_scheduler_graph()
}

///|
pub fn scheduler_left_sample(index : Int32) -> Double {
  @playback_host.scheduler_left_sample(index)
}

///|
pub fn scheduler_right_sample(index : Int32) -> Double {
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
pub fn push_playback_char(code : Int32) -> Unit {
  @playback_host.push_playback_char(code)
}

///|
pub fn player_update_input() -> Int32 {
  @playback_host.player_update_input()
}

///|
pub fn player_restart_input() -> Int32 {
  @playback_host.player_restart_input()
}

///|
pub fn player_play() -> Int32 {
  @playback_host.player_play()
}

///|
pub fn player_pause() -> Int32 {
  @playback_host.player_pause()
}

///|
pub fn player_state() -> Int32 {
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
    Some(Pattern) => Pattern
    Some(Song) => Song
  }
}

///|
/// Zero-based absolute render position in musical cycles, as a Double.
/// This is a floating-point observation, not an exact scheduling timestamp or
/// an estimate of audible position. Pause freezes it; tempo changes preserve
/// continuity. Ended retains the completed run's endpoint across source updates.
/// Returns zero before initialization and in Empty, Ready, or Fault; use
/// `player_state` to distinguish these from the beginning of a performance.
pub fn scheduler_cycle_position() -> Double {
  @playback_host.scheduler_cycle_position()
}

///|
pub fn player_pending_count() -> Int32 {
  @playback_host.player_pending_count()
}

///|
pub fn player_skipped_count() -> Int32 {
  @playback_host.player_skipped_count()
}

///|
pub fn get_playback_error() -> String {
  @playback_host.get_playback_error()
}

///|
pub fn get_playback_error_length() -> Int32 {
  @playback_host.get_playback_error_length()
}

///|
pub fn get_playback_error_char(i : Int32) -> Int32 {
  @playback_host.get_playback_error_char(i)
}

///|
/// Return 0 after an accepted tempo change, or 1 with a playback diagnostic.
pub fn set_scheduler_bpm(bpm : Double) -> Int32 {
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
/// Enable actual-onset observation (1) or disable it (0).
pub fn player_onset_enable(enabled : Int32) -> Unit {
  @playback_host.player_onset_enable(enabled)
}

///|
pub fn player_onset_count() -> Int32 {
  @playback_host.player_onset_count()
}

///|
/// Read a zero-based field from the chronological scheduler-route rows.
pub fn player_onset_field(index : Int32, field : Int32) -> Double {
  @playback_host.player_onset_field(index, field)
}

///|
pub fn player_onset_clear() -> Unit {
  @playback_host.player_onset_clear()
}

///|
pub fn player_onset_dropped() -> Double {
  @playback_host.player_onset_dropped()
}

///|
/// Make the sample store, 32 MiB, if there is none yet, and return its
/// capacity in samples. Call it before the first `process()`: it takes
/// 15–20 ms (ADR-0026 Decision 6).
pub fn init_sample_store() -> Int32 {
  @playback_host.init_sample_store()
}

///|
/// The number of samples in the built-in bank.
pub fn sample_bank_count() -> Int32 {
  @playback_host.sample_bank_count()
}

///|
/// The UTF-16 length of bank sample `entry`'s name, 0 outside the bank.
pub fn sample_bank_name_length(entry : Int32) -> Int32 {
  @playback_host.sample_bank_name(entry).length()
}

///|
/// UTF-16 code unit `index` of bank sample `entry`'s name.
pub fn sample_bank_name_char(entry : Int32, index : Int32) -> Int32 {
  let name = @playback_host.sample_bank_name(entry)
  if index >= 0 && index < name.length() {
    name.code_unit_at(index).to_int()
  } else {
    0
  }
}

///|
/// Begin loading `length` samples into bank sample number `entry`. Returns 0,
/// or what refused it: 1 the sample number, 2 the length, 3 the store's
/// memory, 4 no store.
pub fn sample_load_begin(entry : Int32, length : Int32) -> Int32 {
  @playback_host.sample_load_begin(entry, length)
}

///|
/// Write sample `offset` of the waveform being loaded.
pub fn sample_load_write(offset : Int32, value : Float) -> Unit {
  @playback_host.sample_load_write(offset, value)
}

///|
/// Finish loading the waveform. Returns false when none was being loaded.
pub fn sample_load_commit() -> Bool {
  @playback_host.sample_load_commit()
}

///|
/// Whether sample number `entry` has a waveform.
pub fn sample_loaded(entry : Int32) -> Bool {
  @playback_host.sample_loaded(entry)
}

///|
/// Enable recording of the values sounding notes follow from authored signals.
pub fn player_signal_enable(enabled : Int32) -> Unit {
  @playback_host.player_signal_enable(enabled)
}

///|
pub fn player_signal_count() -> Int32 {
  @playback_host.player_signal_count()
}

///|
/// Read a zero-based field of a signal-value row: sample, source epoch,
/// source serial, material time in cycles, value.
pub fn player_signal_field(index : Int32, field : Int32) -> Double {
  @playback_host.player_signal_field(index, field)
}

///|
pub fn player_signal_clear() -> Unit {
  @playback_host.player_signal_clear()
}

///|
pub fn player_signal_dropped() -> Double {
  @playback_host.player_signal_dropped()
}
