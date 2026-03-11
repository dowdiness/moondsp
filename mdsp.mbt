///|
/// Global demo oscillator used by the browser prototype wrappers.
let demo_oscillator : @ref.Ref[Oscillator] = @ref.new(Oscillator::new())

///|
/// Global demo noise source used by the browser prototype wrappers.
let demo_noise : @ref.Ref[Noise] = @ref.new(Noise::new(DEMO_NOISE_SEED))

///|
const DEMO_NOISE_SEED : UInt = 0x6D2B79F5U

///|
/// Reset oscillator state to the start of the waveform.
pub fn demo_reset_phase() -> Unit {
  demo_oscillator.val.reset()
  demo_noise.val.reset(DEMO_NOISE_SEED)
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
pub fn demo_tick(freq : Double, sample_rate : Double) -> Double {
  demo_tick_source(0, freq, sample_rate)
}

///|
/// Generate one sample from the selected browser demo source.
///
/// Source ids:
/// - `0`: sine
/// - `1`: saw
/// - `2`: square
/// - `3`: triangle
/// - `4`: noise
pub fn tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  match source_id {
    1 => demo_oscillator.val.tick_waveform(Waveform::Saw, freq, sample_rate)
    2 => demo_oscillator.val.tick_waveform(Waveform::Square, freq, sample_rate)
    3 =>
      demo_oscillator.val.tick_waveform(Waveform::Triangle, freq, sample_rate)
    4 =>
      if !is_valid_osc_param(sample_rate) || sample_rate <= 0.0 {
        0.0
      } else {
        demo_noise.val.tick()
      }
    _ => demo_oscillator.val.tick_waveform(Waveform::Sine, freq, sample_rate)
  }
}

///|
/// Backward-compatible browser demo alias for the old prototype name.
pub fn reset_phase() -> Unit {
  demo_reset_phase()
}

///|
/// Backward-compatible browser demo alias for the old prototype name.
pub fn tick(freq : Double, sample_rate : Double) -> Double {
  demo_tick(freq, sample_rate)
}

///|
/// Browser demo source selector entrypoint exported for wasm/js builds.
pub fn demo_tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  tick_source(source_id, freq, sample_rate)
}
