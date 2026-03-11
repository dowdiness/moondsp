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
}

///|
/// Runtime-updatable numeric graph parameter slots.
pub(all) enum GraphParamSlot {
  Value0
  Value1
  Value2
  Value3
  DelaySamples
}

///|
/// Unified runtime control kinds for compiled graphs.
pub(all) enum GraphControlKind {
  GateOn
  GateOff
  SetParam
}

///|
const NYQUIST_RATIO : Double = 0.5

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
/// Declarative DSP graph node in authoring order.
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
/// Executable buffer-based DSP graph compiled from `DspNode`s.
struct CompiledDsp {
  compile_sample_rate : Double
  nodes : FixedArray[DspNode]
  index_map : FixedArray[Int]
  buffers : FixedArray[AudioBuffer]
  osc_states : FixedArray[Oscillator?]
  noise_states : FixedArray[Noise?]
  env_states : FixedArray[Adsr?]
  biquad_states : FixedArray[Biquad?]
  delay_states : FixedArray[DelayLine?]
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
  attack_ms : Double,
  decay_ms : Double,
  sustain : Double,
  release_ms : Double,
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
  input : Int,
  mode : BiquadMode,
  cutoff : Double,
  q : Double,
) -> DspNode {
  DspNode(
    DspNodeKind::Biquad,
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
/// Create a fixed-delay node from one upstream node.
pub fn DspNode::delay(
  input : Int,
  max_delay_samples : Int,
  delay_samples? : Int = graph_default_delay_samples(max_delay_samples),
) -> DspNode {
  DspNode(
    DspNodeKind::Delay,
    input,
    -1,
    0.0,
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
/// Compile a declarative mono graph into an executable buffer graph.
///
/// This first Phase 2 slice accepts nodes in authoring order, requires exactly
/// one reachable `Output` node, rejects cycles, and rejects graphs containing
/// unreachable nodes.
///
/// Current limitation: runtime graph control is still partial.
/// `CompiledDsp::apply_control(...)` provides a unified entrypoint, but only the
/// node/slot combinations implemented in this slice are supported.
pub fn CompiledDsp::compile(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledDsp? {
  let order = match topo_sorted_node_order(nodes, context) {
    Some(order) => order
    None => return None
  }
  let node_count = nodes.length()
  let block_size = compiled_block_size(context)
  let compile_sample_rate = context.sample_rate()
  let index_map = FixedArray::make(node_count, -1)
  for new_index = 0; new_index < order.length(); new_index = new_index + 1 {
    index_map[order[new_index]] = new_index
  }

  let fixed_nodes = FixedArray::makei(node_count, index => {
    remap_node_inputs(nodes[order[index]], index_map)
  })
  let buffers = FixedArray::makei(node_count, _ => {
    AudioBuffer::filled(block_size)
  })
  let osc_states = FixedArray::makei(node_count, index => {
    make_graph_osc_state(fixed_nodes[index])
  })
  let noise_states = FixedArray::makei(node_count, index => {
    make_graph_noise_state(fixed_nodes[index])
  })
  let env_states = FixedArray::makei(node_count, index => {
    make_graph_env_state(fixed_nodes[index])
  })
  let biquad_states = FixedArray::makei(node_count, index => {
    make_graph_biquad_state(fixed_nodes[index])
  })
  let delay_states = FixedArray::makei(node_count, index => {
    make_graph_delay_state(fixed_nodes[index])
  })
  Some({
    compile_sample_rate,
    nodes: fixed_nodes,
    index_map,
    buffers,
    osc_states,
    noise_states,
    env_states,
    biquad_states,
    delay_states,
  })
}

///|
/// Run the compiled graph for one buffer and write the final output into
/// `output`.
pub fn CompiledDsp::process(
  self : CompiledDsp,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = compiled_sample_count(context, output)
  if !valid_compiled_context(sample_rate) {
    clear_compiled_buffers(self.buffers)
    reset_graph_env_states(self.env_states)
    output.fill(0.0)
    return
  }
  if sample_count <= 0 || sample_count > self.compiled_buffer_capacity() {
    clear_compiled_buffers(self.buffers)
    output.fill(0.0)
    return
  }

  for index = 0; index < self.nodes.length(); index = index + 1 {
    let node = self.nodes[index]
    let buffer = self.buffers[index]
    match node.kind {
      Constant => fill_constant_buffer(buffer, sample_count, node.value0)
      Oscillator =>
        self.osc_states[index]
        .unwrap()
        .process_waveform(context, buffer, node.waveform, node.value0)
      Noise => self.noise_states[index].unwrap().process(context, buffer)
      Adsr => self.env_states[index].unwrap().process(context, buffer)
      Biquad => {
        copy_buffer(self.buffers[node.input0], buffer, sample_count)
        process_graph_biquad(
          self.biquad_states[index].unwrap(),
          context,
          buffer,
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      Delay => {
        copy_buffer(self.buffers[node.input0], buffer, sample_count)
        self.delay_states[index].unwrap().process(context, buffer)
      }
      Gain => {
        copy_buffer(self.buffers[node.input0], buffer, sample_count)
        apply_gain_buffer(buffer, sample_count, node.value0)
      }
      Mul =>
        multiply_buffers(
          self.buffers[node.input0],
          self.buffers[node.input1],
          buffer,
          sample_count,
        )
      Mix =>
        mix_buffers(
          self.buffers[node.input0],
          self.buffers[node.input1],
          buffer,
          sample_count,
        )
      Clip => {
        copy_buffer(self.buffers[node.input0], buffer, sample_count)
        clip_buffer(buffer, sample_count, node.value0)
      }
      Output => copy_buffer(self.buffers[node.input0], buffer, sample_count)
    }
  }

  copy_buffer(self.buffers[self.buffers.length() - 1], output, sample_count)
}

///|
/// Apply a runtime control message to a compiled graph.
///
/// This is the preferred Phase 2 runtime-control entrypoint. The older
/// `gate_on(...)`, `gate_off(...)`, and `set_param(...)` methods are retained as
/// compatibility helpers and delegate here.
pub fn CompiledDsp::apply_control(
  self : CompiledDsp,
  control : GraphControl,
) -> Bool {
  match control.kind {
    GateOn => apply_graph_gate_control(self, control.node_index, true)
    GateOff => apply_graph_gate_control(self, control.node_index, false)
    SetParam =>
      apply_graph_param_control(
        self,
        control.node_index,
        control.slot,
        control.value,
      )
  }
}

///|
/// Trigger `gate_on()` on an ADSR node using its original authoring index.
///
/// Compatibility helper; prefer `apply_control(GraphControl::gate_on(...))`.
pub fn CompiledDsp::gate_on(self : CompiledDsp, node_index : Int) -> Bool {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on an ADSR node using its original authoring index.
///
/// Compatibility helper; prefer `apply_control(GraphControl::gate_off(...))`.
pub fn CompiledDsp::gate_off(self : CompiledDsp, node_index : Int) -> Bool {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled node using its original authoring
/// index.
///
/// Returns `false` when the node index is invalid, the slot is unsupported for
/// that node kind, or the new value is invalid for that slot.
///
/// Compatibility helper; prefer
/// `apply_control(GraphControl::set_param(...))`.
pub fn CompiledDsp::set_param(
  self : CompiledDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
fn apply_graph_gate_control(
  compiled : CompiledDsp,
  node_index : Int,
  gate_on : Bool,
) -> Bool {
  match compiled.compiled_index_for(node_index) {
    Some(compiled_index) =>
      match compiled.env_states[compiled_index] {
        Some(env) => {
          if gate_on {
            env.gate_on()
          } else {
            env.gate_off()
          }
          true
        }
        None => false
      }
    None => false
  }
}

///|
fn apply_graph_param_control(
  compiled : CompiledDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  let compiled_index = match compiled.compiled_index_for(node_index) {
    Some(compiled_index) => compiled_index
    None => return false
  }
  let node = compiled.nodes[compiled_index]
  let updated = match
    updated_node_param(node, slot, value, compiled.compile_sample_rate) {
    Some(updated) => updated
    None => return false
  }
  compiled.nodes[compiled_index] = updated
  apply_runtime_param_side_effect(compiled, compiled_index, updated, slot)
}

///|
fn valid_compiled_graph(nodes : Array[DspNode], context : DspContext) -> Bool {
  let sample_rate = context.sample_rate()
  let output_index = match find_single_output_index(nodes) {
    Some(output_index) => output_index
    None => return false
  }
  if nodes.is_empty() {
    return false
  }

  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    if !valid_node_inputs(node, nodes.length(), sample_rate) {
      return false
    }
  }

  has_reachable_acyclic_graph(nodes, output_index)
}

///|
fn valid_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
) -> Bool {
  match node.kind {
    Constant => valid_finite_value(node.value0)
    Oscillator => valid_finite_value(node.value0)
    Noise => true
    Adsr =>
      valid_finite_value(node.value0) &&
      valid_finite_value(node.value1) &&
      valid_finite_value(node.value2) &&
      valid_finite_value(node.value3)
    Biquad =>
      valid_reference(node.input0, node_count) &&
      valid_biquad_graph_params(sample_rate, node.value0, node.value1)
    Delay => valid_reference(node.input0, node_count)
    Gain =>
      valid_reference(node.input0, node_count) &&
      valid_finite_value(node.value0)
    Mul =>
      valid_reference(node.input0, node_count) &&
      valid_reference(node.input1, node_count)
    Mix =>
      valid_reference(node.input0, node_count) &&
      valid_reference(node.input1, node_count)
    Clip =>
      valid_reference(node.input0, node_count) &&
      valid_finite_value(node.value0) &&
      node.value0 > 0.0
    Output => valid_reference(node.input0, node_count)
  }
}

///|
fn valid_reference(input : Int, node_count : Int) -> Bool {
  input >= 0 && input < node_count
}

///|
fn CompiledDsp::compiled_buffer_capacity(self : CompiledDsp) -> Int {
  if self.buffers.length() == 0 {
    0
  } else {
    self.buffers[0].length()
  }
}

///|
fn CompiledDsp::compiled_index_for(
  self : CompiledDsp,
  node_index : Int,
) -> Int? {
  if node_index < 0 || node_index >= self.index_map.length() {
    None
  } else {
    Some(self.index_map[node_index])
  }
}

///|
fn valid_finite_value(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn updated_node_param(
  node : DspNode,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> DspNode? {
  match node.kind {
    Constant =>
      match slot {
        Value0 if valid_finite_value(value) =>
          Some(node_with_value0(node, value))
        _ => None
      }
    Oscillator =>
      match slot {
        Value0 if valid_finite_value(value) =>
          Some(node_with_value0(node, value))
        _ => None
      }
    Adsr => None
    Noise => None
    Biquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1) =>
          Some(node_with_value0(node, value))
        Value1 if valid_biquad_graph_params(sample_rate, node.value0, value) =>
          Some(node_with_value1(node, value))
        _ => None
      }
    Delay =>
      match slot {
        DelaySamples =>
          match exact_int_value(value) {
            Some(delay_samples) =>
              Some(node_with_delay_samples(node, delay_samples))
            None => None
          }
        _ => None
      }
    Gain =>
      match slot {
        Value0 if valid_finite_value(value) =>
          Some(node_with_value0(node, value))
        _ => None
      }
    Mul => None
    Mix => None
    Clip =>
      match slot {
        Value0 if valid_finite_value(value) && value > 0.0 =>
          Some(node_with_value0(node, value))
        _ => None
      }
    Output => None
  }
}

///|
fn apply_runtime_param_side_effect(
  compiled : CompiledDsp,
  compiled_index : Int,
  node : DspNode,
  slot : GraphParamSlot,
) -> Bool {
  match node.kind {
    Delay =>
      match slot {
        DelaySamples =>
          match compiled.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_delay_samples(node.delay_samples)
              true
            }
            None => false
          }
        _ => false
      }
    Constant => true
    Oscillator => true
    Biquad => true
    Gain => true
    Clip => true
    _ => false
  }
}

///|
fn exact_int_value(value : Double) -> Int? {
  if !valid_finite_value(value) || value.trunc() != value {
    return None
  }
  let int_value = value.to_int()
  if Double::from_int(int_value) == value {
    Some(int_value)
  } else {
    None
  }
}

///|
fn valid_biquad_graph_params(
  sample_rate : Double,
  cutoff : Double,
  q : Double,
) -> Bool {
  let nyquist = sample_rate * NYQUIST_RATIO
  valid_finite_value(sample_rate) &&
  sample_rate > 0.0 &&
  valid_finite_value(cutoff) &&
  cutoff > 0.0 &&
  cutoff < nyquist &&
  valid_finite_value(q) &&
  q > 0.0
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
fn topo_sorted_node_order(
  nodes : Array[DspNode],
  context : DspContext,
) -> Array[Int]? {
  if !valid_compiled_graph(nodes, context) {
    return None
  }

  let output_index = find_single_output_index(nodes).unwrap()
  let marks = FixedArray::make(nodes.length(), 0)
  let order = Array::new()
  if !visit_graph_node(output_index, nodes, marks, order) {
    return None
  }
  if order.length() != nodes.length() {
    return None
  }

  Some(order)
}

///|
fn find_single_output_index(nodes : Array[DspNode]) -> Int? {
  let mut output_index = -1
  for index = 0; index < nodes.length(); index = index + 1 {
    if nodes[index].kind is DspNodeKind::Output {
      if output_index >= 0 {
        return None
      }
      output_index = index
    }
  }
  if output_index >= 0 {
    Some(output_index)
  } else {
    None
  }
}

///|
fn has_reachable_acyclic_graph(
  nodes : Array[DspNode],
  output_index : Int,
) -> Bool {
  let marks = FixedArray::make(nodes.length(), 0)
  let order = Array::new()
  if !visit_graph_node(output_index, nodes, marks, order) {
    return false
  }
  order.length() == nodes.length()
}

///|
fn visit_graph_node(
  index : Int,
  nodes : Array[DspNode],
  marks : FixedArray[Int],
  order : Array[Int],
) -> Bool {
  match marks[index] {
    1 => false
    2 => true
    _ => {
      marks[index] = 1
      if !visit_graph_dependencies(nodes[index], nodes, marks, order) {
        return false
      }
      marks[index] = 2
      order.push(index)
      true
    }
  }
}

///|
fn visit_graph_dependencies(
  node : DspNode,
  nodes : Array[DspNode],
  marks : FixedArray[Int],
  order : Array[Int],
) -> Bool {
  match node.kind {
    Constant => true
    Oscillator => true
    Noise => true
    Adsr => true
    Biquad => visit_graph_node(node.input0, nodes, marks, order)
    Delay => visit_graph_node(node.input0, nodes, marks, order)
    Gain => visit_graph_node(node.input0, nodes, marks, order)
    Mul =>
      visit_graph_node(node.input0, nodes, marks, order) &&
      visit_graph_node(node.input1, nodes, marks, order)
    Mix =>
      visit_graph_node(node.input0, nodes, marks, order) &&
      visit_graph_node(node.input1, nodes, marks, order)
    Clip => visit_graph_node(node.input0, nodes, marks, order)
    Output => visit_graph_node(node.input0, nodes, marks, order)
  }
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

///|
fn compiled_block_size(context : DspContext) -> Int {
  if context.block_size() > 0 {
    context.block_size()
  } else {
    1
  }
}

///|
fn compiled_sample_count(context : DspContext, output : AudioBuffer) -> Int {
  if output.length() < context.block_size() {
    output.length()
  } else {
    context.block_size()
  }
}

///|
fn valid_compiled_context(sample_rate : Double) -> Bool {
  !sample_rate.is_nan() && !sample_rate.is_inf() && sample_rate > 0.0
}

///|
fn copy_buffer(
  source : AudioBuffer,
  target : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = if sample_count < source.length() {
    if sample_count < target.length() {
      sample_count
    } else {
      target.length()
    }
  } else if source.length() < target.length() {
    source.length()
  } else {
    target.length()
  }

  for index = 0; index < bounded; index = index + 1 {
    target.set(index, source.get(index))
  }

  for index = bounded; index < target.length(); index = index + 1 {
    target.set(index, 0.0)
  }
}

///|
fn fill_constant_buffer(
  buffer : AudioBuffer,
  sample_count : Int,
  value : Double,
) -> Unit {
  let bounded = if sample_count < buffer.length() {
    sample_count
  } else {
    buffer.length()
  }
  for index = 0; index < bounded; index = index + 1 {
    buffer.set(index, value)
  }
  for index = bounded; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn apply_gain_buffer(
  buffer : AudioBuffer,
  sample_count : Int,
  amount : Double,
) -> Unit {
  let bounded = if sample_count < buffer.length() {
    sample_count
  } else {
    buffer.length()
  }
  for index = 0; index < bounded; index = index + 1 {
    buffer.set(index, buffer.get(index) * amount)
  }
  for index = bounded; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn mix_buffers(
  left : AudioBuffer,
  right : AudioBuffer,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = min_buffer_length(
    sample_count,
    left.length(),
    right.length(),
    output.length(),
  )
  for index = 0; index < bounded; index = index + 1 {
    output.set(index, left.get(index) + right.get(index))
  }
  for index = bounded; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn multiply_buffers(
  left : AudioBuffer,
  right : AudioBuffer,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = min_buffer_length(
    sample_count,
    left.length(),
    right.length(),
    output.length(),
  )
  for index = 0; index < bounded; index = index + 1 {
    output.set(index, left.get(index) * right.get(index))
  }
  for index = bounded; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn clip_buffer(
  buffer : AudioBuffer,
  sample_count : Int,
  threshold : Double,
) -> Unit {
  let bounded = if sample_count < buffer.length() {
    sample_count
  } else {
    buffer.length()
  }
  for index = 0; index < bounded; index = index + 1 {
    let sample = buffer.get(index)
    let clipped = if sample > threshold {
      threshold
    } else if sample < -threshold {
      -threshold
    } else {
      sample
    }
    buffer.set(index, clipped)
  }
  for index = bounded; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn min_buffer_length(a : Int, b : Int, c : Int, d : Int) -> Int {
  let ab = if a < b { a } else { b }
  let cd = if c < d { c } else { d }
  if ab < cd {
    ab
  } else {
    cd
  }
}

///|
fn make_graph_osc_state(node : DspNode) -> Oscillator? {
  match node.kind {
    Oscillator => Some(Oscillator::new())
    _ => None
  }
}

///|
fn make_graph_noise_state(node : DspNode) -> Noise? {
  match node.kind {
    Noise => Some(Noise::new(node.seed))
    _ => None
  }
}

///|
fn make_graph_env_state(node : DspNode) -> Adsr? {
  match node.kind {
    Adsr => Some(Adsr::new(node.value0, node.value1, node.value2, node.value3))
    _ => None
  }
}

///|
fn make_graph_biquad_state(node : DspNode) -> Biquad? {
  match node.kind {
    Biquad => Some(Biquad::new())
    _ => None
  }
}

///|
fn make_graph_delay_state(node : DspNode) -> DelayLine? {
  match node.kind {
    Delay =>
      Some(
        DelayLine::new(node.delay_max_samples, delay_samples=node.delay_samples),
      )
    _ => None
  }
}

///|
fn process_graph_biquad(
  biquad : Biquad,
  context : DspContext,
  buffer : AudioBuffer,
  mode : BiquadMode,
  cutoff : Double,
  q : Double,
) -> Unit {
  if !biquad.update(context, mode, cutoff, q) {
    buffer.fill(0.0)
    return
  }
  biquad.process(context, buffer)
}

///|
fn reset_graph_env_states(env_states : FixedArray[Adsr?]) -> Unit {
  for index = 0; index < env_states.length(); index = index + 1 {
    match env_states[index] {
      Some(env) => env.reset()
      None => ()
    }
  }
}

///|
fn clear_compiled_buffers(buffers : FixedArray[AudioBuffer]) -> Unit {
  for index = 0; index < buffers.length(); index = index + 1 {
    buffers[index].fill(0.0)
  }
}
