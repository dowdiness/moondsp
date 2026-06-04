///|
/// Typed rejection reason for graph compilation.
///
/// Node indices reported by public `compile_result` entry points are original
/// authoring indices when they can be mapped from the analyzed template.
pub enum GraphInputSlot {
  Input0
  Input1
} derive(Debug, Eq)

///|
pub enum GraphCompileError {
  InvalidSampleRate(Double)
  MissingOutput(DspNodeKind)
  MultipleOutputs(DspNodeKind)
  WrongOutputKind(Int, DspNodeKind, DspNodeKind)
  InvalidInput(Int, DspNodeKind, GraphInputSlot, Int)
  InvalidParamValue(Int, DspNodeKind, GraphParamSlot, Double)
  InvalidDelaySamples(Int, Int, Int)
  UnreachableNode(Int)
  InvalidFeedbackEdge(Int, Int, Int)
  DuplicateFeedbackInput(Int, GraphInputSlot)
  InvalidTerminalShape(DspNodeKind)
  InternalRejected(DspNodeKind)
} derive(Debug)

///|
pub impl Show for GraphCompileError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Compile a declarative mono graph and return a typed rejection reason when
/// compilation fails.
pub fn CompiledDsp::compile_result(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> Result[CompiledDsp, GraphCompileError] {
  compile_checked_template(compiled_template, context, DspNodeKind::Output, fn(
    template,
    context,
  ) {
    CompiledDsp::compile_internal(
      template.optimized_nodes(),
      context,
      template.length(),
      template.index_map(),
    )
  })
}

///|
/// Compile a declarative terminal-stereo graph and return a typed rejection
/// reason when compilation fails.
pub fn CompiledStereoDsp::compile_result(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> Result[CompiledStereoDsp, GraphCompileError] {
  compile_checked_template(
    compiled_template,
    context,
    DspNodeKind::StereoOutput,
    fn(template, context) {
      CompiledStereoDsp::compile_internal(
        template.optimized_nodes(),
        context,
        template.length(),
        template.index_map(),
      )
    },
  )
}

///|
fn[T] compile_checked_template(
  compiled_template : CompiledTemplate,
  context : DspContext,
  output_kind : DspNodeKind,
  compile : (CompiledTemplate, DspContext) -> T?,
) -> Result[T, GraphCompileError] {
  match compile_error_for_template(compiled_template, context, output_kind) {
    Some(error) => Err(error)
    None =>
      match compile(compiled_template, context) {
        Some(compiled) => Ok(compiled)
        None => Err(GraphCompileError::InternalRejected(output_kind))
      }
  }
}

///|
fn compile_error_for_template(
  compiled_template : CompiledTemplate,
  context : DspContext,
  output_kind : DspNodeKind,
) -> GraphCompileError? {
  let sample_rate = context.sample_rate()
  if !@dsp.is_finite_positive(sample_rate) {
    return Some(GraphCompileError::InvalidSampleRate(sample_rate))
  }
  match
    authoring_graph_compile_error(
      compiled_template.authoring_nodes(),
      sample_rate,
      output_kind,
    ) {
    Some(error) => return Some(error)
    None => ()
  }
  let optimized = compiled_template.optimized_nodes()
  match graph_compile_error(optimized, context, output_kind) {
    Some(error) =>
      Some(
        remap_graph_compile_error(
          error,
          compile_error_inverse_map(
            compiled_template.index_map(),
            optimized.length(),
          ),
        ),
      )
    None => None
  }
}

///|
fn graph_compile_error(
  nodes : Array[DspNode],
  context : DspContext,
  output_kind : DspNodeKind,
) -> GraphCompileError? {
  let sample_rate = context.sample_rate()
  if !@dsp.is_finite_positive(sample_rate) {
    return Some(GraphCompileError::InvalidSampleRate(sample_rate))
  }
  let output_count = count_output_kind(nodes, output_kind)
  if output_count == 0 {
    return Some(GraphCompileError::MissingOutput(output_kind))
  }
  if output_count > 1 {
    return Some(GraphCompileError::MultipleOutputs(output_kind))
  }
  for index in 0..<nodes.length() {
    match
      invalid_compile_node(
        index,
        nodes[index],
        nodes.length(),
        sample_rate,
        output_kind,
      ) {
      Some(error) => return Some(error)
      None => ()
    }
  }
  let output_index = match
    find_single_output_index_of_kind(nodes, output_kind) {
    Some(index) => index
    None => return Some(GraphCompileError::MissingOutput(output_kind))
  }
  let marks = FixedArray::make(nodes.length(), 0)
  let order = Array::new()
  let raw_feedback_edges = Array::new()
  visit_graph_node_with_feedback(
    output_index, nodes, marks, order, raw_feedback_edges,
  )
  for index in 0..<nodes.length() {
    if marks[index] == 0 {
      return Some(GraphCompileError::UnreachableNode(index))
    }
  }
  let topo_map = FixedArray::make(nodes.length(), -1)
  for new_index in 0..<order.length() {
    topo_map[order[new_index]] = new_index
  }
  let fixed_nodes = FixedArray::makei(nodes.length(), index => {
    @model.remap_node_inputs(nodes[order[index]], topo_map)
  })
  let feedback_edges = remapped_feedback_edges(raw_feedback_edges, topo_map)
  match invalid_feedback_edges(feedback_edges, fixed_nodes.length()) {
    Some(error) => return Some(error)
    None => ()
  }
  let valid_shape = if output_kind is DspNodeKind::Output {
    if feedback_edges.length() == 0 {
      valid_terminal_mono_shapes(fixed_nodes)
    } else {
      valid_feedback_terminal_mono_graph(fixed_nodes, feedback_edges)
    }
  } else if feedback_edges.length() == 0 {
    valid_terminal_stereo_shapes(fixed_nodes)
  } else {
    valid_feedback_terminal_stereo_graph(fixed_nodes, feedback_edges)
  }
  if !valid_shape {
    return Some(GraphCompileError::InvalidTerminalShape(output_kind))
  }
  None
}

///|
/// Validate the reachable authoring graph before optimization can rewrite bad
/// references into sentinel `-1` inputs. Dead authoring nodes are ignored here
/// so diagnostics preserve compile compatibility with optimizer elimination.
fn authoring_graph_compile_error(
  nodes : Array[DspNode],
  sample_rate : Double,
  output_kind : DspNodeKind,
) -> GraphCompileError? {
  if count_output_kind(nodes, output_kind) != 1 {
    return None
  }
  let output_index = match
    find_single_output_index_of_kind(nodes, output_kind) {
    Some(index) => index
    None => return None
  }
  let reachable = FixedArray::make(nodes.length(), false)
  mark_reachable(nodes, reachable, output_index)
  for index in 0..<nodes.length() {
    if reachable[index] {
      match
        invalid_compile_node(
          index,
          nodes[index],
          nodes.length(),
          sample_rate,
          output_kind,
        ) {
        Some(error) => return Some(error)
        None => ()
      }
    }
  }
  None
}

///|
/// Iteratively mark an authoring node and its inputs as reachable using a
/// worklist. This is intentionally compile-diagnostic-local: the optimizer's
/// equivalent raw-model helper lives in `graph/internal/template`.
fn mark_reachable(
  nodes : Array[DspNode],
  reachable : FixedArray[Bool],
  start : Int,
) -> Unit {
  let stack : Array[Int] = [start]
  while stack.length() > 0 {
    let index = stack.pop().unwrap()
    if index < 0 || index >= nodes.length() || reachable[index] {
      continue
    }
    reachable[index] = true
    let node = nodes[index]
    if node.input0() >= 0 {
      stack.push(node.input0())
    }
    if node.input1() >= 0 {
      stack.push(node.input1())
    }
  }
}

///|
fn compile_error_inverse_map(
  index_map : FixedArray[Int],
  optimized_count : Int,
) -> FixedArray[Int] {
  let inverse = FixedArray::make(optimized_count, -1)
  for authoring_index in 0..<index_map.length() {
    let optimized_index = index_map[authoring_index]
    if optimized_index >= 0 &&
      optimized_index < inverse.length() &&
      inverse[optimized_index] < 0 {
      inverse[optimized_index] = authoring_index
    }
  }
  inverse
}

///|
fn remap_compile_index(index : Int, inverse : FixedArray[Int]) -> Int {
  if index >= 0 && index < inverse.length() && inverse[index] >= 0 {
    inverse[index]
  } else {
    index
  }
}

///|
fn remap_graph_compile_error(
  error : GraphCompileError,
  inverse : FixedArray[Int],
) -> GraphCompileError {
  match error {
    WrongOutputKind(index, actual, expected) =>
      GraphCompileError::WrongOutputKind(
        remap_compile_index(index, inverse),
        actual,
        expected,
      )
    InvalidInput(index, kind, slot, input) =>
      GraphCompileError::InvalidInput(
        remap_compile_index(index, inverse),
        kind,
        slot,
        input,
      )
    InvalidParamValue(index, kind, slot, value) =>
      GraphCompileError::InvalidParamValue(
        remap_compile_index(index, inverse),
        kind,
        slot,
        value,
      )
    InvalidDelaySamples(index, delay_samples, delay_max_samples) =>
      GraphCompileError::InvalidDelaySamples(
        remap_compile_index(index, inverse),
        delay_samples,
        delay_max_samples,
      )
    UnreachableNode(index) =>
      GraphCompileError::UnreachableNode(remap_compile_index(index, inverse))
    InvalidFeedbackEdge(source, target, slot) =>
      GraphCompileError::InvalidFeedbackEdge(
        remap_compile_index(source, inverse),
        remap_compile_index(target, inverse),
        slot,
      )
    DuplicateFeedbackInput(target, slot) =>
      GraphCompileError::DuplicateFeedbackInput(
        remap_compile_index(target, inverse),
        slot,
      )
    _ => error
  }
}

///|
fn count_output_kind(nodes : Array[DspNode], output_kind : DspNodeKind) -> Int {
  for node in nodes; count = 0 {
    if node.kind() == output_kind {
      continue count + 1
    }
    continue count
  } nobreak {
    count
  }
}

///|
fn invalid_compile_node(
  index : Int,
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
  output_kind : DspNodeKind,
) -> GraphCompileError? {
  match node.kind() {
    Constant =>
      invalid_finite_param(
        index,
        node.kind(),
        GraphParamSlot::Value0,
        node.value0(),
      )
    Oscillator => invalid_oscillator_node(index, node, node_count)
    Noise => None
    Adsr => invalid_adsr_node(index, node)
    Biquad | StereoBiquad =>
      invalid_biquad_node(index, node, node_count, sample_rate)
    Delay | StereoDelay => invalid_delay_node(index, node, node_count)
    Gain => invalid_gain_node(index, node, node_count)
    Mul | Mix => invalid_binary_input_node(index, node, node_count)
    Clip | StereoClip =>
      invalid_unary_positive_param_node(index, node, node_count)
    Output | StereoOutput =>
      invalid_output_node(index, node, node_count, output_kind)
    Pan | StereoGain => invalid_unary_finite_param_node(index, node, node_count)
    StereoMixDown => invalid_unary_input_node(index, node, node_count)
  }
}

///|
fn invalid_oscillator_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  if node.input0() >= 0 {
    invalid_unary_input_node(index, node, node_count)
  } else {
    invalid_finite_param(
      index,
      node.kind(),
      GraphParamSlot::Value0,
      node.value0(),
    )
  }
}

///|
fn invalid_adsr_node(index : Int, node : DspNode) -> GraphCompileError? {
  let params : Array[(GraphParamSlot, Double)] = [
    (GraphParamSlot::Value0, node.value0()),
    (GraphParamSlot::Value1, node.value1()),
    (GraphParamSlot::Value2, node.value2()),
    (GraphParamSlot::Value3, node.value3()),
  ]
  for param in params {
    match invalid_finite_param(index, node.kind(), param.0, param.1) {
      Some(error) => return Some(error)
      None => ()
    }
  }
  None
}

///|
fn invalid_biquad_node(
  index : Int,
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
) -> GraphCompileError? {
  match invalid_unary_input_node(index, node, node_count) {
    Some(error) => Some(error)
    None =>
      invalid_biquad_params(
        index,
        node.kind(),
        sample_rate,
        node.value0(),
        node.value1(),
      )
  }
}

///|
fn invalid_delay_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  match invalid_unary_input_node(index, node, node_count) {
    Some(error) => Some(error)
    None =>
      invalid_delay_params(
        index,
        node.kind(),
        node.value0(),
        node.delay_samples(),
        node.delay_max_samples(),
      )
  }
}

///|
fn invalid_gain_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  match invalid_unary_input_node(index, node, node_count) {
    Some(error) => Some(error)
    None =>
      if node.input1() >= 0 {
        match
          invalid_input(
            index,
            node.kind(),
            GraphInputSlot::Input1,
            node.input1(),
            node_count,
          ) {
          Some(error) => Some(error)
          None =>
            invalid_finite_param(
              index,
              node.kind(),
              GraphParamSlot::Value0,
              node.value0(),
            )
        }
      } else {
        invalid_finite_param(
          index,
          node.kind(),
          GraphParamSlot::Value0,
          node.value0(),
        )
      }
  }
}

///|
fn invalid_binary_input_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  match invalid_unary_input_node(index, node, node_count) {
    Some(error) => Some(error)
    None =>
      invalid_input(
        index,
        node.kind(),
        GraphInputSlot::Input1,
        node.input1(),
        node_count,
      )
  }
}

///|
fn invalid_unary_positive_param_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  match invalid_unary_input_node(index, node, node_count) {
    Some(error) => Some(error)
    None =>
      if @dsp.is_finite(node.value0()) && node.value0() > 0.0 {
        None
      } else {
        Some(
          GraphCompileError::InvalidParamValue(
            index,
            node.kind(),
            GraphParamSlot::Value0,
            node.value0(),
          ),
        )
      }
  }
}

///|
fn invalid_output_node(
  index : Int,
  node : DspNode,
  node_count : Int,
  output_kind : DspNodeKind,
) -> GraphCompileError? {
  if node.kind() != output_kind {
    Some(GraphCompileError::WrongOutputKind(index, node.kind(), output_kind))
  } else {
    invalid_unary_input_node(index, node, node_count)
  }
}

///|
fn invalid_unary_finite_param_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  match invalid_unary_input_node(index, node, node_count) {
    Some(error) => Some(error)
    None =>
      invalid_finite_param(
        index,
        node.kind(),
        GraphParamSlot::Value0,
        node.value0(),
      )
  }
}

///|
fn invalid_unary_input_node(
  index : Int,
  node : DspNode,
  node_count : Int,
) -> GraphCompileError? {
  invalid_input(
    index,
    node.kind(),
    GraphInputSlot::Input0,
    node.input0(),
    node_count,
  )
}

///|
fn invalid_input(
  index : Int,
  kind : DspNodeKind,
  slot : GraphInputSlot,
  input : Int,
  node_count : Int,
) -> GraphCompileError? {
  if valid_reference(input, node_count) {
    None
  } else {
    Some(GraphCompileError::InvalidInput(index, kind, slot, input))
  }
}

///|
fn invalid_finite_param(
  index : Int,
  kind : DspNodeKind,
  slot : GraphParamSlot,
  value : Double,
) -> GraphCompileError? {
  if @dsp.is_finite(value) {
    None
  } else {
    Some(GraphCompileError::InvalidParamValue(index, kind, slot, value))
  }
}

///|
fn invalid_biquad_params(
  index : Int,
  kind : DspNodeKind,
  sample_rate : Double,
  cutoff : Double,
  q : Double,
) -> GraphCompileError? {
  let nyquist = sample_rate * @model.NYQUIST_RATIO
  if !@dsp.is_finite(cutoff) || cutoff <= 0.0 || cutoff >= nyquist {
    Some(
      GraphCompileError::InvalidParamValue(
        index,
        kind,
        GraphParamSlot::Value0,
        cutoff,
      ),
    )
  } else if !@dsp.is_finite(q) || q <= 0.0 {
    Some(
      GraphCompileError::InvalidParamValue(
        index,
        kind,
        GraphParamSlot::Value1,
        q,
      ),
    )
  } else {
    None
  }
}

///|
fn invalid_delay_params(
  index : Int,
  kind : DspNodeKind,
  feedback : Double,
  delay_samples : Int,
  delay_max_samples : Int,
) -> GraphCompileError? {
  if !valid_delay_feedback(feedback) {
    Some(
      GraphCompileError::InvalidParamValue(
        index,
        kind,
        GraphParamSlot::Value0,
        feedback,
      ),
    )
  } else if !valid_delay_samples(delay_samples, delay_max_samples) {
    Some(
      GraphCompileError::InvalidDelaySamples(
        index, delay_samples, delay_max_samples,
      ),
    )
  } else {
    None
  }
}

///|
fn invalid_feedback_edges(
  feedback_edges : FixedArray[(Int, Int, Int)],
  node_count : Int,
) -> GraphCompileError? {
  let input0_sources = FixedArray::make(node_count, -1)
  let input1_sources = FixedArray::make(node_count, -1)
  for edge in feedback_edges {
    let source = edge.0
    let target = edge.1
    let slot = edge.2
    if source < 0 || source >= node_count || target < 0 || target >= node_count {
      return Some(GraphCompileError::InvalidFeedbackEdge(source, target, slot))
    }
    if slot == 0 {
      if input0_sources[target] >= 0 {
        return Some(
          GraphCompileError::DuplicateFeedbackInput(
            target,
            GraphInputSlot::Input0,
          ),
        )
      }
      input0_sources[target] = source
    } else if slot == 1 {
      if input1_sources[target] >= 0 {
        return Some(
          GraphCompileError::DuplicateFeedbackInput(
            target,
            GraphInputSlot::Input1,
          ),
        )
      }
      input1_sources[target] = source
    } else {
      return Some(GraphCompileError::InvalidFeedbackEdge(source, target, slot))
    }
  }
  None
}
