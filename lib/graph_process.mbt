///|
/// Process one node for a full block. Shared dispatch for mono, stereo, and
/// debug process loops. Both Output and StereoOutput arms are present —
/// compile-time validation guarantees only the appropriate one fires.
fn process_node_block(
  graph : CompiledGraph,
  index : Int,
  context : DspContext,
  sample_count : Int,
  pan : Pan,
) -> Unit {
  let node = graph.nodes[index]
  let buffer = graph.buffers[index]
  match node.kind {
    Constant => fill_constant_buffer(buffer, sample_count, node.value0)
    Oscillator =>
      if node.input0 >= 0 {
        let osc = graph.osc_states[index].unwrap()
        let freq_buf = graph.buffers[node.input0]
        let sr = context.sample_rate()
        for i in 0..<sample_count {
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

///|
/// Shared block-at-a-time process loop for both mono and stereo graphs.
///
/// Runs every node through `process_node_block`, copies the final output,
/// and sanitizes. The `is_stereo` flag controls only the final output copy
/// (mono: last mono buffer → output; stereo: last stereo buffers → left/right).
fn CompiledGraph::process_block_loop(
  self : CompiledGraph,
  context : DspContext,
  output : AudioBuffer,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  is_stereo : Bool,
  sample_count : Int,
) -> Unit {
  let pan = Pan::new()
  for index in 0..<self.nodes.length() {
    process_node_block(self, index, context, sample_count, pan)
  }
  if is_stereo {
    copy_stereo_buffers(
      self.left_buffers[self.left_buffers.length() - 1],
      self.right_buffers[self.right_buffers.length() - 1],
      left_output,
      right_output,
      sample_count,
    )
    self.last_sanitized_count = sanitize_buffer(left_output, sample_count) +
      sanitize_buffer(right_output, sample_count)
  } else {
    copy_buffer(self.buffers[self.buffers.length() - 1], output, sample_count)
    self.last_sanitized_count = sanitize_buffer(output, sample_count)
  }
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
  if self.0.debug_validate {
    self.process_mono_debug(context, output, sample_count)
    return
  }
  if self.0.feedback_edges.length() > 0 {
    self.process_feedback_graph(context, output, sample_count)
    self.0.last_sanitized_count = sanitize_buffer(output, sample_count)
    return
  }
  self.0.process_block_loop(
    context, output, output, output, false, sample_count,
  )
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
  if self.0.debug_validate {
    self.process_stereo_debug(context, left_output, right_output, sample_count)
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
  self.0.process_block_loop(
    context, left_output, left_output, right_output, true, sample_count,
  )
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
