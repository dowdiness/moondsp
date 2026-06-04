///|
/// Failure reason for runtime graph control APIs.
pub enum GraphControlError {
  InvalidNodeIndex(Int)
  /// The authoring node existed but was eliminated by graph optimization.
  OrphanNode(Int)
  InvalidGateNode(Int, DspNodeKind)
  InvalidSlotForNode(Int, DspNodeKind, GraphParamSlot)
  InvalidParamValue(Int, DspNodeKind, GraphParamSlot, Double)
  MissingRuntimeState(Int, DspNodeKind)
} derive(Debug)

///|
pub impl Show for GraphControlError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn CompiledDsp::apply_control(
  self : CompiledDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
/// Apply a runtime control batch transactionally.
pub fn CompiledDsp::apply_controls(
  self : CompiledDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn CompiledDsp::validate_controls(
  self : CompiledDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.validate_controls_impl(controls)
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
    if nodes[i].kind() is Adsr {
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
/// Apply one runtime control message, returning a specific rejection reason.
pub fn CompiledStereoDsp::apply_control(
  self : CompiledStereoDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
/// Apply a runtime control batch transactionally.
pub fn CompiledStereoDsp::apply_controls(
  self : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn CompiledStereoDsp::validate_controls(
  self : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.validate_controls_impl(controls)
}

///|
pub fn CompiledGraph::apply_control_impl(
  self : CompiledGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match control.kind() {
    GateOn => apply_graph_gate_control_result(self, control.node_index(), true)
    GateOff =>
      apply_graph_gate_control_result(self, control.node_index(), false)
    SetParam =>
      apply_graph_param_control_result(
        self,
        control.node_index(),
        control.slot(),
        control.value(),
      )
  }
}

///|
pub fn CompiledGraph::apply_controls_impl(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  match self.validate_controls_impl(controls) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }

  for index = 0; index < controls.length(); index = index + 1 {
    match self.apply_control_impl(controls[index]) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
pub fn CompiledGraph::validate_controls_impl(
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
      let kind = node.kind()
      if node.kind() is Adsr {
        Err(GraphControlError::MissingRuntimeState(node_index, kind))
      } else {
        Err(GraphControlError::InvalidGateNode(node_index, kind))
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
    updated_model_node_param_result(
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
    Err(GraphControlError::MissingRuntimeState(node_index, node.kind()))
  }
}

///|
fn valid_graph_control_result(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[@model.DspNode],
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match control.kind() {
    GateOn => valid_graph_gate_control_result(graph, control.node_index())
    GateOff => valid_graph_gate_control_result(graph, control.node_index())
    SetParam =>
      valid_graph_param_control_result(
        graph,
        simulated_nodes,
        control.node_index(),
        control.slot(),
        control.value(),
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
      let kind = node.kind()
      if node.kind() is Adsr {
        Err(GraphControlError::MissingRuntimeState(node_index, kind))
      } else {
        Err(GraphControlError::InvalidGateNode(node_index, kind))
      }
    }
  }
}

///|
fn valid_graph_param_control_result(
  graph : CompiledGraph,
  simulated_nodes : FixedArray[@model.DspNode],
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  let compiled_index = match graph.compiled_index_result(node_index) {
    Ok(index) => index
    Err(error) => return Err(error)
  }
  let updated = match
    updated_model_node_param_result(
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
pub fn updated_model_node_param_result(
  node : @model.DspNode,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> Result[@model.DspNode, GraphControlError] {
  let kind = node.kind()
  if !@model.node_accepts_slot(node, slot) {
    return Err(GraphControlError::InvalidSlotForNode(node_index, kind, slot))
  }
  match updated_model_node_param(node, slot, value, sample_rate) {
    Some(updated) => Ok(updated)
    None =>
      Err(GraphControlError::InvalidParamValue(node_index, kind, slot, value))
  }
}

///|
fn updated_model_node_param(
  node : @model.DspNode,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> @model.DspNode? {
  match node.kind() {
    Constant =>
      match slot {
        Value0 if @dsp.is_finite(value) =>
          Some(@model.node_with_value0(node, value))
        _ => None
      }
    Oscillator =>
      // FM oscillators (input0 >= 0) read frequency from input buffer;
      // reject Value0 updates for them since the value is unused.
      if node.input0() >= 0 {
        None
      } else {
        match slot {
          Value0 if @dsp.is_finite(value) =>
            Some(@model.node_with_value0(node, value))
          _ => None
        }
      }
    Adsr => None
    Noise => None
    Biquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1()) =>
          Some(@model.node_with_value0(node, value))
        Value1 if valid_biquad_graph_params(sample_rate, node.value0(), value) =>
          Some(@model.node_with_value1(node, value))
        _ => None
      }
    Delay =>
      match slot {
        Value0 if valid_delay_feedback(value) =>
          Some(@model.node_with_value0(node, value))
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples()) =>
              Some(@model.node_with_delay_samples(node, ds))
            _ => None
          }
        _ => None
      }
    Gain =>
      match slot {
        Value0 if @dsp.is_finite(value) =>
          Some(@model.node_with_value0(node, value))
        _ => None
      }
    Mul => None
    Mix => None
    Clip =>
      match slot {
        Value0 if @dsp.is_finite(value) && value > 0.0 =>
          Some(@model.node_with_value0(node, value))
        _ => None
      }
    Output => None
    Pan =>
      match slot {
        Value0 if @dsp.is_finite(value) =>
          Some(@model.node_with_value0(node, value))
        _ => None
      }
    StereoGain =>
      match slot {
        Value0 if @dsp.is_finite(value) =>
          Some(@model.node_with_value0(node, value))
        _ => None
      }
    StereoClip =>
      match slot {
        Value0 if @dsp.is_finite(value) && value > 0.0 =>
          Some(@model.node_with_value0(node, value))
        _ => None
      }
    StereoBiquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1()) =>
          Some(@model.node_with_value0(node, value))
        Value1 if valid_biquad_graph_params(sample_rate, node.value0(), value) =>
          Some(@model.node_with_value1(node, value))
        _ => None
      }
    StereoDelay =>
      match slot {
        Value0 if valid_delay_feedback(value) =>
          Some(@model.node_with_value0(node, value))
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples()) =>
              Some(@model.node_with_delay_samples(node, ds))
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
  node : @model.DspNode,
  slot : GraphParamSlot,
) -> Bool {
  match node.kind() {
    Delay =>
      match slot {
        Value0 =>
          match graph.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_feedback(node.value0())
              delay.set_delay_samples(node.delay_samples())
              true
            }
            None => false
          }
        DelaySamples =>
          match graph.delay_states[compiled_index] {
            Some(delay) => {
              delay.set_feedback(node.value0())
              delay.set_delay_samples(node.delay_samples())
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
            node.delay_samples(),
            node.value0(),
          )
        DelaySamples =>
          apply_stereo_delay_param_side_effect(
            graph.stereo_delay_left_states,
            graph.stereo_delay_right_states,
            compiled_index,
            node.delay_samples(),
            node.value0(),
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
fn make_graph_delay_state(node : @model.DspNode) -> DelayLine? {
  match node.kind() {
    Delay =>
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
