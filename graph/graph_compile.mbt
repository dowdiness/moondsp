///|
/// Executable buffer-based DSP graph compiled from `DspNode`s.
///
/// Public facade wrapper; implementation lives in `graph/internal/runtime`.
struct CompiledDsp(@runtime.CompiledDsp)

///|
/// Executable terminal-stereo graph compiled from `DspNode`s.
///
/// Public facade wrapper; implementation lives in `graph/internal/runtime`.
struct CompiledStereoDsp(@runtime.CompiledStereoDsp)

///|
fn CompiledDsp::from_internal(raw : @runtime.CompiledDsp) -> CompiledDsp {
  CompiledDsp(raw)
}

///|
fn CompiledDsp::raw(self : CompiledDsp) -> @runtime.CompiledDsp {
  self.0
}

///|
fn CompiledDsp::raw_graph(self : CompiledDsp) -> @runtime.CompiledGraph {
  self.0.raw_graph()
}

///|
fn CompiledStereoDsp::from_internal(
  raw : @runtime.CompiledStereoDsp,
) -> CompiledStereoDsp {
  CompiledStereoDsp(raw)
}

///|
fn CompiledStereoDsp::raw(
  self : CompiledStereoDsp,
) -> @runtime.CompiledStereoDsp {
  self.0
}

///|
fn CompiledStereoDsp::raw_graph(
  self : CompiledStereoDsp,
) -> @runtime.CompiledGraph {
  self.0.raw_graph()
}

///|
/// Number of non-finite samples replaced with 0.0 during the most recent
/// process() call. Returns 0 if output was clean.
pub fn CompiledDsp::last_sanitized_count(self : CompiledDsp) -> Int {
  self.0.last_sanitized_count()
}

///|
pub fn CompiledStereoDsp::last_sanitized_count(self : CompiledStereoDsp) -> Int {
  self.0.last_sanitized_count()
}

///|
/// True when the compiled graph contains feedback (back) edges that require
/// per-sample processing with self-registers.
pub fn CompiledDsp::has_feedback_edges(self : CompiledDsp) -> Bool {
  self.0.has_feedback_edges()
}

///|
pub fn CompiledStereoDsp::has_feedback_edges(self : CompiledStereoDsp) -> Bool {
  self.0.has_feedback_edges()
}

///|
/// Compile a declarative mono graph into an executable buffer graph.
///
/// Accepts a `CompiledTemplate` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// (e.g., no reachable `Output`, invalid feedback cycle, missing node
/// inputs). Produce the input via `CompiledTemplate::analyze(nodes)` or
/// `GraphBuilder::analyze`.
pub fn CompiledDsp::compile(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> CompiledDsp? {
  @runtime.CompiledDsp::compile(compiled_template.raw(), context).map(
    CompiledDsp::from_internal,
  )
}

///|
/// Compile without optimization — used by topology controllers where authoring
/// indices must be preserved for runtime controls.
fn CompiledDsp::compile_raw(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledDsp? {
  @runtime.CompiledDsp::compile_raw(dsp_nodes_to_model(nodes), context).map(
    CompiledDsp::from_internal,
  )
}

///|
/// Compile a declarative terminal-stereo graph into an executable
/// stereo graph.
///
/// Accepts a `CompiledTemplate` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// — including the stereo-specific requirement of a single reachable
/// `StereoOutput`.
pub fn CompiledStereoDsp::compile(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> CompiledStereoDsp? {
  @runtime.CompiledStereoDsp::compile(compiled_template.raw(), context).map(
    CompiledStereoDsp::from_internal,
  )
}

///|
fn CompiledStereoDsp::compile_raw(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledStereoDsp? {
  @runtime.CompiledStereoDsp::compile_raw(dsp_nodes_to_model(nodes), context).map(
    CompiledStereoDsp::from_internal,
  )
}

///|
fn CompiledDsp::compiled_buffer_capacity(self : CompiledDsp) -> Int {
  self.0.compiled_buffer_capacity()
}

///|
fn CompiledStereoDsp::compiled_buffer_capacity(self : CompiledStereoDsp) -> Int {
  self.0.compiled_buffer_capacity()
}
