///|
/// Shared internal graph state for both mono and stereo compiled DSP graphs.
/// Both CompiledDsp and CompiledStereoDsp wrap this struct as newtypes.
///
/// All three buffer families (buffers, left_buffers, right_buffers) are allocated
/// for every node regardless of mono/stereo variant. Mono nodes write only to
/// `buffers`; stereo nodes write only to `left_buffers`/`right_buffers`. This
/// uniform layout enables hot-swap state copy without knowing the variant.
pub struct CompiledGraph {
  priv compile_sample_rate : Double
  priv nodes : FixedArray[@model.DspNode]
  priv default_nodes : FixedArray[@model.DspNode]
  priv index_map : FixedArray[Int]
  // Mono signal path buffers — one per node
  priv buffers : FixedArray[AudioBuffer]
  // Stereo signal path buffers — one pair per node (populated only for stereo-aware nodes)
  priv left_buffers : FixedArray[AudioBuffer]
  priv right_buffers : FixedArray[AudioBuffer]
  priv osc_states : FixedArray[Oscillator?]
  priv noise_states : FixedArray[Noise?]
  priv env_states : FixedArray[Adsr?]
  priv biquad_states : FixedArray[Biquad?]
  priv stereo_biquad_left_states : FixedArray[Biquad?]
  priv stereo_biquad_right_states : FixedArray[Biquad?]
  priv delay_states : FixedArray[DelayLine?]
  priv stereo_delay_left_states : FixedArray[DelayLine?]
  priv stereo_delay_right_states : FixedArray[DelayLine?]
  priv feedback_edges : FixedArray[(Int, Int, Int)]
  // Feedback graph per-sample self-registers — one value per node, updated each sample
  priv self_values : FixedArray[Double]
  priv self_left_values : FixedArray[Double]
  priv self_right_values : FixedArray[Double]
  priv self_enabled : FixedArray[Bool]
  priv back_edge_input0_source : FixedArray[Int]
  priv back_edge_input1_source : FixedArray[Int]
  // Pre-allocated scratch arrays for feedback processing (avoid hot-path alloc)
  priv sample_values : FixedArray[Double]
  priv left_sample_values : FixedArray[Double]
  priv right_sample_values : FixedArray[Double]
  // Pre-computed pan gains — trig is done once per block, not per sample
  priv pan_left_gains : FixedArray[Double]
  priv pan_right_gains : FixedArray[Double]
  priv mut last_sanitized_count : Int
  priv mut debug_validate : Bool
  priv mut last_validation_errors : Array[GraphValidationError]
}

///|
pub fn CompiledGraph::compile_sample_rate(self : CompiledGraph) -> Double {
  self.compile_sample_rate
}

///|
pub fn CompiledGraph::copy_compatible_runtime_state_from(
  self : CompiledGraph,
  old_graph : CompiledGraph,
) -> Unit {
  let old_map = old_graph.index_map
  let new_map = self.index_map
  let shared_count = if old_map.length() < new_map.length() {
    old_map.length()
  } else {
    new_map.length()
  }
  for authoring_idx = 0
      authoring_idx < shared_count
      authoring_idx = authoring_idx + 1 {
    let old_compiled = old_map[authoring_idx]
    let new_compiled = new_map[authoring_idx]
    if old_compiled >= 0 &&
      new_compiled >= 0 &&
      old_compiled < old_graph.nodes.length() &&
      new_compiled < self.nodes.length() &&
      old_graph.nodes[old_compiled].kind() == self.nodes[new_compiled].kind() {
      self.osc_states[new_compiled] = old_graph.osc_states[old_compiled]
      self.noise_states[new_compiled] = old_graph.noise_states[old_compiled]
      self.env_states[new_compiled] = old_graph.env_states[old_compiled]
      self.biquad_states[new_compiled] = old_graph.biquad_states[old_compiled]
      self.stereo_biquad_left_states[new_compiled] = old_graph.stereo_biquad_left_states[old_compiled]
      self.stereo_biquad_right_states[new_compiled] = old_graph.stereo_biquad_right_states[old_compiled]
      // Only copy delay state if buffer capacity matches
      match
        (old_graph.delay_states[old_compiled], self.delay_states[new_compiled]) {
        (Some(old_delay), Some(new_delay)) =>
          if old_delay.max_delay_samples() == new_delay.max_delay_samples() {
            self.delay_states[new_compiled] = old_graph.delay_states[old_compiled]
          }
        _ => ()
      }
      match
        (
          old_graph.stereo_delay_left_states[old_compiled],
          self.stereo_delay_left_states[new_compiled],
        ) {
        (Some(old_delay), Some(new_delay)) =>
          if old_delay.max_delay_samples() == new_delay.max_delay_samples() {
            self.stereo_delay_left_states[new_compiled] = old_graph.stereo_delay_left_states[old_compiled]
          }
        _ => ()
      }
      match
        (
          old_graph.stereo_delay_right_states[old_compiled],
          self.stereo_delay_right_states[new_compiled],
        ) {
        (Some(old_delay), Some(new_delay)) =>
          if old_delay.max_delay_samples() == new_delay.max_delay_samples() {
            self.stereo_delay_right_states[new_compiled] = old_graph.stereo_delay_right_states[old_compiled]
          }
        _ => ()
      }
      self.self_values[new_compiled] = old_graph.self_values[old_compiled]
      self.self_left_values[new_compiled] = old_graph.self_left_values[old_compiled]
      self.self_right_values[new_compiled] = old_graph.self_right_values[old_compiled]
    }
  }
}

///|
/// Executable buffer-based DSP graph compiled from `DspNode`s.
struct CompiledDsp(CompiledGraph)

///|
/// Executable terminal-stereo graph compiled from `DspNode`s.
struct CompiledStereoDsp(CompiledGraph)

///|
pub fn CompiledDsp::from_graph(graph : CompiledGraph) -> CompiledDsp {
  CompiledDsp(graph)
}

///|
pub fn CompiledDsp::raw_graph(self : CompiledDsp) -> CompiledGraph {
  self.0
}

///|
pub fn CompiledStereoDsp::from_graph(
  graph : CompiledGraph,
) -> CompiledStereoDsp {
  CompiledStereoDsp(graph)
}

///|
pub fn CompiledStereoDsp::raw_graph(self : CompiledStereoDsp) -> CompiledGraph {
  self.0
}

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
/// Accepts a `CompiledTemplate` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// (e.g., no reachable `Output`, invalid feedback cycle, missing node
/// inputs). Produce the input via `CompiledTemplate::analyze(nodes)` or
/// `GraphBuilder::analyze`.
pub fn CompiledDsp::compile(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> CompiledDsp? {
  CompiledDsp::compile_internal(
    compiled_template.optimized_nodes(),
    context,
    compiled_template.length(),
    compiled_template.index_map(),
  )
}

///|
/// Compile without optimization — used by topology controllers where authoring
/// indices must be preserved for runtime controls.
pub fn CompiledDsp::compile_raw(
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
  validate : (FixedArray[@model.DspNode], FixedArray[(Int, Int, Int)]) -> Bool,
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
    @model.remap_node_inputs(nodes[order[index]], topo_map)
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
    default_nodes: FixedArray::makei(node_count, index => {
      @model.clone_node(fixed_nodes[index])
    }),
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
/// Compile a declarative terminal-stereo graph into an executable
/// stereo graph.
///
/// Accepts a `CompiledTemplate` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// — including the stereo-specific requirement of a single reachable
/// `StereoOutput`.
pub fn CompiledStereoDsp::compile(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> CompiledStereoDsp? {
  CompiledStereoDsp::compile_internal(
    compiled_template.optimized_nodes(),
    context,
    compiled_template.length(),
    compiled_template.index_map(),
  )
}

///|
pub fn CompiledStereoDsp::compile_raw(
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
pub fn CompiledGraph::compiled_buffer_capacity(self : CompiledGraph) -> Int {
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
pub fn CompiledDsp::compiled_buffer_capacity(self : CompiledDsp) -> Int {
  self.0.compiled_buffer_capacity()
}

///|
pub fn CompiledStereoDsp::compiled_buffer_capacity(
  self : CompiledStereoDsp,
) -> Int {
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
  match node.kind() {
    Constant => ()
    Oscillator =>
      if node.input0() >= 0 {
        visit_graph_input_with_feedback(
          node.input0(),
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
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Delay =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Gain => {
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
      if node.input1() >= 0 {
        visit_graph_input_with_feedback(
          node.input1(),
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
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
      visit_graph_input_with_feedback(
        node.input1(),
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
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
      visit_graph_input_with_feedback(
        node.input1(),
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
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Output =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    Pan =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoGain =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoClip =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoBiquad =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoDelay =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoMixDown =>
      visit_graph_input_with_feedback(
        node.input0(),
        index,
        0,
        nodes,
        marks,
        order,
        feedback_edges,
      )
    StereoOutput =>
      visit_graph_input_with_feedback(
        node.input0(),
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
    if nodes[index].kind() == kind {
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
fn make_graph_osc_state(node : @model.DspNode) -> Oscillator? {
  match node.kind() {
    Oscillator => Some(Oscillator::new())
    _ => None
  }
}

///|
fn make_graph_noise_state(node : @model.DspNode) -> Noise? {
  match node.kind() {
    Noise => Some(Noise::new(node.seed()))
    _ => None
  }
}

///|
fn make_graph_env_state(node : @model.DspNode) -> Adsr? {
  match node.kind() {
    Adsr =>
      Some(
        Adsr::new(
          attack_ms=node.value0(),
          decay_ms=node.value1(),
          sustain=node.value2(),
          release_ms=node.value3(),
        ),
      )
    _ => None
  }
}

///|
fn make_graph_biquad_state(node : @model.DspNode) -> Biquad? {
  match node.kind() {
    Biquad => Some(Biquad::new())
    _ => None
  }
}

///|
fn make_graph_stereo_biquad_state(node : @model.DspNode) -> Biquad? {
  match node.kind() {
    StereoBiquad => Some(Biquad::new())
    _ => None
  }
}

///|
fn make_graph_stereo_delay_state(node : @model.DspNode) -> DelayLine? {
  match node.kind() {
    StereoDelay =>
      Some(
        DelayLine::new(
          node.delay_max_samples(),
          delay_samples=node.delay_samples(),
          feedback=node.value0(),
        ),
      )
    _ => None
  }
}

///|
