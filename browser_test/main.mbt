///|
/// Browser test wrapper package that proves mono compiled fallback when
/// stereo initialization fails from the wasm side.
fn main {
  ()
}

///|
pub fn reset_phase() -> Unit {
  @browser.reset_phase()
}

///|
pub fn tick(freq : Double, sample_rate : Double) -> Double {
  @browser.tick(freq, sample_rate)
}

///|
pub fn tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  @browser.tick_source(source_id, freq, sample_rate)
}

///|
pub fn init_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  @browser.init_compiled_graph(sample_rate, block_size)
}

///|
pub fn process_compiled_block(
  freq : Double,
  gain : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  @browser.process_compiled_block(freq, gain, sample_rate, block_size)
}

///|
pub fn compiled_output_sample(index : Int) -> Double {
  @browser.compiled_output_sample(index)
}

///|
pub fn init_compiled_stereo_graph(
  _sample_rate : Double,
  _block_size : Int,
) -> Bool {
  false
}

///|
pub fn process_compiled_stereo_block(
  _freq : Double,
  _gain : Double,
  _pan : Double,
  _cutoff : Double,
  _sample_rate : Double,
  _block_size : Int,
) -> Bool {
  false
}

///|
pub fn compiled_stereo_left_sample(_index : Int) -> Double {
  0.0
}

///|
pub fn compiled_stereo_right_sample(_index : Int) -> Double {
  0.0
}
