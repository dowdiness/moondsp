///|
/// Global demo oscillator used by the browser prototype wrappers.
let demo_oscillator : @ref.Ref[Oscillator] = @ref.new(Oscillator::new())

///|
/// Reset oscillator state to the start of the waveform.
pub fn reset_phase() -> Unit {
  demo_oscillator.val.reset()
}

///|
/// Entry point required because the root package is built as a main package for
/// the exported wasm/js prototype.
fn main {
  ()
}

///|
/// Generate one sine sample for the current frequency.
///
/// This function is exported for the `wasm-gc` and `js` backends so the
/// browser prototype can call it from the AudioWorklet processor.
pub fn tick(freq : Double, sample_rate : Double) -> Double {
  demo_oscillator.val.tick(freq, sample_rate)
}
