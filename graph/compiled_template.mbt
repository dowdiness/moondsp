///|
/// Topology artifact: template snapshot paired with its optimize_graph
/// result. Holds the minimum needed to answer post-optimization topology
/// questions ("is this node live?", "how many ADSRs were eliminated?")
/// without allocating runtime buffers or per-voice state.
///
/// WHY a separate artifact from CompiledDsp: CompiledDsp conflates topology
/// with runtime state. Binding validation and pool-level orphan gates only
/// need topology — making that a lightweight standalone type avoids
/// paying for buffers we never use, and keeps the API mono/stereo-agnostic
/// (the same CompiledTemplate shape applies to any graph variant).
pub struct CompiledTemplate {
  priv template : Array[DspNode]
  priv index_map : FixedArray[Int]
}

///|
/// Snapshot the template and run optimize_graph once.
///
/// WHY defensive copy: the caller's `template` array is mutable from
/// outside. Without a snapshot, any post-analyze mutation of the source
/// array would corrupt the `self.template` field we rely on for every
/// subsequent query. `optimize_graph` itself does not mutate its input,
/// so the copy is only guarding against caller-side mutation.
///
/// WHY no DspContext: optimize_graph is a pure function of Array[DspNode];
/// sample rate and block size do not affect which nodes survive
/// dead-code elimination. Omitting the context makes analyze infallible
/// and cheap.
pub fn CompiledTemplate::analyze(template : Array[DspNode]) -> CompiledTemplate {
  // DspNode is a flat value struct (no nested arrays/refs), so Array.copy() produces a fully independent snapshot.
  let snapshot = template.copy()
  let (_, index_map) = optimize_graph(snapshot)
  { template: snapshot, index_map }
}

///|
/// Length of the authoring template snapshot.
fn CompiledTemplate::length(self : CompiledTemplate) -> Int {
  self.template.length()
}

///|
/// Return the authoring node at `index` (panics if out of range; callers
/// are expected to bounds-check first).
fn CompiledTemplate::node_at(self : CompiledTemplate, index : Int) -> DspNode {
  self.template[index]
}
