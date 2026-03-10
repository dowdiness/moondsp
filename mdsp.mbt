///|
/// Phase accumulator for the Step 0 browser prototype.
/// Keep this as primitive numeric state so audio-rate code does not allocate.
let phase : @ref.Ref[Double] = @ref.new(0.0)

///|
/// Reset oscillator state to the start of the waveform.
pub fn reset_phase() -> Unit {
  phase.val = 0.0
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
  if sample_rate <= 0.0 {
    return 0.0
  }
  let two_pi = 6.283185307179586
  let out = @math.sin(phase.val * two_pi)
  phase.val = phase.val + freq / sample_rate
  if phase.val >= 1.0 {
    phase.val = phase.val - 1.0
  }
  out
}
