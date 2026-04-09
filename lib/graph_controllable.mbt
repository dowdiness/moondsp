///|
/// Capability trait for runtime control of compiled DSP graphs.
///
/// Both mono and stereo compiled graphs, their hot-swap wrappers, and their
/// topology controllers share the same control interface. This trait captures
/// that shared interface so consumer code can be written generically over any
/// controllable graph.
///
/// The `process` method is intentionally excluded because mono and stereo
/// graphs have different output arity (one buffer vs. two).
///
/// WHY 12 identical impl blocks below: MoonBit has no blanket impls or
/// default trait methods. Each of the 6 wrapper types (CompiledDsp,
/// CompiledStereoDsp, CompiledDspHotSwap, CompiledStereoDspHotSwap,
/// CompiledDspTopologyController, CompiledStereoDspTopologyController)
/// must declare both methods individually, all delegating to
/// `.0.apply_control_impl()` / `.0.apply_controls_impl()`. This is
/// irreducible boilerplate under the current type system.
pub(open) trait GraphControllable {
  apply_control(Self, GraphControl) -> Bool
  apply_controls(Self, Array[GraphControl]) -> Bool
}

///|
pub impl GraphControllable for CompiledDsp with apply_control(self, control) -> Bool {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledDsp with apply_controls(self, controls) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledStereoDsp with apply_control(
  self,
  control,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledStereoDsp with apply_controls(
  self,
  controls,
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledDspHotSwap with apply_control(
  self,
  control,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledDspHotSwap with apply_controls(
  self,
  controls,
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledStereoDspHotSwap with apply_control(
  self,
  control,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledStereoDspHotSwap with apply_controls(
  self,
  controls,
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledDspTopologyController with apply_control(
  self,
  control,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledDspTopologyController with apply_controls(
  self,
  controls,
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledStereoDspTopologyController with apply_control(
  self,
  control,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledStereoDspTopologyController with apply_controls(
  self,
  controls,
) -> Bool {
  self.0.apply_controls_impl(controls)
}
