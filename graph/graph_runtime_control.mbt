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
fn graph_control_error_from_staging(
  error : @staging.GraphControlError,
) -> GraphControlError {
  match error {
    @staging.GraphControlError::InvalidNodeIndex(index) =>
      GraphControlError::InvalidNodeIndex(index)
    @staging.GraphControlError::OrphanNode(index) =>
      GraphControlError::OrphanNode(index)
    @staging.GraphControlError::InvalidGateNode(index, kind) =>
      GraphControlError::InvalidGateNode(index, dsp_node_kind_from_model(kind))
    @staging.GraphControlError::InvalidSlotForNode(index, kind, slot) =>
      GraphControlError::InvalidSlotForNode(
        index,
        dsp_node_kind_from_model(kind),
        graph_param_slot_from_model(slot),
      )
    @staging.GraphControlError::InvalidParamValue(index, kind, slot, value) =>
      GraphControlError::InvalidParamValue(
        index,
        dsp_node_kind_from_model(kind),
        graph_param_slot_from_model(slot),
        value,
      )
    @staging.GraphControlError::MissingRuntimeState(index, kind) =>
      GraphControlError::MissingRuntimeState(
        index,
        dsp_node_kind_from_model(kind),
      )
  }
}

///|
fn graph_control_result_from_staging(
  result : Result[Unit, @staging.GraphControlError],
) -> Result[Unit, GraphControlError] {
  match result {
    Ok(_) => Ok(())
    Err(error) => Err(graph_control_error_from_staging(error))
  }
}

///|
/// Trigger `gate_on()` on an ADSR node using its original authoring index.
pub fn Dsp::gate_on(
  self : Dsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on an ADSR node using its original authoring index.
pub fn Dsp::gate_off(
  self : Dsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled node using its original authoring
/// index.
pub fn Dsp::set_param(
  self : Dsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn Dsp::apply_control(
  self : Dsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(self.raw().apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally.
pub fn Dsp::apply_controls(
  self : Dsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn Dsp::validate_controls(
  self : Dsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().validate_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Allocation-conscious gate-on primitive for prevalidated host paths.
pub fn Dsp::gate_on_bool(self : Dsp, node_index : Int) -> Bool {
  self.raw().gate_on_bool(node_index)
}

///|
/// Allocation-conscious gate-off primitive for prevalidated host paths.
pub fn Dsp::gate_off_bool(self : Dsp, node_index : Int) -> Bool {
  self.raw().gate_off_bool(node_index)
}

///|
/// Allocation-conscious parameter primitive for prevalidated host paths.
pub fn Dsp::set_param_bool(
  self : Dsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.raw().set_param_bool(node_index, slot.to_model(), value)
}

///|
/// Allocation-conscious parameter validation for prevalidated host paths.
pub fn Dsp::can_set_param_bool(
  self : Dsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Bool {
  self.raw().can_set_param_bool(node_index, slot.to_model(), value)
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
  self.raw().is_voice_finished()
}

///|
/// Reset mutable runtime state and restore compile-time node parameters.
pub fn Dsp::reset_runtime_state(self : Dsp) -> Unit {
  self.raw().reset_runtime_state()
}

///|
/// Trigger `gate_on()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn StereoDsp::gate_on(
  self : StereoDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger `gate_off()` on a stereo-graph ADSR node using its original
/// authoring index.
pub fn StereoDsp::gate_off(
  self : StereoDsp,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter on a compiled stereo node using its original
/// authoring index.
pub fn StereoDsp::set_param(
  self : StereoDsp,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message, returning a specific rejection reason.
pub fn StereoDsp::apply_control(
  self : StereoDsp,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(self.raw().apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally.
pub fn StereoDsp::apply_controls(
  self : StereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Validate a runtime control batch without mutating the compiled graph.
pub fn StereoDsp::validate_controls(
  self : StereoDsp,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_runtime(
    self.raw().validate_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Trigger runtime gate-on through a mono hot-swap wrapper.
pub fn DspHotSwap::gate_on(
  self : DspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a mono hot-swap wrapper.
pub fn DspHotSwap::gate_off(
  self : DspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a mono hot-swap wrapper.
pub fn DspHotSwap::set_param(
  self : DspHotSwap,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a mono hot-swap wrapper.
pub fn DspHotSwap::apply_control(
  self : DspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(self.0.apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally through a mono hot-swap wrapper.
pub fn DspHotSwap::apply_controls(
  self : DspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(
    self.0.apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Trigger runtime gate-on through a stereo hot-swap wrapper.
pub fn StereoDspHotSwap::gate_on(
  self : StereoDspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a stereo hot-swap wrapper.
pub fn StereoDspHotSwap::gate_off(
  self : StereoDspHotSwap,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a stereo hot-swap wrapper.
pub fn StereoDspHotSwap::set_param(
  self : StereoDspHotSwap,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a stereo hot-swap wrapper.
pub fn StereoDspHotSwap::apply_control(
  self : StereoDspHotSwap,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(self.0.apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally through a stereo hot-swap wrapper.
pub fn StereoDspHotSwap::apply_controls(
  self : StereoDspHotSwap,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(
    self.0.apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Trigger runtime gate-on through a mono topology controller.
pub fn DspTopologyController::gate_on(
  self : DspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a mono topology controller.
pub fn DspTopologyController::gate_off(
  self : DspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a mono topology controller.
pub fn DspTopologyController::set_param(
  self : DspTopologyController,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a mono topology controller.
pub fn DspTopologyController::apply_control(
  self : DspTopologyController,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(self.0.apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally through a mono topology controller.
pub fn DspTopologyController::apply_controls(
  self : DspTopologyController,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(
    self.0.apply_controls(graph_controls_to_model(controls)),
  )
}

///|
/// Trigger runtime gate-on through a stereo topology controller.
pub fn StereoDspTopologyController::gate_on(
  self : StereoDspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_on(node_index))
}

///|
/// Trigger runtime gate-off through a stereo topology controller.
pub fn StereoDspTopologyController::gate_off(
  self : StereoDspTopologyController,
  node_index : Int,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::gate_off(node_index))
}

///|
/// Update a runtime parameter through a stereo topology controller.
pub fn StereoDspTopologyController::set_param(
  self : StereoDspTopologyController,
  node_index : Int,
  slot : GraphParamSlot,
  value : Double,
) -> Result[Unit, GraphControlError] {
  self.apply_control(GraphControl::set_param(node_index, slot, value))
}

///|
/// Apply one runtime control message through a stereo topology controller.
pub fn StereoDspTopologyController::apply_control(
  self : StereoDspTopologyController,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(self.0.apply_control(control.raw()))
}

///|
/// Apply a runtime control batch transactionally through a stereo topology
/// controller.
pub fn StereoDspTopologyController::apply_controls(
  self : StereoDspTopologyController,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  graph_control_result_from_staging(
    self.0.apply_controls(graph_controls_to_model(controls)),
  )
}

///|
fn graph_controls_to_model(
  controls : Array[GraphControl],
) -> Array[@model.GraphControl] {
  let raw_controls = Array(capacity=controls.length())
  for control in controls {
    raw_controls.push(control.raw())
  }
  raw_controls
}
