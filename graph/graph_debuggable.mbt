///|
/// Capability trait for debug validation of compiled DSP graphs.
///
/// Both mono and stereo compiled graphs support enabling debug validation
/// mode, which checks node inputs and state before each process call.
pub(open) trait GraphDebuggable {
  enable_debug_validation(Self) -> Unit
  disable_debug_validation(Self) -> Unit
  last_validation_errors(Self) -> Array[GraphValidationError]
}

///|
pub impl GraphDebuggable for CompiledDsp with enable_debug_validation(self) {
  self.0.debug_validate = true
}

///|
pub impl GraphDebuggable for CompiledDsp with disable_debug_validation(self) {
  self.0.debug_validate = false
  self.0.last_validation_errors = []
}

///|
pub impl GraphDebuggable for CompiledDsp with last_validation_errors(self) {
  self.0.last_validation_errors
}

///|
pub impl GraphDebuggable for CompiledStereoDsp with enable_debug_validation(
  self,
) {
  self.0.debug_validate = true
}

///|
pub impl GraphDebuggable for CompiledStereoDsp with disable_debug_validation(
  self,
) {
  self.0.debug_validate = false
  self.0.last_validation_errors = []
}

///|
pub impl GraphDebuggable for CompiledStereoDsp with last_validation_errors(self) {
  self.0.last_validation_errors
}
