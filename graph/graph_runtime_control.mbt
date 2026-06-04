///|
/// Failure reason for runtime graph control APIs.
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
pub impl Show for GraphControlError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn graph_control_error_from_runtime(
  error : @runtime.GraphControlError,
) -> GraphControlError {
  match error {
    @runtime.GraphControlError::InvalidNodeIndex(index) =>
      GraphControlError::InvalidNodeIndex(index)
    @runtime.GraphControlError::OrphanNode(index) =>
      GraphControlError::OrphanNode(index)
    @runtime.GraphControlError::InvalidGateNode(index, kind) =>
      GraphControlError::InvalidGateNode(index, dsp_node_kind_from_model(kind))
    @runtime.GraphControlError::InvalidSlotForNode(index, kind, slot) =>
      GraphControlError::InvalidSlotForNode(
        index,
        dsp_node_kind_from_model(kind),
        graph_param_slot_from_model(slot),
      )
    @runtime.GraphControlError::InvalidParamValue(index, kind, slot, value) =>
      GraphControlError::InvalidParamValue(
        index,
        dsp_node_kind_from_model(kind),
        graph_param_slot_from_model(slot),
        value,
      )
    @runtime.GraphControlError::MissingRuntimeState(index, kind) =>
      GraphControlError::MissingRuntimeState(
        index,
        dsp_node_kind_from_model(kind),
      )
  }
}

///|
fn graph_control_result_from_runtime(
  result : Result[Unit, @runtime.GraphControlError],
) -> Result[Unit, GraphControlError] {
  match result {
    Ok(_) => Ok(())
    Err(error) => Err(graph_control_error_from_runtime(error))
  }
}

///|
/// Trigger `gate_on()` on an ADSR node using its original authoring index.
pub fn CompiledDsp::gate_on(
  self : CompiledDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on an ADSR node using its original authoring index.
pub fn CompiledDsp::gate_off(
  self : CompiledDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled node using its original authoring
/// index.
pub fn CompiledDsp::set_param(
  self : CompiledDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn CompiledDsp::apply_control(
  self : CompiledDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(self.raw().apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally.
pub fn CompiledDsp::apply_controls(
  self : CompiledDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn CompiledDsp::validate_controls(
  self : CompiledDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().validate_controls(graph_controls_to_model(controls)),
  )
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
  self.raw().is_voice_finished()
}

///|
/// Trigger `gate_on()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_on(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn CompiledStereoDsp::gate_off(
  self : CompiledStereoDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
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
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn CompiledStereoDsp::apply_control(
  self : CompiledStereoDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(self.raw().apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally.
pub fn CompiledStereoDsp::apply_controls(
  self : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn CompiledStereoDsp::validate_controls(
  self : CompiledStereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().validate_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Trigger runtime gate-on through a mono hot-swap wrapper.
pub fn CompiledDspHotSwap::gate_on(
  self : CompiledDspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a mono hot-swap wrapper.
pub fn CompiledDspHotSwap::gate_off(
  self : CompiledDspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a mono hot-swap wrapper.
pub fn CompiledDspHotSwap::set_param(
  self : CompiledDspHotSwap,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a mono hot-swap wrapper.
pub fn CompiledDspHotSwap::apply_control(
  self : CompiledDspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
/// Apply a runtime control batch transactionally through a mono hot-swap wrapper.
pub fn CompiledDspHotSwap::apply_controls(
  self : CompiledDspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Trigger runtime gate-on through a stereo hot-swap wrapper.
pub fn CompiledStereoDspHotSwap::gate_on(
  self : CompiledStereoDspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a stereo hot-swap wrapper.
pub fn CompiledStereoDspHotSwap::gate_off(
  self : CompiledStereoDspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a stereo hot-swap wrapper.
pub fn CompiledStereoDspHotSwap::set_param(
  self : CompiledStereoDspHotSwap,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a stereo hot-swap wrapper.
pub fn CompiledStereoDspHotSwap::apply_control(
  self : CompiledStereoDspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
/// Apply a runtime control batch transactionally through a stereo hot-swap wrapper.
pub fn CompiledStereoDspHotSwap::apply_controls(
  self : CompiledStereoDspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Trigger runtime gate-on through a mono topology controller.
pub fn CompiledDspTopologyController::gate_on(
  self : CompiledDspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a mono topology controller.
pub fn CompiledDspTopologyController::gate_off(
  self : CompiledDspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a mono topology controller.
pub fn CompiledDspTopologyController::set_param(
  self : CompiledDspTopologyController,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a mono topology controller.
pub fn CompiledDspTopologyController::apply_control(
  self : CompiledDspTopologyController,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
/// Apply a runtime control batch transactionally through a mono topology controller.
pub fn CompiledDspTopologyController::apply_controls(
  self : CompiledDspTopologyController,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
/// Trigger runtime gate-on through a stereo topology controller.
pub fn CompiledStereoDspTopologyController::gate_on(
  self : CompiledStereoDspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a stereo topology controller.
pub fn CompiledStereoDspTopologyController::gate_off(
  self : CompiledStereoDspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a stereo topology controller.
pub fn CompiledStereoDspTopologyController::set_param(
  self : CompiledStereoDspTopologyController,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a stereo topology controller.
pub fn CompiledStereoDspTopologyController::apply_control(
  self : CompiledStereoDspTopologyController,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
/// Apply a runtime control batch transactionally through a stereo topology
/// controller.
pub fn CompiledStereoDspTopologyController::apply_controls(
  self : CompiledStereoDspTopologyController,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
fn graph_controls_to_model(
  controls : Array[GraphControl],
) -> Array[@model.GraphControl] {
  let raw_controls = Array::new(capacity=controls.length())
  for control in controls {
    raw_controls.push(control.raw())
  }
  raw_controls
}

///|
fn updated_node_param_result(
  node : DspNode,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
  sample_rate : Double,
) -> Result[DspNode, GraphControlError] {
  match
    @runtime.updated_model_node_param_result(
      node.raw(),
      node_index,
      slot.to_model(),
      value,
      sample_rate,
    ) {
    Ok(updated) => Ok(DspNode::from_model(updated))
    Err(error) => Err(graph_control_error_from_runtime(error))
  }
}
