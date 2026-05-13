///|
pub(all) suberror GraphTemplateDocError {
  LengthMismatch(Int, Int)
  DuplicateNodeId(String)
  MissingNodeId(String)
  RetiredNodeId(String)
  Topology(GraphTopologyEditError)
} derive(Debug)

///|
pub impl Show for GraphTemplateDocError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Identity-bearing authoring wrapper for graph templates.
///
/// Runtime graph compilation remains index-based. `GraphTemplateDoc` owns the
/// stable authoring IDs and exposes `GraphIndexMap` at the boundary where
/// controls, bindings, and topology edits are translated to existing indices.
pub struct GraphTemplateDoc {
  priv revision : @identity.Revision
  priv ids : Array[@identity.GraphNodeId]
  priv nodes : Array[DspNode]
  priv retired_ids : Map[String, Bool]
}

///|
pub struct GraphIndexMap {
  priv revision : @identity.Revision
  priv ids : Array[@identity.GraphNodeId]
  priv indices : Map[String, Int]
}

///|
fn copy_retired_graph_ids(source : Map[String, Bool]) -> Map[String, Bool] {
  let result : Map[String, Bool] = {}
  source.each(fn(id, retired) { result[id] = retired })
  result
}

///|
fn find_graph_id_index(
  ids : Array[@identity.GraphNodeId],
  id : @identity.GraphNodeId,
) -> Int? {
  for index in 0..<ids.length() {
    if ids[index] == id {
      return Some(index)
    }
  }
  None
}

///|
fn validate_graph_template_ids(
  ids : Array[@identity.GraphNodeId],
  expected_length : Int,
) -> Unit raise GraphTemplateDocError {
  if ids.length() != expected_length {
    raise LengthMismatch(ids.length(), expected_length)
  }
  let seen : Map[String, Bool] = {}
  for id in ids {
    let key = id.value()
    if seen.contains(key) {
      raise DuplicateNodeId(key)
    }
    seen[key] = true
  }
}

///|
fn validate_new_graph_id(
  current_ids : Array[@identity.GraphNodeId],
  retired_ids : Map[String, Bool],
  id : @identity.GraphNodeId,
) -> Unit raise GraphTemplateDocError {
  let key = id.value()
  if find_graph_id_index(current_ids, id) is Some(_) {
    raise DuplicateNodeId(key)
  }
  if retired_ids.contains(key) {
    raise RetiredNodeId(key)
  }
}

///|
fn validate_new_graph_ids(
  current_ids : Array[@identity.GraphNodeId],
  retired_ids : Map[String, Bool],
  ids : Array[@identity.GraphNodeId],
) -> Unit raise GraphTemplateDocError {
  let seen : Map[String, Bool] = {}
  for id in ids {
    let key = id.value()
    if seen.contains(key) {
      raise DuplicateNodeId(key)
    }
    seen[key] = true
    validate_new_graph_id(current_ids, retired_ids, id)
  }
}

///|
fn graph_id_index_or_raise(
  ids : Array[@identity.GraphNodeId],
  id : @identity.GraphNodeId,
) -> Int raise GraphTemplateDocError {
  match find_graph_id_index(ids, id) {
    Some(index) => index
    None => raise MissingNodeId(id.value())
  }
}

///|
fn apply_graph_template_edit(
  nodes : Array[DspNode],
  edit : GraphTopologyEdit,
) -> Unit raise GraphTemplateDocError {
  match apply_topology_edit_result(nodes, edit) {
    Ok(_) => ()
    Err(error) => raise Topology(error)
  }
}

///|
fn compact_graph_ids_after_delete(
  ids : Array[@identity.GraphNodeId],
  start_index : Int,
  end_index : Int,
) -> Array[@identity.GraphNodeId] {
  let result : Array[@identity.GraphNodeId] = []
  for index in 0..<ids.length() {
    if index < start_index || index > end_index {
      result.push(ids[index])
    }
  }
  result
}

///|
fn retire_graph_id_range(
  retired_ids : Map[String, Bool],
  ids : Array[@identity.GraphNodeId],
  start_index : Int,
  end_index : Int,
) -> Unit {
  for index = start_index; index <= end_index; index = index + 1 {
    retired_ids[ids[index].value()] = true
  }
}

///|
pub fn GraphTemplateDoc::from_nodes(
  ids~ : Array[@identity.GraphNodeId],
  nodes~ : Array[DspNode],
) -> GraphTemplateDoc raise GraphTemplateDocError {
  validate_graph_template_ids(ids, nodes.length())
  {
    revision: @identity.Revision::zero(),
    ids: ids.copy(),
    nodes: nodes.copy(),
    retired_ids: {},
  }
}

///|
pub fn GraphTemplateDoc::revision(
  self : GraphTemplateDoc,
) -> @identity.Revision {
  self.revision
}

///|
pub fn GraphTemplateDoc::length(self : GraphTemplateDoc) -> Int {
  self.nodes.length()
}

///|
pub fn GraphTemplateDoc::nodes(self : GraphTemplateDoc) -> Array[DspNode] {
  self.nodes.copy()
}

///|
pub fn GraphTemplateDoc::node_index(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> Int? {
  find_graph_id_index(self.ids, id)
}

///|
pub fn GraphTemplateDoc::node_id_at(
  self : GraphTemplateDoc,
  index : Int,
) -> @identity.GraphNodeId? {
  if index < 0 || index >= self.ids.length() {
    None
  } else {
    Some(self.ids[index])
  }
}

///|
pub fn GraphTemplateDoc::node_at(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> DspNode? {
  match self.node_index(id) {
    Some(index) => Some(self.nodes[index])
    None => None
  }
}

///|
pub fn GraphTemplateDoc::contains_node(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> Bool {
  self.node_index(id) is Some(_)
}

///|
pub fn GraphTemplateDoc::contains_retired_node(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
) -> Bool {
  self.retired_ids.contains(id.value())
}

///|
pub fn GraphTemplateDoc::index_map(self : GraphTemplateDoc) -> GraphIndexMap {
  let indices : Map[String, Int] = {}
  for index in 0..<self.ids.length() {
    indices[self.ids[index].value()] = index
  }
  { revision: self.revision, ids: self.ids.copy(), indices }
}

///|
pub fn GraphTemplateDoc::analyze(self : GraphTemplateDoc) -> CompiledTemplate {
  CompiledTemplate::analyze(self.nodes)
}

///|
pub fn GraphTemplateDoc::compile(
  self : GraphTemplateDoc,
  context : DspContext,
) -> CompiledDsp? {
  CompiledDsp::compile(self.nodes, context)
}

///|
pub fn GraphTemplateDoc::compile_stereo(
  self : GraphTemplateDoc,
  context : DspContext,
) -> CompiledStereoDsp? {
  CompiledStereoDsp::compile(self.nodes, context)
}

///|
pub fn GraphTemplateDoc::replace_node(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
  replacement : DspNode,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  let index = graph_id_index_or_raise(self.ids, id)
  let nodes = self.nodes.copy()
  nodes[index] = replacement
  {
    revision: self.revision.next(),
    ids: self.ids.copy(),
    nodes,
    retired_ids: copy_retired_graph_ids(self.retired_ids),
  }
}

///|
pub fn GraphTemplateDoc::rewire_input(
  self : GraphTemplateDoc,
  id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  source_id : @identity.GraphNodeId,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  let index = graph_id_index_or_raise(self.ids, id)
  let source_index = graph_id_index_or_raise(self.ids, source_id)
  let nodes = self.nodes.copy()
  apply_graph_template_edit(
    nodes,
    GraphTopologyEdit::rewire_input(index, input_slot, source_index),
  )
  {
    revision: self.revision.next(),
    ids: self.ids.copy(),
    nodes,
    retired_ids: copy_retired_graph_ids(self.retired_ids),
  }
}

///|
pub fn GraphTemplateDoc::insert_node(
  self : GraphTemplateDoc,
  inserted_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  inserted_node : DspNode,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  validate_new_graph_id(self.ids, self.retired_ids, inserted_id)
  let retarget_index = graph_id_index_or_raise(self.ids, retarget_id)
  let nodes = self.nodes.copy()
  apply_graph_template_edit(
    nodes,
    GraphTopologyEdit::insert_node(retarget_index, input_slot, inserted_node),
  )
  let ids = self.ids.copy()
  ids.push(inserted_id)
  {
    revision: self.revision.next(),
    ids,
    nodes,
    retired_ids: copy_retired_graph_ids(self.retired_ids),
  }
}

///|
pub fn GraphTemplateDoc::insert_chain(
  self : GraphTemplateDoc,
  inserted_ids : Array[@identity.GraphNodeId],
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> GraphTemplateDoc raise GraphTemplateDocError {
  validate_new_graph_ids(self.ids, self.retired_ids, inserted_ids)
  if inserted_ids.length() != chain_nodes.length() {
    raise LengthMismatch(inserted_ids.length(), chain_nodes.length())
  }
  let retarget_index = graph_id_index_or_raise(self.ids, retarget_id)
  let nodes = self.nodes.copy()
  apply_graph_template_edit(
    nodes,
    GraphTopologyEdit::insert_chain(retarget_index, input_slot, chain_nodes),
  )
  let ids = self.ids.copy()
  for id in inserted_ids {
    ids.push(id)
  }
  {
    revision: self.revision.next(),
    ids,
    nodes,
    retired_ids: copy_retired_graph_ids(self.retired_ids),
  }
}

///|
pub fn GraphTemplateDoc::delete_node(
  self : GraphTemplateDoc,
  delete_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphTemplateDoc raise GraphTemplateDocError {
  let delete_index = graph_id_index_or_raise(self.ids, delete_id)
  let retarget_index = graph_id_index_or_raise(self.ids, retarget_id)
  let replacement_source_index = graph_id_index_or_raise(
    self.ids,
    replacement_source_id,
  )
  let nodes = self.nodes.copy()
  apply_graph_template_edit(
    nodes,
    GraphTopologyEdit::delete_node(
      delete_index, retarget_index, input_slot, replacement_source_index,
    ),
  )
  let retired_ids = copy_retired_graph_ids(self.retired_ids)
  retire_graph_id_range(retired_ids, self.ids, delete_index, delete_index)
  {
    revision: self.revision.next(),
    ids: compact_graph_ids_after_delete(self.ids, delete_index, delete_index),
    nodes,
    retired_ids,
  }
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
  let start_index = graph_id_index_or_raise(self.ids, start_id)
  let end_index = graph_id_index_or_raise(self.ids, end_id)
  let retarget_index = graph_id_index_or_raise(self.ids, retarget_id)
  let replacement_source_index = graph_id_index_or_raise(
    self.ids,
    replacement_source_id,
  )
  let nodes = self.nodes.copy()
  apply_graph_template_edit(
    nodes,
    GraphTopologyEdit::delete_chain(
      start_index, end_index, retarget_index, input_slot, replacement_source_index,
    ),
  )
  let retired_ids = copy_retired_graph_ids(self.retired_ids)
  retire_graph_id_range(retired_ids, self.ids, start_index, end_index)
  {
    revision: self.revision.next(),
    ids: compact_graph_ids_after_delete(self.ids, start_index, end_index),
    nodes,
    retired_ids,
  }
}

///|
pub fn GraphIndexMap::revision(self : GraphIndexMap) -> @identity.Revision {
  self.revision
}

///|
pub fn GraphIndexMap::length(self : GraphIndexMap) -> Int {
  self.ids.length()
}

///|
pub fn GraphIndexMap::node_index(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
) -> Int? {
  self.indices.get(id.value())
}

///|
pub fn GraphIndexMap::node_id_at(
  self : GraphIndexMap,
  index : Int,
) -> @identity.GraphNodeId? {
  if index < 0 || index >= self.ids.length() {
    None
  } else {
    Some(self.ids[index])
  }
}

///|
pub fn GraphIndexMap::gate_on(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
) -> GraphControl? {
  self.node_index(id).map(fn(index) { GraphControl::gate_on(index) })
}

///|
pub fn GraphIndexMap::gate_off(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
) -> GraphControl? {
  self.node_index(id).map(fn(index) { GraphControl::gate_off(index) })
}

///|
pub fn GraphIndexMap::set_param(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
  slot : GraphParamSlot,
  value : Double,
) -> GraphControl? {
  self
  .node_index(id)
  .map(fn(index) { GraphControl::set_param(index, slot, value) })
}

///|
pub fn GraphIndexMap::bind_control(
  self : GraphIndexMap,
  builder : ControlBindingBuilder,
  key : String,
  id : @identity.GraphNodeId,
  slot : GraphParamSlot,
) -> ControlBindingBuilder? {
  self
  .node_index(id)
  .map(fn(index) { builder.bind(key~, node_index=index, slot~) })
}

///|
pub fn GraphIndexMap::replace_node(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
  replacement : DspNode,
) -> GraphTopologyEdit? {
  self
  .node_index(id)
  .map(fn(index) { GraphTopologyEdit::replace_node(index, replacement) })
}

///|
pub fn GraphIndexMap::rewire_input(
  self : GraphIndexMap,
  id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  source_id : @identity.GraphNodeId,
) -> GraphTopologyEdit? {
  match (self.node_index(id), self.node_index(source_id)) {
    (Some(index), Some(source_index)) =>
      Some(GraphTopologyEdit::rewire_input(index, input_slot, source_index))
    _ => None
  }
}

///|
pub fn GraphIndexMap::insert_node(
  self : GraphIndexMap,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  inserted_node : DspNode,
) -> GraphTopologyEdit? {
  self
  .node_index(retarget_id)
  .map(fn(index) {
    GraphTopologyEdit::insert_node(index, input_slot, inserted_node)
  })
}

///|
pub fn GraphIndexMap::delete_node(
  self : GraphIndexMap,
  delete_id : @identity.GraphNodeId,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  replacement_source_id : @identity.GraphNodeId,
) -> GraphTopologyEdit? {
  match
    (
      self.node_index(delete_id),
      self.node_index(retarget_id),
      self.node_index(replacement_source_id),
    ) {
    (Some(delete_index), Some(retarget_index), Some(replacement_source_index)) =>
      Some(
        GraphTopologyEdit::delete_node(
          delete_index, retarget_index, input_slot, replacement_source_index,
        ),
      )
    _ => None
  }
}

///|
pub fn GraphIndexMap::insert_chain(
  self : GraphIndexMap,
  retarget_id : @identity.GraphNodeId,
  input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> GraphTopologyEdit? {
  self
  .node_index(retarget_id)
  .map(fn(index) {
    GraphTopologyEdit::insert_chain(index, input_slot, chain_nodes)
  })
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
  match
    (
      self.node_index(start_id),
      self.node_index(end_id),
      self.node_index(retarget_id),
      self.node_index(replacement_source_id),
    ) {
    (
      Some(start_index),
      Some(end_index),
      Some(retarget_index),
      Some(replacement_source_index),
    ) =>
      Some(
        GraphTopologyEdit::delete_chain(
          start_index, end_index, retarget_index, input_slot, replacement_source_index,
        ),
      )
    _ => None
  }
}
