///|
pub(all) suberror GraphTemplateDocError {
  LengthMismatch(Int, Int)
  DuplicateNodeId(String)
  MissingNodeId(String)
  RetiredNodeId(String)
  Topology(GraphTopologyEditError)
} derive(Debug)

///|
pub impl Show for GraphTemplateDocError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn graph_template_doc_error_from_authoring(
  error : @authoring.GraphTemplateDocError,
) -> GraphTemplateDocError {
  match error {
    @authoring.GraphTemplateDocError::LengthMismatch(actual, expected) =>
      GraphTemplateDocError::LengthMismatch(actual, expected)
    @authoring.GraphTemplateDocError::DuplicateNodeId(id) =>
      GraphTemplateDocError::DuplicateNodeId(id)
    @authoring.GraphTemplateDocError::MissingNodeId(id) =>
      GraphTemplateDocError::MissingNodeId(id)
    @authoring.GraphTemplateDocError::RetiredNodeId(id) =>
      GraphTemplateDocError::RetiredNodeId(id)
    @authoring.GraphTemplateDocError::Topology(error) =>
      GraphTemplateDocError::Topology(
        graph_topology_edit_error_from_staging(error),
      )
  }
}

///|
fn graph_template_doc_from_authoring_result(
  result : Result[@authoring.GraphTemplateDoc, @authoring.GraphTemplateDocError],
) -> GraphTemplateDoc raise GraphTemplateDocError {
  match result {
    Ok(raw) => GraphTemplateDoc::from_internal(raw)
    Err(error) => raise graph_template_doc_error_from_authoring(error)
  }
}

///|
/// Identity-bearing authoring wrapper for graph templates.
///
/// Runtime graph compilation remains index-based. `GraphTemplateDoc` owns the
/// stable authoring IDs and exposes `GraphIndexMap` at the boundary where
/// controls, bindings, and topology edits are translated to existing indices.
///
/// Public facade wrapper; implementation lives in `graph/internal/authoring`.
pub struct GraphTemplateDoc {
  priv raw : @authoring.GraphTemplateDoc
}

///|
fn GraphTemplateDoc::from_internal(
  raw : @authoring.GraphTemplateDoc,
) -> GraphTemplateDoc {
  { raw, }
}

///|
/// Stable-ID to authoring-index lookup produced by `GraphTemplateDoc`.
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
pub fn GraphTemplateDoc::from_nodes(
  ids~ : Array[@identity.GraphNodeId],
  nodes~ : Array[DspNode],
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? @authoring.GraphTemplateDoc::from_nodes(
      ids~,
      nodes=dsp_nodes_to_model(nodes),
    ),
  )
}

///|
pub fn GraphTemplateDoc::revision(
  self : GraphTemplateDoc,
) -> @identity.Revision {
  self.raw.revision()
}

///|
pub fn GraphTemplateDoc::length(self : GraphTemplateDoc) -> Int {
  self.raw.length()
}

///|
pub fn GraphTemplateDoc::nodes(self : GraphTemplateDoc) -> Array[DspNode] {
  dsp_nodes_from_model(self.raw.nodes())
}

///|
pub fn GraphTemplateDoc::node_index(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> Int? {
  self.raw.node_index(id)
}

///|
pub fn GraphTemplateDoc::node_id_at(
  self : GraphTemplateDoc,
  index : Int,
) -> @identity.GraphNodeId? {
  self.raw.node_id_at(index)
}

///|
pub fn GraphTemplateDoc::node_at(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> DspNode? {
  self.raw.node_at(id).map(DspNode::from_model)
}

///|
pub fn GraphTemplateDoc::contains_node(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> Bool {
  self.raw.contains_node(id)
}

///|
pub fn GraphTemplateDoc::contains_retired_node(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> Bool {
  self.raw.contains_retired_node(id)
}

///|
pub fn GraphTemplateDoc::index_map(self : GraphTemplateDoc) -> GraphIndexMap {
  GraphIndexMap::from_internal(self.raw.index_map())
}

///|
pub fn GraphTemplateDoc::analyze(self : GraphTemplateDoc) -> CompiledTemplate {
  CompiledTemplate::from_internal(self.raw.analyze())
}

///|
pub fn GraphTemplateDoc::compile(
  self : GraphTemplateDoc,
  context : DspContext,
) -> CompiledDsp? {
  @runtime.CompiledDsp::compile(self.raw.analyze(), context).map(
    CompiledDsp::from_internal,
  )
}

///|
pub fn GraphTemplateDoc::compile_stereo(
  self : GraphTemplateDoc,
  context : DspContext,
) -> CompiledStereoDsp? {
  @runtime.CompiledStereoDsp::compile(self.raw.analyze(), context).map(
    CompiledStereoDsp::from_internal,
  )
}

///|
pub fn GraphTemplateDoc::replace_node(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
  replacement : DspNode,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? self.raw.replace_node(id, replacement.raw()),
  )
}

///|
pub fn GraphTemplateDoc::rewire_input(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  source_id : @identity.GraphNodeId,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? self.raw.rewire_input(id, input_slot.to_staging(), source_id),
  )
}

///|
pub fn GraphTemplateDoc::insert_node(
  self : GraphTemplateDoc,
  inserted_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  inserted_node : DspNode,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? self.raw.insert_node(
      inserted_id,
      retarget_id,
      input_slot.to_staging(),
      inserted_node.raw(),
    ),
  )
}

///|
pub fn GraphTemplateDoc::insert_chain(
  self : GraphTemplateDoc,
  inserted_ids : Array[@identity.GraphNodeId],
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? self.raw.insert_chain(
      inserted_ids,
      retarget_id,
      input_slot.to_staging(),
      dsp_nodes_to_model(chain_nodes),
    ),
  )
}

///|
pub fn GraphTemplateDoc::delete_node(
  self : GraphTemplateDoc,
  delete_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? self.raw.delete_node(
      delete_id,
      retarget_id,
      input_slot.to_staging(),
      replacement_source_id,
    ),
  )
}

///|
pub fn GraphTemplateDoc::delete_chain(
  self : GraphTemplateDoc,
  start_id : @identity.GraphNodeId,
  end_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  graph_template_doc_from_authoring_result(
    try? self.raw.delete_chain(
      start_id,
      end_id,
      retarget_id,
      input_slot.to_staging(),
      replacement_source_id,
    ),
  )
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
