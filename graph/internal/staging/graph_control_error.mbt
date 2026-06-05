///|
/// Failure reason for staging-layer runtime control APIs.
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
fn graph_control_error_from_runtime(
  error : @runtime.GraphControlError,
) -> GraphControlError {
  match error {
    @runtime.GraphControlError::InvalidNodeIndex(index) =>
      GraphControlError::InvalidNodeIndex(index)
    @runtime.GraphControlError::OrphanNode(index) =>
      GraphControlError::OrphanNode(index)
    @runtime.GraphControlError::InvalidGateNode(index, kind) =>
      GraphControlError::InvalidGateNode(index, kind)
    @runtime.GraphControlError::InvalidSlotForNode(index, kind, slot) =>
      GraphControlError::InvalidSlotForNode(index, kind, slot)
    @runtime.GraphControlError::InvalidParamValue(index, kind, slot, value) =>
      GraphControlError::InvalidParamValue(index, kind, slot, value)
    @runtime.GraphControlError::MissingRuntimeState(index, kind) =>
      GraphControlError::MissingRuntimeState(index, kind)
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
fn[T] graph_control_value_result_from_runtime(
  result : Result[T, @runtime.GraphControlError],
) -> Result[T, GraphControlError] {
  match result {
    Ok(value) => Ok(value)
    Err(error) => Err(graph_control_error_from_runtime(error))
  }
}
