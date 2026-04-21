///|
/// Public API facade for the `dowdiness/moondsp` library.
///
/// This file re-exports the library surface directly from `@dsp`, `@graph`,
/// and `@voice`. External consumers and internal sub-packages both import
/// `dowdiness/moondsp` and access types as `@moondsp.X`.

///|
// Re-export dsp/ package — DSP primitives, tagless algebra, utilities.
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
  pan_left_gain,
  pan_right_gain,

  // Tagless compositions
  exit_deliverable,
  range,
  lin_map,

  // Demo
  type DemoSource,
}

///|
// Re-export graph/ package — compiled graph runtime, topology editing, etc.
pub using @graph {
  type CompiledDsp,
  type CompiledDspHotSwap,
  type CompiledDspTopologyController,
  type CompiledStereoDsp,
  type CompiledStereoDspHotSwap,
  type CompiledStereoDspTopologyController,
  type CompiledTemplate,
  type DspNode,
  type DspNodeKind,
  type GraphBuilder,
  type GraphControl,
  type GraphControlKind,
  type GraphParamSlot,
  type GraphTopologyEdit,
  type GraphTopologyInputSlot,
  type GraphValidationError,

  // Control binding
  type ControlBinding,
  type ControlBindingBuilder,
  type ControlBindingError,
  type ControlBindingMap,

  // Traits
  trait GraphControllable,
  trait GraphDebuggable,
  trait NodeEditable,
  trait NodeFoldable,
  trait NodeSpanning,
  trait NodeStateful,

  // Functions
  node_accepts_slot,
  optimize_graph,
  replay,
}

///|
// Re-export voice/ package — polyphonic voice pool with priority stealing.
pub using @voice {type VoiceHandle, type VoicePool, type VoiceState}
