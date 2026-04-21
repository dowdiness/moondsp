///|
/// Minimal Phase 2 graph node kinds for compiled mono DSP graphs.
pub(all) enum DspNodeKind {
  Constant
  Oscillator
  Noise
  Adsr
  Biquad
  Delay
  Gain
  Mul
  Mix
  Clip
  Output
  Pan
  StereoGain
  StereoClip
  StereoBiquad
  StereoDelay
  StereoMixDown
  StereoOutput
} derive(Eq)

///|
/// Runtime-updatable numeric graph parameter slots.
pub(all) enum GraphParamSlot {
  Value0
  Value1
  Value2
  Value3
  DelaySamples
} derive(Eq, Debug)

///|
pub impl Show for GraphParamSlot with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Unified runtime control kinds for compiled graphs.
pub(all) enum GraphControlKind {
  GateOn
  GateOff
  SetParam
} derive(Eq)

///|
const NYQUIST_RATIO : Double = 0.5

///|
const MONO_SIGNAL_SHAPE : Int = 0

///|
const STEREO_SIGNAL_SHAPE : Int = 1

///|
/// Runtime control message for a compiled graph.
pub struct GraphControl {
  kind : GraphControlKind
  node_index : Int
  slot : GraphParamSlot
  value : Double

  fn new(
    kind : GraphControlKind,
    node_index : Int,
    slot : GraphParamSlot,
    value : Double,
  ) -> GraphControl
}

///|
fn GraphControl::new(
  kind : GraphControlKind,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> GraphControl {
  { kind, node_index, slot, value }
}

///|
/// Flat graph node representation for compiled DSP graphs.
///
/// Design decision: DspNode uses a flat struct with generic fields (value0-value3)
/// rather than per-kind structs or a tagged union with payloads. This is deliberate:
///
/// 1. **Flat memory layout** — all nodes are the same size, enabling fixed-array
///    storage without boxing. Critical for zero-allocation audio processing.
/// 2. **Copy-on-update** — node_with_value0/value1/delay_samples create updated
///    copies without knowing the node kind, supporting runtime parameter changes.
/// 3. **Serialization** — uniform layout simplifies graph serialization for
///    hot-swap and topology editing.
///
/// The cost is that field semantics depend on `kind` — see each constructor
/// (e.g. `DspNode::oscillator`, `DspNode::biquad`) for the field mapping.
pub struct DspNode {
  kind : DspNodeKind
  input0 : Int
  input1 : Int
  value0 : Double
  value1 : Double
  value2 : Double
  value3 : Double
  waveform : Waveform
  filter_mode : BiquadMode
  delay_max_samples : Int
  delay_samples : Int
  seed : UInt

  fn new(
    kind : DspNodeKind,
    input0 : Int,
    input1 : Int,
    value0 : Double,
    value1 : Double,
    value2 : Double,
    value3 : Double,
    waveform : Waveform,
    filter_mode : BiquadMode,
    delay_max_samples : Int,
    delay_samples : Int,
    seed : UInt,
  ) -> DspNode
}

///|
fn DspNode::new(
  kind : DspNodeKind,
  input0 : Int,
  input1 : Int,
  value0 : Double,
  value1 : Double,
  value2 : Double,
  value3 : Double,
  waveform : Waveform,
  filter_mode : BiquadMode,
  delay_max_samples : Int,
  delay_samples : Int,
  seed : UInt,
) -> DspNode {
  {
    kind,
    input0,
    input1,
    value0,
    value1,
    value2,
    value3,
    waveform,
    filter_mode,
    delay_max_samples,
    delay_samples,
    seed,
  }
}

///|
/// Create a constant-value node.
pub fn DspNode::constant(value : Double) -> DspNode {
  DspNode(
    DspNodeKind::Constant,
    -1,
    -1,
    value,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create an oscillator node with a fixed frequency.
pub fn DspNode::oscillator(waveform : Waveform, freq : Double) -> DspNode {
  DspNode(
    DspNodeKind::Oscillator,
    -1,
    -1,
    freq,
    0.0,
    0.0,
    0.0,
    waveform,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create an oscillator node that reads frequency from another node (FM mode).
pub fn DspNode::oscillator_from(input : Int, waveform : Waveform) -> DspNode {
  DspNode(
    DspNodeKind::Oscillator,
    input,
    -1,
    0.0,
    0.0,
    0.0,
    0.0,
    waveform,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a white-noise source node.
pub fn DspNode::noise(seed : UInt) -> DspNode {
  DspNode(
    DspNodeKind::Noise,
    -1,
    -1,
    0.0,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    seed,
  )
}

///|
/// Create an ADSR envelope source node.
///
/// Use `CompiledDsp::apply_control(GraphControl::gate_on(...))` and
/// `CompiledDsp::apply_control(GraphControl::gate_off(...))` to drive the
/// envelope after compilation.
pub fn DspNode::adsr(
  attack_ms~ : Double,
  decay_ms~ : Double,
  sustain~ : Double,
  release_ms~ : Double,
) -> DspNode {
  DspNode(
    DspNodeKind::Adsr,
    -1,
    -1,
    attack_ms,
    decay_ms,
    sustain,
    release_ms,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a fixed-parameter biquad node from one upstream node.
pub fn DspNode::biquad(
  input~ : Int,
  mode~ : BiquadMode,
  cutoff_hz~ : Double,
  q~ : Double,
) -> DspNode {
  DspNode(
    DspNodeKind::Biquad,
    input,
    -1,
    cutoff_hz,
    q,
    0.0,
    0.0,
    Waveform::Sine,
    mode,
    0,
    0,
    0U,
  )
}

///|
/// Create a fixed-delay node from one upstream node.
pub fn DspNode::delay(
  input : Int,
  max_delay_samples : Int,
  delay_samples? : Int = graph_default_delay_samples(max_delay_samples),
  feedback? : Double = 0.0,
) -> DspNode {
  DspNode(
    DspNodeKind::Delay,
    input,
    -1,
    feedback,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    max_delay_samples,
    delay_samples,
    0U,
  )
}

///|
/// Create an in-place gain node from one upstream node.
pub fn DspNode::gain(input : Int, amount : Double) -> DspNode {
  DspNode(
    DspNodeKind::Gain,
    input,
    -1,
    amount,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a gain node with envelope modulation from two upstream nodes.
/// The output is: input_signal * envelope_buffer * amount.
pub fn DspNode::envelope_gain(
  input : Int,
  envelope : Int,
  amount : Double,
) -> DspNode {
  DspNode(
    DspNodeKind::Gain,
    input,
    envelope,
    amount,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a sample-wise multiply node from two upstream nodes.
pub fn DspNode::mul(left : Int, right : Int) -> DspNode {
  DspNode(
    DspNodeKind::Mul,
    left,
    right,
    0.0,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a mix node from two upstream nodes.
pub fn DspNode::mix(left : Int, right : Int) -> DspNode {
  DspNode(
    DspNodeKind::Mix,
    left,
    right,
    0.0,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a clip node from one upstream node.
pub fn DspNode::clip(input : Int, threshold : Double) -> DspNode {
  DspNode(
    DspNodeKind::Clip,
    input,
    -1,
    threshold,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Mark the final output node.
pub fn DspNode::output(input : Int) -> DspNode {
  DspNode(
    DspNodeKind::Output,
    input,
    -1,
    0.0,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a terminal stereo pan node from one mono upstream node.
pub fn DspNode::pan(input : Int, position : Double) -> DspNode {
  DspNode(
    DspNodeKind::Pan,
    input,
    -1,
    position,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a stereo gain node from one stereo upstream node.
pub fn DspNode::stereo_gain(input : Int, amount : Double) -> DspNode {
  DspNode(
    DspNodeKind::StereoGain,
    input,
    -1,
    amount,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a stereo clip node from one stereo upstream node.
pub fn DspNode::stereo_clip(input : Int, threshold : Double) -> DspNode {
  DspNode(
    DspNodeKind::StereoClip,
    input,
    -1,
    threshold,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a stereo biquad node from one stereo upstream node.
pub fn DspNode::stereo_biquad(
  input : Int,
  mode : BiquadMode,
  cutoff : Double,
  q : Double,
) -> DspNode {
  DspNode(
    DspNodeKind::StereoBiquad,
    input,
    -1,
    cutoff,
    q,
    0.0,
    0.0,
    Waveform::Sine,
    mode,
    0,
    0,
    0U,
  )
}

///|
/// Create a stereo delay node from one stereo upstream node.
pub fn DspNode::stereo_delay(
  input : Int,
  max_delay_samples : Int,
  delay_samples? : Int = graph_default_delay_samples(max_delay_samples),
  feedback? : Double = 0.0,
) -> DspNode {
  DspNode(
    DspNodeKind::StereoDelay,
    input,
    -1,
    feedback,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    max_delay_samples,
    delay_samples,
    0U,
  )
}

///|
/// Create a fixed-policy stereo-to-mono fold-down node.
pub fn DspNode::stereo_mixdown(input : Int) -> DspNode {
  DspNode(
    DspNodeKind::StereoMixDown,
    input,
    -1,
    0.0,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Mark the final stereo output node.
pub fn DspNode::stereo_output(input : Int) -> DspNode {
  DspNode(
    DspNodeKind::StereoOutput,
    input,
    -1,
    0.0,
    0.0,
    0.0,
    0.0,
    Waveform::Sine,
    BiquadMode::LowPass,
    0,
    0,
    0U,
  )
}

///|
/// Create a runtime gate-on control targeting an original authoring index.
pub fn GraphControl::gate_on(node_index : Int) -> GraphControl {
  GraphControl(
    GraphControlKind::GateOn,
    node_index,
    GraphParamSlot::Value0,
    0.0,
  )
}

///|
/// Create a runtime gate-off control targeting an original authoring index.
pub fn GraphControl::gate_off(node_index : Int) -> GraphControl {
  GraphControl(
    GraphControlKind::GateOff,
    node_index,
    GraphParamSlot::Value0,
    0.0,
  )
}

///|
/// Create a runtime numeric parameter update targeting an original authoring
/// index.
pub fn GraphControl::set_param(
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> GraphControl {
  GraphControl(GraphControlKind::SetParam, node_index, slot, value)
}

///|
fn remap_node_inputs(node : DspNode, remap : FixedArray[Int]) -> DspNode {
  DspNode(
    node.kind,
    remapped_input(node.input0, remap),
    remapped_input(node.input1, remap),
    node.value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
  )
}

///|
fn node_with_value0(node : DspNode, value0 : Double) -> DspNode {
  DspNode(
    node.kind,
    node.input0,
    node.input1,
    value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
  )
}

///|
fn node_with_value1(node : DspNode, value1 : Double) -> DspNode {
  DspNode(
    node.kind,
    node.input0,
    node.input1,
    node.value0,
    value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
  )
}

///|
fn node_with_delay_samples(node : DspNode, delay_samples : Int) -> DspNode {
  DspNode(
    node.kind,
    node.input0,
    node.input1,
    node.value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    delay_samples,
    node.seed,
  )
}

///|
fn remapped_input(input : Int, remap : FixedArray[Int]) -> Int {
  if input >= 0 {
    remap[input]
  } else {
    -1
  }
}
