///|
/// Input slot selector for fixed-length topology rewiring.
pub(all) enum GraphTopologyInputSlot {
  Input0
  Input1
} derive(Eq)

///|
/// Declarative topology edit applied in authoring order before recompilation.
///
/// Each variant carries exactly the fields it needs — no sentinel values.
pub(all) enum GraphTopologyEdit {
  ReplaceNode(Int, DspNode)
  RewireInput(Int, GraphTopologyInputSlot, Int)
  InsertNode(Int, GraphTopologyInputSlot, DspNode)
  DeleteNode(Int, Int, GraphTopologyInputSlot, Int)
  InsertChain(Int, GraphTopologyInputSlot, Array[DspNode])
  DeleteChain(Int, Int, Int, GraphTopologyInputSlot, Int)
}

///|
/// Replace one authoring-order node, including its kind and input wiring.
pub fn GraphTopologyEdit::replace_node(
  node_index : Int,
  replacement : DspNode,
) -> GraphTopologyEdit {
  ReplaceNode(node_index, replacement)
}

///|
/// Rewire one authoring-order node input to a different upstream source.
pub fn GraphTopologyEdit::rewire_input(
  node_index : Int,
  input_slot : GraphTopologyInputSlot,
  source_index : Int,
) -> GraphTopologyEdit {
  RewireInput(node_index, input_slot, source_index)
}

///|
/// Insert one unary authoring-order node and retarget one downstream input to
/// the inserted node.
///
/// This first slice appends the inserted node at the end of the authoring
/// array so existing node indices remain stable across the staged replacement.
/// `retarget_node_index` and `retarget_input_slot` identify the downstream
/// input that will be rerouted to the inserted node. The inserted node itself
/// inherits that input's previous upstream source as its own `input0`.
pub fn GraphTopologyEdit::insert_node(
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  inserted_node : DspNode,
) -> GraphTopologyEdit {
  InsertNode(retarget_node_index, retarget_input_slot, inserted_node)
}

///|
/// Delete one unary authoring-order node and retarget one downstream input to a
/// replacement upstream source.
///
/// This first slice is the inverse of append-only `InsertNode`: it only
/// supports deleting unary nodes on the mono path, and the caller must provide
/// the downstream target plus the replacement upstream source explicitly.
pub fn GraphTopologyEdit::delete_node(
  delete_node_index : Int,
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  replacement_source_index : Int,
) -> GraphTopologyEdit {
  DeleteNode(
    delete_node_index, retarget_node_index, retarget_input_slot, replacement_source_index,
  )
}

///|
/// Insert a chain of unary authoring-order nodes and retarget one downstream
/// input to the last node in the chain.
///
/// Each node in the chain is appended at the end of the authoring array. The
/// first chain node inherits the previous upstream source of the retarget
/// input; each subsequent chain node reads from the preceding chain node. The
/// retarget input is then rerouted to the last chain node.
pub fn GraphTopologyEdit::insert_chain(
  retarget_node : Int,
  input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> GraphTopologyEdit {
  InsertChain(retarget_node, input_slot, chain_nodes)
}

///|
/// Delete a contiguous chain of unary authoring-order nodes and retarget one
/// downstream input to a replacement upstream source.
///
/// All nodes from `start_node` through `end_node` (inclusive) must be unary
/// and each must feed exactly one downstream consumer. The retarget input of
/// `retarget_node` is rerouted to `replacement_source`, and every node in the
/// chain is removed with index compaction.
pub fn GraphTopologyEdit::delete_chain(
  start_node : Int,
  end_node : Int,
  retarget_node : Int,
  input_slot : GraphTopologyInputSlot,
  replacement_source : Int,
) -> GraphTopologyEdit {
  DeleteChain(
    start_node, end_node, retarget_node, input_slot, replacement_source,
  )
}
