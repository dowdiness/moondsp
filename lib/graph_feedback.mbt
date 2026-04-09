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
