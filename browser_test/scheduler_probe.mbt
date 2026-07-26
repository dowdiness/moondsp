// Test-only browser scheduler wrappers for #212. These exports live only in
// moonbit_dsp_test.wasm. They deliberately reuse the production playback host,
// Mini parser, PatternScheduler, BoundVoicePool, and browser demo templates so
// Triangle/Sine comparisons differ only by the oscillator waveform.

///|
fn init_scheduler_probe_graph_with_waveform(
  sample_rate : Double,
  block_size : Int,
  waveform : @moondsp.Waveform,
) -> Bool {
  @test_support.init_scheduler_graph_with_waveform(
    sample_rate, block_size, waveform,
  )
}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  init_scheduler_probe_graph_with_waveform(
    sample_rate,
    block_size,
    @moondsp.Waveform::Triangle,
  )
}

///|
pub fn init_scheduler_sine_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  init_scheduler_probe_graph_with_waveform(
    sample_rate,
    block_size,
    @moondsp.Waveform::Sine,
  )
}

///|
pub fn process_scheduler_block() -> Bool {
  @test_support.process_scheduler_block()
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  @test_support.scheduler_left_sample(index)
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  @test_support.scheduler_right_sample(index)
}

///|
pub fn clear_pattern_input() -> Unit {
  @test_support.clear_pattern_input()
}

///|
pub fn push_pattern_char(code : Int) -> Unit {
  @test_support.push_pattern_char(code)
}

///|
pub fn eval_pattern_input() -> Int {
  @test_support.eval_pattern_input()
}

///|
pub fn get_pattern_error_length() -> Int {
  @test_support.get_pattern_error_length()
}

///|
pub fn get_pattern_error_char(index : Int) -> Int {
  @test_support.get_pattern_error_char(index)
}

///|
pub fn get_browser_error_length() -> Int {
  0
}

///|
pub fn get_browser_error_char(_index : Int) -> Int {
  0
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  @test_support.set_scheduler_bpm(bpm)
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  @test_support.set_scheduler_gain(gain)
}

///|
pub fn scheduler_last_sanitized_count() -> Int {
  @test_support.scheduler_last_sanitized_count()
}

///|
pub fn scheduler_synth_active_voice_count() -> Int {
  @test_support.scheduler_synth_active_voice_count()
}

///|
pub fn scheduler_synth_voice_capacity() -> Int {
  @test_support.scheduler_synth_voice_capacity()
}
