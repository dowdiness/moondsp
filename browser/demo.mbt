///|
/// Default seed for the browser demo noise source.
const DEMO_NOISE_SEED : UInt = 0x6D2B79F5U

///|
/// Demo oscillator — owned by the browser package, not the library.
let demo_oscillator : @ref.Ref[@lib.Oscillator] = @ref.new(
  @lib.Oscillator::new(),
)

///|
/// Demo noise source — owned by the browser package, not the library.
let demo_noise : @ref.Ref[@lib.Noise] = @ref.new(
  @lib.Noise::new(DEMO_NOISE_SEED),
)

///|
/// Reset oscillator and noise state to the start of the waveform.
fn reset_demo_phase() -> Unit {
  demo_oscillator.val.reset()
  demo_noise.val.reset(DEMO_NOISE_SEED)
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
fn demo_tick_source(
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
