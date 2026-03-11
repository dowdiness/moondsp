///|
/// Minimal Phase 2 graph node kinds for compiled mono DSP graphs.
pub(all) enum DspNodeKind {
  Constant
  Oscillator
  Noise
  Gain
  Mix
  Clip
  Output
}

///|
/// Declarative DSP graph node in already-topological order.
pub struct DspNode {
  kind : DspNodeKind
  input0 : Int
  input1 : Int
  value0 : Double
  waveform : Waveform
  seed : UInt

  fn new(
    kind : DspNodeKind,
    input0 : Int,
    input1 : Int,
    value0 : Double,
    waveform : Waveform,
    seed : UInt,
  ) -> DspNode
}

///|
fn DspNode::new(
  kind : DspNodeKind,
  input0 : Int,
  input1 : Int,
  value0 : Double,
  waveform : Waveform,
  seed : UInt,
) -> DspNode {
  { kind, input0, input1, value0, waveform, seed }
}

///|
/// Executable buffer-based DSP graph compiled from `DspNode`s.
pub struct CompiledDsp {
  nodes : FixedArray[DspNode]
  buffers : FixedArray[AudioBuffer]
  states : FixedArray[GraphNodeState]
}

///|
/// Create a constant-value node.
pub fn DspNode::constant(value : Double) -> DspNode {
  DspNode(DspNodeKind::Constant, -1, -1, value, Waveform::Sine, 0U)
}

///|
/// Create an oscillator node with a fixed frequency.
pub fn DspNode::oscillator(waveform : Waveform, freq : Double) -> DspNode {
  DspNode(DspNodeKind::Oscillator, -1, -1, freq, waveform, 0U)
}

///|
/// Create a white-noise source node.
pub fn DspNode::noise(seed : UInt) -> DspNode {
  DspNode(DspNodeKind::Noise, -1, -1, 0.0, Waveform::Sine, seed)
}

///|
/// Create an in-place gain node from one upstream node.
pub fn DspNode::gain(input : Int, amount : Double) -> DspNode {
  DspNode(DspNodeKind::Gain, input, -1, amount, Waveform::Sine, 0U)
}

///|
/// Create a mix node from two upstream nodes.
pub fn DspNode::mix(left : Int, right : Int) -> DspNode {
  DspNode(DspNodeKind::Mix, left, right, 0.0, Waveform::Sine, 0U)
}

///|
/// Create a clip node from one upstream node.
pub fn DspNode::clip(input : Int, threshold : Double) -> DspNode {
  DspNode(DspNodeKind::Clip, input, -1, threshold, Waveform::Sine, 0U)
}

///|
/// Mark the final output node.
pub fn DspNode::output(input : Int) -> DspNode {
  DspNode(DspNodeKind::Output, input, -1, 0.0, Waveform::Sine, 0U)
}

///|
/// Compile an already-topological mono graph into an executable buffer graph.
///
/// This first Phase 2 slice intentionally requires the final node to be
/// `Output` and all references to point backward.
pub fn CompiledDsp::compile(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledDsp? {
  if !valid_compiled_graph(nodes) {
    return None
  }

  let node_count = nodes.length()
  let block_size = compiled_block_size(context)
  let fixed_nodes = FixedArray::makei(node_count, index => nodes[index])
  let buffers = FixedArray::makei(node_count, _ => {
    AudioBuffer::filled(block_size)
  })
  let states = FixedArray::makei(node_count, index => {
    make_graph_node_state(nodes[index])
  })
  Some({ nodes: fixed_nodes, buffers, states })
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
  if !valid_compiled_context(sample_rate) ||
    sample_count <= 0 ||
    sample_count > self.compiled_buffer_capacity() {
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
        self.states[index].osc
        .unwrap()
        .process_waveform(context, buffer, node.waveform, node.value0)
      Noise => self.states[index].noise.unwrap().process(context, buffer)
      Gain => {
        copy_buffer(self.buffers[node.input0], buffer, sample_count)
        apply_gain_buffer(buffer, sample_count, node.value0)
      }
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
fn valid_compiled_graph(nodes : Array[DspNode]) -> Bool {
  if nodes.is_empty() {
    return false
  }
  if !(nodes[nodes.length() - 1].kind is DspNodeKind::Output) {
    return false
  }

  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    if !valid_node_inputs(node, index) {
      return false
    }
  }

  true
}

///|
fn valid_node_inputs(node : DspNode, index : Int) -> Bool {
  match node.kind {
    Constant => valid_finite_value(node.value0)
    Oscillator => valid_finite_value(node.value0)
    Noise => true
    Gain =>
      valid_reference(node.input0, index) && valid_finite_value(node.value0)
    Mix =>
      valid_reference(node.input0, index) && valid_reference(node.input1, index)
    Clip =>
      valid_reference(node.input0, index) &&
      valid_finite_value(node.value0) &&
      node.value0 > 0.0
    Output => valid_reference(node.input0, index)
  }
}

///|
fn valid_reference(input : Int, index : Int) -> Bool {
  input >= 0 && input < index
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
fn valid_finite_value(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
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
struct GraphNodeState {
  osc : Oscillator?
  noise : Noise?
}

///|
fn make_graph_node_state(node : DspNode) -> GraphNodeState {
  match node.kind {
    Oscillator => { osc: Some(Oscillator::new()), noise: None }
    Noise => { osc: None, noise: Some(Noise::new(node.seed)) }
    _ => { osc: None, noise: None }
  }
}

///|
fn clear_compiled_buffers(buffers : FixedArray[AudioBuffer]) -> Unit {
  for index = 0; index < buffers.length(); index = index + 1 {
    buffers[index].fill(0.0)
  }
}
