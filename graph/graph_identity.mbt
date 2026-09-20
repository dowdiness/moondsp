///|
pub(all) suberror GraphDocumentError {
  LengthMismatch(Int, Int)
  DuplicateNodeId(String)
  MissingNodeId(String)
  RetiredNodeId(String)
  Topology(GraphTopologyEditError)
} derive(Debug)

///|
pub impl Show for GraphDocumentError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn graph_template_doc_error_from_authoring(
  error : @authoring.GraphDocumentError,
) -> GraphDocumentError {
  match error {
    @authoring.GraphDocumentError::LengthMismatch(actual, expected) =>
      GraphDocumentError::LengthMismatch(actual, expected)
    @authoring.GraphDocumentError::DuplicateNodeId(id) =>
      GraphDocumentError::DuplicateNodeId(id)
    @authoring.GraphDocumentError::MissingNodeId(id) =>
      GraphDocumentError::MissingNodeId(id)
    @authoring.GraphDocumentError::RetiredNodeId(id) =>
      GraphDocumentError::RetiredNodeId(id)
    @authoring.GraphDocumentError::Topology(error) =>
      GraphDocumentError::Topology(
        graph_topology_edit_error_from_staging(error),
      )
  }
}

///|
/// Identity-bearing authoring wrapper for graph templates.
///
/// Runtime graph compilation remains index-based. `GraphDocument` owns the
/// stable authoring IDs and exposes `GraphIndexMap` at the boundary where
/// controls, bindings, and topology edits are translated to existing indices.
///
/// Public facade wrapper; implementation lives in `graph/internal/authoring`.
pub struct GraphDocument {
  priv raw : @authoring.GraphDocument
}

///|
fn GraphDocument::from_internal(
  raw : @authoring.GraphDocument,
) -> GraphDocument {
  { raw, }
}

///|
/// Stable-ID to authoring-index lookup produced by `GraphDocument`.
///
/// Public facade wrapper; implementation lives in `graph/internal/authoring`.
pub struct GraphIndexMap {
  priv raw : @authoring.GraphIndexMap
}

///|
fn GraphIndexMap::from_internal(
  raw : @authoring.GraphIndexMap,
) -> GraphIndexMap {
  { raw, }
}

///|
pub fn GraphDocument::from_nodes(
  ids~ : Array[@identity.GraphNodeId],
  nodes~ : Array[DspNode],
) -> GraphDocument raise GraphDocumentError {
  let raw = @authoring.GraphDocument::from_nodes(
    ids~,
    nodes=dsp_nodes_to_model(nodes),
  ) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphDocument::revision(self : GraphDocument) -> @identity.Revision {
  self.raw.revision()
}

///|
pub fn GraphDocument::length(self : GraphDocument) -> Int {
  self.raw.length()
}

///|
pub fn GraphDocument::nodes(self : GraphDocument) -> Array[DspNode] {
  dsp_nodes_from_model(self.raw.nodes())
}

///|
pub fn GraphDocument::node_index(
  self : GraphDocument,
  id : @identity.GraphNodeId,
) -> Int? {
  self.raw.node_index(id)
}

///|
pub fn GraphDocument::node_id_at(
  self : GraphDocument,
  index : Int,
) -> @identity.GraphNodeId? {
  self.raw.node_id_at(index)
}

///|
pub fn GraphDocument::node_at(
  self : GraphDocument,
  id : @identity.GraphNodeId,
) -> DspNode? {
  self.raw.node_at(id).map(DspNode::from_model)
}

///|
pub fn GraphDocument::contains_node(
  self : GraphDocument,
  id : @identity.GraphNodeId,
) -> Bool {
  self.raw.contains_node(id)
}

///|
pub fn GraphDocument::contains_retired_node(
  self : GraphDocument,
  id : @identity.GraphNodeId,
) -> Bool {
  self.raw.contains_retired_node(id)
}

///|
pub fn GraphDocument::index_map(self : GraphDocument) -> GraphIndexMap {
  GraphIndexMap::from_internal(self.raw.index_map())
}

///|
pub fn GraphDocument::analyze(self : GraphDocument) -> AnalyzedGraph {
  AnalyzedGraph::from_internal(self.raw.analyze())
}

///|
pub fn GraphDocument::compile(
  self : GraphDocument,
  context : DspContext,
) -> Dsp? {
  @runtime.Dsp::compile(self.raw.analyze(), context).map(Dsp::from_internal)
}

///|
pub fn GraphDocument::compile_stereo(
  self : GraphDocument,
  context : DspContext,
) -> StereoDsp? {
  @runtime.StereoDsp::compile(self.raw.analyze(), context).map(
    StereoDsp::from_internal,
  )
}

///|
pub fn GraphDocument::replace_node(
  self : GraphDocument,
  id : @identity.GraphNodeId,
  replacement : DspNode,
) -> GraphDocument raise GraphDocumentError {
  let raw = self.raw.replace_node(id, replacement.raw()) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphDocument::rewire_input(
  self : GraphDocument,
  id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  source_id : @identity.GraphNodeId,
) -> GraphDocument raise GraphDocumentError {
  let raw = self.raw.rewire_input(id, input_slot.to_staging(), source_id) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphDocument::insert_node(
  self : GraphDocument,
  inserted_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  inserted_node : DspNode,
) -> GraphDocument raise GraphDocumentError {
  let raw = self.raw.insert_node(
    inserted_id,
    retarget_id,
    input_slot.to_staging(),
    inserted_node.raw(),
  ) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphDocument::insert_chain(
  self : GraphDocument,
  inserted_ids : Array[@identity.GraphNodeId],
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> GraphDocument raise GraphDocumentError {
  let raw = self.raw.insert_chain(
    inserted_ids,
    retarget_id,
    input_slot.to_staging(),
    dsp_nodes_to_model(chain_nodes),
  ) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphDocument::delete_node(
  self : GraphDocument,
  delete_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphDocument raise GraphDocumentError {
  let raw = self.raw.delete_node(
    delete_id,
    retarget_id,
    input_slot.to_staging(),
    replacement_source_id,
  ) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphDocument::delete_chain(
  self : GraphDocument,
  start_id : @identity.GraphNodeId,
  end_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphDocument raise GraphDocumentError {
  let raw = self.raw.delete_chain(
    start_id,
    end_id,
    retarget_id,
    input_slot.to_staging(),
    replacement_source_id,
  ) catch {
    error => raise graph_template_doc_error_from_authoring(error)
  }
  GraphDocument::from_internal(raw)
}

///|
pub fn GraphIndexMap::revision(self : GraphIndexMap) -> @identity.Revision {
  self.raw.revision()
}

///|
pub fn GraphIndexMap::length(self : GraphIndexMap) -> Int {
  self.raw.length()
}

///|
pub fn GraphIndexMap::node_index(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
) -> Int? {
  self.raw.node_index(id)
}

///|
pub fn GraphIndexMap::node_id_at(
  self : GraphIndexMap,
  index : Int,
) -> @identity.GraphNodeId? {
  self.raw.node_id_at(index)
}

///|
pub fn GraphIndexMap::gate_on(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
) -> GraphControl? {
  self.raw.gate_on(id).map(GraphControl::from_model)
}

///|
pub fn GraphIndexMap::gate_off(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
) -> GraphControl? {
  self.raw.gate_off(id).map(GraphControl::from_model)
}

///|
pub fn GraphIndexMap::set_param(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
  slot : GraphParamSlot,
  value : Double,
) -> GraphControl? {
  self.raw.set_param(id, slot.to_model(), value).map(GraphControl::from_model)
}

///|
pub fn GraphIndexMap::bind_control(
  self : GraphIndexMap,
  builder : ControlBindingBuilder,
  key : String,
  id : @identity.GraphNodeId,
  slot : GraphParamSlot,
) -> ControlBindingBuilder? {
  self.raw
  .bind_control(builder.raw, key, id, slot.to_model())
  .map(ControlBindingBuilder::from_internal)
}

///|
pub fn GraphIndexMap::replace_node(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
  replacement : DspNode,
) -> GraphTopologyEdit? {
  self.raw
  .replace_node(id, replacement.raw())
  .map(graph_topology_edit_from_staging)
}

///|
pub fn GraphIndexMap::rewire_input(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  source_id : @identity.GraphNodeId,
) -> GraphTopologyEdit? {
  self.raw
  .rewire_input(id, input_slot.to_staging(), source_id)
  .map(graph_topology_edit_from_staging)
}

///|
pub fn GraphIndexMap::insert_node(
  self : GraphIndexMap,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  inserted_node : DspNode,
) -> GraphTopologyEdit? {
  self.raw
  .insert_node(retarget_id, input_slot.to_staging(), inserted_node.raw())
  .map(graph_topology_edit_from_staging)
}

///|
pub fn GraphIndexMap::delete_node(
  self : GraphIndexMap,
  delete_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphTopologyEdit? {
  self.raw
  .delete_node(
    delete_id,
    retarget_id,
    input_slot.to_staging(),
    replacement_source_id,
  )
  .map(graph_topology_edit_from_staging)
}

///|
pub fn GraphIndexMap::insert_chain(
  self : GraphIndexMap,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> GraphTopologyEdit? {
  self.raw
  .insert_chain(
    retarget_id,
    input_slot.to_staging(),
    dsp_nodes_to_model(chain_nodes),
  )
  .map(graph_topology_edit_from_staging)
}

///|
pub fn GraphIndexMap::delete_chain(
  self : GraphIndexMap,
  start_id : @identity.GraphNodeId,
  end_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphTopologyEdit? {
  self.raw
  .delete_chain(
    start_id,
    end_id,
    retarget_id,
    input_slot.to_staging(),
    replacement_source_id,
  )
  .map(graph_topology_edit_from_staging)
}
