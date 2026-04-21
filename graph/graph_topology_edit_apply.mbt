///|
fn apply_topology_edits(
  nodes : Array[DspNode],
  edits : Array[GraphTopologyEdit],
) -> Bool {
  for edit in edits {
    if !apply_topology_edit(nodes, edit) {
      return false
    }
  }
  true
}

///|
fn apply_topology_edit(
  nodes : Array[DspNode],
  edit : GraphTopologyEdit,
) -> Bool {
  match edit {
    ReplaceNode(node_index, replacement) =>
      if node_index < 0 || node_index >= nodes.length() {
        false
      } else {
        nodes[node_index] = replacement
        true
      }
    RewireInput(node_index, input_slot, source_index) =>
      if node_index < 0 ||
        node_index >= nodes.length() ||
        source_index < 0 ||
        source_index >= nodes.length() {
        false
      } else {
        apply_topology_rewire_input(nodes, node_index, input_slot, source_index)
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
        false
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
) -> Bool {
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return false
  }
  let old_source = match
    topology_node_input(nodes[retarget_node_index], retarget_input_slot) {
    Some(old_source) => old_source
    None => return false
  }
  let inserted = match topology_inserted_node(inserted_template, old_source) {
    Some(inserted) => inserted
    None => return false
  }
  let inserted_index = nodes.length()
  nodes.push(inserted)
  if apply_topology_rewire_input(
      nodes, retarget_node_index, retarget_input_slot, inserted_index,
    ) {
    true
  } else {
    ignore(nodes.pop())
    false
  }
}

///|
fn apply_topology_delete_node(
  nodes : Array[DspNode],
  delete_node_index : Int,
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  replacement_source_index : Int,
) -> Bool {
  let unary_input = match
    topology_node_input(
      nodes[delete_node_index],
      GraphTopologyInputSlot::Input0,
    ) {
    Some(unary_input) => unary_input
    None => return false
  }
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return false
  }
  let consumer_index = match
    topology_single_consumer_for_input(nodes, delete_node_index) {
    Some(consumer_index) => consumer_index
    _ => return false
  }
  if consumer_index != retarget_node_index {
    return false
  }
  // If the caller specified the deleted node itself as the replacement source,
  // substitute its upstream input instead — the deleted node won't exist.
  let expected_replacement = if replacement_source_index == delete_node_index {
    unary_input
  } else {
    replacement_source_index
  }
  if !apply_topology_rewire_input(
      nodes, consumer_index, retarget_input_slot, expected_replacement,
    ) {
    return false
  }
  let compacted = Array::new(capacity=nodes.length() - 1)
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
  true
}

///|
fn apply_topology_insert_chain(
  nodes : Array[DspNode],
  retarget_node_index : Int,
  retarget_input_slot : GraphTopologyInputSlot,
  chain_nodes : Array[DspNode],
) -> Bool {
  if chain_nodes.length() == 0 {
    return false
  }
  if retarget_node_index < 0 || retarget_node_index >= nodes.length() {
    return false
  }
  // Validate all chain nodes are unary (no input1)
  for node in chain_nodes {
    if node.input1 >= 0 {
      return false
    }
  }
  // Get original source of the retarget node's input
  let old_source = match
    topology_node_input(nodes[retarget_node_index], retarget_input_slot) {
    Some(old_source) => old_source
    None => return false
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
        return false
      }
    }
    last_index = nodes.length()
    nodes.push(inserted)
    prev_source = last_index
  }
  // Retarget the downstream node's input to the last chain node
  if apply_topology_rewire_input(
      nodes, retarget_node_index, retarget_input_slot, last_index,
    ) {
    true
  } else {
    // Roll back
    while nodes.length() > first_chain_index {
      ignore(nodes.pop())
    }
    false
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
) -> Bool {
  // Basic bounds check
  if start_node_index < 0 ||
    start_node_index >= nodes.length() ||
    end_node_index < 0 ||
    end_node_index >= nodes.length() ||
    start_node_index > end_node_index ||
    retarget_node_index < 0 ||
    retarget_node_index >= nodes.length() ||
    replacement_source_index < 0 ||
    replacement_source_index >= nodes.length() {
    return false
  }
  // Reject if replacement_source is inside the deleted span
  if replacement_source_index >= start_node_index &&
    replacement_source_index <= end_node_index {
    return false
  }
  // Validate: each node in the chain must be unary (input1 < 0) and not
  // Output/StereoOutput, and each must feed exactly one downstream consumer
  for index = start_node_index; index <= end_node_index; index = index + 1 {
    let node = nodes[index]
    if node.input1 >= 0 {
      return false
    }
    if node.kind is Output || node.kind is StereoOutput {
      return false
    }
    let consumer = match topology_single_consumer_for_input(nodes, index) {
      Some(consumer) => consumer
      None => return false
    }
    // Each chain node except the last must feed the next node in the chain
    if index < end_node_index {
      if consumer != index + 1 {
        return false
      }
      // Last chain node must feed the retarget node
    } else if consumer != retarget_node_index {
      return false
    }
  }
  // Retarget the downstream node's input to the replacement source
  if !apply_topology_rewire_input(
      nodes, retarget_node_index, retarget_input_slot, replacement_source_index,
    ) {
    return false
  }
  // Build compacted array excluding all chain nodes, adjusting indices
  // We need to delete nodes from start_node_index to end_node_index inclusive
  let chain_count = end_node_index - start_node_index + 1
  let compacted = Array::new(capacity=nodes.length() - chain_count)
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
  true
}

///|
fn topology_chain_compacted_node_inputs(
  node : DspNode,
  start_deleted : Int,
  end_deleted : Int,
) -> DspNode {
  DspNode(
    node.kind,
    topology_chain_compacted_input(node.input0, start_deleted, end_deleted),
    topology_chain_compacted_input(node.input1, start_deleted, end_deleted),
    node.value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
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
    if node.input0 == source_index || node.input1 == source_index {
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
  DspNode(
    node.kind,
    topology_compacted_input(node.input0, deleted_index),
    topology_compacted_input(node.input1, deleted_index),
    node.value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
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
  match (node.kind, input_slot) {
    (DspNodeKind::Mul, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::Mul, GraphTopologyInputSlot::Input1) => Some(node.input1)
    (DspNodeKind::Mix, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::Mix, GraphTopologyInputSlot::Input1) => Some(node.input1)
    (DspNodeKind::Gain, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::Clip, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::Output, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::Pan, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::StereoGain, GraphTopologyInputSlot::Input0) =>
      Some(node.input0)
    (DspNodeKind::StereoClip, GraphTopologyInputSlot::Input0) =>
      Some(node.input0)
    (DspNodeKind::StereoMixDown, GraphTopologyInputSlot::Input0) =>
      Some(node.input0)
    (DspNodeKind::StereoOutput, GraphTopologyInputSlot::Input0) =>
      Some(node.input0)
    (DspNodeKind::Biquad, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::Delay, GraphTopologyInputSlot::Input0) => Some(node.input0)
    (DspNodeKind::StereoBiquad, GraphTopologyInputSlot::Input0) =>
      Some(node.input0)
    (DspNodeKind::StereoDelay, GraphTopologyInputSlot::Input0) =>
      Some(node.input0)
    _ => None
  }
}

///|
fn topology_inserted_node(template : DspNode, input_source : Int) -> DspNode? {
  match template.kind {
    DspNodeKind::Gain => Some(DspNode::gain(input_source, template.value0))
    DspNodeKind::Clip => Some(DspNode::clip(input_source, template.value0))
    DspNodeKind::Pan => Some(DspNode::pan(input_source, template.value0))
    DspNodeKind::StereoGain =>
      Some(DspNode::stereo_gain(input_source, template.value0))
    DspNodeKind::StereoClip =>
      Some(DspNode::stereo_clip(input_source, template.value0))
    DspNodeKind::StereoMixDown => Some(DspNode::stereo_mixdown(input_source))
    DspNodeKind::Output => Some(DspNode::output(input_source))
    DspNodeKind::StereoOutput => Some(DspNode::stereo_output(input_source))
    DspNodeKind::Biquad =>
      Some(
        DspNode::biquad(
          input=input_source,
          mode=template.filter_mode,
          cutoff_hz=template.value0,
          q=template.value1,
        ),
      )
    DspNodeKind::Delay =>
      Some(
        DspNode::delay(
          input_source,
          template.delay_max_samples,
          delay_samples=template.delay_samples,
          feedback=template.value0,
        ),
      )
    DspNodeKind::StereoBiquad =>
      Some(
        DspNode::stereo_biquad(
          input_source,
          template.filter_mode,
          template.value0,
          template.value1,
        ),
      )
    DspNodeKind::StereoDelay =>
      Some(
        DspNode::stereo_delay(
          input_source,
          template.delay_max_samples,
          delay_samples=template.delay_samples,
          feedback=template.value0,
        ),
      )
    _ => None
  }
}

///|
fn apply_topology_rewire_input(
  nodes : Array[DspNode],
  node_index : Int,
  input_slot : GraphTopologyInputSlot,
  source_index : Int,
) -> Bool {
  let node = nodes[node_index]
  let rewired = match (node.kind, input_slot) {
    (DspNodeKind::Gain, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::gain(source_index, node.value0))
    (DspNodeKind::Mul, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::mul(source_index, node.input1))
    (DspNodeKind::Mul, GraphTopologyInputSlot::Input1) =>
      Some(DspNode::mul(node.input0, source_index))
    (DspNodeKind::Mix, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::mix(source_index, node.input1))
    (DspNodeKind::Mix, GraphTopologyInputSlot::Input1) =>
      Some(DspNode::mix(node.input0, source_index))
    (DspNodeKind::Clip, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::clip(source_index, node.value0))
    (DspNodeKind::Output, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::output(source_index))
    (DspNodeKind::Pan, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::pan(source_index, node.value0))
    (DspNodeKind::StereoGain, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::stereo_gain(source_index, node.value0))
    (DspNodeKind::StereoClip, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::stereo_clip(source_index, node.value0))
    (DspNodeKind::StereoMixDown, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::stereo_mixdown(source_index))
    (DspNodeKind::StereoOutput, GraphTopologyInputSlot::Input0) =>
      Some(DspNode::stereo_output(source_index))
    (DspNodeKind::Biquad, GraphTopologyInputSlot::Input0) =>
      Some(
        DspNode::biquad(
          input=source_index,
          mode=node.filter_mode,
          cutoff_hz=node.value0,
          q=node.value1,
        ),
      )
    (DspNodeKind::Delay, GraphTopologyInputSlot::Input0) =>
      Some(
        DspNode::delay(
          source_index,
          node.delay_max_samples,
          delay_samples=node.delay_samples,
          feedback=node.value0,
        ),
      )
    (DspNodeKind::StereoBiquad, GraphTopologyInputSlot::Input0) =>
      Some(
        DspNode::stereo_biquad(
          source_index,
          node.filter_mode,
          node.value0,
          node.value1,
        ),
      )
    (DspNodeKind::StereoDelay, GraphTopologyInputSlot::Input0) =>
      Some(
        DspNode::stereo_delay(
          source_index,
          node.delay_max_samples,
          delay_samples=node.delay_samples,
          feedback=node.value0,
        ),
      )
    _ => None
  }
  match rewired {
    Some(rewired) => {
      nodes[node_index] = rewired
      true
    }
    None => false
  }
}
