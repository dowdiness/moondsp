///|
const DEMO_NOISE_SEED : UInt = 0x6D2B79F5U

///|
/// Encapsulates the mutable oscillator + noise state used by the browser
/// demo tick functions.  Each WASM entry point (root, browser/, browser_test/)
/// creates its own instance so module-level mutable globals stay per-package.
pub struct DemoSource {
  priv oscillator : Oscillator
  priv noise : Noise
}

///|
pub fn DemoSource::new() -> DemoSource {
  { oscillator: Oscillator::new(), noise: Noise::new(DEMO_NOISE_SEED) }
}

///|
/// Reset oscillator and noise state to the start of the waveform.
pub fn DemoSource::reset(self : DemoSource) -> Unit {
  self.oscillator.reset()
  self.noise.reset(DEMO_NOISE_SEED)
}

///|
/// Generate one sample from the selected source.
///
/// Source ids:
/// - `0`: sine (default)
/// - `1`: saw
/// - `2`: square
/// - `3`: triangle
/// - `4`: noise
pub fn DemoSource::tick_source(
  self : DemoSource,
  source_id~ : Int,
  freq_hz~ : Double,
  sample_rate~ : Double,
) -> Double {
  match source_id {
    1 =>
      self.oscillator.tick_waveform(
        waveform=Waveform::Saw,
        freq_hz~,
        sample_rate~,
      )
    2 =>
      self.oscillator.tick_waveform(
        waveform=Waveform::Square,
        freq_hz~,
        sample_rate~,
      )
    3 =>
      self.oscillator.tick_waveform(
        waveform=Waveform::Triangle,
        freq_hz~,
        sample_rate~,
      )
    4 =>
      if !is_finite(sample_rate) || sample_rate <= 0.0 {
        0.0
      } else {
        self.noise.tick()
      }
    _ =>
      self.oscillator.tick_waveform(
        waveform=Waveform::Sine,
        freq_hz~,
        sample_rate~,
      )
  }
}
