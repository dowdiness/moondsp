///|
pub(all) enum GraphValidationError {
  InvalidInput0(Int, Int, Int)
  InvalidInput1(Int, Int, Int)
  InvalidStateIndex(Int, String)
} derive(Debug, Eq)

///|
pub impl Show for GraphValidationError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn graph_validation_error_from_runtime(
  error : @runtime.GraphValidationError,
) -> GraphValidationError {
  match error {
    @runtime.GraphValidationError::InvalidInput0(index, input, max_valid) =>
      GraphValidationError::InvalidInput0(index, input, max_valid)
    @runtime.GraphValidationError::InvalidInput1(index, input, max_valid) =>
      GraphValidationError::InvalidInput1(index, input, max_valid)
    @runtime.GraphValidationError::InvalidStateIndex(index, kind) =>
      GraphValidationError::InvalidStateIndex(index, kind)
  }
}

///|
fn graph_validation_errors_from_runtime(
  errors : Array[@runtime.GraphValidationError],
) -> Array[GraphValidationError] {
  let facade_errors = Array::new(capacity=errors.length())
  for error in errors {
    facade_errors.push(graph_validation_error_from_runtime(error))
  }
  facade_errors
}
