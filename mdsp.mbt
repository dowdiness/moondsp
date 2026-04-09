///|
const DEMO_NOISE_SEED : UInt = 0x6D2B79F5U

///|
let demo_oscillator : @ref.Ref[@lib.Oscillator] = @ref.new(
  @lib.Oscillator::new(),
)

///|
let demo_noise : @ref.Ref[@lib.Noise] = @ref.new(
  @lib.Noise::new(DEMO_NOISE_SEED),
)

///|
/// Entry point required because the root package is built as a main package for
/// the exported wasm/js prototype.
fn main {
  ()
}

///|
/// Reset oscillator and noise state to the start of the waveform.
pub fn demo_reset_phase() -> Unit {
  demo_oscillator.val.reset()
  demo_noise.val.reset(DEMO_NOISE_SEED)
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
/// Browser demo source selector entrypoint exported for wasm/js builds.
pub fn demo_tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  match source_id {
    1 =>
      demo_oscillator.val.tick_waveform(@lib.Waveform::Saw, freq, sample_rate)
    2 =>
      demo_oscillator.val.tick_waveform(
        @lib.Waveform::Square,
        freq,
        sample_rate,
      )
    3 =>
      demo_oscillator.val.tick_waveform(
        @lib.Waveform::Triangle,
        freq,
        sample_rate,
      )
    4 =>
      if !@lib.is_finite(sample_rate) || sample_rate <= 0.0 {
        0.0
      } else {
        demo_noise.val.tick()
      }
    _ =>
      demo_oscillator.val.tick_waveform(@lib.Waveform::Sine, freq, sample_rate)
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
/// Backward-compatible browser demo alias.
pub fn tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  demo_tick_source(source_id, freq, sample_rate)
}
