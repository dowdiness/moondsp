///|
/// Shared internal graph state for both mono and stereo compiled DSP graphs.
/// Both Dsp and StereoDsp wrap this struct as newtypes.
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
  priv controls : ControlScratch
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
/// Executable buffer-based DSP graph compiled from `DspNode`s.
struct Dsp(CompiledGraph)

///|
/// Executable terminal-stereo graph compiled from `DspNode`s.
struct StereoDsp(CompiledGraph)

///|
pub fn Dsp::from_graph(graph : CompiledGraph) -> Dsp {
  Dsp(graph)
}

///|
pub fn Dsp::raw_graph(self : Dsp) -> CompiledGraph {
  self.0
}

///|
pub fn StereoDsp::from_graph(graph : CompiledGraph) -> StereoDsp {
  StereoDsp(graph)
}

///|
pub fn StereoDsp::raw_graph(self : StereoDsp) -> CompiledGraph {
  self.0
}

///|
/// Number of non-finite samples replaced with 0.0 during the most recent
/// process() call. Returns 0 if output was clean.
pub fn Dsp::last_sanitized_count(self : Dsp) -> Int {
  self.0.last_sanitized_count
}

///|
pub fn StereoDsp::last_sanitized_count(self : StereoDsp) -> Int {
  self.0.last_sanitized_count
}

///|
/// True when the compiled graph contains feedback (back) edges that require
/// per-sample processing with self-registers.
pub fn Dsp::has_feedback_edges(self : Dsp) -> Bool {
  !self.0.feedback_edges.is_empty()
}

///|
pub fn StereoDsp::has_feedback_edges(self : StereoDsp) -> Bool {
  !self.0.feedback_edges.is_empty()
}

///|
/// Compile a declarative mono graph into an executable buffer graph.
///
/// Accepts a `AnalyzedGraph` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// (e.g., no reachable `Output`, invalid feedback cycle, missing node
/// inputs). Produce the input via `AnalyzedGraph::analyze(nodes)` or
/// `GraphBuilder::analyze`.
pub fn Dsp::compile(
  compiled_template : AnalyzedGraph,
  context : DspContext,
) -> Dsp? {
  match Dsp::compile_result(compiled_template, context) {
    Ok(graph) => Some(graph)
    Err(_) => None
  }
}

///|
/// Compile without optimization — used by topology controllers where authoring
/// indices must be preserved for runtime controls.
pub fn Dsp::compile_raw(nodes : Array[DspNode], context : DspContext) -> Dsp? {
  match build_graph_program(nodes, context, DspNodeKind::Output) {
    Ok(program) => Some(DspProgram(program).instantiate())
    Err(_) => None
  }
}

///|
/// Allocate independent execution state from an already checked graph program.
fn GraphProgram::instantiate(self : GraphProgram) -> CompiledGraph {
  let node_count = self.nodes.length()
  let block_size = self.block_size
  let compile_sample_rate = self.sample_rate
  let fixed_nodes = FixedArray::makei(node_count, i => {
    @model.clone_node(self.nodes[i])
  })
  let index_map = self.index_map
  let feedback_edges = self.feedback_edges
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
  {
    compile_sample_rate,
    nodes: fixed_nodes,
    default_nodes: FixedArray::makei(node_count, index => {
      @model.clone_node(fixed_nodes[index])
    }),
    index_map,
    controls: make_control_scratch(
      fixed_nodes, env_states, delay_states, stereo_delay_left_states, stereo_delay_right_states,
    ),
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
    self_enabled: self.self_enabled,
    back_edge_input0_source: self.back_edge_input0_source,
    back_edge_input1_source: self.back_edge_input1_source,
    sample_values: FixedArray::make(node_count, 0.0),
    left_sample_values: FixedArray::make(node_count, 0.0),
    right_sample_values: FixedArray::make(node_count, 0.0),
    pan_left_gains: FixedArray::make(node_count, 0.0),
    pan_right_gains: FixedArray::make(node_count, 0.0),
    last_sanitized_count: 0,
    debug_validate: false,
    last_validation_errors: [],
  }
}

///|
/// Compile a declarative terminal-stereo graph into an executable
/// stereo graph.
///
/// Accepts a `AnalyzedGraph` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// — including the stereo-specific requirement of a single reachable
/// `StereoOutput`.
pub fn StereoDsp::compile(
  compiled_template : AnalyzedGraph,
  context : DspContext,
) -> StereoDsp? {
  match StereoDsp::compile_result(compiled_template, context) {
    Ok(graph) => Some(graph)
    Err(_) => None
  }
}

///|
pub fn StereoDsp::compile_raw(
  nodes : Array[DspNode],
  context : DspContext,
) -> StereoDsp? {
  match build_graph_program(nodes, context, DspNodeKind::StereoOutput) {
    Ok(program) => Some(StereoDspProgram(program).instantiate())
    Err(_) => None
  }
}

///|
pub fn CompiledGraph::compiled_buffer_capacity(self : CompiledGraph) -> Int {
  if self.buffers.is_empty() {
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
pub fn Dsp::compiled_buffer_capacity(self : Dsp) -> Int {
  self.0.compiled_buffer_capacity()
}

///|
pub fn StereoDsp::compiled_buffer_capacity(self : StereoDsp) -> Int {
  self.0.compiled_buffer_capacity()
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
