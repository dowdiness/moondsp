///|
/// Topology artifact: template snapshot paired with its optimize_graph
/// result. Holds the minimum needed to answer post-optimization topology
/// questions ("is this node live?", "how many ADSRs were eliminated?")
/// without allocating runtime buffers or per-voice state.
///
/// WHY a separate artifact from Dsp: Dsp conflates topology
/// with runtime state. Binding validation and pool-level orphan gates only
/// need topology — making that a lightweight standalone type avoids
/// paying for buffers we never use, and keeps the API mono/stereo-agnostic
/// (the same AnalyzedGraph shape applies to any graph variant).
///
/// This public facade keeps `Array[DspNode] -> AnalyzedGraph` as the
/// canonical authoring/runtime crossing while the implementation lives in
/// `graph/internal/template` over the raw graph model.
pub struct AnalyzedGraph {
  priv raw : @template.AnalyzedGraph
}

///|
fn AnalyzedGraph::from_internal(raw : @template.AnalyzedGraph) -> AnalyzedGraph {
  { raw, }
}

///|
fn AnalyzedGraph::raw(self : AnalyzedGraph) -> @template.AnalyzedGraph {
  self.raw
}

///|
fn dsp_nodes_to_model(nodes : Array[DspNode]) -> Array[@model.DspNode] {
  let raw_nodes : Array[@model.DspNode] = []
  raw_nodes.reserve_capacity(nodes.length())
  for node in nodes {
    raw_nodes.push(node.raw())
  }
  raw_nodes
}

///|
fn dsp_nodes_from_model(nodes : Array[@model.DspNode]) -> Array[DspNode] {
  let facade_nodes : Array[DspNode] = []
  facade_nodes.reserve_capacity(nodes.length())
  for node in nodes {
    facade_nodes.push(DspNode::from_model(node))
  }
  facade_nodes
}

///|
/// Structural equality for analyzed template artifacts.
pub impl Eq for AnalyzedGraph with fn equal(self, other) {
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
pub fn AnalyzedGraph::analyze(template : Array[DspNode]) -> AnalyzedGraph {
  AnalyzedGraph::from_internal(
    @template.AnalyzedGraph::analyze(dsp_nodes_to_model(template)),
  )
}

///|
/// Length of the authoring template snapshot.
fn AnalyzedGraph::length(self : AnalyzedGraph) -> Int {
  self.raw.length()
}

///|
/// Return the authoring node at `index` (panics if out of range; callers
/// are expected to bounds-check first).
fn AnalyzedGraph::node_at(self : AnalyzedGraph, index : Int) -> DspNode {
  DspNode::from_model(self.raw.node_at(index))
}

///|
/// Does authoring index `i` survive the optimizer? Returns false for
/// out-of-range indices (no abort).
fn AnalyzedGraph::is_node_live(self : AnalyzedGraph, index : Int) -> Bool {
  self.raw.is_node_live(index)
}

///|
/// Count Adsr nodes in the template snapshot whose compiled index is < 0
/// (eliminated by optimize_graph as dead code). On a Dsp, `gate_on`
/// for an orphan ADSR returns `Err(OrphanNode)` — VoicePool::new and
/// set_template reject templates where this count is > 0 so the per-note
/// gate loop can `.unwrap()` instead of branching on every voice trigger.
///
/// Parameterless because the template snapshot is owned by self; callers
/// do not need to remember which template was compiled.
pub fn AnalyzedGraph::orphan_adsr_count(self : AnalyzedGraph) -> Int {
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
/// on note_on / note_off — they call Dsp::gate_on/gate_off
/// which take authoring indices and remap through index_map internally.
///
/// WHY authoring indices, not runtime: Dsp::gate_on/gate_off
/// expect the original authoring index; returning runtime indices
/// would cause voice/ to double-map and target wrong nodes.
///
/// WHY a separate accessor instead of exposing length/node_at:
/// keeps the accessor surface minimal (principle 7). Specific
/// validation patterns get their own public method; generic
/// introspection waits for a concrete consumer.
pub fn AnalyzedGraph::adsr_authoring_indices(
  self : AnalyzedGraph,
) -> FixedArray[Int] {
  self.raw.adsr_authoring_indices()
}
