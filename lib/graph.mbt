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
} derive(Eq, Show)

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
/// Shared internal graph state for both mono and stereo compiled DSP graphs.
/// Both CompiledDsp and CompiledStereoDsp wrap this struct as newtypes.
///
/// All three buffer families (buffers, left_buffers, right_buffers) are allocated
/// for every node regardless of mono/stereo variant. Mono nodes write only to
/// `buffers`; stereo nodes write only to `left_buffers`/`right_buffers`. This
/// uniform layout enables hot-swap state copy without knowing the variant.
priv struct CompiledGraph {
  compile_sample_rate : Double
  nodes : FixedArray[DspNode]
  index_map : FixedArray[Int]
  // Mono signal path buffers — one per node
  buffers : FixedArray[AudioBuffer]
  // Stereo signal path buffers — one pair per node (populated only for stereo-aware nodes)
  left_buffers : FixedArray[AudioBuffer]
  right_buffers : FixedArray[AudioBuffer]
  osc_states : FixedArray[Oscillator?]
  noise_states : FixedArray[Noise?]
  env_states : FixedArray[Adsr?]
  biquad_states : FixedArray[Biquad?]
  stereo_biquad_left_states : FixedArray[Biquad?]
  stereo_biquad_right_states : FixedArray[Biquad?]
  delay_states : FixedArray[DelayLine?]
  stereo_delay_left_states : FixedArray[DelayLine?]
  stereo_delay_right_states : FixedArray[DelayLine?]
  feedback_edges : FixedArray[(Int, Int, Int)]
  // Feedback graph per-sample self-registers — one value per node, updated each sample
  self_values : FixedArray[Double]
  self_left_values : FixedArray[Double]
  self_right_values : FixedArray[Double]
  self_enabled : FixedArray[Bool]
  back_edge_input0_source : FixedArray[Int]
  back_edge_input1_source : FixedArray[Int]
  // Pre-allocated scratch arrays for feedback processing (avoid hot-path alloc)
  sample_values : FixedArray[Double]
  left_sample_values : FixedArray[Double]
  right_sample_values : FixedArray[Double]
  // Pre-computed pan gains — trig is done once per block, not per sample
  pan_left_gains : FixedArray[Double]
  pan_right_gains : FixedArray[Double]
  mut last_sanitized_count : Int
}

///|
/// Executable buffer-based DSP graph compiled from `DspNode`s.
struct CompiledDsp(CompiledGraph)

///|
/// Executable terminal-stereo graph compiled from `DspNode`s.
struct CompiledStereoDsp(CompiledGraph)

///|
/// Number of non-finite samples replaced with 0.0 during the most recent
/// process() call. Returns 0 if output was clean.
pub fn CompiledDsp::last_sanitized_count(self : CompiledDsp) -> Int {
  self.0.last_sanitized_count
}

///|
pub fn CompiledStereoDsp::last_sanitized_count(self : CompiledStereoDsp) -> Int {
  self.0.last_sanitized_count
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
/// Compile a declarative mono graph into an executable buffer graph.
///
/// This first Phase 2 slice accepts nodes in authoring order, requires exactly
/// one reachable `Output` node, rejects unreachable nodes, and supports a
/// narrow mono-only feedback slice by resolving detected back-edges as
/// implicit `z^-1` inputs.
///
/// Current limitation: runtime graph control is still partial.
/// `CompiledDsp::apply_control(...)` provides a unified entrypoint, but only the
/// node/slot combinations implemented in this slice are supported.
pub fn CompiledDsp::compile(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledDsp? {
  let original_count = nodes.length()
  let (nodes, opt_map) = optimize_graph(nodes)
  CompiledDsp::compile_internal(nodes, context, original_count, opt_map)
}

///|
/// Compile without optimization — used by topology controllers where authoring
/// indices must be preserved for runtime controls.
fn CompiledDsp::compile_raw(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledDsp? {
  let count = nodes.length()
  let identity_map = FixedArray::makei(count, fn(i) { i })
  CompiledDsp::compile_internal(nodes, context, count, identity_map)
}

///|
/// Shared compilation logic for both mono and stereo graphs.
///
/// WHY callbacks instead of an enum: the validation logic differs not just by
/// mono/stereo but also by presence of feedback edges (simple vs feedback
/// variant). A `validate` callback lets the caller compose both checks in
/// one closure without adding a separate parameter for feedback mode.
/// `compile_plan` selects the mono or stereo topological sort + feedback detection.
fn compile_graph_impl(
  nodes : Array[DspNode],
  context : DspContext,
  original_count : Int,
  opt_map : FixedArray[Int],
  compile_plan : (Array[DspNode], DspContext) -> (
    Array[Int],
    Array[(Int, Int, Int)],
  )?,
  validate : (FixedArray[DspNode], FixedArray[(Int, Int, Int)]) -> Bool,
) -> CompiledGraph? {
  let plan = match compile_plan(nodes, context) {
    Some(plan) => plan
    None => return None
  }
  let order = plan.0
  let node_count = nodes.length()
  let block_size = compiled_block_size(context)
  let compile_sample_rate = context.sample_rate()
  let topo_map = FixedArray::make(node_count, -1)
  for new_index = 0; new_index < order.length(); new_index = new_index + 1 {
    topo_map[order[new_index]] = new_index
  }
  // Compose: original index -> optimized index -> compiled index
  let index_map = FixedArray::makei(original_count, fn(i) {
    let opt_i = opt_map[i]
    if opt_i < 0 {
      -1
    } else {
      topo_map[opt_i]
    }
  })

  let fixed_nodes = FixedArray::makei(node_count, index => {
    remap_node_inputs(nodes[order[index]], topo_map)
  })
  let feedback_edges = remapped_feedback_edges(plan.1, topo_map)
  if !validate(fixed_nodes, feedback_edges) {
    return None
  }
  let buffers = FixedArray::makei(node_count, _ => {
    AudioBuffer::filled(block_size)
  })
  let left_buffers = FixedArray::makei(node_count, _ => {
    AudioBuffer::filled(block_size)
  })
  let right_buffers = FixedArray::makei(node_count, _ => {
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
  let stereo_biquad_left_states = FixedArray::makei(node_count, index => {
    make_graph_stereo_biquad_state(fixed_nodes[index])
  })
  let stereo_biquad_right_states = FixedArray::makei(node_count, index => {
    make_graph_stereo_biquad_state(fixed_nodes[index])
  })
  let delay_states = FixedArray::makei(node_count, index => {
    make_graph_delay_state(fixed_nodes[index])
  })
  let stereo_delay_left_states = FixedArray::makei(node_count, index => {
    make_graph_stereo_delay_state(fixed_nodes[index])
  })
  let stereo_delay_right_states = FixedArray::makei(node_count, index => {
    make_graph_stereo_delay_state(fixed_nodes[index])
  })
  let self_values = FixedArray::make(node_count, 0.0)
  let self_left_values = FixedArray::make(node_count, 0.0)
  let self_right_values = FixedArray::make(node_count, 0.0)
  let self_enabled = FixedArray::make(node_count, false)
  let back_edge_input0_source = FixedArray::make(node_count, -1)
  let back_edge_input1_source = FixedArray::make(node_count, -1)
  for i = 0; i < feedback_edges.length(); i = i + 1 {
    let edge = feedback_edges[i]
    let source_idx = edge.0
    let target_idx = edge.1
    let slot = edge.2
    self_enabled[source_idx] = true
    if slot == 0 {
      if back_edge_input0_source[target_idx] >= 0 {
        return None
      }
      back_edge_input0_source[target_idx] = source_idx
    } else {
      if back_edge_input1_source[target_idx] >= 0 {
        return None
      }
      back_edge_input1_source[target_idx] = source_idx
    }
  }
  Some({
    compile_sample_rate,
    nodes: fixed_nodes,
    index_map,
    buffers,
    left_buffers,
    right_buffers,
    osc_states,
    noise_states,
    env_states,
    biquad_states,
    stereo_biquad_left_states,
    stereo_biquad_right_states,
    delay_states,
    stereo_delay_left_states,
    stereo_delay_right_states,
    feedback_edges,
    self_values,
    self_left_values,
    self_right_values,
    self_enabled,
    back_edge_input0_source,
    back_edge_input1_source,
    sample_values: FixedArray::make(node_count, 0.0),
    left_sample_values: FixedArray::make(node_count, 0.0),
    right_sample_values: FixedArray::make(node_count, 0.0),
    pan_left_gains: FixedArray::make(node_count, 0.0),
    pan_right_gains: FixedArray::make(node_count, 0.0),
    last_sanitized_count: 0,
  })
}

///|
fn CompiledDsp::compile_internal(
  nodes : Array[DspNode],
  context : DspContext,
  original_count : Int,
  opt_map : FixedArray[Int],
) -> CompiledDsp? {
  compile_graph_impl(
    nodes,
    context,
    original_count,
    opt_map,
    mono_compile_plan,
    fn(fixed_nodes, feedback_edges) {
      if feedback_edges.length() == 0 {
        valid_terminal_mono_shapes(fixed_nodes)
      } else {
        valid_feedback_terminal_mono_graph(fixed_nodes, feedback_edges)
      }
    },
  ).map(fn(graph) { CompiledDsp(graph) })
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
  let sample_count = effective_sample_count(context, output)
  if !is_finite_positive(sample_rate) {
    clear_compiled_buffers(self.0.buffers)
    clear_compiled_buffers(self.0.left_buffers)
    clear_compiled_buffers(self.0.right_buffers)
    reset_graph_env_states(self.0.env_states)
    output.fill(0.0)
    self.0.last_sanitized_count = 0
    return
  }
  if sample_count <= 0 || sample_count > self.compiled_buffer_capacity() {
    clear_compiled_buffers(self.0.buffers)
    clear_compiled_buffers(self.0.left_buffers)
    clear_compiled_buffers(self.0.right_buffers)
    output.fill(0.0)
    self.0.last_sanitized_count = 0
    return
  }
  if self.0.feedback_edges.length() > 0 {
    self.process_feedback_graph(context, output, sample_count)
    self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
    return
  }

  let pan = Pan::new()
  for index = 0; index < self.0.nodes.length(); index = index + 1 {
    let node = self.0.nodes[index]
    let buffer = self.0.buffers[index]
    match node.kind {
      Constant => fill_constant_buffer(buffer, sample_count, node.value0)
      Oscillator =>
        if node.input0 >= 0 {
          let osc = self.0.osc_states[index].unwrap()
          let freq_buf = self.0.buffers[node.input0]
          let sr = context.sample_rate()
          for i = 0; i < sample_count; i = i + 1 {
            buffer.set(i, osc.tick_waveform(node.waveform, freq_buf.get(i), sr))
          }
        } else {
          self.0.osc_states[index]
          .unwrap()
          .process_waveform(context, buffer, node.waveform, node.value0)
        }
      Noise => self.0.noise_states[index].unwrap().process(context, buffer)
      Adsr => self.0.env_states[index].unwrap().process(context, buffer)
      Biquad => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        process_graph_biquad(
          self.0.biquad_states[index].unwrap(),
          context,
          buffer,
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      Delay => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        self.0.delay_states[index].unwrap().process(context, buffer)
      }
      Gain => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        apply_gain_buffer(buffer, sample_count, node.value0)
      }
      Mul =>
        multiply_buffers(
          self.0.buffers[node.input0],
          self.0.buffers[node.input1],
          buffer,
          sample_count,
        )
      Mix =>
        mix_buffers(
          self.0.buffers[node.input0],
          self.0.buffers[node.input1],
          buffer,
          sample_count,
        )
      Clip => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        clip_buffer(buffer, sample_count, node.value0)
      }
      Output => copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
      Pan =>
        pan.process(
          context,
          self.0.buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          node.value0,
        )
      StereoGain => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        apply_gain_buffer(self.0.left_buffers[index], sample_count, node.value0)
        apply_gain_buffer(
          self.0.right_buffers[index],
          sample_count,
          node.value0,
        )
      }
      StereoClip => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        clip_buffer(self.0.left_buffers[index], sample_count, node.value0)
        clip_buffer(self.0.right_buffers[index], sample_count, node.value0)
      }
      StereoBiquad => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        process_graph_biquad(
          self.0.stereo_biquad_left_states[index].unwrap(),
          context,
          self.0.left_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
        process_graph_biquad(
          self.0.stereo_biquad_right_states[index].unwrap(),
          context,
          self.0.right_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      StereoDelay => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        self.0.stereo_delay_left_states[index]
        .unwrap()
        .process(context, self.0.left_buffers[index])
        self.0.stereo_delay_right_states[index]
        .unwrap()
        .process(context, self.0.right_buffers[index])
      }
      StereoMixDown =>
        mixdown_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          buffer,
          sample_count,
        )
      StereoOutput => buffer.fill(0.0)
    }
  }

  copy_buffer(self.0.buffers[self.0.buffers.length() - 1], output, sample_count)
  self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
}

///|
/// Unified feedback graph processing for both mono and stereo graphs.
///
/// Both `Output` and `StereoOutput` arms are present in the match — validation
/// at compile time guarantees a mono graph never contains `StereoOutput` and
/// vice-versa, so the "wrong" arm is a no-op that never fires at runtime.
///
/// WHY `is_stereo` flag instead of inspecting the last node's kind: the flag
/// is precomputed and branch-predictable (constant for a given graph type),
/// avoiding an index lookup on the hot path. It controls only the final
/// output copy (once per block, not per sample):
/// - mono:   copies last mono buffer to `output`
/// - stereo: copies last stereo buffers to `left_output` / `right_output`
fn CompiledGraph::process_feedback_graph_impl(
  self : CompiledGraph,
  context : DspContext,
  output : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  is_stereo : Bool,
  sample_count : Int,
) -> Unit {
  clear_compiled_buffers(self.buffers)
  clear_compiled_buffers(self.left_buffers)
  clear_compiled_buffers(self.right_buffers)
  self.prepare_feedback_biquads(context)
  // Use pre-allocated scratch arrays instead of allocating per call
  let sample_values = self.sample_values
  let left_sv = self.left_sample_values
  let right_sv = self.right_sample_values
  for i = 0; i < sample_values.length(); i = i + 1 {
    sample_values[i] = 0.0
    left_sv[i] = 0.0
    right_sv[i] = 0.0
  }
  let sample_rate = context.sample_rate()
  // Pre-compute pan trig gains once per block (position is constant within block)
  for i = 0; i < self.nodes.length(); i = i + 1 {
    if self.nodes[i].kind is Pan {
      self.pan_left_gains[i] = feedback_pan_left_gain(self.nodes[i].value0)
      self.pan_right_gains[i] = feedback_pan_right_gain(self.nodes[i].value0)
    }
  }

  for sample_index = 0
      sample_index < sample_count
      sample_index = sample_index + 1 {
    for node_index = 0
        node_index < self.nodes.length()
        node_index = node_index + 1 {
      let node = self.nodes[node_index]
      match node.kind {
        Constant => {
          let value = node.value0
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Oscillator => {
          let freq = if node.input0 >= 0 {
            self_register_input_sample(
              sample_values,
              self.self_values,
              node.input0,
              self.back_edge_input0_source[node_index],
            )
          } else {
            node.value0
          }
          let value = self.osc_states[node_index]
            .unwrap()
            .tick_waveform(node.waveform, freq, sample_rate)
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Noise => {
          let value = self.noise_states[node_index].unwrap().tick()
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Adsr => {
          let value = self.env_states[node_index].unwrap().tick(context)
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Biquad => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let value = self.biquad_states[node_index].unwrap().tick(input0)
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Delay => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let value = self.delay_states[node_index].unwrap().tick(input0)
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Gain => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let value = input0 * node.value0
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Mul => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input1 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input1,
            self.back_edge_input1_source[node_index],
          )
          let value = input0 * input1
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Mix => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input1 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input1,
            self.back_edge_input1_source[node_index],
          )
          let value = input0 + input1
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Clip => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let value = clip_feedback_sample(input0, node.value0)
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        Output => {
          // Mono terminal: reads input into mono buffer.
          // In stereo graphs this arm never matches (no Output node present).
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          sample_values[node_index] = input0
          self.buffers[node_index].set(sample_index, input0)
        }
        Pan => {
          let input0 = self_register_input_sample(
            sample_values,
            self.self_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let pan_left = input0 * self.pan_left_gains[node_index]
          let pan_right = input0 * self.pan_right_gains[node_index]
          left_sv[node_index] = pan_left
          right_sv[node_index] = pan_right
          self.left_buffers[node_index].set(sample_index, pan_left)
          self.right_buffers[node_index].set(sample_index, pan_right)
        }
        StereoGain => {
          let input_left = self_register_stereo_input_left(
            left_sv,
            self.self_left_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input_right = self_register_stereo_input_right(
            right_sv,
            self.self_right_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let left = input_left * node.value0
          let right = input_right * node.value0
          left_sv[node_index] = left
          right_sv[node_index] = right
          self.left_buffers[node_index].set(sample_index, left)
          self.right_buffers[node_index].set(sample_index, right)
        }
        StereoClip => {
          let input_left = self_register_stereo_input_left(
            left_sv,
            self.self_left_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input_right = self_register_stereo_input_right(
            right_sv,
            self.self_right_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let left = clip_feedback_sample(input_left, node.value0)
          let right = clip_feedback_sample(input_right, node.value0)
          left_sv[node_index] = left
          right_sv[node_index] = right
          self.left_buffers[node_index].set(sample_index, left)
          self.right_buffers[node_index].set(sample_index, right)
        }
        StereoBiquad => {
          let input_left = self_register_stereo_input_left(
            left_sv,
            self.self_left_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input_right = self_register_stereo_input_right(
            right_sv,
            self.self_right_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let left = self.stereo_biquad_left_states[node_index]
            .unwrap()
            .tick(input_left)
          let right = self.stereo_biquad_right_states[node_index]
            .unwrap()
            .tick(input_right)
          left_sv[node_index] = left
          right_sv[node_index] = right
          self.left_buffers[node_index].set(sample_index, left)
          self.right_buffers[node_index].set(sample_index, right)
        }
        StereoDelay => {
          let input_left = self_register_stereo_input_left(
            left_sv,
            self.self_left_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input_right = self_register_stereo_input_right(
            right_sv,
            self.self_right_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let left = self.stereo_delay_left_states[node_index]
            .unwrap()
            .tick(input_left)
          let right = self.stereo_delay_right_states[node_index]
            .unwrap()
            .tick(input_right)
          left_sv[node_index] = left
          right_sv[node_index] = right
          self.left_buffers[node_index].set(sample_index, left)
          self.right_buffers[node_index].set(sample_index, right)
        }
        StereoMixDown => {
          let input_left = self_register_stereo_input_left(
            left_sv,
            self.self_left_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input_right = self_register_stereo_input_right(
            right_sv,
            self.self_right_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let value = (input_left + input_right) * 0.5
          sample_values[node_index] = value
          self.buffers[node_index].set(sample_index, value)
        }
        StereoOutput => {
          // Stereo terminal: reads stereo input into left/right buffers.
          // In mono graphs this arm never matches (no StereoOutput node present).
          let input_left = self_register_stereo_input_left(
            left_sv,
            self.self_left_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          let input_right = self_register_stereo_input_right(
            right_sv,
            self.self_right_values,
            node.input0,
            self.back_edge_input0_source[node_index],
          )
          left_sv[node_index] = input_left
          right_sv[node_index] = input_right
          self.left_buffers[node_index].set(sample_index, input_left)
          self.right_buffers[node_index].set(sample_index, input_right)
        }
      }
      // Update self-register for feedback sources
      if self.self_enabled[node_index] {
        self.self_values[node_index] = sample_values[node_index]
        self.self_left_values[node_index] = left_sv[node_index]
        self.self_right_values[node_index] = right_sv[node_index]
      }
    }
  }

  // Final output copy: mono copies one buffer, stereo copies two
  if is_stereo {
    copy_stereo_buffers(
      self.left_buffers[self.left_buffers.length() - 1],
      self.right_buffers[self.right_buffers.length() - 1],
      left_output,
      right_output,
      sample_count,
    )
  } else {
    copy_buffer(self.buffers[self.buffers.length() - 1], output, sample_count)
  }
}

///|
fn CompiledDsp::process_feedback_graph(
  self : CompiledDsp,
  context : DspContext,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  // Mono wrapper: left_output/right_output are unused — pass output as a
  // harmless placeholder (is_stereo=false means only the mono copy fires).
  self.0.process_feedback_graph_impl(
    context, output, output, output, false, sample_count,
  )
}

///|
/// Compile a declarative terminal-stereo graph into an executable stereo graph.
///
/// This stereo slice keeps the existing `DspNode` language but requires a
/// single reachable `StereoOutput` node and an overall terminal stereo shape.
pub fn CompiledStereoDsp::compile(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledStereoDsp? {
  let original_count = nodes.length()
  let (nodes, opt_map) = optimize_graph(nodes)
  CompiledStereoDsp::compile_internal(nodes, context, original_count, opt_map)
}

///|
fn CompiledStereoDsp::compile_raw(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledStereoDsp? {
  let count = nodes.length()
  let identity_map = FixedArray::makei(count, fn(i) { i })
  CompiledStereoDsp::compile_internal(nodes, context, count, identity_map)
}

///|
fn CompiledStereoDsp::compile_internal(
  nodes : Array[DspNode],
  context : DspContext,
  original_count : Int,
  opt_map : FixedArray[Int],
) -> CompiledStereoDsp? {
  compile_graph_impl(
    nodes,
    context,
    original_count,
    opt_map,
    stereo_compile_plan,
    fn(fixed_nodes, feedback_edges) {
      if feedback_edges.length() == 0 {
        valid_terminal_stereo_shapes(fixed_nodes)
      } else {
        valid_feedback_terminal_stereo_graph(fixed_nodes, feedback_edges)
      }
    },
  ).map(fn(graph) { CompiledStereoDsp(graph) })
}

///|
/// Run the compiled stereo graph for one buffer and write the final output into
/// explicit left and right buffers.
pub fn CompiledStereoDsp::process(
  self : CompiledStereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = compiled_stereo_sample_count(
    context, left_output, right_output,
  )
  if !is_finite_positive(sample_rate) {
    clear_compiled_buffers(self.0.buffers)
    clear_compiled_buffers(self.0.left_buffers)
    clear_compiled_buffers(self.0.right_buffers)
    reset_graph_env_states(self.0.env_states)
    left_output.fill(0.0)
    right_output.fill(0.0)
    self.0.last_sanitized_count = 0
    return
  }
  if sample_count <= 0 || sample_count > self.compiled_buffer_capacity() {
    clear_compiled_buffers(self.0.buffers)
    clear_compiled_buffers(self.0.left_buffers)
    clear_compiled_buffers(self.0.right_buffers)
    left_output.fill(0.0)
    right_output.fill(0.0)
    self.0.last_sanitized_count = 0
    return
  }
  if self.0.feedback_edges.length() > 0 {
    self.process_feedback_graph(
      context, left_output, right_output, sample_count,
    )
    self.0.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
      sanitize_buffer(right_output, sample_count)
    return
  }

  let pan = Pan::new()
  for index = 0; index < self.0.nodes.length(); index = index + 1 {
    let node = self.0.nodes[index]
    let buffer = self.0.buffers[index]
    match node.kind {
      Constant => fill_constant_buffer(buffer, sample_count, node.value0)
      Oscillator =>
        if node.input0 >= 0 {
          let osc = self.0.osc_states[index].unwrap()
          let freq_buf = self.0.buffers[node.input0]
          let sr = context.sample_rate()
          for i = 0; i < sample_count; i = i + 1 {
            buffer.set(i, osc.tick_waveform(node.waveform, freq_buf.get(i), sr))
          }
        } else {
          self.0.osc_states[index]
          .unwrap()
          .process_waveform(context, buffer, node.waveform, node.value0)
        }
      Noise => self.0.noise_states[index].unwrap().process(context, buffer)
      Adsr => self.0.env_states[index].unwrap().process(context, buffer)
      Biquad => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        process_graph_biquad(
          self.0.biquad_states[index].unwrap(),
          context,
          buffer,
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      Delay => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        self.0.delay_states[index].unwrap().process(context, buffer)
      }
      Gain => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        apply_gain_buffer(buffer, sample_count, node.value0)
      }
      Mul =>
        multiply_buffers(
          self.0.buffers[node.input0],
          self.0.buffers[node.input1],
          buffer,
          sample_count,
        )
      Mix =>
        mix_buffers(
          self.0.buffers[node.input0],
          self.0.buffers[node.input1],
          buffer,
          sample_count,
        )
      Clip => {
        copy_buffer(self.0.buffers[node.input0], buffer, sample_count)
        clip_buffer(buffer, sample_count, node.value0)
      }
      Pan =>
        pan.process(
          context,
          self.0.buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          node.value0,
        )
      StereoGain => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        apply_gain_buffer(self.0.left_buffers[index], sample_count, node.value0)
        apply_gain_buffer(
          self.0.right_buffers[index],
          sample_count,
          node.value0,
        )
      }
      StereoClip => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        clip_buffer(self.0.left_buffers[index], sample_count, node.value0)
        clip_buffer(self.0.right_buffers[index], sample_count, node.value0)
      }
      StereoBiquad => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        process_graph_biquad(
          self.0.stereo_biquad_left_states[index].unwrap(),
          context,
          self.0.left_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
        process_graph_biquad(
          self.0.stereo_biquad_right_states[index].unwrap(),
          context,
          self.0.right_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      StereoDelay => {
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
        self.0.stereo_delay_left_states[index]
        .unwrap()
        .process(context, self.0.left_buffers[index])
        self.0.stereo_delay_right_states[index]
        .unwrap()
        .process(context, self.0.right_buffers[index])
      }
      StereoMixDown =>
        mixdown_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          buffer,
          sample_count,
        )
      StereoOutput =>
        copy_stereo_buffers(
          self.0.left_buffers[node.input0],
          self.0.right_buffers[node.input0],
          self.0.left_buffers[index],
          self.0.right_buffers[index],
          sample_count,
        )
      Output => ()
    }
  }

  copy_stereo_buffers(
    self.0.left_buffers[self.0.left_buffers.length() - 1],
    self.0.right_buffers[self.0.right_buffers.length() - 1],
    left_output,
    right_output,
    sample_count,
  )
  self.0.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
    sanitize_buffer(right_output, sample_count)
}

///|
fn CompiledStereoDsp::process_feedback_graph(
  self : CompiledStereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  // Stereo wrapper: output is unused — pass left_output as a harmless
  // placeholder (is_stereo=true means only the stereo copy fires).
  self.0.process_feedback_graph_impl(
    context, left_output, left_output, right_output, true, sample_count,
  )
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
  self.0.apply_control_impl(control)
}

///|
/// Apply a batch of runtime control messages to a compiled graph.
///
/// Controls are validated as a transaction first and then applied in order.
/// If any control in the batch is invalid, nothing is applied and the function
/// returns `false`.
pub fn CompiledDsp::apply_controls(
  self : CompiledDsp,
  controls : Array[GraphControl],
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
/// Apply a runtime control message to a compiled stereo graph.
pub fn CompiledStereoDsp::apply_control(
  self : CompiledStereoDsp,
  control : GraphControl,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
/// Apply a batch of runtime control messages to a compiled stereo graph.
pub fn CompiledStereoDsp::apply_controls(
  self : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Bool {
  self.0.apply_controls_impl(controls)
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
/// Returns true when a voice using this compiled graph can be safely reclaimed.
///
/// Two-stage check:
/// 1. All ADSR nodes must be in Idle stage (envelope has finished)
/// 2. The last output buffer must be silent (all samples below threshold)
///
/// WHY two stages: ADSR-only detection would cut voices with downstream delay
/// or feedback tails that are still audible. Energy-only detection would keep
/// voices alive during sustain (where output is non-zero but expected).
pub fn CompiledDsp::is_voice_finished(self : CompiledDsp) -> Bool {
  let nodes = self.0.nodes
  let env_states = self.0.env_states
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].kind is Adsr {
      match env_states[i] {
        Some(adsr) => if !(adsr.stage() is EnvStage::Idle) { return false }
        None => ()
      }
    }
  }
  let last_index = nodes.length() - 1
  if last_index < 0 {
    return true
  }
  let output_buf = self.0.buffers[last_index]
  for i = 0; i < output_buf.length(); i = i + 1 {
    if output_buf.get(i).abs() > 0.0001 {
      return false
    }
  }
  true
}

///|
/// Trigger `gate_on()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_on(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Bool {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_off(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Bool {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled stereo node using its original
/// authoring index.
pub fn CompiledStereoDsp::set_param(
  self : CompiledStereoDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
fn CompiledGraph::apply_control_impl(
  self : CompiledGraph,
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
fn CompiledGraph::apply_controls_impl(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Bool {
  let simulated_nodes = FixedArray::makei(self.nodes.length(), index => {
    self.nodes[index]
  })
  for index = 0; index < controls.length(); index = index + 1 {
    if !valid_graph_control(self, simulated_nodes, controls[index]) {
      return false
    }
  }

  for index = 0; index < controls.length(); index = index + 1 {
    if !self.apply_control_impl(controls[index]) {
      return false
    }
  }
  true
}

///|
fn apply_graph_gate_control(
  graph : CompiledGraph,
  node_index : Int,
  gate_on : Bool,
) -> Bool {
  match graph.compiled_index_for(node_index) {
    Some(compiled_index) =>
      match graph.env_states[compiled_index] {
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
  graph : CompiledGraph,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  let compiled_index = match graph.compiled_index_for(node_index) {
    Some(compiled_index) => compiled_index
    None => return false
  }
  let node = graph.nodes[compiled_index]
  let updated = match
    updated_node_param(node, slot, value, graph.compile_sample_rate) {
    Some(updated) => updated
    None => return false
  }
  graph.nodes[compiled_index] = updated
  apply_runtime_param_side_effect(graph, compiled_index, updated, slot)
}

///|
fn valid_graph_control(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  control : GraphControl,
) -> Bool {
  match control.kind {
    GateOn => valid_graph_gate_control(graph, control.node_index)
    GateOff => valid_graph_gate_control(graph, control.node_index)
    SetParam =>
      valid_graph_param_control(
        graph,
        simulated_nodes,
        control.node_index,
        control.slot,
        control.value,
      )
  }
}

///|
fn valid_graph_gate_control(graph : CompiledGraph, node_index : Int) -> Bool {
  match graph.compiled_index_for(node_index) {
    Some(compiled_index) => graph.env_states[compiled_index] is Some(_)
    None => false
  }
}

///|
fn valid_graph_param_control(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  let compiled_index = match graph.compiled_index_for(node_index) {
    Some(compiled_index) => compiled_index
    None => return false
  }
  let updated = match
    updated_node_param(
      simulated_nodes[compiled_index],
      slot,
      value,
      graph.compile_sample_rate,
    ) {
    Some(updated) => updated
    None => return false
  }
  simulated_nodes[compiled_index] = updated
  true
}

///|
fn stereo_compile_plan(
  nodes : Array[DspNode],
  context : DspContext,
) -> (Array[Int], Array[(Int, Int, Int)])? {
  let sample_rate = context.sample_rate()
  if !is_finite_positive(sample_rate) {
    return None
  }
  let output_index = match
    find_single_output_index_of_kind(nodes, DspNodeKind::StereoOutput) {
    Some(output_index) => output_index
    None => return None
  }
  if nodes.is_empty() {
    return None
  }

  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    if !valid_stereo_node_inputs(node, nodes.length(), sample_rate) {
      return None
    }
  }

  let marks = FixedArray::make(nodes.length(), 0)
  let order = Array::new()
  let feedback_edges = Array::new()
  visit_graph_node_with_feedback(
    output_index, nodes, marks, order, feedback_edges,
  )
  if order.length() != nodes.length() {
    return None
  }

  Some((order, feedback_edges))
}

///|
fn valid_any_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
  output_kind : DspNodeKind,
) -> Bool {
  match node.kind {
    Constant => is_finite(node.value0)
    Oscillator =>
      if node.input0 >= 0 {
        valid_reference(node.input0, node_count)
      } else {
        is_finite(node.value0)
      }
    Noise => true
    Adsr =>
      is_finite(node.value0) &&
      is_finite(node.value1) &&
      is_finite(node.value2) &&
      is_finite(node.value3)
    Biquad =>
      valid_reference(node.input0, node_count) &&
      valid_biquad_graph_params(sample_rate, node.value0, node.value1)
    Delay =>
      valid_reference(node.input0, node_count) &&
      valid_delay_feedback(node.value0) &&
      valid_delay_samples(node.delay_samples, node.delay_max_samples)
    Gain => valid_reference(node.input0, node_count) && is_finite(node.value0)
    Mul =>
      valid_reference(node.input0, node_count) &&
      valid_reference(node.input1, node_count)
    Mix =>
      valid_reference(node.input0, node_count) &&
      valid_reference(node.input1, node_count)
    Clip =>
      valid_reference(node.input0, node_count) &&
      is_finite(node.value0) &&
      node.value0 > 0.0
    Output =>
      node.kind == output_kind && valid_reference(node.input0, node_count)
    Pan => valid_reference(node.input0, node_count) && is_finite(node.value0)
    StereoGain =>
      valid_reference(node.input0, node_count) && is_finite(node.value0)
    StereoClip =>
      valid_reference(node.input0, node_count) &&
      is_finite(node.value0) &&
      node.value0 > 0.0
    StereoBiquad =>
      valid_reference(node.input0, node_count) &&
      valid_biquad_graph_params(sample_rate, node.value0, node.value1)
    StereoDelay =>
      valid_reference(node.input0, node_count) &&
      valid_delay_feedback(node.value0) &&
      valid_delay_samples(node.delay_samples, node.delay_max_samples)
    StereoMixDown => valid_reference(node.input0, node_count)
    StereoOutput =>
      node.kind == output_kind && valid_reference(node.input0, node_count)
  }
}

///|
fn valid_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
) -> Bool {
  valid_any_node_inputs(node, node_count, sample_rate, Output)
}

///|
fn valid_stereo_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
) -> Bool {
  valid_any_node_inputs(node, node_count, sample_rate, StereoOutput)
}

///|
fn valid_reference(input : Int, node_count : Int) -> Bool {
  input >= 0 && input < node_count
}

///|
fn CompiledGraph::compiled_buffer_capacity(self : CompiledGraph) -> Int {
  if self.buffers.length() == 0 {
    0
  } else {
    self.buffers[0].length()
  }
}

///|
fn CompiledGraph::compiled_index_for(
  self : CompiledGraph,
  node_index : Int,
) -> Int? {
  if node_index < 0 || node_index >= self.index_map.length() {
    None
  } else {
    let compiled = self.index_map[node_index]
    if compiled < 0 {
      None
    } else {
      Some(compiled)
    }
  }
}

///|
fn CompiledDsp::compiled_buffer_capacity(self : CompiledDsp) -> Int {
  self.0.compiled_buffer_capacity()
}

///|
fn CompiledStereoDsp::compiled_buffer_capacity(self : CompiledStereoDsp) -> Int {
  self.0.compiled_buffer_capacity()
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
        Value0 if is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    Oscillator =>
      // FM oscillators (input0 >= 0) read frequency from input buffer;
      // reject Value0 updates for them since the value is unused.
      if node.input0 >= 0 {
        None
      } else {
        match slot {
          Value0 if is_finite(value) => Some(node_with_value0(node, value))
          _ => None
        }
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
        Value0 if valid_delay_feedback(value) =>
          Some(node_with_value0(node, value))
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples) =>
              Some(node_with_delay_samples(node, ds))
            _ => None
          }
        _ => None
      }
    Gain =>
      match slot {
        Value0 if is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    Mul => None
    Mix => None
    Clip =>
      match slot {
        Value0 if is_finite(value) && value > 0.0 =>
          Some(node_with_value0(node, value))
        _ => None
      }
    Output => None
    Pan =>
      match slot {
        Value0 if is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    StereoGain =>
      match slot {
        Value0 if is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    StereoClip =>
      match slot {
        Value0 if is_finite(value) && value > 0.0 =>
          Some(node_with_value0(node, value))
        _ => None
      }
    StereoBiquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1) =>
          Some(node_with_value0(node, value))
        Value1 if valid_biquad_graph_params(sample_rate, node.value0, value) =>
          Some(node_with_value1(node, value))
        _ => None
      }
    StereoDelay =>
      match slot {
        Value0 if valid_delay_feedback(value) =>
          Some(node_with_value0(node, value))
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples) =>
              Some(node_with_delay_samples(node, ds))
            _ => None
          }
        _ => None
      }
    StereoMixDown => None
    StereoOutput => None
  }
}

///|
fn apply_runtime_param_side_effect(
  graph : CompiledGraph,
  compiled_index : Int,
  node : DspNode,
  slot : GraphParamSlot,
) -> Bool {
  match node.kind {
    Delay =>
      match slot {
        Value0 =>
          match graph.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_feedback(node.value0)
              delay.set_delay_samples(node.delay_samples)
              true
            }
            None => false
          }
        DelaySamples =>
          match graph.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_feedback(node.value0)
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
    Pan => true
    StereoGain => true
    StereoClip => true
    StereoBiquad => true
    StereoDelay =>
      match slot {
        Value0 =>
          apply_stereo_delay_param_side_effect(
            graph.stereo_delay_left_states,
            graph.stereo_delay_right_states,
            compiled_index,
            node.delay_samples,
            node.value0,
          )
        DelaySamples =>
          apply_stereo_delay_param_side_effect(
            graph.stereo_delay_left_states,
            graph.stereo_delay_right_states,
            compiled_index,
            node.delay_samples,
            node.value0,
          )
        _ => false
      }
    StereoMixDown => false
    _ => false
  }
}

///|
fn exact_int_value(value : Double) -> Int? {
  if !is_finite(value) || value.trunc() != value {
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
  is_finite(sample_rate) &&
  sample_rate > 0.0 &&
  is_finite(cutoff) &&
  cutoff > 0.0 &&
  cutoff < nyquist &&
  is_finite(q) &&
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
fn valid_delay_feedback(value : Double) -> Bool {
  is_finite(value) &&
  value >= -max_feedback_amount() &&
  value <= max_feedback_amount()
}

///|
/// Shared validation for delay_samples used by both compile-time
/// (`valid_any_node_inputs`) and runtime (`updated_node_param`) paths.
fn valid_delay_samples(delay_samples : Int, delay_max_samples : Int) -> Bool {
  delay_samples >= 0 && delay_samples <= delay_max_samples
}

///|
/// Structural check: does this node kind accept SetParam on the given slot?
/// Used by ControlBindingBuilder::build() to validate bindings at graph
/// construction time. Does not check value-domain constraints.
pub fn node_accepts_slot(node : DspNode, slot : GraphParamSlot) -> Bool {
  match node.kind {
    Constant => slot is Value0
    Oscillator => node.input0 < 0 && slot is Value0
    Noise => false
    Adsr => false
    Biquad => slot is Value0 || slot is Value1
    Delay => slot is Value0 || slot is DelaySamples
    Gain => slot is Value0
    Mul => false
    Mix => false
    Clip => slot is Value0
    Output => false
    Pan => slot is Value0
    StereoGain => slot is Value0
    StereoClip => slot is Value0
    StereoBiquad => slot is Value0 || slot is Value1
    StereoDelay => slot is Value0 || slot is DelaySamples
    StereoMixDown => false
    StereoOutput => false
  }
}

///|
fn mono_compile_plan(
  nodes : Array[DspNode],
  context : DspContext,
) -> (Array[Int], Array[(Int, Int, Int)])? {
  let sample_rate = context.sample_rate()
  if !is_finite_positive(sample_rate) {
    return None
  }
  let output_index = match find_single_output_index(nodes) {
    Some(output_index) => output_index
    None => return None
  }
  for index = 0; index < nodes.length(); index = index + 1 {
    if !valid_node_inputs(nodes[index], nodes.length(), sample_rate) {
      return None
    }
  }

  let marks = FixedArray::make(nodes.length(), 0)
  let order = Array::new()
  let feedback_edges = Array::new()
  visit_graph_node_with_feedback(
    output_index, nodes, marks, order, feedback_edges,
  )
  if order.length() != nodes.length() {
    return None
  }

  Some((order, feedback_edges))
}

///|
fn visit_graph_node_with_feedback(
  index : Int,
  nodes : Array[DspNode],
  marks : FixedArray[Int],
  order : Array[Int],
  feedback_edges : Array[(Int, Int, Int)],
) -> Unit {
  if marks[index] != 0 {
    return
  }
  marks[index] = 1
  visit_graph_dependencies_with_feedback(
    index, nodes, marks, order, feedback_edges,
  )
  marks[index] = 2
  order.push(index)
}

///|
fn visit_graph_dependencies_with_feedback(
  index : Int,
  nodes : Array[DspNode],
  marks : FixedArray[Int],
  order : Array[Int],
  feedback_edges : Array[(Int, Int, Int)],
) -> Unit {
  let node = nodes[index]
  match node.kind {
    Constant => ()
    Oscillator =>
      if node.input0 >= 0 {
        visit_graph_input_with_feedback(
          node.input0,
          index,
          0,
          nodes,
          marks,
          order,
          feedback_edges,
        )
      }
    Noise => ()
    Adsr => ()
    Biquad =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Delay =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Gain =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Mul => {
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
      visit_graph_input_with_feedback(
        node.input1,
        index,
        1,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    }
    Mix => {
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
      visit_graph_input_with_feedback(
        node.input1,
        index,
        1,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    }
    Clip =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Output =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Pan =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoGain =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoClip =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoBiquad =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoDelay =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoMixDown =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoOutput =>
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
  }
}

///|
fn visit_graph_input_with_feedback(
  input : Int,
  target_index : Int,
  target_slot : Int,
  nodes : Array[DspNode],
  marks : FixedArray[Int],
  order : Array[Int],
  feedback_edges : Array[(Int, Int, Int)],
) -> Unit {
  match marks[input] {
    0 =>
      visit_graph_node_with_feedback(input, nodes, marks, order, feedback_edges)
    1 => feedback_edges.push((input, target_index, target_slot))
    _ => ()
  }
}

///|
fn find_single_output_index(nodes : Array[DspNode]) -> Int? {
  find_single_output_index_of_kind(nodes, DspNodeKind::Output)
}

///|
fn find_single_output_index_of_kind(
  nodes : Array[DspNode],
  kind : DspNodeKind,
) -> Int? {
  let mut output_index = -1
  for index = 0; index < nodes.length(); index = index + 1 {
    if nodes[index].kind == kind {
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
fn remapped_feedback_edges(
  edges : Array[(Int, Int, Int)],
  remap : FixedArray[Int],
) -> FixedArray[(Int, Int, Int)] {
  FixedArray::makei(edges.length(), index => {
    let edge = edges[index]
    (remap[edge.0], remap[edge.1], edge.2)
  })
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
fn compiled_stereo_sample_count(
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Int {
  let output_length = if left_output.length() < right_output.length() {
    left_output.length()
  } else {
    right_output.length()
  }
  if output_length < context.block_size() {
    output_length
  } else {
    context.block_size()
  }
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
fn copy_stereo_buffers(
  source_left : AudioBuffer,
  source_right : AudioBuffer,
  target_left : AudioBuffer,
  target_right : AudioBuffer,
  sample_count : Int,
) -> Unit {
  copy_buffer(source_left, target_left, sample_count)
  copy_buffer(source_right, target_right, sample_count)
}

///|
fn mixdown_stereo_buffers(
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
    output.set(index, (left.get(index) + right.get(index)) * 0.5)
  }
  for index = bounded; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
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
fn make_graph_stereo_biquad_state(node : DspNode) -> Biquad? {
  match node.kind {
    StereoBiquad => Some(Biquad::new())
    _ => None
  }
}

///|
fn make_graph_stereo_delay_state(node : DspNode) -> DelayLine? {
  match node.kind {
    StereoDelay =>
      Some(
        DelayLine::new(
          node.delay_max_samples,
          delay_samples=node.delay_samples,
          feedback=node.value0,
        ),
      )
    _ => None
  }
}

///|
fn apply_stereo_delay_param_side_effect(
  left_states : FixedArray[DelayLine?],
  right_states : FixedArray[DelayLine?],
  compiled_index : Int,
  delay_samples : Int,
  feedback : Double,
) -> Bool {
  match left_states[compiled_index] {
    Some(left_delay) =>
      match right_states[compiled_index] {
        Some(right_delay) => {
          left_delay.set_feedback(feedback)
          left_delay.set_delay_samples(delay_samples)
          right_delay.set_feedback(feedback)
          right_delay.set_delay_samples(delay_samples)
          true
        }
        None => false
      }
    None => false
  }
}

///|
fn make_graph_delay_state(node : DspNode) -> DelayLine? {
  match node.kind {
    Delay =>
      Some(
        DelayLine::new(
          node.delay_max_samples,
          delay_samples=node.delay_samples,
          feedback=node.value0,
        ),
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
/// Re-derive biquad coefficients for all filter nodes before feedback processing.
/// Called once per block — coefficients depend on sample rate and cutoff/Q which
/// may have changed via runtime parameter control.
fn CompiledGraph::prepare_feedback_biquads(
  self : CompiledGraph,
  context : DspContext,
) -> Unit {
  for index = 0; index < self.nodes.length(); index = index + 1 {
    let node = self.nodes[index]
    match node.kind {
      Biquad =>
        ignore(
          self.biquad_states[index]
          .unwrap()
          .update(context, node.filter_mode, node.value0, node.value1),
        )
      StereoBiquad => {
        ignore(
          self.stereo_biquad_left_states[index]
          .unwrap()
          .update(context, node.filter_mode, node.value0, node.value1),
        )
        ignore(
          self.stereo_biquad_right_states[index]
          .unwrap()
          .update(context, node.filter_mode, node.value0, node.value1),
        )
      }
      _ => ()
    }
  }
}

///|
fn self_register_input_sample(
  sample_values : FixedArray[Double],
  self_values : FixedArray[Double],
  input_index : Int,
  back_edge_source : Int,
) -> Double {
  if back_edge_source >= 0 {
    self_values[back_edge_source]
  } else if input_index >= 0 {
    sample_values[input_index]
  } else {
    0.0
  }
}

///|
fn self_register_stereo_input_left(
  left_sv : FixedArray[Double],
  self_left_values : FixedArray[Double],
  input_index : Int,
  back_edge_source : Int,
) -> Double {
  if back_edge_source >= 0 {
    self_left_values[back_edge_source]
  } else if input_index >= 0 {
    left_sv[input_index]
  } else {
    0.0
  }
}

///|
fn self_register_stereo_input_right(
  right_sv : FixedArray[Double],
  self_right_values : FixedArray[Double],
  input_index : Int,
  back_edge_source : Int,
) -> Double {
  if back_edge_source >= 0 {
    self_right_values[back_edge_source]
  } else if input_index >= 0 {
    right_sv[input_index]
  } else {
    0.0
  }
}

///|
fn feedback_pan_left_gain(position : Double) -> Double {
  if !is_finite(position) {
    0.0
  } else {
    let clamped = position.clamp(min=-1.0, max=1.0)
    if clamped <= -1.0 {
      1.0
    } else if clamped >= 1.0 {
      0.0
    } else {
      let angle = (clamped + 1.0) * @math.PI * 0.25
      @math.cos(angle)
    }
  }
}

///|
fn feedback_pan_right_gain(position : Double) -> Double {
  if !is_finite(position) {
    0.0
  } else {
    let clamped = position.clamp(min=-1.0, max=1.0)
    if clamped <= -1.0 {
      0.0
    } else if clamped >= 1.0 {
      1.0
    } else {
      let angle = (clamped + 1.0) * @math.PI * 0.25
      @math.sin(angle)
    }
  }
}

///|
fn clip_feedback_sample(value : Double, threshold : Double) -> Double {
  if value > threshold {
    threshold
  } else if value < -threshold {
    -threshold
  } else {
    value
  }
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

///|
fn is_mono_shape(shape : Int?) -> Bool {
  match shape {
    Some(MONO_SIGNAL_SHAPE) => true
    _ => false
  }
}

///|
fn valid_feedback_terminal_mono_graph(
  nodes : FixedArray[DspNode],
  feedback_edges : FixedArray[(Int, Int, Int)],
) -> Bool {
  // Build per-slot back-edge source maps for shape resolution.
  let be_input0_src = FixedArray::make(nodes.length(), -1)
  let be_input1_src = FixedArray::make(nodes.length(), -1)
  for i = 0; i < feedback_edges.length(); i = i + 1 {
    let edge = feedback_edges[i]
    if edge.2 == 0 {
      be_input0_src[edge.1] = edge.0
    } else {
      be_input1_src[edge.1] = edge.0
    }
  }
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          match
            feedback_resolved_input_shape(
              node.input0,
              be_input0_src[index],
              shapes,
              nodes,
            ) {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return false
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Delay =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Gain =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Mul => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      }
      Mix => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      }
      Clip =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Output =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Pan =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoGain =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoClip =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoBiquad =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoDelay =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoMixDown =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      StereoOutput => return false
    }
    shapes[index] = shape
  }
  // Verify no feedback edges go through Output nodes
  for index = 0; index < feedback_edges.length(); index = index + 1 {
    let edge = feedback_edges[index]
    if nodes[edge.0].kind is Output || nodes[edge.1].kind is Output {
      return false
    }
    // Verify shape compatibility
    match feedback_target_shape(nodes[edge.1], edge.2) {
      Some(expected_shape) =>
        if shapes[edge.0] != expected_shape {
          return false
        }
      None => return false
    }
  }
  let last = nodes.length() - 1
  nodes[last].kind is DspNodeKind::Output && shapes[last] == MONO_SIGNAL_SHAPE
}

///|
fn valid_terminal_mono_shapes(nodes : FixedArray[DspNode]) -> Bool {
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          match input_shape(node.input0, shapes) {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return false
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Delay =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Gain =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Mul =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      Mix =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      Clip =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Output =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Pan =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoGain =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoClip =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoBiquad =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoDelay =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoMixDown =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      StereoOutput => return false
    }
    shapes[index] = shape
  }

  let last = nodes.length() - 1
  nodes[last].kind is DspNodeKind::Output && shapes[last] == MONO_SIGNAL_SHAPE
}

///|
fn valid_terminal_stereo_shapes(nodes : FixedArray[DspNode]) -> Bool {
  compiled_stereo_shapes(nodes) is Some(_)
}

///|
fn compiled_stereo_shapes(nodes : FixedArray[DspNode]) -> FixedArray[Int]? {
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          match input_shape(node.input0, shapes) {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return None
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Delay =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Gain =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Mul =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      Mix =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      Clip =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Output => return None
      Pan =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoGain =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoClip =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoBiquad =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoDelay =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoMixDown => return None
      StereoOutput =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
    }
    shapes[index] = shape
  }

  let last = nodes.length() - 1
  if nodes[last].kind is DspNodeKind::StereoOutput &&
    shapes[last] == STEREO_SIGNAL_SHAPE {
    Some(shapes)
  } else {
    None
  }
}

///|
/// Infer signal shapes for a stereo feedback graph. Back-edge inputs are
/// resolved from the source node's intrinsic output shape rather than from
/// forward propagation, which lets the analysis succeed for cycles that cross
/// the mono/stereo boundary (e.g. Pan -> StereoGain -> StereoMixDown -> Mix).
fn compiled_feedback_stereo_shapes(
  nodes : FixedArray[DspNode],
  feedback_edges : FixedArray[(Int, Int, Int)],
) -> FixedArray[Int]? {
  // Build per-slot back-edge source maps so we can skip them during forward
  // shape propagation.
  let be_input0_src = FixedArray::make(nodes.length(), -1)
  let be_input1_src = FixedArray::make(nodes.length(), -1)
  for i = 0; i < feedback_edges.length(); i = i + 1 {
    let edge = feedback_edges[i]
    if edge.2 == 0 {
      be_input0_src[edge.1] = edge.0
    } else {
      be_input1_src[edge.1] = edge.0
    }
  }
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          let s = feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          )
          match s {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return None
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Delay => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Gain => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Mul => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      }
      Mix => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      }
      Clip => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Output => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Pan => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoGain => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoClip => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoBiquad => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoDelay => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoMixDown => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoOutput => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
    }
    shapes[index] = shape
  }

  let last = nodes.length() - 1
  if nodes[last].kind is DspNodeKind::StereoOutput &&
    shapes[last] == STEREO_SIGNAL_SHAPE {
    Some(shapes)
  } else {
    None
  }
}

///|
/// Resolve the shape of an input, accounting for back-edges. If the input is a
/// back-edge, use the intrinsic output shape of the source node.
fn feedback_resolved_input_shape(
  input_index : Int,
  back_edge_source : Int,
  shapes : FixedArray[Int],
  nodes : FixedArray[DspNode],
) -> Int? {
  if back_edge_source >= 0 {
    Some(nodes[back_edge_source].signal_shape())
  } else {
    input_shape(input_index, shapes)
  }
}

///|
fn valid_feedback_terminal_stereo_graph(
  nodes : FixedArray[DspNode],
  feedback_edges : FixedArray[(Int, Int, Int)],
) -> Bool {
  let shapes = match compiled_feedback_stereo_shapes(nodes, feedback_edges) {
    Some(shapes) => shapes
    None => return false
  }
  for index = 0; index < feedback_edges.length(); index = index + 1 {
    let edge = feedback_edges[index]
    if nodes[edge.0].kind is Output ||
      nodes[edge.0].kind is StereoOutput ||
      nodes[edge.1].kind is Output ||
      nodes[edge.1].kind is StereoOutput {
      return false
    }
    // Verify shape compatibility: source shape must match what target slot expects
    match feedback_target_shape(nodes[edge.1], edge.2) {
      Some(expected_shape) =>
        if shapes[edge.0] != expected_shape {
          return false
        }
      None => return false
    }
  }
  true
}

///|
fn feedback_target_shape(node : DspNode, target_slot : Int) -> Int? {
  match node.kind {
    Biquad => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Delay => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Gain => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Mul =>
      if target_slot == 0 || target_slot == 1 {
        Some(MONO_SIGNAL_SHAPE)
      } else {
        None
      }
    Mix =>
      if target_slot == 0 || target_slot == 1 {
        Some(MONO_SIGNAL_SHAPE)
      } else {
        None
      }
    Clip => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Pan => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    StereoGain =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoClip =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoBiquad =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoDelay =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoMixDown =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    Output => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    StereoOutput =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    _ => None
  }
}

///|
fn input_shape(input : Int, shapes : FixedArray[Int]) -> Int? {
  if input < 0 || input >= shapes.length() {
    None
  } else {
    Some(shapes[input])
  }
}
