// Explicit test boundary for end-to-end browser scheduler diagnostics.
// Production browser code does not import this package, and its functions are
// not part of the production AudioWorklet export ABI.

///|
pub fn init_scheduler_graph_with_waveform(
  sample_rate : Double,
  block_size : Int,
  waveform : @moondsp.Waveform,
) -> Bool {
  @playback_host.init_scheduler_graph_with_templates(
    sample_rate,
    block_size,
    @demo_templates.bd_template(),
    @demo_templates.sd_template(),
    @demo_templates.hh_template(),
    @demo_templates.cp_template(),
    @demo_templates.oh_template(),
    @demo_templates.synth_template_for_waveform(waveform),
  )
}

///|
pub fn process_scheduler_block() -> Bool {
  @playback_host.process_scheduler_block()
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
pub fn apply_prepared_playback(token : Int, restart : Bool) -> Int {
  @playback_host.apply_prepared_playback(token, restart)
}

///|
pub fn get_playback_error_length() -> Int {
  @playback_host.get_playback_error_length()
}

///|
pub fn get_playback_error_char(index : Int) -> Int {
  @playback_host.get_playback_error_char(index)
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  @playback_host.set_scheduler_bpm(bpm)
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  @playback_host.set_scheduler_gain(gain)
}

///|
pub fn scheduler_last_sanitized_count() -> Int {
  @playback_host.scheduler_last_sanitized_count()
}

///|
pub fn scheduler_synth_active_voice_count() -> Int {
  @playback_host.scheduler_synth_active_voice_count()
}

///|
pub fn scheduler_synth_voice_capacity() -> Int {
  @playback_host.scheduler_synth_voice_capacity()
}
