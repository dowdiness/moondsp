///|
/// Trigger `gate_on()` on an ADSR node using its original authoring index.
///
/// Compatibility helper; prefer `apply_control(GraphControl::gate_on(...))`.
pub fn CompiledDsp::gate_on(self : CompiledDsp, node_index : Int) -> Bool {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on an ADSR node using its original authoring index.
///
/// Compatibility helper; prefer `apply_control(GraphControl::gate_off(...))`.
pub fn CompiledDsp::gate_off(self : CompiledDsp, node_index : Int) -> Bool {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled node using its original authoring
/// index.
///
/// Returns `false` when the node index is invalid, the slot is unsupported for
/// that node kind, or the new value is invalid for that slot.
///
/// Compatibility helper; prefer
/// `apply_control(GraphControl::set_param(...))`.
pub fn CompiledDsp::set_param(
  self : CompiledDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Returns true when a voice using this compiled graph can be safely reclaimed.
///
/// Two-stage check:
/// 1. All ADSR nodes must be in Idle stage (envelope has finished)
/// 2. The last output buffer must be silent (all samples below threshold)
///
/// WHY two stages: ADSR-only detection would cut voices with downstream delay
/// or feedback tails that are still audible. Energy-only detection would keep
/// voices alive during sustain (where output is non-zero but expected).
pub fn CompiledDsp::is_voice_finished(self : CompiledDsp) -> Bool {
  let nodes = self.0.nodes
  let env_states = self.0.env_states
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].kind is Adsr {
      match env_states[i] {
        Some(adsr) => if !(adsr.stage() is EnvStage::Idle) { return false }
        None => ()
      }
    }
  }
  let last_index = nodes.length() - 1
  if last_index < 0 {
    return true
  }
  let output_buf = self.0.buffers[last_index]
  for i = 0; i < output_buf.length(); i = i + 1 {
    if output_buf.get(i).abs() > 0.0001 {
      return false
    }
  }
  true
}

///|
/// Trigger `gate_on()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_on(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Bool {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_off(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Bool {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled stereo node using its original
/// authoring index.
pub fn CompiledStereoDsp::set_param(
  self : CompiledStereoDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
fn CompiledGraph::apply_control_impl(
  self : CompiledGraph,
  control : GraphControl,
) -> Bool {
  match control.kind {
    GateOn => apply_graph_gate_control(self, control.node_index, true)
    GateOff => apply_graph_gate_control(self, control.node_index, false)
    SetParam =>
      apply_graph_param_control(
        self,
        control.node_index,
        control.slot,
        control.value,
      )
  }
}

///|
fn CompiledGraph::apply_controls_impl(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Bool {
  let simulated_nodes = FixedArray::makei(self.nodes.length(), index => {
    self.nodes[index]
  })
  for index = 0; index < controls.length(); index = index + 1 {
    if !valid_graph_control(self, simulated_nodes, controls[index]) {
      return false
    }
  }

  for index = 0; index < controls.length(); index = index + 1 {
    if !self.apply_control_impl(controls[index]) {
      return false
    }
  }
  true
}

///|
fn apply_graph_gate_control(
  graph : CompiledGraph,
  node_index : Int,
  gate_on : Bool,
) -> Bool {
  match graph.compiled_index_for(node_index) {
    Some(compiled_index) =>
      match graph.env_states[compiled_index] {
        Some(env) => {
          if gate_on {
            env.gate_on()
          } else {
            env.gate_off()
          }
          true
        }
        None => false
      }
    None => false
  }
}

///|
fn apply_graph_param_control(
  graph : CompiledGraph,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  let compiled_index = match graph.compiled_index_for(node_index) {
    Some(compiled_index) => compiled_index
    None => return false
  }
  let node = graph.nodes[compiled_index]
  let updated = match
    updated_node_param(node, slot, value, graph.compile_sample_rate) {
    Some(updated) => updated
    None => return false
  }
  graph.nodes[compiled_index] = updated
  apply_runtime_param_side_effect(graph, compiled_index, updated, slot)
}

///|
fn valid_graph_control(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  control : GraphControl,
) -> Bool {
  match control.kind {
    GateOn => valid_graph_gate_control(graph, control.node_index)
    GateOff => valid_graph_gate_control(graph, control.node_index)
    SetParam =>
      valid_graph_param_control(
        graph,
        simulated_nodes,
        control.node_index,
        control.slot,
        control.value,
      )
  }
}

///|
fn valid_graph_gate_control(graph : CompiledGraph, node_index : Int) -> Bool {
  match graph.compiled_index_for(node_index) {
    Some(compiled_index) => graph.env_states[compiled_index] is Some(_)
    None => false
  }
}

///|
fn valid_graph_param_control(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  let compiled_index = match graph.compiled_index_for(node_index) {
    Some(compiled_index) => compiled_index
    None => return false
  }
  let updated = match
    updated_node_param(
      simulated_nodes[compiled_index],
      slot,
      value,
      graph.compile_sample_rate,
    ) {
    Some(updated) => updated
    None => return false
  }
  simulated_nodes[compiled_index] = updated
  true
}

///|

///|
fn updated_node_param(
  node : DspNode,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> DspNode? {
  match node.kind {
    Constant =>
      match slot {
        Value0 if @dsp.is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    Oscillator =>
      // FM oscillators (input0 >= 0) read frequency from input buffer;
      // reject Value0 updates for them since the value is unused.
      if node.input0 >= 0 {
        None
      } else {
        match slot {
          Value0 if @dsp.is_finite(value) => Some(node_with_value0(node, value))
          _ => None
        }
      }
    Adsr => None
    Noise => None
    Biquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1) =>
          Some(node_with_value0(node, value))
        Value1 if valid_biquad_graph_params(sample_rate, node.value0, value) =>
          Some(node_with_value1(node, value))
        _ => None
      }
    Delay =>
      match slot {
        Value0 if valid_delay_feedback(value) =>
          Some(node_with_value0(node, value))
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples) =>
              Some(node_with_delay_samples(node, ds))
            _ => None
          }
        _ => None
      }
    Gain =>
      match slot {
        Value0 if @dsp.is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    Mul => None
    Mix => None
    Clip =>
      match slot {
        Value0 if @dsp.is_finite(value) && value > 0.0 =>
          Some(node_with_value0(node, value))
        _ => None
      }
    Output => None
    Pan =>
      match slot {
        Value0 if @dsp.is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    StereoGain =>
      match slot {
        Value0 if @dsp.is_finite(value) => Some(node_with_value0(node, value))
        _ => None
      }
    StereoClip =>
      match slot {
        Value0 if @dsp.is_finite(value) && value > 0.0 =>
          Some(node_with_value0(node, value))
        _ => None
      }
    StereoBiquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1) =>
          Some(node_with_value0(node, value))
        Value1 if valid_biquad_graph_params(sample_rate, node.value0, value) =>
          Some(node_with_value1(node, value))
        _ => None
      }
    StereoDelay =>
      match slot {
        Value0 if valid_delay_feedback(value) =>
          Some(node_with_value0(node, value))
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples) =>
              Some(node_with_delay_samples(node, ds))
            _ => None
          }
        _ => None
      }
    StereoMixDown => None
    StereoOutput => None
  }
}

///|
fn apply_runtime_param_side_effect(
  graph : CompiledGraph,
  compiled_index : Int,
  node : DspNode,
  slot : GraphParamSlot,
) -> Bool {
  match node.kind {
    Delay =>
      match slot {
        Value0 =>
          match graph.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_feedback(node.value0)
              delay.set_delay_samples(node.delay_samples)
              true
            }
            None => false
          }
        DelaySamples =>
          match graph.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_feedback(node.value0)
              delay.set_delay_samples(node.delay_samples)
              true
            }
            None => false
          }
        _ => false
      }
    Constant => true
    Oscillator => true
    Biquad => true
    Gain => true
    Clip => true
    Pan => true
    StereoGain => true
    StereoClip => true
    StereoBiquad => true
    StereoDelay =>
      match slot {
        Value0 =>
          apply_stereo_delay_param_side_effect(
            graph.stereo_delay_left_states,
            graph.stereo_delay_right_states,
            compiled_index,
            node.delay_samples,
            node.value0,
          )
        DelaySamples =>
          apply_stereo_delay_param_side_effect(
            graph.stereo_delay_left_states,
            graph.stereo_delay_right_states,
            compiled_index,
            node.delay_samples,
            node.value0,
          )
        _ => false
      }
    StereoMixDown => false
    _ => false
  }
}

///|
fn exact_int_value(value : Double) -> Int? {
  if !@dsp.is_finite(value) || value.trunc() != value {
    return None
  }
  let int_value = value.to_int()
  if Double::from_int(int_value) == value {
    Some(int_value)
  } else {
    None
  }
}

///|
fn valid_biquad_graph_params(
  sample_rate : Double,
  cutoff : Double,
  q : Double,
) -> Bool {
  let nyquist = sample_rate * NYQUIST_RATIO
  @dsp.is_finite(sample_rate) &&
  sample_rate > 0.0 &&
  @dsp.is_finite(cutoff) &&
  cutoff > 0.0 &&
  cutoff < nyquist &&
  @dsp.is_finite(q) &&
  q > 0.0
}

///|
fn graph_default_delay_samples(value : Int) -> Int {
  if value > 0 {
    value
  } else {
    0
  }
}

///|
fn valid_delay_feedback(value : Double) -> Bool {
  @dsp.is_finite(value) &&
  value >= -@dsp.max_feedback_amount() &&
  value <= @dsp.max_feedback_amount()
}

///|
/// Shared validation for delay_samples used by both compile-time
/// (`valid_any_node_inputs`) and runtime (`updated_node_param`) paths.
fn valid_delay_samples(delay_samples : Int, delay_max_samples : Int) -> Bool {
  delay_samples >= 0 && delay_samples <= delay_max_samples
}

///|
/// Structural check: does this node kind accept SetParam on the given slot?
/// Used by ControlBindingBuilder::build() to validate bindings at graph
/// construction time. Does not check value-domain constraints.
pub fn node_accepts_slot(node : DspNode, slot : GraphParamSlot) -> Bool {
  match node.kind {
    Constant => slot is Value0
    Oscillator => node.input0 < 0 && slot is Value0
    Noise => false
    Adsr => false
    Biquad => slot is Value0 || slot is Value1
    Delay => slot is Value0 || slot is DelaySamples
    Gain => slot is Value0
    Mul => false
    Mix => false
    Clip => slot is Value0
    Output => false
    Pan => slot is Value0
    StereoGain => slot is Value0
    StereoClip => slot is Value0
    StereoBiquad => slot is Value0 || slot is Value1
    StereoDelay => slot is Value0 || slot is DelaySamples
    StereoMixDown => false
    StereoOutput => false
  }
}

///|
fn apply_stereo_delay_param_side_effect(
  left_states : FixedArray[DelayLine?],
  right_states : FixedArray[DelayLine?],
  compiled_index : Int,
  delay_samples : Int,
  feedback : Double,
) -> Bool {
  match left_states[compiled_index] {
    Some(left_delay) =>
      match right_states[compiled_index] {
        Some(right_delay) => {
          left_delay.set_feedback(feedback)
          left_delay.set_delay_samples(delay_samples)
          right_delay.set_feedback(feedback)
          right_delay.set_delay_samples(delay_samples)
          true
        }
        None => false
      }
    None => false
  }
}

///|
fn make_graph_delay_state(node : DspNode) -> DelayLine? {
  match node.kind {
    Delay =>
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
