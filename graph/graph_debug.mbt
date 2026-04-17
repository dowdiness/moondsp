///|
const MAX_DEBUG_ERRORS : Int = 32

///|
pub(all) enum GraphValidationError {
  InvalidInput0(Int, Int, Int)
  InvalidInput1(Int, Int, Int)
  InvalidStateIndex(Int, String)
} derive(Debug, Eq)

///|
pub impl Show for GraphValidationError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Check that node's input0 and input1 are within buffer bounds.
/// Called per node in debug mode only. Returns true if valid.
fn validate_node_inputs(
  node : DspNode,
  node_index : Int,
  buffer_count : Int,
  errors : Array[GraphValidationError],
) -> Bool {
  let max_valid = buffer_count - 1
  let mut valid = true
  if node.input0 >= 0 && node.input0 >= buffer_count {
    if errors.length() < MAX_DEBUG_ERRORS {
      errors.push(
        GraphValidationError::InvalidInput0(node_index, node.input0, max_valid),
      )
    }
    valid = false
  }
  if node.input1 >= 0 && node.input1 >= buffer_count {
    if errors.length() < MAX_DEBUG_ERRORS {
      errors.push(
        GraphValidationError::InvalidInput1(node_index, node.input1, max_valid),
      )
    }
    valid = false
  }
  valid
}

///|
/// Check that stateful node has its required state present.
/// Called per node in debug mode only. Returns true if valid.
fn validate_node_state(
  graph : CompiledGraph,
  node : DspNode,
  node_index : Int,
  errors : Array[GraphValidationError],
) -> Bool {
  let missing = match node.kind {
    Oscillator =>
      if graph.osc_states[node_index] is None {
        Some("osc")
      } else {
        None
      }
    Noise =>
      if graph.noise_states[node_index] is None {
        Some("noise")
      } else {
        None
      }
    Adsr =>
      if graph.env_states[node_index] is None {
        Some("env")
      } else {
        None
      }
    Biquad =>
      if graph.biquad_states[node_index] is None {
        Some("biquad")
      } else {
        None
      }
    Delay =>
      if graph.delay_states[node_index] is None {
        Some("delay")
      } else {
        None
      }
    StereoBiquad =>
      if graph.stereo_biquad_left_states[node_index] is None ||
        graph.stereo_biquad_right_states[node_index] is None {
        Some("stereo_biquad")
      } else {
        None
      }
    StereoDelay =>
      if graph.stereo_delay_left_states[node_index] is None ||
        graph.stereo_delay_right_states[node_index] is None {
        Some("stereo_delay")
      } else {
        None
      }
    _ => None
  }
  match missing {
    Some(kind) => {
      if errors.length() < MAX_DEBUG_ERRORS {
        errors.push(GraphValidationError::InvalidStateIndex(node_index, kind))
      }
      false
    }
    None => true
  }
}

///|
/// Shared debug process loop for both mono and stereo graphs.
/// Validates each node's inputs and state before processing.
/// On violation, fills output with silence and skips to next node.
///
/// Delegates per-node processing to process_node_block (graph_process.mbt),
/// the single source of truth for block-at-a-time node dispatch. Debug mode
/// adds validation before each node; the processing itself is identical.
fn process_debug_loop(
  graph : CompiledGraph,
  context : DspContext,
  sample_count : Int,
) -> Unit {
  graph.last_validation_errors = []
  let buffer_count = graph.buffers.length()
  let pan = Pan::new()
  for index = 0; index < graph.nodes.length(); index = index + 1 {
    let node = graph.nodes[index]
    if !validate_node_inputs(
        node,
        index,
        buffer_count,
        graph.last_validation_errors,
      ) ||
      !validate_node_state(graph, node, index, graph.last_validation_errors) {
      // WHY zero all three buffers: stereo nodes (Pan, StereoGain, etc.) write
      // to left_buffers/right_buffers, not the mono buffer. Without zeroing all
      // three, downstream stereo consumers would see stale data from the
      // previous block instead of silence.
      graph.buffers[index].fill(0.0)
      graph.left_buffers[index].fill(0.0)
      graph.right_buffers[index].fill(0.0)
      continue index + 1
    }
    process_node_block(graph, index, context, sample_count, pan)
  }
}

///|
/// Validate all nodes once (inputs in bounds, required state present).
/// Resets `last_validation_errors` and returns true when every node passes.
fn validate_all_nodes(graph : CompiledGraph) -> Bool {
  graph.last_validation_errors = []
  let buffer_count = graph.buffers.length()
  for index = 0; index < graph.nodes.length(); index = index + 1 {
    let node = graph.nodes[index]
    ignore(
      validate_node_inputs(
        node,
        index,
        buffer_count,
        graph.last_validation_errors,
      ),
    )
    ignore(
      validate_node_state(graph, node, index, graph.last_validation_errors),
    )
  }
  graph.last_validation_errors.length() == 0
}

///|
/// Debug variant of mono process. Validates each node before processing.
/// For feedback graphs, validates once per block then delegates to the
/// production per-sample feedback path for bit-identical output.
fn CompiledDsp::process_mono_debug(
  self : CompiledDsp,
  context : DspContext,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  if self.0.feedback_edges.length() > 0 {
    if validate_all_nodes(self.0) {
      self.process_feedback_graph(context, output, sample_count)
    } else {
      output.fill(0.0)
    }
    self.0.last_sanitized_count = @dsp.sanitize_buffer(output, sample_count)
    return
  }
  process_debug_loop(self.0, context, sample_count)
  copy_buffer(self.0.buffers[self.0.buffers.length() - 1], output, sample_count)
  self.0.last_sanitized_count = @dsp.sanitize_buffer(output, sample_count)
}

///|
/// Debug variant of stereo process. Validates each node before processing.
/// For feedback graphs, validates once per block then delegates to the
/// production per-sample feedback path for bit-identical output.
fn CompiledStereoDsp::process_stereo_debug(
  self : CompiledStereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  if self.0.feedback_edges.length() > 0 {
    if validate_all_nodes(self.0) {
      self.process_feedback_graph(
        context, left_output, right_output, sample_count,
      )
    } else {
      left_output.fill(0.0)
      right_output.fill(0.0)
    }
    self.0.last_sanitized_count = @dsp.sanitize_buffer(
        left_output, sample_count,
      ) +
      @dsp.sanitize_buffer(right_output, sample_count)
    return
  }
  process_debug_loop(self.0, context, sample_count)
  copy_stereo_buffers(
    self.0.left_buffers[self.0.left_buffers.length() - 1],
    self.0.right_buffers[self.0.right_buffers.length() - 1],
    left_output,
    right_output,
    sample_count,
  )
  self.0.last_sanitized_count = @dsp.sanitize_buffer(left_output, sample_count) +
    @dsp.sanitize_buffer(right_output, sample_count)
}
