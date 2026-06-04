///|
/// Test-only DSP imports for graph blackbox tests. These keep test sources
/// readable without making `dowdiness/moondsp/graph` a public DSP facade.
using @dsp {
  type AudioBuffer,
  type DspContext,
  type Waveform,
  type BiquadMode,
  trait ArithSym,
  trait DspSym,
  trait FilterSym,
  trait DelaySym,
  trait StereoSym,
  trait StereoFilterSym,
  trait StereoDelaySym,
  is_finite,
}
