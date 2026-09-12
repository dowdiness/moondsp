///|
/// Core algebra for the Finally Tagless DSP representation.
/// Downstream packages implement this trait to provide different
/// interpretations (evaluation, code generation, pretty printing, etc.).
pub(open) trait ArithSym {
  fn constant(Double) -> Self
  fn mul(Self, Self) -> Self
  fn mix(Self, Self) -> Self
  fn clip(Self, Double) -> Self
}

///|
pub(open) trait DspSym: ArithSym {
  fn oscillator(Self, Waveform) -> Self
  fn noise(UInt) -> Self
  fn adsr(Double, Double, Double, Double) -> Self
  fn gain(Self, Double) -> Self
  fn output(Self) -> Self
}

///|
pub(open) trait FilterSym: DspSym {
  fn biquad(Self, BiquadMode, Double, Double) -> Self
}

///|
pub(open) trait DelaySym: DspSym {
  fn delay(Self, Int, Int, Double) -> Self
}

///|
pub(open) trait StereoSym: DspSym {
  fn pan(Self, Double) -> Self
  fn stereo_gain(Self, Double) -> Self
  fn stereo_clip(Self, Double) -> Self
  fn stereo_mixdown(Self) -> Self
  fn stereo_output(Self) -> Self
}

///|
pub(open) trait StereoFilterSym: StereoSym + FilterSym {
  fn stereo_biquad(Self, BiquadMode, Double, Double) -> Self
}

///|
pub(open) trait StereoDelaySym: StereoSym + DelaySym {
  fn stereo_delay(Self, Int, Int, Double) -> Self
}
