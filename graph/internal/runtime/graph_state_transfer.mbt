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
      match
        (old_graph.osc_states[old_compiled], self.osc_states[new_compiled]) {
        (Some(old_state), Some(new_state)) =>
          new_state.copy_state_from(old_state)
        _ => ()
      }
      match
        (old_graph.noise_states[old_compiled], self.noise_states[new_compiled]) {
        (Some(old_state), Some(new_state)) =>
          new_state.copy_state_from(old_state)
        _ => ()
      }
      match
        (old_graph.env_states[old_compiled], self.env_states[new_compiled]) {
        (Some(old_state), Some(new_state)) =>
          new_state.copy_state_from(old_state)
        _ => ()
      }
      match
        (
          old_graph.biquad_states[old_compiled],
          self.biquad_states[new_compiled],
        ) {
        (Some(old_state), Some(new_state)) =>
          new_state.copy_state_from(old_state)
        _ => ()
      }
      match
        (
          old_graph.stereo_biquad_left_states[old_compiled],
          self.stereo_biquad_left_states[new_compiled],
        ) {
        (Some(old_state), Some(new_state)) =>
          new_state.copy_state_from(old_state)
        _ => ()
      }
      match
        (
          old_graph.stereo_biquad_right_states[old_compiled],
          self.stereo_biquad_right_states[new_compiled],
        ) {
        (Some(old_state), Some(new_state)) =>
          new_state.copy_state_from(old_state)
        _ => ()
      }
      match
        (old_graph.delay_states[old_compiled], self.delay_states[new_compiled]) {
        (Some(old_state), Some(new_state)) =>
          ignore(new_state.copy_state_from(old_state))
        _ => ()
      }
      match
        (
          old_graph.stereo_delay_left_states[old_compiled],
          self.stereo_delay_left_states[new_compiled],
        ) {
        (Some(old_state), Some(new_state)) =>
          ignore(new_state.copy_state_from(old_state))
        _ => ()
      }
      match
        (
          old_graph.stereo_delay_right_states[old_compiled],
          self.stereo_delay_right_states[new_compiled],
        ) {
        (Some(old_state), Some(new_state)) =>
          ignore(new_state.copy_state_from(old_state))
        _ => ()
      }
      self.self_values[new_compiled] = old_graph.self_values[old_compiled]
      self.self_left_values[new_compiled] = old_graph.self_left_values[old_compiled]
      self.self_right_values[new_compiled] = old_graph.self_right_values[old_compiled]
    }
  }
}
