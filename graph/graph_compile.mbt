///|
/// Executable buffer-based DSP graph compiled from `DspNode`s.
///
/// Public facade wrapper; implementation lives in `graph/internal/runtime`.
struct Dsp(@runtime.Dsp)

///|
/// Executable terminal-stereo graph compiled from `DspNode`s.
///
/// Public facade wrapper; implementation lives in `graph/internal/runtime`.
struct StereoDsp(@runtime.StereoDsp)

///|
fn Dsp::from_internal(raw : @runtime.Dsp) -> Dsp {
  Dsp(raw)
}

///|
fn Dsp::raw(self : Dsp) -> @runtime.Dsp {
  self.0
}

///|
fn StereoDsp::from_internal(raw : @runtime.StereoDsp) -> StereoDsp {
  StereoDsp(raw)
}

///|
fn StereoDsp::raw(self : StereoDsp) -> @runtime.StereoDsp {
  self.0
}

///|
/// Number of non-finite samples replaced with 0.0 during the most recent
/// process() call. Returns 0 if output was clean.
pub fn Dsp::last_sanitized_count(self : Dsp) -> Int {
  self.0.last_sanitized_count()
}

///|
pub fn StereoDsp::last_sanitized_count(self : StereoDsp) -> Int {
  self.0.last_sanitized_count()
}

///|
/// True when the compiled graph contains feedback (back) edges that require
/// per-sample processing with self-registers.
pub fn Dsp::has_feedback_edges(self : Dsp) -> Bool {
  self.0.has_feedback_edges()
}

///|
pub fn StereoDsp::has_feedback_edges(self : StereoDsp) -> Bool {
  self.0.has_feedback_edges()
}

///|
/// Compile a declarative mono graph into an executable buffer graph.
///
/// Accepts a `AnalyzedGraph` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// (e.g., no reachable `Output`, invalid feedback cycle, missing node
/// inputs). Produce the input via `AnalyzedGraph::analyze(nodes)` or
/// `GraphBuilder::analyze`.
pub fn Dsp::compile(
  compiled_template : AnalyzedGraph,
  context : DspContext,
) -> Dsp? {
  @runtime.Dsp::compile(compiled_template.raw(), context).map(
    Dsp::from_internal,
  )
}

///|
/// Compile a declarative terminal-stereo graph into an executable
/// stereo graph.
///
/// Accepts a `AnalyzedGraph` (the runtime exchange boundary per
/// ADR-0010) and returns `None` if the template's topology is rejected
/// — including the stereo-specific requirement of a single reachable
/// `StereoOutput`.
pub fn StereoDsp::compile(
  compiled_template : AnalyzedGraph,
  context : DspContext,
) -> StereoDsp? {
  @runtime.StereoDsp::compile(compiled_template.raw(), context).map(
    StereoDsp::from_internal,
  )
}
