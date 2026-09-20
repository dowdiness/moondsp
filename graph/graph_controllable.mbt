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
/// WHY 12 near-identical impl blocks below: MoonBit has no blanket impls or
/// default trait methods. Each of the 6 wrapper types (Dsp,
/// StereoDsp, DspHotSwap, StereoDspHotSwap,
/// DspTopologyController, StereoDspTopologyController)
/// must declare both methods individually. The compiled wrappers delegate to
/// `graph/internal/runtime`; staging wrappers delegate to their local state.
/// This is irreducible boilerplate under the current type system.
pub trait GraphControllable {
  fn apply_control(Self, GraphControl) -> Result[Unit, GraphControlError]
  fn apply_controls(Self, Array[GraphControl]) -> Result[
    Unit,
    GraphControlError,
  ]
}

///|
pub impl GraphControllable for Dsp with fn apply_control(self, control) -> Result[
  Unit,
  GraphControlError,
] {
  graph_control_result_from_runtime(self.raw().apply_control(control.raw()))
}

///|
pub impl GraphControllable for Dsp with fn apply_controls(self, controls) -> Result[
  Unit,
  GraphControlError,
] {
  graph_control_result_from_runtime(
    self.raw().apply_controls(graph_controls_to_model(controls)),
  )
}

///|
pub impl GraphControllable for StereoDsp with fn apply_control(self, control) -> Result[
  Unit,
  GraphControlError,
] {
  graph_control_result_from_runtime(self.raw().apply_control(control.raw()))
}

///|
pub impl GraphControllable for StereoDsp with fn apply_controls(self, controls) -> Result[
  Unit,
  GraphControlError,
] {
  graph_control_result_from_runtime(
    self.raw().apply_controls(graph_controls_to_model(controls)),
  )
}

///|
pub impl GraphControllable for DspHotSwap with fn apply_control(self, control) -> Result[
  Unit,
  GraphControlError,
] {
  self.apply_control(control)
}

///|
pub impl GraphControllable for DspHotSwap with fn apply_controls(self, controls) -> Result[
  Unit,
  GraphControlError,
] {
  self.apply_controls(controls)
}

///|
pub impl GraphControllable for StereoDspHotSwap with fn apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.apply_control(control)
}

///|
pub impl GraphControllable for StereoDspHotSwap with fn apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.apply_controls(controls)
}

///|
pub impl GraphControllable for DspTopologyController with fn apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.apply_control(control)
}

///|
pub impl GraphControllable for DspTopologyController with fn apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.apply_controls(controls)
}

///|
pub impl GraphControllable for StereoDspTopologyController with fn apply_control(
  self,
  control,
) -> Result[Unit, GraphControlError] {
  self.apply_control(control)
}

///|
pub impl GraphControllable for StereoDspTopologyController with fn apply_controls(
  self,
  controls,
) -> Result[Unit, GraphControlError] {
  self.apply_controls(controls)
}

///|
/// Apply one control batch atomically to every successful mono target.
/// All targets are prepared before any target is committed.
pub fn[T] Dsp::apply_controls_to_all(
  targets : Array[Result[Dsp, T]],
  controls : Array[GraphControl],
  wrap_error : (GraphControlError) -> T,
) -> Result[Unit, T] {
  let raw_targets : Array[Result[@runtime.Dsp, T]] = []
  raw_targets.reserve_capacity(targets.length())
  for target in targets {
    match target {
      Ok(graph) => raw_targets.push(Ok(graph.raw()))
      Err(error) => raw_targets.push(Err(error))
    }
  }
  @runtime.Dsp::apply_controls_to_all(
    raw_targets,
    graph_controls_to_model(controls),
    error => wrap_error(graph_control_error_from_runtime(error)),
  )
}
