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
pub fn Dsp::apply_control(
  self : Dsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl([control])
}

///|
/// Apply a runtime control batch transactionally.
pub fn Dsp::apply_controls(
  self : Dsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn Dsp::validate_controls(
  self : Dsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.validate_controls_impl(controls)
}

///|
/// Allocation-conscious gate-on primitive for prevalidated host paths.
pub fn Dsp::gate_on_bool(self : Dsp, node_index : Int) -> Bool {
  self.0.apply_gate_control_bool_impl(node_index, true)
}

///|
/// Allocation-conscious gate-off primitive for prevalidated host paths.
pub fn Dsp::gate_off_bool(self : Dsp, node_index : Int) -> Bool {
  self.0.apply_gate_control_bool_impl(node_index, false)
}

///|
/// Allocation-conscious parameter primitive for prevalidated host paths.
pub fn Dsp::set_param_bool(
  self : Dsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.0.apply_param_control_bool_impl(node_index, slot, value)
}

///|
/// Allocation-conscious parameter validation for prevalidated host paths.
pub fn Dsp::can_set_param_bool(
  self : Dsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.0.can_param_control_bool_impl(node_index, slot, value)
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
pub fn Dsp::is_voice_finished(self : Dsp) -> Bool {
  let nodes = self.0.nodes
  let env_states = self.0.env_states
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].kind() is Adsr &&
      env_states[i] is Some(adsr) &&
      !(adsr.stage() is EnvStage::Idle) {
      return false
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
pub fn StereoDsp::apply_control(
  self : StereoDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl([control])
}

///|
/// Apply a runtime control batch transactionally.
pub fn StereoDsp::apply_controls(
  self : StereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn StereoDsp::validate_controls(
  self : StereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.validate_controls_impl(controls)
}

///|
pub fn CompiledGraph::apply_control_impl(
  self : CompiledGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.controls.begin(self.nodes)
  match self.prepare_control(control) {
    Err(error) => Err(error)
    Ok(_) => {
      self.commit_prepared_controls()
      Ok(())
    }
  }
}

///|
pub fn CompiledGraph::apply_controls_impl(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  match self.prepare_controls(controls) {
    Ok(_) => {
      self.commit_prepared_controls()
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
pub fn CompiledGraph::apply_controls_to_pair(
  self : CompiledGraph,
  other : CompiledGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  match self.prepare_controls(controls) {
    Err(error) => Err(error)
    Ok(_) =>
      match other.prepare_controls(controls) {
        Err(error) => Err(error)
        Ok(_) => {
          self.commit_prepared_controls()
          other.commit_prepared_controls()
          Ok(())
        }
      }
  }
}

///|
fn CompiledGraph::prepare_controls(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.controls.begin(self.nodes)
  for control in controls {
    match self.prepare_control(control) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn CompiledGraph::prepare_control(
  self : CompiledGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  let compiled_index = match self.compiled_index_result(control.node_index()) {
    Ok(index) => index
    Err(error) => return Err(error)
  }
  match control.kind() {
    GateOn | GateOff => {
      guard self.controls.targets[compiled_index] is Envelope(target) else {
        let kind = self.nodes[compiled_index].kind()
        if kind is Adsr {
          return Err(
            GraphControlError::MissingRuntimeState(control.node_index(), kind),
          )
        }
        return Err(
          GraphControlError::InvalidGateNode(control.node_index(), kind),
        )
      }
      target.gate = fold_gate_state(target.gate, control.kind() is GateOn)
      Ok(())
    }
    SetParam => {
      let slot = control.slot()
      let value = control.value()
      let node = self.controls.nodes[compiled_index]
      if !@model.node_accepts_slot(node, slot) {
        return Err(
          GraphControlError::InvalidSlotForNode(
            control.node_index(),
            node.kind(),
            slot,
          ),
        )
      }
      if !model_node_param_valid(node, slot, value, self.compile_sample_rate) {
        return Err(
          GraphControlError::InvalidParamValue(
            control.node_index(),
            node.kind(),
            slot,
            value,
          ),
        )
      }
      match slot {
        Value0 => @model.set_node_value0(node, value)
        Value1 => @model.set_node_value1(node, value)
        Value2 => @model.set_node_value2(node, value)
        Value3 => @model.set_node_value3(node, value)
        DelaySamples => @model.set_node_delay_samples(node, value.to_int())
      }
      self.controls.touched[compiled_index] = true
      Ok(())
    }
  }
}

///|
fn CompiledGraph::commit_prepared_controls(self : CompiledGraph) -> Unit {
  for i = 0; i < self.nodes.length(); i = i + 1 {
    if self.controls.touched[i] {
      let source = self.controls.nodes[i]
      let target = self.nodes[i]
      copy_node_parameters(source, target)
      match self.controls.targets[i] {
        Plain => ()
        Envelope(target) =>
          target.state.set_parameters(
            attack_ms=source.value0(),
            decay_ms=source.value1(),
            sustain=source.value2(),
            release_ms=source.value3(),
          )
        Delay(delay) => {
          delay.set_feedback(source.value0())
          delay.set_delay_samples(source.delay_samples())
        }
        StereoDelay(left, right) => {
          left.set_feedback(source.value0())
          left.set_delay_samples(source.delay_samples())
          right.set_feedback(source.value0())
          right.set_delay_samples(source.delay_samples())
        }
      }
    }
    match self.controls.targets[i] {
      Envelope(target) =>
        match target.gate {
          None => ()
          On => target.state.gate_on()
          Off => target.state.gate_off()
          OnThenOff => {
            target.state.gate_on()
            target.state.gate_off()
          }
        }
      _ => ()
    }
  }
}

///|
pub fn[T] Dsp::apply_controls_to_all(
  targets : Array[Result[Dsp, T]],
  controls : Array[GraphControl],
  wrap_error : (GraphControlError) -> T,
) -> Result[Unit, T] {
  for target in targets {
    match target {
      Err(error) => return Err(error)
      Ok(graph) =>
        match graph.0.prepare_controls(controls) {
          Ok(_) => ()
          Err(error) => return Err(wrap_error(error))
        }
    }
  }
  for target in targets {
    match target {
      Ok(graph) => graph.0.commit_prepared_controls()
      Err(_) =>
        abort("prepared target list changed during synchronous adoption")
    }
  }
  Ok(())
}

///|
pub fn CompiledGraph::validate_controls_impl(
  self : CompiledGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.prepare_controls(controls)
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
fn CompiledGraph::apply_gate_control_bool_impl(
  self : CompiledGraph,
  node_index : Int,
  gate_on : Bool,
) -> Bool {
  match self.compiled_index_for(node_index) {
    None => false
    Some(compiled_index) =>
      match self.env_states[compiled_index] {
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
  }
}

///|
fn CompiledGraph::apply_param_control_bool_impl(
  self : CompiledGraph,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  match self.compiled_index_for(node_index) {
    None => false
    Some(compiled_index) => {
      let node = self.nodes[compiled_index]
      if !set_model_node_param_in_place(
          node,
          slot,
          value,
          self.compile_sample_rate,
        ) {
        return false
      }
      apply_runtime_param_side_effect(self, compiled_index, node, slot)
    }
  }
}

///|
fn CompiledGraph::can_param_control_bool_impl(
  self : CompiledGraph,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  match self.compiled_index_for(node_index) {
    None => false
    Some(compiled_index) => {
      let node = self.nodes[compiled_index]
      model_node_param_valid(node, slot, value, self.compile_sample_rate) &&
      runtime_param_state_available(self, compiled_index, node, slot)
    }
  }
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
fn model_node_param_valid(
  node : @model.DspNode,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> Bool {
  match node.kind() {
    Constant => slot is Value0 && @dsp.is_finite(value)
    Oscillator => node.input0() < 0 && slot is Value0 && @dsp.is_finite(value)
    Adsr =>
      @dsp.is_finite(value) &&
      value >= 0.0 &&
      (match slot {
        Value0 | Value1 | Value3 => true
        Value2 => value <= 1.0
        _ => false
      })
    Noise => false
    Biquad =>
      match slot {
        Value0 => valid_biquad_graph_params(sample_rate, value, node.value1())
        Value1 => valid_biquad_graph_params(sample_rate, node.value0(), value)
        _ => false
      }
    Delay =>
      match slot {
        Value0 => valid_delay_feedback(value)
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) => valid_delay_samples(ds, node.delay_max_samples())
            _ => false
          }
        _ => false
      }
    Gain => slot is Value0 && @dsp.is_finite(value)
    Mul => false
    Mix => false
    Clip => slot is Value0 && @dsp.is_finite(value) && value > 0.0
    Output => false
    Pan => slot is Value0 && @dsp.is_finite(value)
    StereoGain => slot is Value0 && @dsp.is_finite(value)
    StereoClip => slot is Value0 && @dsp.is_finite(value) && value > 0.0
    StereoBiquad =>
      match slot {
        Value0 => valid_biquad_graph_params(sample_rate, value, node.value1())
        Value1 => valid_biquad_graph_params(sample_rate, node.value0(), value)
        _ => false
      }
    StereoDelay =>
      match slot {
        Value0 => valid_delay_feedback(value)
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) => valid_delay_samples(ds, node.delay_max_samples())
            _ => false
          }
        _ => false
      }
    StereoMixDown => false
    StereoOutput => false
  }
}

///|
fn runtime_param_state_available(
  graph : CompiledGraph,
  compiled_index : Int,
  node : @model.DspNode,
  slot : GraphParamSlot,
) -> Bool {
  match node.kind() {
    Adsr => graph.env_states[compiled_index] is Some(_)
    Delay =>
      match slot {
        Value0 | DelaySamples => graph.delay_states[compiled_index] is Some(_)
        _ => false
      }
    StereoDelay =>
      match slot {
        Value0 | DelaySamples =>
          graph.stereo_delay_left_states[compiled_index] is Some(_) &&
          graph.stereo_delay_right_states[compiled_index] is Some(_)
        _ => false
      }
    Constant
    | Oscillator
    | Biquad
    | Gain
    | Clip
    | Pan
    | StereoGain
    | StereoClip
    | StereoBiquad => true
    _ => false
  }
}

///|
fn set_model_node_param_in_place(
  node : @model.DspNode,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> Bool {
  match node.kind() {
    Constant =>
      match slot {
        Value0 if @dsp.is_finite(value) => {
          @model.set_node_value0(node, value)
          true
        }
        _ => false
      }
    Oscillator =>
      if node.input0() >= 0 {
        false
      } else {
        match slot {
          Value0 if @dsp.is_finite(value) => {
            @model.set_node_value0(node, value)
            true
          }
          _ => false
        }
      }
    Adsr => {
      if !model_node_param_valid(node, slot, value, sample_rate) {
        return false
      }
      match slot {
        Value0 => @model.set_node_value0(node, value)
        Value1 => @model.set_node_value1(node, value)
        Value2 => @model.set_node_value2(node, value)
        Value3 => @model.set_node_value3(node, value)
        _ => return false
      }
      true
    }
    Noise => false
    Biquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1()) => {
          @model.set_node_value0(node, value)
          true
        }
        Value1 if valid_biquad_graph_params(sample_rate, node.value0(), value) => {
          @model.set_node_value1(node, value)
          true
        }
        _ => false
      }
    Delay =>
      match slot {
        Value0 if valid_delay_feedback(value) => {
          @model.set_node_value0(node, value)
          true
        }
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples()) => {
              @model.set_node_delay_samples(node, ds)
              true
            }
            _ => false
          }
        _ => false
      }
    Gain =>
      match slot {
        Value0 if @dsp.is_finite(value) => {
          @model.set_node_value0(node, value)
          true
        }
        _ => false
      }
    Mul => false
    Mix => false
    Clip =>
      match slot {
        Value0 if @dsp.is_finite(value) && value > 0.0 => {
          @model.set_node_value0(node, value)
          true
        }
        _ => false
      }
    Output => false
    Pan =>
      match slot {
        Value0 if @dsp.is_finite(value) => {
          @model.set_node_value0(node, value)
          true
        }
        _ => false
      }
    StereoGain =>
      match slot {
        Value0 if @dsp.is_finite(value) => {
          @model.set_node_value0(node, value)
          true
        }
        _ => false
      }
    StereoClip =>
      match slot {
        Value0 if @dsp.is_finite(value) && value > 0.0 => {
          @model.set_node_value0(node, value)
          true
        }
        _ => false
      }
    StereoBiquad =>
      match slot {
        Value0 if valid_biquad_graph_params(sample_rate, value, node.value1()) => {
          @model.set_node_value0(node, value)
          true
        }
        Value1 if valid_biquad_graph_params(sample_rate, node.value0(), value) => {
          @model.set_node_value1(node, value)
          true
        }
        _ => false
      }
    StereoDelay =>
      match slot {
        Value0 if valid_delay_feedback(value) => {
          @model.set_node_value0(node, value)
          true
        }
        DelaySamples =>
          match exact_int_value(value) {
            Some(ds) if valid_delay_samples(ds, node.delay_max_samples()) => {
              @model.set_node_delay_samples(node, ds)
              true
            }
            _ => false
          }
        _ => false
      }
    StereoMixDown => false
    StereoOutput => false
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
    Adsr => {
      if !model_node_param_valid(node, slot, value, sample_rate) {
        return None
      }
      match slot {
        Value0 => Some(@model.node_with_value0(node, value))
        Value1 => Some(@model.node_with_value1(node, value))
        Value2 => Some(@model.node_with_value2(node, value))
        Value3 => Some(@model.node_with_value3(node, value))
        _ => None
      }
    }
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
    Adsr =>
      match graph.env_states[compiled_index] {
        Some(env) => {
          env.set_parameters(
            attack_ms=node.value0(),
            decay_ms=node.value1(),
            sustain=node.value2(),
            release_ms=node.value3(),
          )
          true
        }
        None => false
      }
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
