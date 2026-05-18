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
/// Visibility: `pub`, not `pub(open)`. The trait is intended for the six
/// canonical wrapper types defined in this package; external types should
/// compose with these wrappers rather than implement the trait directly.
/// If a downstream use case for an external impl emerges, the contract to
/// honour is: (a) `apply_control` returns the same `GraphControlError`
/// variants the canonical wrappers do, (b) `apply_controls` is
/// transactional — validate the whole batch first, then apply, leaving
/// the graph unchanged on the first error.
///
/// WHY 12 identical impl blocks below: MoonBit has no blanket impls or
/// default trait methods. Each of the 6 wrapper types (CompiledDsp,
/// CompiledStereoDsp, CompiledDspHotSwap, CompiledStereoDspHotSwap,
/// CompiledDspTopologyController, CompiledStereoDspTopologyController)
/// must declare both methods individually, all delegating to
/// `.0.apply_control_impl()` / `.0.apply_controls_impl()`. This is
/// irreducible boilerplate under the current type system.
pub trait GraphControllable {
  apply_control(Self, GraphControl) -> Result[Unit, GraphControlError]
  apply_controls(Self, Array[GraphControl]) -> Result[Unit, GraphControlError]
}

///|
pub impl GraphControllable for CompiledDsp with apply_control(self, control) -> Result[
  Unit,
  GraphControlError,
] {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledDsp with apply_controls(self, controls) -> Result[
  Unit,
  GraphControlError,
] {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledStereoDsp with apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledStereoDsp with apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledDspHotSwap with apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledDspHotSwap with apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledStereoDspHotSwap with apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledStereoDspHotSwap with apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledDspTopologyController with apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledDspTopologyController with apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}

///|
pub impl GraphControllable for CompiledStereoDspTopologyController with apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.0.apply_control_impl(control)
}

///|
pub impl GraphControllable for CompiledStereoDspTopologyController with apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.0.apply_controls_impl(controls)
}
