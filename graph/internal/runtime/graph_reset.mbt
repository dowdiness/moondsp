///|
/// Reset mutable runtime state and restore compile-time node parameters.
pub fn CompiledDsp::reset_runtime_state(self : CompiledDsp) -> Unit {
  self.0.reset_runtime_state()
}

///|
fn CompiledGraph::reset_runtime_state(self : CompiledGraph) -> Unit {
  restore_default_nodes(self.nodes, self.default_nodes)
  clear_compiled_buffers(self.buffers)
  clear_compiled_buffers(self.left_buffers)
  clear_compiled_buffers(self.right_buffers)
  reset_graph_osc_states(self.osc_states)
  reset_graph_noise_states(self.noise_states, self.nodes)
  reset_graph_env_states(self.env_states)
  reset_graph_biquad_states(self.biquad_states)
  reset_graph_biquad_states(self.stereo_biquad_left_states)
  reset_graph_biquad_states(self.stereo_biquad_right_states)
  reset_graph_delay_states(self.delay_states, self.nodes)
  reset_graph_delay_states(self.stereo_delay_left_states, self.nodes)
  reset_graph_delay_states(self.stereo_delay_right_states, self.nodes)
  self.self_values.fill(0.0)
  self.self_left_values.fill(0.0)
  self.self_right_values.fill(0.0)
  self.sample_values.fill(0.0)
  self.left_sample_values.fill(0.0)
  self.right_sample_values.fill(0.0)
  self.pan_left_gains.fill(0.0)
  self.pan_right_gains.fill(0.0)
  self.last_sanitized_count = 0
}

///|
fn restore_default_nodes(
  nodes : FixedArray[@model.DspNode],
  defaults : FixedArray[@model.DspNode],
) -> Unit {
  let count = if nodes.length() < defaults.length() {
    nodes.length()
  } else {
    defaults.length()
  }
  for index in 0..<count {
    @model.restore_node_runtime_params(nodes[index], defaults[index])
  }
}

///|
fn reset_graph_osc_states(osc_states : FixedArray[Oscillator?]) -> Unit {
  for index in 0..<osc_states.length() {
    match osc_states[index] {
      Some(osc) => osc.reset()
      None => ()
    }
  }
}

///|
fn reset_graph_noise_states(
  noise_states : FixedArray[Noise?],
  nodes : FixedArray[@model.DspNode],
) -> Unit {
  let count = if noise_states.length() < nodes.length() {
    noise_states.length()
  } else {
    nodes.length()
  }
  for index in 0..<count {
    match noise_states[index] {
      Some(noise) => noise.reset(nodes[index].seed())
      None => ()
    }
  }
}

///|
fn reset_graph_biquad_states(biquad_states : FixedArray[Biquad?]) -> Unit {
  for index in 0..<biquad_states.length() {
    match biquad_states[index] {
      Some(biquad) => biquad.reset()
      None => ()
    }
  }
}

///|
fn reset_graph_delay_states(
  delay_states : FixedArray[DelayLine?],
  nodes : FixedArray[@model.DspNode],
) -> Unit {
  let count = if delay_states.length() < nodes.length() {
    delay_states.length()
  } else {
    nodes.length()
  }
  for index in 0..<count {
    match delay_states[index] {
      Some(delay) => reset_delay_state_to_node(delay, nodes[index])
      None => ()
    }
  }
}

///|
fn reset_delay_state_to_node(delay : DelayLine, node : @model.DspNode) -> Unit {
  match node.kind() {
    Delay => {
      delay.set_feedback(node.value0())
      delay.set_delay_samples(node.delay_samples())
      delay.reset()
    }
    StereoDelay => {
      delay.set_feedback(node.value0())
      delay.set_delay_samples(node.delay_samples())
      delay.reset()
    }
    _ => delay.reset()
  }
}
