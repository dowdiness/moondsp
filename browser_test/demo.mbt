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
fn reset_demo_phase() -> Unit {
  demo_oscillator.val.reset()
  demo_noise.val.reset(DEMO_NOISE_SEED)
}

///|
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
