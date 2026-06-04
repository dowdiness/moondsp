///|
pub(open) trait GraphDebuggable {
  ///| Enable per-node runtime validation during process().
  fn enable_debug_validation(Self) -> Unit
  ///| Disable debug validation and clear accumulated errors.
  fn disable_debug_validation(Self) -> Unit
  ///| Validation errors captured during the last debug process() call.
  fn last_validation_errors(Self) -> Array[GraphValidationError]
}

///|
pub impl GraphDebuggable for CompiledDsp with fn enable_debug_validation(self) {
  self.raw().enable_debug_validation()
}

///|
pub impl GraphDebuggable for CompiledDsp with fn disable_debug_validation(self) {
  self.raw().disable_debug_validation()
}

///|
pub impl GraphDebuggable for CompiledDsp with fn last_validation_errors(self) {
  graph_validation_errors_from_runtime(self.raw().last_validation_errors())
}

///|
pub impl GraphDebuggable for CompiledStereoDsp with fn enable_debug_validation(
  self,
) {
  self.raw().enable_debug_validation()
}

///|
pub impl GraphDebuggable for CompiledStereoDsp with fn disable_debug_validation(
  self,
) {
  self.raw().disable_debug_validation()
}

///|
pub impl GraphDebuggable for CompiledStereoDsp with fn last_validation_errors(
  self,
) {
  graph_validation_errors_from_runtime(self.raw().last_validation_errors())
}
