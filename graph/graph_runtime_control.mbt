///|
/// Failure reason for result-typed runtime graph control APIs.
pub(all) enum GraphControlError {
  InvalidNodeIndex(Int)
  /// The authoring node existed but was eliminated by graph optimization.
  OrphanNode(Int)
  InvalidGateNode(Int, DspNodeKind)
  InvalidSlotForNode(Int, DspNodeKind, GraphParamSlot)
  InvalidParamValue(Int, DspNodeKind, GraphParamSlot, Double)
  MissingRuntimeState(Int, DspNodeKind)
} derive(Debug)

///|
pub impl Show for GraphControlError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Trigger `gate_on()` on an ADSR node using its original authoring index.
///
/// Compatibility helper; prefer `apply_control(GraphControl::gate_on(...))`.
pub fn CompiledDsp::gate_on(self : CompiledDsp, node_index : Int) -> Bool {
  self.gate_on_result(node_index) is Ok(_)
}

///|
/// Result-typed companion to `gate_on(...)`.
pub fn CompiledDsp::gate_on_result(
  self : CompiledDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control_result(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on an ADSR node using its original authoring index.
///
/// Compatibility helper; prefer `apply_control(GraphControl::gate_off(...))`.
pub fn CompiledDsp::gate_off(self : CompiledDsp, node_index : Int) -> Bool {
  self.gate_off_result(node_index) is Ok(_)
}

///|
/// Result-typed companion to `gate_off(...)`.
pub fn CompiledDsp::gate_off_result(
  self : CompiledDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control_result(GraphControl::gate_off(node_index))
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
  self.set_param_result(node_index, slot, value) is Ok(_)
}

///|
/// Result-typed companion to `set_param(...)`.
pub fn CompiledDsp::set_param_result(
  self : CompiledDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control_result(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn CompiledDsp::apply_control_result(
  self : CompiledDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_result_impl(control)
}

///|
/// Apply a runtime control batch transactionally.
pub fn CompiledDsp::apply_controls_result(
  self : CompiledDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_result_impl(controls)
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
  self.gate_on_result(node_index) is Ok(_)
}

///|
/// Result-typed companion to `gate_on(...)`.
pub fn CompiledStereoDsp::gate_on_result(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control_result(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_off(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Bool {
  self.gate_off_result(node_index) is Ok(_)
}

///|
/// Result-typed companion to `gate_off(...)`.
pub fn CompiledStereoDsp::gate_off_result(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control_result(GraphControl::gate_off(node_index))
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
  self.set_param_result(node_index, slot, value) is Ok(_)
}

///|
/// Result-typed companion to `set_param(...)`.
pub fn CompiledStereoDsp::set_param_result(
  self : CompiledStereoDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control_result(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn CompiledStereoDsp::apply_control_result(
  self : CompiledStereoDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_result_impl(control)
}

///|
/// Apply a runtime control batch transactionally.
pub fn CompiledStereoDsp::apply_controls_result(
  self : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_result_impl(controls)
}

///|
fn CompiledGraph::apply_control_impl(
  self : CompiledGraph,
  control : GraphControl,
) -> Bool {
  self.apply_control_result_impl(control) is Ok(_)
}

///|
fn CompiledGraph::apply_control_result_impl(
  self : CompiledGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match control.kind {
    GateOn => apply_graph_gate_control_result(self, control.node_index, true)
    GateOff => apply_graph_gate_control_result(self, control.node_index, false)
    SetParam =>
      apply_graph_param_control_result(
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
  self.apply_controls_result_impl(controls) is Ok(_)
}

///|
fn CompiledGraph::apply_controls_result_impl(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  let simulated_nodes = FixedArray::makei(self.nodes.length(), index => {
    self.nodes[index]
  })
  for index = 0; index < controls.length(); index = index + 1 {
    match valid_graph_control_result(self, simulated_nodes, controls[index]) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }

  for index = 0; index < controls.length(); index = index + 1 {
    match self.apply_control_result_impl(controls[index]) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn CompiledGraph::compiled_index_result(
  self : CompiledGraph,
  node_index : Int,
) -> Result[Int, GraphControlError] {
  match self.compiled_index_for(node_index) {
    Some(compiled) => Ok(compiled)
    None =>
      if node_index < 0 || node_index >= self.index_map.length() {
        Err(GraphControlError::InvalidNodeIndex(node_index))
      } else {
        Err(GraphControlError::OrphanNode(node_index))
      }
  }
}

///|
fn apply_graph_gate_control_result(
  graph : CompiledGraph,
  node_index : Int,
  gate_on : Bool,
) -> Result[Unit, GraphControlError] {
  let compiled_index = match graph.compiled_index_result(node_index) {
    Ok(index) => index
    Err(error) => return Err(error)
  }
  match graph.env_states[compiled_index] {
    Some(env) => {
      if gate_on {
        env.gate_on()
      } else {
        env.gate_off()
      }
      Ok(())
    }
    None => {
      let node = graph.nodes[compiled_index]
      if node.kind is Adsr {
        Err(GraphControlError::MissingRuntimeState(node_index, node.kind))
      } else {
        Err(GraphControlError::InvalidGateNode(node_index, node.kind))
      }
    }
  }
}

///|
fn apply_graph_param_control_result(
  graph : CompiledGraph,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  let compiled_index = match graph.compiled_index_result(node_index) {
    Ok(index) => index
    Err(error) => return Err(error)
  }
  let node = graph.nodes[compiled_index]
  let updated = match
    updated_node_param_result(
      node,
      node_index,
      slot,
      value,
      graph.compile_sample_rate,
    ) {
    Ok(updated) => updated
    Err(error) => return Err(error)
  }
  graph.nodes[compiled_index] = updated
  if apply_runtime_param_side_effect(graph, compiled_index, updated, slot) {
    Ok(())
  } else {
    Err(GraphControlError::MissingRuntimeState(node_index, node.kind))
  }
}

///|
fn valid_graph_control(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  control : GraphControl,
) -> Bool {
  valid_graph_control_result(graph, simulated_nodes, control) is Ok(_)
}

///|
fn valid_graph_control_result(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match control.kind {
    GateOn => valid_graph_gate_control_result(graph, control.node_index)
    GateOff => valid_graph_gate_control_result(graph, control.node_index)
    SetParam =>
      valid_graph_param_control_result(
        graph,
        simulated_nodes,
        control.node_index,
        control.slot,
        control.value,
      )
  }
}

///|
fn valid_graph_gate_control_result(
  graph : CompiledGraph,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  let compiled_index = match graph.compiled_index_result(node_index) {
    Ok(index) => index
    Err(error) => return Err(error)
  }
  match graph.env_states[compiled_index] {
    Some(_) => Ok(())
    None => {
      let node = graph.nodes[compiled_index]
      if node.kind is Adsr {
        Err(GraphControlError::MissingRuntimeState(node_index, node.kind))
      } else {
        Err(GraphControlError::InvalidGateNode(node_index, node.kind))
      }
    }
  }
}

///|
fn valid_graph_param_control_result(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[DspNode],
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  let compiled_index = match graph.compiled_index_result(node_index) {
    Ok(index) => index
    Err(error) => return Err(error)
  }
  let updated = match
    updated_node_param_result(
      simulated_nodes[compiled_index],
      node_index,
      slot,
      value,
      graph.compile_sample_rate,
    ) {
    Ok(updated) => updated
    Err(error) => return Err(error)
  }
  simulated_nodes[compiled_index] = updated
  Ok(())
}

///|
fn updated_node_param_result(
  node : DspNode,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> Result[DspNode, GraphControlError] {
  if !node_accepts_slot(node, slot) {
    return Err(
      GraphControlError::InvalidSlotForNode(node_index, node.kind, slot),
    )
  }
  match updated_node_param(node, slot, value, sample_rate) {
    Some(updated) => Ok(updated)
    None =>
      Err(
        GraphControlError::InvalidParamValue(node_index, node.kind, slot, value),
      )
  }
}

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
