///|
/// Public graph facade wrappers for the raw graph model in
/// `graph/internal/model`.
///
/// These wrappers preserve source compatibility for callers that write
/// `@graph.DspNode::constant(...)` while keeping the extracted model package
/// hidden behind the facade.
///
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
} derive(Eq, Debug)

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
pub impl Show for GraphParamSlot with fn output(self, logger) {
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
/// Runtime control message for a compiled graph.
pub struct GraphControl {
  priv raw : @model.GraphControl
}

///|
fn GraphControl::from_model(raw : @model.GraphControl) -> GraphControl {
  { raw, }
}

///|
fn GraphControl::raw(self : GraphControl) -> @model.GraphControl {
  self.raw
}

///|
pub fn GraphControl::kind(self : GraphControl) -> GraphControlKind {
  graph_control_kind_from_model(self.raw.kind())
}

///|
pub fn GraphControl::node_index(self : GraphControl) -> Int {
  self.raw.node_index()
}

///|
pub fn GraphControl::slot(self : GraphControl) -> GraphParamSlot {
  graph_param_slot_from_model(self.raw.slot())
}

///|
pub fn GraphControl::value(self : GraphControl) -> Double {
  self.raw.value()
}

///|
/// Flat graph node representation for compiled DSP graphs.
pub struct DspNode {
  priv raw : @model.DspNode
}

///|
fn DspNode::from_model(raw : @model.DspNode) -> DspNode {
  { raw, }
}

///|
fn DspNode::raw(self : DspNode) -> @model.DspNode {
  self.raw
}

///|
/// Structural equality for authoring graph nodes.
pub impl Eq for DspNode with fn equal(self, other) {
  self.raw == other.raw
}

///|
pub fn DspNode::kind(self : DspNode) -> DspNodeKind {
  dsp_node_kind_from_model(self.raw.kind())
}

///|
pub fn DspNode::input0(self : DspNode) -> Int {
  self.raw.input0()
}

///|
pub fn DspNode::input1(self : DspNode) -> Int {
  self.raw.input1()
}

///|
pub fn DspNode::value0(self : DspNode) -> Double {
  self.raw.value0()
}

///|
pub fn DspNode::value1(self : DspNode) -> Double {
  self.raw.value1()
}

///|
pub fn DspNode::value2(self : DspNode) -> Double {
  self.raw.value2()
}

///|
pub fn DspNode::value3(self : DspNode) -> Double {
  self.raw.value3()
}

///|
pub fn DspNode::waveform(self : DspNode) -> Waveform {
  self.raw.waveform()
}

///|
pub fn DspNode::filter_mode(self : DspNode) -> BiquadMode {
  self.raw.filter_mode()
}

///|
pub fn DspNode::delay_max_samples(self : DspNode) -> Int {
  self.raw.delay_max_samples()
}

///|
pub fn DspNode::delay_samples(self : DspNode) -> Int {
  self.raw.delay_samples()
}

///|
pub fn DspNode::seed(self : DspNode) -> UInt {
  self.raw.seed()
}

///|
/// Create a constant-value node.
pub fn DspNode::constant(value : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::constant(value))
}

///|
/// Create an oscillator node with a fixed frequency.
pub fn DspNode::oscillator(waveform : Waveform, freq : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::oscillator(waveform, freq))
}

///|
/// Create an oscillator node that reads frequency from another node (FM mode).
pub fn DspNode::oscillator_from(input : Int, waveform : Waveform) -> DspNode {
  DspNode::from_model(@model.DspNode::oscillator_from(input, waveform))
}

///|
/// Create a white-noise source node.
pub fn DspNode::noise(seed : UInt) -> DspNode {
  DspNode::from_model(@model.DspNode::noise(seed))
}

///|
/// Create an ADSR envelope source node.
pub fn DspNode::adsr(
  attack_ms~ : Double,
  decay_ms~ : Double,
  sustain~ : Double,
  release_ms~ : Double,
) -> DspNode {
  DspNode::from_model(
    @model.DspNode::adsr(attack_ms~, decay_ms~, sustain~, release_ms~),
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
  DspNode::from_model(@model.DspNode::biquad(input~, mode~, cutoff_hz~, q~))
}

///|
/// Create a fixed-delay node from one upstream node.
pub fn DspNode::delay(
  input~ : Int,
  max_delay_samples~ : Int,
  delay_samples? : Int = graph_default_delay_samples(max_delay_samples),
  feedback? : Double = 0.0,
) -> DspNode {
  DspNode::from_model(
    @model.DspNode::delay(input~, max_delay_samples~, delay_samples~, feedback~),
  )
}

///|
/// Create an in-place gain node from one upstream node.
pub fn DspNode::gain(input : Int, amount : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::gain(input, amount))
}

///|
/// Create a gain node with envelope modulation from two upstream nodes.
pub fn DspNode::envelope_gain(
  input~ : Int,
  envelope~ : Int,
  amount~ : Double,
) -> DspNode {
  DspNode::from_model(@model.DspNode::envelope_gain(input~, envelope~, amount~))
}

///|
/// Create a sample-wise multiply node from two upstream nodes.
pub fn DspNode::mul(left : Int, right : Int) -> DspNode {
  DspNode::from_model(@model.DspNode::mul(left, right))
}

///|
/// Create a mix node from two upstream nodes.
pub fn DspNode::mix(left : Int, right : Int) -> DspNode {
  DspNode::from_model(@model.DspNode::mix(left, right))
}

///|
/// Create a clip node from one upstream node.
pub fn DspNode::clip(input : Int, threshold : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::clip(input, threshold))
}

///|
/// Mark the final output node.
pub fn DspNode::output(input : Int) -> DspNode {
  DspNode::from_model(@model.DspNode::output(input))
}

///|
/// Create a terminal stereo pan node from one mono upstream node.
pub fn DspNode::pan(input : Int, position : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::pan(input, position))
}

///|
/// Create a stereo gain node from one stereo upstream node.
pub fn DspNode::stereo_gain(input~ : Int, amount~ : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::stereo_gain(input~, amount~))
}

///|
/// Create a stereo clip node from one stereo upstream node.
pub fn DspNode::stereo_clip(input~ : Int, threshold~ : Double) -> DspNode {
  DspNode::from_model(@model.DspNode::stereo_clip(input~, threshold~))
}

///|
/// Create a stereo biquad node from one stereo upstream node.
pub fn DspNode::stereo_biquad(
  input~ : Int,
  mode~ : BiquadMode,
  cutoff_hz~ : Double,
  q~ : Double,
) -> DspNode {
  DspNode::from_model(
    @model.DspNode::stereo_biquad(input~, mode~, cutoff_hz~, q~),
  )
}

///|
/// Create a stereo delay node from one stereo upstream node.
pub fn DspNode::stereo_delay(
  input~ : Int,
  max_delay_samples~ : Int,
  delay_samples? : Int = graph_default_delay_samples(max_delay_samples),
  feedback? : Double = 0.0,
) -> DspNode {
  DspNode::from_model(
    @model.DspNode::stereo_delay(
      input~,
      max_delay_samples~,
      delay_samples~,
      feedback~,
    ),
  )
}

///|
/// Create a fixed-policy stereo-to-mono fold-down node.
pub fn DspNode::stereo_mixdown(input : Int) -> DspNode {
  DspNode::from_model(@model.DspNode::stereo_mixdown(input))
}

///|
/// Mark the final stereo output node.
pub fn DspNode::stereo_output(input : Int) -> DspNode {
  DspNode::from_model(@model.DspNode::stereo_output(input))
}

///|
/// Create a runtime gate-on control targeting an original authoring index.
pub fn GraphControl::gate_on(node_index : Int) -> GraphControl {
  { raw: @model.GraphControl::gate_on(node_index) }
}

///|
/// Create a runtime gate-off control targeting an original authoring index.
pub fn GraphControl::gate_off(node_index : Int) -> GraphControl {
  { raw: @model.GraphControl::gate_off(node_index) }
}

///|
/// Create a runtime numeric parameter update targeting an original authoring
/// index.
pub fn GraphControl::set_param(
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> GraphControl {
  { raw: @model.GraphControl::set_param(node_index, slot.to_model(), value) }
}

///|
fn node_with_offset_inputs(node : DspNode, offset : Int) -> DspNode {
  DspNode::from_model(@model.node_with_offset_inputs(node.raw(), offset))
}

///|
/// Structural check: does this node kind accept SetParam on the given slot?
pub fn node_accepts_slot(node : DspNode, slot : GraphParamSlot) -> Bool {
  @model.node_accepts_slot(node.raw(), slot.to_model())
}

///|
fn graph_default_delay_samples(value : Int) -> Int {
  if value > 0 {
    value
  } else {
    0
  }
}

///|
fn dsp_node_kind_from_model(kind : @model.DspNodeKind) -> DspNodeKind {
  match kind {
    @model.DspNodeKind::Constant => DspNodeKind::Constant
    @model.DspNodeKind::Oscillator => DspNodeKind::Oscillator
    @model.DspNodeKind::Noise => DspNodeKind::Noise
    @model.DspNodeKind::Adsr => DspNodeKind::Adsr
    @model.DspNodeKind::Biquad => DspNodeKind::Biquad
    @model.DspNodeKind::Delay => DspNodeKind::Delay
    @model.DspNodeKind::Gain => DspNodeKind::Gain
    @model.DspNodeKind::Mul => DspNodeKind::Mul
    @model.DspNodeKind::Mix => DspNodeKind::Mix
    @model.DspNodeKind::Clip => DspNodeKind::Clip
    @model.DspNodeKind::Output => DspNodeKind::Output
    @model.DspNodeKind::Pan => DspNodeKind::Pan
    @model.DspNodeKind::StereoGain => DspNodeKind::StereoGain
    @model.DspNodeKind::StereoClip => DspNodeKind::StereoClip
    @model.DspNodeKind::StereoBiquad => DspNodeKind::StereoBiquad
    @model.DspNodeKind::StereoDelay => DspNodeKind::StereoDelay
    @model.DspNodeKind::StereoMixDown => DspNodeKind::StereoMixDown
    @model.DspNodeKind::StereoOutput => DspNodeKind::StereoOutput
  }
}

///|
fn GraphParamSlot::to_model(self : GraphParamSlot) -> @model.GraphParamSlot {
  match self {
    Value0 => @model.GraphParamSlot::Value0
    Value1 => @model.GraphParamSlot::Value1
    Value2 => @model.GraphParamSlot::Value2
    Value3 => @model.GraphParamSlot::Value3
    DelaySamples => @model.GraphParamSlot::DelaySamples
  }
}

///|
fn graph_param_slot_from_model(slot : @model.GraphParamSlot) -> GraphParamSlot {
  match slot {
    @model.GraphParamSlot::Value0 => GraphParamSlot::Value0
    @model.GraphParamSlot::Value1 => GraphParamSlot::Value1
    @model.GraphParamSlot::Value2 => GraphParamSlot::Value2
    @model.GraphParamSlot::Value3 => GraphParamSlot::Value3
    @model.GraphParamSlot::DelaySamples => GraphParamSlot::DelaySamples
  }
}

///|
fn graph_control_kind_from_model(
  kind : @model.GraphControlKind,
) -> GraphControlKind {
  match kind {
    @model.GraphControlKind::GateOn => GraphControlKind::GateOn
    @model.GraphControlKind::GateOff => GraphControlKind::GateOff
    @model.GraphControlKind::SetParam => GraphControlKind::SetParam
  }
}
