///|
/// Re-export all public symbols from the `dsp/` package so that existing
/// consumers of `lib/` continue to work without changing their imports.
///
/// `pub using` both re-exports the symbols AND makes them available
/// locally within this package, so graph code can use `AudioBuffer`,
/// `DspContext`, etc. without the `@dsp.` prefix.

///|
// Foundation types
pub using @dsp {
  type AudioBuffer,
  type DspContext,
  type Mono,
  type Stereo,

  // DSP primitives — stateful
  type Oscillator,
  type Noise,
  type Adsr,
  type Biquad,
  type DelayLine,
  type ParamSmoother,

  // DSP primitives — stateless
  type Gain,
  type Clip,
  type Mix,
  type Pan,

  // Enums
  type Waveform,
  type BiquadMode,
  type EnvStage,

  // Tagless algebra traits
  trait ArithSym,
  trait DspSym,
  trait FilterSym,
  trait DelaySym,
  trait StereoSym,
  trait StereoFilterSym,
  trait StereoDelaySym,
  trait ChannelSpec,

  // Utility functions
  is_finite,
  is_finite_positive,
  effective_sample_count,
  sanitize_buffer,
  mono_shape,
  stereo_shape,
  max_feedback_amount,

  // Tagless compositions
  exit_deliverable,
  range,
  lin_map,
}
