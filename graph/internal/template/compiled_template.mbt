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
  priv template : Array[@model.DspNode]
  priv optimized : Array[@model.DspNode]
  priv index_map : FixedArray[Int]
}

///|
fn dsp_node_array_equal(
  left : Array[@model.DspNode],
  right : Array[@model.DspNode],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn int_fixed_array_equal(
  left : FixedArray[Int],
  right : FixedArray[Int],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
/// Structural equality for analyzed template artifacts.
pub impl Eq for CompiledTemplate with fn equal(self, other) {
  dsp_node_array_equal(self.template, other.template) &&
  dsp_node_array_equal(self.optimized, other.optimized) &&
  int_fixed_array_equal(self.index_map, other.index_map)
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
pub fn CompiledTemplate::analyze(
  template : Array[@model.DspNode],
) -> CompiledTemplate {
  let snapshot = template.copy()
  let (optimized, index_map) = optimize_graph(snapshot)
  { template: snapshot, optimized, index_map }
}

///|
/// Length of the authoring template snapshot.
pub fn CompiledTemplate::length(self : CompiledTemplate) -> Int {
  self.template.length()
}

///|
/// Return the authoring node at `index` (panics if out of range; callers
/// are expected to bounds-check first).
pub fn CompiledTemplate::node_at(
  self : CompiledTemplate,
  index : Int,
) -> @model.DspNode {
  self.template[index]
}

///|
/// Return the authoring template snapshot.
pub fn CompiledTemplate::authoring_nodes(
  self : CompiledTemplate,
) -> Array[@model.DspNode] {
  self.template
}

///|
/// Return the optimized template snapshot.
pub fn CompiledTemplate::optimized_nodes(
  self : CompiledTemplate,
) -> Array[@model.DspNode] {
  self.optimized
}

///|
/// Return the authoring-to-optimized index map.
pub fn CompiledTemplate::index_map(self : CompiledTemplate) -> FixedArray[Int] {
  self.index_map
}

///|
/// Does authoring index `i` survive the optimizer? Returns false for
/// out-of-range indices (no abort).
pub fn CompiledTemplate::is_node_live(
  self : CompiledTemplate,
  index : Int,
) -> Bool {
  index >= 0 && index < self.index_map.length() && self.index_map[index] >= 0
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
  let result = FixedArray::make(self.template.length(), -1)
  let n = for i in 0..<self.template.length(); count = 0 {
    if self.template[i].kind() is @model.DspNodeKind::Adsr &&
      self.index_map[i] >= 0 {
      result[count] = i
      continue count + 1
    }
    continue count
  } nobreak {
    count
  }
  let snapshot = FixedArray::make(n, 0)
  for i in 0..<n {
    snapshot[i] = result[i]
  }
  snapshot
}
