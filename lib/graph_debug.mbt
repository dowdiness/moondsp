///|
const MAX_DEBUG_ERRORS : Int = 32

///|
pub(all) enum GraphValidationError {
  InvalidInput0(Int, Int, Int)
  InvalidInput1(Int, Int, Int)
  InvalidStateIndex(Int, String)
} derive(Show, Eq)

///|
pub fn CompiledDsp::enable_debug_validation(self : CompiledDsp) -> Unit {
  self.0.debug_validate = true
}

///|
pub fn CompiledDsp::disable_debug_validation(self : CompiledDsp) -> Unit {
  self.0.debug_validate = false
  self.0.last_validation_errors = []
}

///|
pub fn CompiledDsp::last_validation_errors(
  self : CompiledDsp,
) -> Array[GraphValidationError] {
  self.0.last_validation_errors
}

///|
pub fn CompiledStereoDsp::enable_debug_validation(
  self : CompiledStereoDsp,
) -> Unit {
  self.0.debug_validate = true
}

///|
pub fn CompiledStereoDsp::disable_debug_validation(
  self : CompiledStereoDsp,
) -> Unit {
  self.0.debug_validate = false
  self.0.last_validation_errors = []
}

///|
pub fn CompiledStereoDsp::last_validation_errors(
  self : CompiledStereoDsp,
) -> Array[GraphValidationError] {
  self.0.last_validation_errors
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
/// WHY duplicated from the production loops: validation checks run per-node
/// inside the tight loop. Keeping them in a separate function preserves the
/// production fast path's code shape unchanged (no debug branches to optimize
/// away). If new node kinds are added, update this loop alongside the
/// production loops in graph.mbt.
///
/// WHY shared between mono and stereo: compile-time validation guarantees
/// mono graphs have Output (never StereoOutput) and stereo graphs have
/// StereoOutput (never Output). Both arms are present but only the
/// appropriate one fires for each graph type.
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
    let buffer = graph.buffers[index]
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
      buffer.fill(0.0)
      graph.left_buffers[index].fill(0.0)
      graph.right_buffers[index].fill(0.0)
      continue index + 1
    }
    match node.kind {
      Constant => fill_constant_buffer(buffer, sample_count, node.value0)
      Oscillator =>
        if node.input0 >= 0 {
          let osc = graph.osc_states[index].unwrap()
          let freq_buf = graph.buffers[node.input0]
          let sr = context.sample_rate()
          for i = 0; i < sample_count; i = i + 1 {
            buffer.set(i, osc.tick_waveform(node.waveform, freq_buf.get(i), sr))
          }
        } else {
          graph.osc_states[index]
          .unwrap()
          .process_waveform(context, buffer, node.waveform, node.value0)
        }
      Noise => graph.noise_states[index].unwrap().process(context, buffer)
      Adsr => graph.env_states[index].unwrap().process(context, buffer)
      Biquad => {
        copy_buffer(graph.buffers[node.input0], buffer, sample_count)
        process_graph_biquad(
          graph.biquad_states[index].unwrap(),
          context,
          buffer,
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      Delay => {
        copy_buffer(graph.buffers[node.input0], buffer, sample_count)
        graph.delay_states[index].unwrap().process(context, buffer)
      }
      Gain => {
        copy_buffer(graph.buffers[node.input0], buffer, sample_count)
        apply_gain_buffer(buffer, sample_count, node.value0)
      }
      Mul =>
        multiply_buffers(
          graph.buffers[node.input0],
          graph.buffers[node.input1],
          buffer,
          sample_count,
        )
      Mix =>
        mix_buffers(
          graph.buffers[node.input0],
          graph.buffers[node.input1],
          buffer,
          sample_count,
        )
      Clip => {
        copy_buffer(graph.buffers[node.input0], buffer, sample_count)
        clip_buffer(buffer, sample_count, node.value0)
      }
      Output => copy_buffer(graph.buffers[node.input0], buffer, sample_count)
      Pan =>
        pan.process(
          context,
          graph.buffers[node.input0],
          graph.left_buffers[index],
          graph.right_buffers[index],
          node.value0,
        )
      StereoGain => {
        copy_stereo_buffers(
          graph.left_buffers[node.input0],
          graph.right_buffers[node.input0],
          graph.left_buffers[index],
          graph.right_buffers[index],
          sample_count,
        )
        apply_gain_buffer(graph.left_buffers[index], sample_count, node.value0)
        apply_gain_buffer(graph.right_buffers[index], sample_count, node.value0)
      }
      StereoClip => {
        copy_stereo_buffers(
          graph.left_buffers[node.input0],
          graph.right_buffers[node.input0],
          graph.left_buffers[index],
          graph.right_buffers[index],
          sample_count,
        )
        clip_buffer(graph.left_buffers[index], sample_count, node.value0)
        clip_buffer(graph.right_buffers[index], sample_count, node.value0)
      }
      StereoBiquad => {
        copy_stereo_buffers(
          graph.left_buffers[node.input0],
          graph.right_buffers[node.input0],
          graph.left_buffers[index],
          graph.right_buffers[index],
          sample_count,
        )
        process_graph_biquad(
          graph.stereo_biquad_left_states[index].unwrap(),
          context,
          graph.left_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
        process_graph_biquad(
          graph.stereo_biquad_right_states[index].unwrap(),
          context,
          graph.right_buffers[index],
          node.filter_mode,
          node.value0,
          node.value1,
        )
      }
      StereoDelay => {
        copy_stereo_buffers(
          graph.left_buffers[node.input0],
          graph.right_buffers[node.input0],
          graph.left_buffers[index],
          graph.right_buffers[index],
          sample_count,
        )
        graph.stereo_delay_left_states[index]
        .unwrap()
        .process(context, graph.left_buffers[index])
        graph.stereo_delay_right_states[index]
        .unwrap()
        .process(context, graph.right_buffers[index])
      }
      StereoMixDown =>
        mixdown_stereo_buffers(
          graph.left_buffers[node.input0],
          graph.right_buffers[node.input0],
          buffer,
          sample_count,
        )
      StereoOutput =>
        copy_stereo_buffers(
          graph.left_buffers[node.input0],
          graph.right_buffers[node.input0],
          graph.left_buffers[index],
          graph.right_buffers[index],
          sample_count,
        )
    }
  }
}

///|
/// Debug variant of mono process. Validates each node before processing.
fn CompiledDsp::process_mono_debug(
  self : CompiledDsp,
  context : DspContext,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  process_debug_loop(self.0, context, sample_count)
  copy_buffer(self.0.buffers[self.0.buffers.length() - 1], output, sample_count)
  self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
}

///|
/// Debug variant of stereo process. Validates each node before processing.
fn CompiledStereoDsp::process_stereo_debug(
  self : CompiledStereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  process_debug_loop(self.0, context, sample_count)
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
