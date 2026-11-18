///|
/// Failure reason for staging-layer runtime control APIs.
#derive(Debug)
pub enum GraphControlError {
  InvalidNodeIndex(Int32)
  /// The authoring node existed but was eliminated by graph optimization.
  OrphanNode(Int32)
  InvalidGateNode(Int32, DspNodeKind)
  InvalidSlotForNode(Int32, DspNodeKind, GraphParamSlot)
  InvalidParamValue(Int32, DspNodeKind, GraphParamSlot, Double)
  MissingRuntimeState(Int32, DspNodeKind)
}

///|
pub extend GraphControlError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub impl Show for GraphControlError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend GraphControlError with Show::{to_string, output}

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
