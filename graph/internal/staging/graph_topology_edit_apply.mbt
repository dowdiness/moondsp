///|
pub(all) struct GraphTopologyEditFailure {
  edit_index : Int
  reason : GraphTopologyEditError
}

///|
pub fn apply_topology_edits(
  nodes : Array[DspNode],
  edits : Array[GraphTopologyEdit],
) -> Result[GraphEditResult, GraphTopologyEditFailure] {
  let working = nodes.map(@model.clone_node)
  let correspondence : Array[Int] = [ for index in 0..<nodes.length() => index ]
  for index = 0; index < edits.length(); index = index + 1 {
    let edit = edits[index]
    match apply_topology_edit_mutating(working, edit) {
      Ok(_) =>
        match edit {
          InsertNode(_, _, _) => correspondence.push(-1)
          InsertChain(_, _, chain_nodes) =>
            for _ in chain_nodes {
              correspondence.push(-1)
            }
          DeleteNode(delete_index, _, _, _) =>
            ignore(correspondence.remove(delete_index))
          DeleteChain(start_index, end_index, _, _, _) =>
            for _ in start_index..<=end_index {
              ignore(correspondence.remove(start_index))
            }
          _ => ()
        }
      Err(reason) => return Err({ edit_index: index, reason, })
    }
  }
  let old_to_new = FixedArray::make(nodes.length(), -1)
  for new_index in 0..<correspondence.length() {
    let original_index = correspondence[new_index]
    if original_index >= 0 {
      old_to_new[original_index] = new_index
    }
  }
  Ok({ final_nodes: working, correspondence: old_to_new, })
}

///|
pub fn apply_topology_edit_result(
  nodes : Array[DspNode],
  edit : GraphTopologyEdit,
) -> Result[GraphEditResult, GraphTopologyEditError] {
  let result = apply_topology_edits(nodes, [edit])
  match result {
    Ok(result) => Ok(result)
    Err(failure) => Err(failure.reason)
  }
}

///|
fn apply_topology_edit_mutating(
  nodes : Array[DspNode],
  edit : GraphTopologyEdit,
) -> Result[Unit, GraphTopologyEditError] {
  match edit {
    ReplaceNode(node_index, replacement) =>
      if node_index < 0 || node_index >= nodes.length() {
        Err(GraphTopologyEditError::InvalidNodeIndex(node_index))
      } else {
        nodes[node_index] = @model.clone_node(replacement)
        Ok(())
      }
    RewireInput(node_index, input_slot, source_index) =>
      if node_index < 0 || node_index >= nodes.length() {
        Err(GraphTopologyEditError::InvalidNodeIndex(node_index))
      } else if source_index < 0 || source_index >= nodes.length() {
        Err(GraphTopologyEditError::InvalidSourceIndex(source_index))
      } else {
        apply_topology_rewire_input_result(
          nodes, node_index, input_slot, source_index,
        )
      }
    InsertNode(retarget_node_index, retarget_input_slot, inserted_node) =>
      apply_topology_insert_node(
        nodes, retarget_node_index, inserted_node, retarget_input_slot,
      )
    DeleteNode(
      delete_node_index,
      retarget_node_index,
      retarget_input_slot,
      replacement_source_index
    ) =>
      if delete_node_index < 0 ||
        delete_node_index >= nodes.length() ||
        replacement_source_index < 0 ||
        replacement_source_index >= nodes.length() {
        if delete_node_index < 0 || delete_node_index >= nodes.length() {
          Err(GraphTopologyEditError::InvalidNodeIndex(delete_node_index))
        } else {
          Err(
            GraphTopologyEditError::InvalidSourceIndex(replacement_source_index),
          )
        }
      } else {
        apply_topology_delete_node(
          nodes, delete_node_index, retarget_node_index, retarget_input_slot, replacement_source_index,
        )
      }
    InsertChain(retarget_node, input_slot, chain_nodes) =>
      apply_topology_insert_chain(nodes, retarget_node, input_slot, chain_nodes)
    DeleteChain(
      start_node,
      end_node,
      retarget_node,
      input_slot,
      replacement_source
    ) =>
      apply_topology_delete_chain(
        nodes, start_node, end_node, retarget_node, input_slot, replacement_source,
      )
  }
}

///|
fn apply_topology_insert_node(
  nodes : Array[DspNode],
  retarget_node_index : Int,
  inserted_template : DspNode,
  retarget_input_slot : GraphTopologyInputSlot,
) -> Result[Unit, GraphTopologyEditError] {
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return Err(GraphTopologyEditError::InvalidNodeIndex(retarget_node_index))
  }
  let old_source = match
    topology_node_input(nodes[retarget_node_index], retarget_input_slot) {
    Some(old_source) => old_source
    None =>
      return Err(
        GraphTopologyEditError::UnsupportedInputSlot(
          retarget_node_index,
          retarget_input_slot,
          nodes[retarget_node_index].kind(),
        ),
      )
  }
  let inserted = match topology_inserted_node(inserted_template, old_source) {
    Some(inserted) => inserted
    None =>
      return Err(
        GraphTopologyEditError::UnsupportedInsertTemplate(
          inserted_template.kind(),
        ),
      )
  }
  let inserted_index = nodes.length()
  nodes.push(inserted)
  match
    apply_topology_rewire_input_result(
      nodes, retarget_node_index, retarget_input_slot, inserted_index,
    ) {
    Ok(_) => Ok(())
    Err(error) => {
      ignore(nodes.pop())
      Err(error)
    }
  }
}

///|
fn apply_topology_delete_node(
  nodes : Array[DspNode],
  delete_node_index : Int,
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  replacement_source_index : Int,
) -> Result[Unit, GraphTopologyEditError] {
  let unary_input = match
    topology_node_input(
      nodes[delete_node_index],
      GraphTopologyInputSlot::Input0,
    ) {
    Some(unary_input) => unary_input
    None =>
      return Err(
        GraphTopologyEditError::DeleteNodeRequiresUnary(
          delete_node_index,
          nodes[delete_node_index].kind(),
        ),
      )
  }
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return Err(GraphTopologyEditError::InvalidNodeIndex(retarget_node_index))
  }
  let consumer_index = match
    topology_single_consumer_for_input(nodes, delete_node_index) {
    Some(consumer_index) => consumer_index
    _ =>
      return Err(
        GraphTopologyEditError::DeleteNodeRequiresSingleConsumer(
          delete_node_index,
        ),
      )
  }
  if consumer_index != retarget_node_index {
    return Err(
      GraphTopologyEditError::DeleteNodeConsumerMismatch(
        consumer_index, retarget_node_index,
      ),
    )
  }
  // If the caller specified the deleted node itself as the replacement source,
  // substitute its upstream input instead — the deleted node won't exist.
  let expected_replacement = if replacement_source_index == delete_node_index {
    unary_input
  } else {
    replacement_source_index
  }
  match
    apply_topology_rewire_input_result(
      nodes, consumer_index, retarget_input_slot, expected_replacement,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let compacted : Array[DspNode] = []
  compacted.reserve_capacity(nodes.length() - 1)
  for index in 0..<nodes.length() {
    if index != delete_node_index {
      compacted.push(
        topology_compacted_node_inputs(nodes[index], delete_node_index),
      )
    }
  }
  nodes.clear()
  for node in compacted {
    nodes.push(node)
  }
  Ok(())
}

///|
fn apply_topology_insert_chain(
  nodes : Array[DspNode],
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> Result[Unit, GraphTopologyEditError] {
  if chain_nodes.is_empty() {
    return Err(GraphTopologyEditError::EmptyInsertChain)
  }
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return Err(GraphTopologyEditError::InvalidNodeIndex(retarget_node_index))
  }
  // Validate all chain nodes are unary (no input1)
  for index = 0; index < chain_nodes.length(); index = index + 1 {
    let node = chain_nodes[index]
    if node.input1() >= 0 {
      return Err(
        GraphTopologyEditError::UnsupportedChainNode(index, node.kind()),
      )
    }
  }
  // Get original source of the retarget node's input
  let old_source = match
    topology_node_input(nodes[retarget_node_index], retarget_input_slot) {
    Some(old_source) => old_source
    None =>
      return Err(
        GraphTopologyEditError::UnsupportedInputSlot(
          retarget_node_index,
          retarget_input_slot,
          nodes[retarget_node_index].kind(),
        ),
      )
  }
  // For each node in the chain: append to authoring array
  let mut prev_source = old_source
  let mut last_index = -1
  let first_chain_index = nodes.length()
  for chain_node in chain_nodes {
    let inserted = match topology_inserted_node(chain_node, prev_source) {
      Some(inserted) => inserted
      None => {
        // Roll back: remove all chain nodes appended so far
        while nodes.length() > first_chain_index {
          ignore(nodes.pop())
        }
        return Err(
          GraphTopologyEditError::UnsupportedInsertTemplate(chain_node.kind()),
        )
      }
    }
    last_index = nodes.length()
    nodes.push(inserted)
    prev_source = last_index
  }
  // Retarget the downstream node's input to the last chain node
  match
    apply_topology_rewire_input_result(
      nodes, retarget_node_index, retarget_input_slot, last_index,
    ) {
    Ok(_) => Ok(())
    Err(error) => {
      // Roll back
      while nodes.length() > first_chain_index {
        ignore(nodes.pop())
      }
      Err(error)
    }
  }
}

///|
fn apply_topology_delete_chain(
  nodes : Array[DspNode],
  start_node_index : Int,
  end_node_index : Int,
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  replacement_source_index : Int,
) -> Result[Unit, GraphTopologyEditError] {
  // Basic bounds check
  if start_node_index < 0 || start_node_index >= nodes.length() {
    return Err(GraphTopologyEditError::InvalidNodeIndex(start_node_index))
  }
  if end_node_index < 0 || end_node_index >= nodes.length() {
    return Err(GraphTopologyEditError::InvalidNodeIndex(end_node_index))
  }
  if start_node_index > end_node_index {
    return Err(
      GraphTopologyEditError::InvalidDeleteRange(
        start_node_index, end_node_index,
      ),
    )
  }
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return Err(GraphTopologyEditError::InvalidNodeIndex(retarget_node_index))
  }
  if replacement_source_index < 0 || replacement_source_index >= nodes.length() {
    return Err(
      GraphTopologyEditError::InvalidSourceIndex(replacement_source_index),
    )
  }
  // Reject if replacement_source is inside the deleted span
  if replacement_source_index >= start_node_index &&
    replacement_source_index <= end_node_index {
    return Err(
      GraphTopologyEditError::ReplacementSourceInDeletedRange(
        replacement_source_index,
      ),
    )
  }
  // Validate: each node in the chain must be unary (input1 < 0) and not
  // Output/StereoOutput, and each must feed exactly one downstream consumer
  for index = start_node_index; index <= end_node_index; index = index + 1 {
    let node = nodes[index]
    if node.input1() >= 0 {
      return Err(
        GraphTopologyEditError::DeleteChainRequiresUnary(index, node.kind()),
      )
    }
    if node.kind() is Output || node.kind() is StereoOutput {
      return Err(
        GraphTopologyEditError::DeleteChainRequiresUnary(index, node.kind()),
      )
    }
    let consumer = match topology_single_consumer_for_input(nodes, index) {
      Some(consumer) => consumer
      None =>
        return Err(
          GraphTopologyEditError::DeleteChainRequiresSingleConsumer(index),
        )
    }
    // Each chain node except the last must feed the next node in the chain
    if index < end_node_index {
      if consumer != index + 1 {
        return Err(
          GraphTopologyEditError::DeleteChainConsumerMismatch(
            index,
            consumer,
            index + 1,
          ),
        )
      }
      // Last chain node must feed the retarget node
    } else if consumer != retarget_node_index {
      return Err(
        GraphTopologyEditError::DeleteChainConsumerMismatch(
          index, consumer, retarget_node_index,
        ),
      )
    }
  }
  // Retarget the downstream node's input to the replacement source
  match
    apply_topology_rewire_input_result(
      nodes, retarget_node_index, retarget_input_slot, replacement_source_index,
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  // Build compacted array excluding all chain nodes, adjusting indices
  // We need to delete nodes from start_node_index to end_node_index inclusive
  let chain_count = end_node_index - start_node_index + 1
  let compacted : Array[DspNode] = []
  compacted.reserve_capacity(nodes.length() - chain_count)
  for index in 0..<nodes.length() {
    if index < start_node_index || index > end_node_index {
      let node = topology_chain_compacted_node_inputs(
        nodes[index],
        start_node_index,
        end_node_index,
      )
      compacted.push(node)
    }
  }
  nodes.clear()
  for node in compacted {
    nodes.push(node)
  }
  Ok(())
}

///|
fn topology_chain_compacted_node_inputs(
  node : DspNode,
  start_deleted : Int,
  end_deleted : Int,
) -> DspNode {
  @model.node_with_inputs(
    node,
    input0=topology_chain_compacted_input(
      node.input0(),
      start_deleted,
      end_deleted,
    ),
    input1=topology_chain_compacted_input(
      node.input1(),
      start_deleted,
      end_deleted,
    ),
  )
}

///|
fn topology_chain_compacted_input(
  input : Int,
  start_deleted : Int,
  end_deleted : Int,
) -> Int {
  if input < 0 {
    input
  } else if input > end_deleted {
    input - (end_deleted - start_deleted + 1)
  } else if input >= start_deleted {
    // This should not happen for valid graphs (we already rewired away from
    // deleted nodes), but return -1 as a safety measure
    -1
  } else {
    input
  }
}

///|
fn topology_single_consumer_for_input(
  nodes : Array[DspNode],
  source_index : Int,
) -> Int? {
  let mut consumer = -1
  for index in 0..<nodes.length() {
    let node = nodes[index]
    if node.input0() == source_index || node.input1() == source_index {
      if consumer >= 0 {
        return None
      }
      consumer = index
    }
  }
  if consumer >= 0 {
    Some(consumer)
  } else {
    None
  }
}

///|
fn topology_compacted_node_inputs(
  node : DspNode,
  deleted_index : Int,
) -> DspNode {
  @model.node_with_inputs(
    node,
    input0=topology_compacted_input(node.input0(), deleted_index),
    input1=topology_compacted_input(node.input1(), deleted_index),
  )
}

///|
fn topology_compacted_input(input : Int, deleted_index : Int) -> Int {
  if input >= 0 && input > deleted_index {
    input - 1
  } else {
    input
  }
}

///|
fn topology_node_input(
  node : DspNode,
  input_slot : GraphTopologyInputSlot,
) -> Int? {
  match (node.kind(), input_slot) {
    (DspNodeKind::Mul, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::Mul, GraphTopologyInputSlot::Input1) => Some(node.input1())
    (DspNodeKind::Mix, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::Mix, GraphTopologyInputSlot::Input1) => Some(node.input1())
    (DspNodeKind::Gain, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::Clip, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::Output, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::Pan, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::StereoGain, GraphTopologyInputSlot::Input0) =>
      Some(node.input0())
    (DspNodeKind::StereoClip, GraphTopologyInputSlot::Input0) =>
      Some(node.input0())
    (DspNodeKind::StereoMixDown, GraphTopologyInputSlot::Input0) =>
      Some(node.input0())
    (DspNodeKind::StereoOutput, GraphTopologyInputSlot::Input0) =>
      Some(node.input0())
    (DspNodeKind::Biquad, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::Delay, GraphTopologyInputSlot::Input0) => Some(node.input0())
    (DspNodeKind::StereoBiquad, GraphTopologyInputSlot::Input0) =>
      Some(node.input0())
    (DspNodeKind::StereoDelay, GraphTopologyInputSlot::Input0) =>
      Some(node.input0())
    _ => None
  }
}

///|
fn topology_inserted_node(template : DspNode, input_source : Int) -> DspNode? {
  match template.kind() {
    DspNodeKind::Gain
    | DspNodeKind::Clip
    | DspNodeKind::Pan
    | DspNodeKind::StereoGain
    | DspNodeKind::StereoClip
    | DspNodeKind::StereoMixDown
    | DspNodeKind::Output
    | DspNodeKind::StereoOutput
    | DspNodeKind::Biquad
    | DspNodeKind::Delay
    | DspNodeKind::StereoBiquad
    | DspNodeKind::StereoDelay =>
      Some(
        @model.node_with_inputs(
          template,
          input0=input_source,
          input1=template.input1(),
        ),
      )
    _ => None
  }
}

///|
fn apply_topology_rewire_input_result(
  nodes : Array[DspNode],
  node_index : Int,
  input_slot : GraphTopologyInputSlot,
  source_index : Int,
) -> Result[Unit, GraphTopologyEditError] {
  let node = nodes[node_index]
  match topology_node_input(node, input_slot) {
    Some(_) => {
      let input0 = match input_slot {
        GraphTopologyInputSlot::Input0 => source_index
        GraphTopologyInputSlot::Input1 => node.input0()
      }
      let input1 = match input_slot {
        GraphTopologyInputSlot::Input0 => node.input1()
        GraphTopologyInputSlot::Input1 => source_index
      }
      nodes[node_index] = @model.node_with_inputs(node, input0~, input1~)
      Ok(())
    }
    None =>
      Err(
        GraphTopologyEditError::UnsupportedInputSlot(
          node_index,
          input_slot,
          node.kind(),
        ),
      )
  }
}
