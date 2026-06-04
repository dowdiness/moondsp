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
///
/// This public facade keeps `Array[DspNode] -> CompiledTemplate` as the
/// canonical authoring/runtime crossing while the implementation lives in
/// `graph/internal/template` over the raw graph model.
pub struct CompiledTemplate {
  priv raw : @template.CompiledTemplate
}

///|
fn CompiledTemplate::from_internal(
  raw : @template.CompiledTemplate,
) -> CompiledTemplate {
  { raw, }
}

///|
fn CompiledTemplate::raw(self : CompiledTemplate) -> @template.CompiledTemplate {
  self.raw
}

///|
fn dsp_nodes_to_model(nodes : Array[DspNode]) -> Array[@model.DspNode] {
  let raw_nodes = Array::new(capacity=nodes.length())
  for node in nodes {
    raw_nodes.push(node.raw())
  }
  raw_nodes
}

///|
/// Structural equality for analyzed template artifacts.
pub impl Eq for CompiledTemplate with fn equal(self, other) {
  self.raw == other.raw
}

///|
/// Snapshot the template and run optimize_graph once.
///
/// WHY defensive copy: the caller's `template` array is mutable from
/// outside. Without a snapshot, any post-analyze mutation of the source
/// array would corrupt the authoring snapshot we rely on for every
/// subsequent query. `optimize_graph` itself does not mutate its input,
/// so the copy is only guarding against caller-side mutation.
///
/// WHY no DspContext: optimize_graph is a pure function of Array[DspNode];
/// sample rate and block size do not affect which nodes survive
/// dead-code elimination. Omitting the context makes analyze infallible
/// and cheap.
pub fn CompiledTemplate::analyze(template : Array[DspNode]) -> CompiledTemplate {
  CompiledTemplate::from_internal(
    @template.CompiledTemplate::analyze(dsp_nodes_to_model(template)),
  )
}

///|
/// Length of the authoring template snapshot.
fn CompiledTemplate::length(self : CompiledTemplate) -> Int {
  self.raw.length()
}

///|
/// Return the authoring node at `index` (panics if out of range; callers
/// are expected to bounds-check first).
fn CompiledTemplate::node_at(self : CompiledTemplate, index : Int) -> DspNode {
  DspNode::from_model(self.raw.node_at(index))
}

///|
/// Does authoring index `i` survive the optimizer? Returns false for
/// out-of-range indices (no abort).
fn CompiledTemplate::is_node_live(self : CompiledTemplate, index : Int) -> Bool {
  self.raw.is_node_live(index)
}

///|
/// Count Adsr nodes in the template snapshot whose compiled index is < 0
/// (eliminated by optimize_graph as dead code). On a CompiledDsp, `gate_on`
/// for an orphan ADSR returns `Err(OrphanNode)` — VoicePool::new and
/// set_template reject templates where this count is > 0 so the per-note
/// gate loop can `.unwrap()` instead of branching on every voice trigger.
///
/// Parameterless because the template snapshot is owned by self; callers
/// do not need to remember which template was compiled.
pub fn CompiledTemplate::orphan_adsr_count(self : CompiledTemplate) -> Int {
  let count = for i in 0..<self.length(); total = 0 {
    if self.node_at(i).kind() is Adsr && !self.is_node_live(i) {
      continue total + 1
    }
    continue total
  } nobreak {
    total
  }
  count
}

///|
/// Authoring indices of ADSR nodes that survived optimize_graph,
/// in authoring order. Used by voice/ to gate the surviving ADSRs
/// on note_on / note_off — they call CompiledDsp::gate_on/gate_off
/// which take authoring indices and remap through index_map internally.
///
/// WHY authoring indices, not runtime: CompiledDsp::gate_on/gate_off
/// expect the original authoring index; returning runtime indices
/// would cause voice/ to double-map and target wrong nodes.
///
/// WHY a separate accessor instead of exposing length/node_at:
/// keeps the accessor surface minimal (principle 7). Specific
/// validation patterns get their own public method; generic
/// introspection waits for a concrete consumer.
pub fn CompiledTemplate::adsr_authoring_indices(
  self : CompiledTemplate,
) -> FixedArray[Int] {
  self.raw.adsr_authoring_indices()
}
