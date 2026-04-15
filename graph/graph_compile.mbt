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
  mut debug_validate : Bool
  mut last_validation_errors : Array[GraphValidationError]
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
/// True when the compiled graph contains feedback (back) edges that require
/// per-sample processing with self-registers.
pub fn CompiledDsp::has_feedback_edges(self : CompiledDsp) -> Bool {
  self.0.feedback_edges.length() > 0
}

///|
pub fn CompiledStereoDsp::has_feedback_edges(self : CompiledStereoDsp) -> Bool {
  self.0.feedback_edges.length() > 0
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
  for edge in feedback_edges {
    let source_idx = edge.0
    let target_idx = edge.1
    let slot = edge.2
    guard source_idx >= 0 &&
      source_idx < node_count &&
      target_idx >= 0 &&
      target_idx < node_count else {
      return None
    }
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
    debug_validate: false,
    last_validation_errors: [],
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
fn stereo_compile_plan(
  nodes : Array[DspNode],
  context : DspContext,
) -> (Array[Int], Array[(Int, Int, Int)])? {
  let sample_rate = context.sample_rate()
  if !@dsp.is_finite_positive(sample_rate) {
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
fn mono_compile_plan(
  nodes : Array[DspNode],
  context : DspContext,
) -> (Array[Int], Array[(Int, Int, Int)])? {
  let sample_rate = context.sample_rate()
  if !@dsp.is_finite_positive(sample_rate) {
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
    Gain => {
      visit_graph_input_with_feedback(
        node.input0,
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
      if node.input1 >= 0 {
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
    }
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
