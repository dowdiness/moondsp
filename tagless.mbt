///|
/// Core algebra for the Finally Tagless DSP representation.
/// Downstream packages implement this trait to provide different
/// interpretations (evaluation, code generation, pretty printing, etc.).
pub(open) trait ArithSym {
  constant(Double) -> Self
  mul(Self, Self) -> Self
  mix(Self, Self) -> Self
  clip(Self, Double) -> Self
}

///|
pub(open) trait DspSym: ArithSym {
  oscillator(Self, Waveform) -> Self
  noise(UInt) -> Self
  adsr(Double, Double, Double, Double) -> Self
  gain(Self, Double) -> Self
  output(Self) -> Self
}

///|
pub(open) trait FilterSym: DspSym {
  biquad(Self, BiquadMode, Double, Double) -> Self
}

///|
pub(open) trait DelaySym: DspSym {
  delay(Self, Int, Int, Double) -> Self
}

///|
pub(open) trait StereoSym: DspSym {
  pan(Self, Double) -> Self
  stereo_gain(Self, Double) -> Self
  stereo_clip(Self, Double) -> Self
  stereo_mixdown(Self) -> Self
  stereo_output(Self) -> Self
}

///|
pub(open) trait StereoFilterSym: StereoSym + FilterSym {
  stereo_biquad(Self, BiquadMode, Double, Double) -> Self
}

///|
pub(open) trait StereoDelaySym: StereoSym + DelaySym {
  stereo_delay(Self, Int, Int, Double) -> Self
}
