///|
/// Narrow topology-edit kinds for compiled mono graphs.
pub(all) enum GraphTopologyEditKind {
  ReplaceNode
  RewireInput
  InsertNode
  DeleteNode
  InsertChain
  DeleteChain
} derive(Eq)

///|
/// Input slot selector for fixed-length topology rewiring.
pub(all) enum GraphTopologyInputSlot {
  Input0
  Input1
} derive(Eq)

///|
/// Declarative topology edit applied in authoring order before recompilation.
pub struct GraphTopologyEdit {
  kind : GraphTopologyEditKind
  node_index : Int
  replacement : DspNode
  input_slot : GraphTopologyInputSlot
  source_index : Int
  chain_nodes : Array[DspNode]
  end_node_index : Int
  replacement_source_index : Int

  fn new(
    kind : GraphTopologyEditKind,
    node_index : Int,
    replacement : DspNode,
    input_slot : GraphTopologyInputSlot,
    source_index : Int,
    chain_nodes : Array[DspNode],
    end_node_index : Int,
    replacement_source_index : Int,
  ) -> GraphTopologyEdit
}

///|
fn GraphTopologyEdit::new(
  kind : GraphTopologyEditKind,
  node_index : Int,
  replacement : DspNode,
  input_slot : GraphTopologyInputSlot,
  source_index : Int,
  chain_nodes : Array[DspNode],
  end_node_index : Int,
  replacement_source_index : Int,
) -> GraphTopologyEdit {
  {
    kind,
    node_index,
    replacement,
    input_slot,
    source_index,
    chain_nodes,
    end_node_index,
    replacement_source_index,
  }
}

///|
/// Replace one authoring-order node, including its kind and input wiring.
pub fn GraphTopologyEdit::replace_node(
  node_index : Int,
  replacement : DspNode,
) -> GraphTopologyEdit {
  GraphTopologyEdit(
    GraphTopologyEditKind::ReplaceNode,
    node_index,
    replacement,
    GraphTopologyInputSlot::Input0,
    -1,
    [],
    -1,
    -1,
  )
}

///|
/// Rewire one authoring-order node input to a different upstream source.
pub fn GraphTopologyEdit::rewire_input(
  node_index : Int,
  input_slot : GraphTopologyInputSlot,
  source_index : Int,
) -> GraphTopologyEdit {
  GraphTopologyEdit(
    GraphTopologyEditKind::RewireInput,
    node_index,
    DspNode::constant(0.0),
    input_slot,
    source_index,
    [],
    -1,
    -1,
  )
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
  GraphTopologyEdit(
    GraphTopologyEditKind::InsertNode,
    retarget_node_index,
    inserted_node,
    retarget_input_slot,
    -1,
    [],
    -1,
    -1,
  )
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
  GraphTopologyEdit(
    GraphTopologyEditKind::DeleteNode,
    delete_node_index,
    topology_delete_marker(retarget_node_index),
    retarget_input_slot,
    replacement_source_index,
    [],
    -1,
    -1,
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
  GraphTopologyEdit(
    GraphTopologyEditKind::InsertChain,
    retarget_node,
    DspNode::constant(0.0),
    input_slot,
    -1,
    chain_nodes,
    -1,
    -1,
  )
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
  GraphTopologyEdit(
    GraphTopologyEditKind::DeleteChain,
    start_node,
    topology_delete_marker(retarget_node),
    input_slot,
    replacement_source,
    [],
    end_node,
    replacement_source,
  )
}

///|
/// Shared topology-edit state for both mono and stereo compiled graphs.
///
/// Holds the authoring-order nodes, compile-time parameters, and the
/// hot-swap graph used for block-boundary graph replacement.
priv struct TopologyGraph {
  mut authoring_nodes : Array[DspNode]
  compile_sample_rate : Double
  compile_block_size : Int
  hot_swap : HotSwapGraph
}

///|
/// Mono topology-edit wrapper that recompiles authoring nodes and stages the
/// replacement through `HotSwapGraph`.
///
/// This first slice keeps edits narrow and deterministic: only `ReplaceNode`
/// and `RewireInput` frames are supported, plus narrow unary `InsertNode` and
/// `DeleteNode` frames on the mono path. Only one staged topology replacement
/// may be pending at a time.
struct CompiledDspTopologyController(TopologyGraph)

///|
/// Build a `TopologyGraph` from a compile+wrap callback.
///
/// WHY a callback instead of an enum: the mono and stereo paths produce
/// different concrete wrappers (`CompiledDspHotSwap` vs `CompiledStereoDspHotSwap`)
/// that allocate different buffer layouts (mono: old_output/new_output at
/// capacity; stereo: old_left/old_right/new_left/new_right). A callback lets
/// each `from_nodes` caller supply its variant-specific compile+unwrap logic
/// without a `GraphKind` enum and a match inside this function.
fn build_topology_graph(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples : Int,
  compile_and_wrap : (Array[DspNode], DspContext, Int) -> HotSwapGraph?,
) -> TopologyGraph? {
  let hot_swap = match compile_and_wrap(nodes, context, crossfade_samples) {
    Some(hs) => hs
    None => return None
  }
  Some({
    authoring_nodes: nodes.copy(),
    compile_sample_rate: context.sample_rate(),
    compile_block_size: context.block_size(),
    hot_swap,
  })
}

///|
/// Build a topology-edit wrapper from authoring-order mono nodes.
pub fn CompiledDspTopologyController::from_nodes(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples? : Int = 0,
) -> CompiledDspTopologyController? {
  build_topology_graph(nodes, context, crossfade_samples, fn(ns, ctx, xf) {
    match CompiledDsp::compile_raw(ns, ctx) {
      Some(compiled) =>
        Some(CompiledDspHotSwap::from_graph(compiled, crossfade_samples=xf).0)
      None => None
    }
  }).map(fn(tg) { CompiledDspTopologyController(tg) })
}

///|
/// Apply one runtime control message to the active or in-flight graph.
fn TopologyGraph::apply_control_impl(
  self : TopologyGraph,
  control : GraphControl,
) -> Bool {
  let updated_authoring_nodes = match
    topology_control_updated_nodes(
      self.authoring_nodes,
      self.compile_sample_rate,
      [control],
    ) {
    Some(updated_authoring_nodes) => updated_authoring_nodes
    None => return false
  }
  if !self.hot_swap.apply_control_impl(control) {
    return false
  }
  self.authoring_nodes = updated_authoring_nodes
  true
}

///|
/// Apply a batch of runtime control messages to the active or in-flight graph.
fn TopologyGraph::apply_controls_impl(
  self : TopologyGraph,
  controls : Array[GraphControl],
) -> Bool {
  let updated_authoring_nodes = match
    topology_control_updated_nodes(
      self.authoring_nodes,
      self.compile_sample_rate,
      controls,
    ) {
    Some(updated_authoring_nodes) => updated_authoring_nodes
    None => return false
  }
  if !self.hot_swap.apply_controls_impl(controls) {
    return false
  }
  self.authoring_nodes = updated_authoring_nodes
  true
}

///|
/// Queue one topology edit for the next hot-swap recompilation.
fn TopologyGraph::queue_topology_edit_impl(
  self : TopologyGraph,
  edit : GraphTopologyEdit,
  compile_fn : (Array[DspNode], DspContext) -> CompiledGraph?,
) -> Bool {
  self.queue_topology_edits_impl([edit], compile_fn)
}

///|
/// Queue an ordered topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
fn TopologyGraph::queue_topology_edits_impl(
  self : TopologyGraph,
  edits : Array[GraphTopologyEdit],
  compile_fn : (Array[DspNode], DspContext) -> CompiledGraph?,
) -> Bool {
  if self.hot_swap.pending is Some(_) {
    return false
  }
  let edited_nodes = self.authoring_nodes.copy()
  if !apply_topology_edits(edited_nodes, edits) {
    return false
  }
  let compile_context = DspContext::new(
    self.compile_sample_rate,
    self.compile_block_size,
  )
  let replacement = match compile_fn(edited_nodes, compile_context) {
    Some(replacement) => replacement
    None => return false
  }
  // Skip state copy after delete operations — authoring indices shift,
  // so position-based matching may copy state from the wrong node.
  // The crossfade smooths the transition with fresh state.
  let has_delete = edits
    .iter()
    .any(fn(e) {
      e.kind is GraphTopologyEditKind::DeleteNode ||
      e.kind is GraphTopologyEditKind::DeleteChain
    })
  if !has_delete {
    copy_compiled_graph_state(self.hot_swap.active, replacement)
  }
  if !self.hot_swap.queue_swap_impl(replacement) {
    return false
  }
  self.authoring_nodes = edited_nodes
  true
}

///|
/// Apply one runtime control message to the active or in-flight mono graph.
pub fn CompiledDspTopologyController::apply_control(
  self : CompiledDspTopologyController,
  control : GraphControl,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
/// Apply a batch of runtime control messages to the active or in-flight mono
/// graph.
pub fn CompiledDspTopologyController::apply_controls(
  self : CompiledDspTopologyController,
  controls : Array[GraphControl],
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
/// Queue one topology edit for the next hot-swap recompilation.
pub fn CompiledDspTopologyController::queue_topology_edit(
  self : CompiledDspTopologyController,
  edit : GraphTopologyEdit,
) -> Bool {
  self.0.queue_topology_edit_impl(edit, compile_mono_graph)
}

///|
/// Queue an ordered topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
pub fn CompiledDspTopologyController::queue_topology_edits(
  self : CompiledDspTopologyController,
  edits : Array[GraphTopologyEdit],
) -> Bool {
  self.0.queue_topology_edits_impl(edits, compile_mono_graph)
}

///|
/// Process one block through the active or crossfading mono graph.
pub fn CompiledDspTopologyController::process(
  self : CompiledDspTopologyController,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  CompiledDspHotSwap(self.0.hot_swap).process(context, output)
}

///|
fn apply_topology_edits(
  nodes : Array[DspNode],
  edits : Array[GraphTopologyEdit],
) -> Bool {
  for index = 0; index < edits.length(); index = index + 1 {
    if !apply_topology_edit(nodes, edits[index]) {
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
  match edit.kind {
    GraphTopologyEditKind::ReplaceNode =>
      if edit.node_index < 0 || edit.node_index >= nodes.length() {
        false
      } else {
        nodes[edit.node_index] = edit.replacement
        true
      }
    GraphTopologyEditKind::RewireInput =>
      if edit.node_index < 0 ||
        edit.node_index >= nodes.length() ||
        edit.source_index < 0 ||
        edit.source_index >= nodes.length() {
        false
      } else {
        apply_topology_rewire_input(
          nodes,
          edit.node_index,
          edit.input_slot,
          edit.source_index,
        )
      }
    GraphTopologyEditKind::InsertNode =>
      apply_topology_insert_node(
        nodes,
        edit.node_index,
        edit.replacement,
        edit.input_slot,
      )
    GraphTopologyEditKind::DeleteNode =>
      if edit.node_index < 0 ||
        edit.node_index >= nodes.length() ||
        edit.source_index < 0 ||
        edit.source_index >= nodes.length() {
        false
      } else {
        apply_topology_delete_node(
          nodes,
          edit.node_index,
          topology_delete_retarget_node_index(edit),
          edit.input_slot,
          edit.source_index,
        )
      }
    GraphTopologyEditKind::InsertChain =>
      apply_topology_insert_chain(
        nodes,
        edit.node_index,
        edit.input_slot,
        edit.chain_nodes,
      )
    GraphTopologyEditKind::DeleteChain =>
      apply_topology_delete_chain(
        nodes,
        edit.node_index,
        edit.end_node_index,
        topology_delete_retarget_node_index(edit),
        edit.input_slot,
        edit.replacement_source_index,
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
  for index = 0; index < nodes.length(); index = index + 1 {
    if index != delete_node_index {
      compacted.push(
        topology_compacted_node_inputs(nodes[index], delete_node_index),
      )
    }
  }
  nodes.clear()
  for index = 0; index < compacted.length(); index = index + 1 {
    nodes.push(compacted[index])
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
  for index = 0; index < chain_nodes.length(); index = index + 1 {
    if chain_nodes[index].input1 >= 0 {
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
  for index = 0; index < chain_nodes.length(); index = index + 1 {
    let inserted = match
      topology_inserted_node(chain_nodes[index], prev_source) {
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
  for index = 0; index < nodes.length(); index = index + 1 {
    if index < start_node_index || index > end_node_index {
      let mut node = nodes[index]
      // Compact inputs: shift down by the number of deleted nodes before each
      // reference
      node = topology_chain_compacted_node_inputs(
        node, start_node_index, end_node_index,
      )
      compacted.push(node)
    }
  }
  nodes.clear()
  for index = 0; index < compacted.length(); index = index + 1 {
    nodes.push(compacted[index])
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
/// Encode the retarget node index inside a DspNode for delete operations.
/// Uses DspNode::output because its input0 field stores a node index,
/// which we recover via topology_delete_retarget_node_index.
fn topology_delete_marker(retarget_node_index : Int) -> DspNode {
  DspNode::output(retarget_node_index)
}

///|
/// Decode the retarget node index from a delete edit's replacement marker.
fn topology_delete_retarget_node_index(edit : GraphTopologyEdit) -> Int {
  edit.replacement.input0
}

///|
fn topology_single_consumer_for_input(
  nodes : Array[DspNode],
  source_index : Int,
) -> Int? {
  let mut consumer = -1
  for index = 0; index < nodes.length(); index = index + 1 {
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
          input_source,
          template.filter_mode,
          template.value0,
          template.value1,
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
          source_index,
          node.filter_mode,
          node.value0,
          node.value1,
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

///|
/// Terminal-stereo topology-edit wrapper that recompiles authoring nodes and
/// stages the replacement through `HotSwapGraph`.
///
/// This stereo parity slice keeps the same narrow semantics as the mono
/// controller: only `ReplaceNode` and `RewireInput` frames are supported,
/// graph length stays fixed, and only one staged topology replacement may be
/// pending at a time.
struct CompiledStereoDspTopologyController(TopologyGraph)

///|
/// Build a topology-edit wrapper from authoring-order terminal-stereo nodes.
pub fn CompiledStereoDspTopologyController::from_nodes(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspTopologyController? {
  build_topology_graph(nodes, context, crossfade_samples, fn(ns, ctx, xf) {
    match CompiledStereoDsp::compile_raw(ns, ctx) {
      Some(compiled) =>
        Some(
          CompiledStereoDspHotSwap::from_graph(compiled, crossfade_samples=xf).0,
        )
      None => None
    }
  }).map(fn(tg) { CompiledStereoDspTopologyController(tg) })
}

///|
/// Apply one runtime control message to the active or in-flight stereo graph.
pub fn CompiledStereoDspTopologyController::apply_control(
  self : CompiledStereoDspTopologyController,
  control : GraphControl,
) -> Bool {
  self.0.apply_control_impl(control)
}

///|
/// Apply a batch of runtime control messages to the active or in-flight stereo
/// graph.
pub fn CompiledStereoDspTopologyController::apply_controls(
  self : CompiledStereoDspTopologyController,
  controls : Array[GraphControl],
) -> Bool {
  self.0.apply_controls_impl(controls)
}

///|
/// Queue one topology edit for the next stereo hot-swap recompilation.
pub fn CompiledStereoDspTopologyController::queue_topology_edit(
  self : CompiledStereoDspTopologyController,
  edit : GraphTopologyEdit,
) -> Bool {
  self.0.queue_topology_edit_impl(edit, compile_stereo_graph)
}

///|
/// Queue an ordered stereo topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
pub fn CompiledStereoDspTopologyController::queue_topology_edits(
  self : CompiledStereoDspTopologyController,
  edits : Array[GraphTopologyEdit],
) -> Bool {
  self.0.queue_topology_edits_impl(edits, compile_stereo_graph)
}

///|
/// Process one block through the active or crossfading stereo graph.
pub fn CompiledStereoDspTopologyController::process(
  self : CompiledStereoDspTopologyController,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  CompiledStereoDspHotSwap(self.0.hot_swap).process(
    context, left_output, right_output,
  )
}

///|
fn topology_control_updated_nodes(
  authoring_nodes : Array[DspNode],
  compile_sample_rate : Double,
  controls : Array[GraphControl],
) -> Array[DspNode]? {
  let updated_nodes = authoring_nodes.copy()
  for index = 0; index < controls.length(); index = index + 1 {
    if !apply_topology_runtime_control(
        updated_nodes,
        compile_sample_rate,
        controls[index],
      ) {
      return None
    }
  }
  Some(updated_nodes)
}

///|
fn apply_topology_runtime_control(
  nodes : Array[DspNode],
  compile_sample_rate : Double,
  control : GraphControl,
) -> Bool {
  match control.kind {
    SetParam => {
      if control.node_index < 0 || control.node_index >= nodes.length() {
        return false
      }
      let updated = match
        updated_node_param(
          nodes[control.node_index],
          control.slot,
          control.value,
          compile_sample_rate,
        ) {
        Some(updated) => updated
        None => return false
      }
      nodes[control.node_index] = updated
      true
    }
    _ => true
  }
}

///|
/// Compile helper for mono graphs, returning `CompiledGraph` directly.
fn compile_mono_graph(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledGraph? {
  CompiledDsp::compile_raw(nodes, context).map(fn(c) { c.0 })
}

///|
/// Compile helper for stereo graphs, returning `CompiledGraph` directly.
fn compile_stereo_graph(
  nodes : Array[DspNode],
  context : DspContext,
) -> CompiledGraph? {
  CompiledStereoDsp::compile_raw(nodes, context).map(fn(c) { c.0 })
}

///|
/// Copy runtime state from an old compiled graph to a new one for nodes
/// that share the same authoring index and node kind.
fn copy_compiled_graph_state(
  old_graph : CompiledGraph,
  new_graph : CompiledGraph,
) -> Unit {
  let old_map = old_graph.index_map
  let new_map = new_graph.index_map
  let shared_count = if old_map.length() < new_map.length() {
    old_map.length()
  } else {
    new_map.length()
  }
  for authoring_idx = 0
      authoring_idx < shared_count
      authoring_idx = authoring_idx + 1 {
    let old_compiled = old_map[authoring_idx]
    let new_compiled = new_map[authoring_idx]
    if old_compiled >= 0 &&
      new_compiled >= 0 &&
      old_compiled < old_graph.nodes.length() &&
      new_compiled < new_graph.nodes.length() &&
      old_graph.nodes[old_compiled].kind == new_graph.nodes[new_compiled].kind {
      new_graph.osc_states[new_compiled] = old_graph.osc_states[old_compiled]
      new_graph.noise_states[new_compiled] = old_graph.noise_states[old_compiled]
      new_graph.env_states[new_compiled] = old_graph.env_states[old_compiled]
      new_graph.biquad_states[new_compiled] = old_graph.biquad_states[old_compiled]
      new_graph.stereo_biquad_left_states[new_compiled] = old_graph.stereo_biquad_left_states[old_compiled]
      new_graph.stereo_biquad_right_states[new_compiled] = old_graph.stereo_biquad_right_states[old_compiled]
      // Only copy delay state if buffer capacity matches
      match
        (
          old_graph.delay_states[old_compiled],
          new_graph.delay_states[new_compiled],
        ) {
        (Some(old_delay), Some(new_delay)) =>
          if old_delay.max_delay_samples() == new_delay.max_delay_samples() {
            new_graph.delay_states[new_compiled] = old_graph.delay_states[old_compiled]
          }
        _ => ()
      }
      match
        (
          old_graph.stereo_delay_left_states[old_compiled],
          new_graph.stereo_delay_left_states[new_compiled],
        ) {
        (Some(old_delay), Some(new_delay)) =>
          if old_delay.max_delay_samples() == new_delay.max_delay_samples() {
            new_graph.stereo_delay_left_states[new_compiled] = old_graph.stereo_delay_left_states[old_compiled]
          }
        _ => ()
      }
      match
        (
          old_graph.stereo_delay_right_states[old_compiled],
          new_graph.stereo_delay_right_states[new_compiled],
        ) {
        (Some(old_delay), Some(new_delay)) =>
          if old_delay.max_delay_samples() == new_delay.max_delay_samples() {
            new_graph.stereo_delay_right_states[new_compiled] = old_graph.stereo_delay_right_states[old_compiled]
          }
        _ => ()
      }
      new_graph.self_values[new_compiled] = old_graph.self_values[old_compiled]
      new_graph.self_left_values[new_compiled] = old_graph.self_left_values[old_compiled]
      new_graph.self_right_values[new_compiled] = old_graph.self_right_values[old_compiled]
    }
  }
}
