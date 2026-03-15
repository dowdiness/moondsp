///|
/// Narrow topology-edit kinds for compiled mono graphs.
pub(all) enum GraphTopologyEditKind {
  ReplaceNode
  RewireInput
  InsertNode
  DeleteNode
}

///|
/// Input slot selector for fixed-length topology rewiring.
pub(all) enum GraphTopologyInputSlot {
  Input0
  Input1
}

///|
/// Declarative topology edit applied in authoring order before recompilation.
pub struct GraphTopologyEdit {
  kind : GraphTopologyEditKind
  node_index : Int
  replacement : DspNode
  input_slot : GraphTopologyInputSlot
  source_index : Int

  fn new(
    kind : GraphTopologyEditKind,
    node_index : Int,
    replacement : DspNode,
    input_slot : GraphTopologyInputSlot,
    source_index : Int,
  ) -> GraphTopologyEdit
}

///|
fn GraphTopologyEdit::new(
  kind : GraphTopologyEditKind,
  node_index : Int,
  replacement : DspNode,
  input_slot : GraphTopologyInputSlot,
  source_index : Int,
) -> GraphTopologyEdit {
  { kind, node_index, replacement, input_slot, source_index }
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
  )
}

///|
/// Mono topology-edit wrapper that recompiles authoring nodes and stages the
/// replacement through `CompiledDspHotSwap`.
///
/// This first slice keeps edits narrow and deterministic: only `ReplaceNode`
/// and `RewireInput` frames are supported, plus narrow unary `InsertNode` and
/// `DeleteNode` frames on the mono path. Only one staged topology replacement
/// may be pending at a time.
struct CompiledDspTopologyController {
  mut authoring_nodes : Array[DspNode]
  compile_sample_rate : Double
  compile_block_size : Int
  hot_swap : CompiledDspHotSwap
}

///|
/// Build a topology-edit wrapper from authoring-order mono nodes.
pub fn CompiledDspTopologyController::from_nodes(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples? : Int = 0,
) -> CompiledDspTopologyController? {
  let compiled = match CompiledDsp::compile(nodes, context) {
    Some(compiled) => compiled
    None => return None
  }
  Some(
    make_compiled_dsp_topology_controller(
      nodes.copy(),
      context.sample_rate(),
      context.block_size(),
      CompiledDspHotSwap::from_graph(compiled, crossfade_samples~),
    ),
  )
}

///|
/// Apply one runtime control message to the active or in-flight mono graph.
pub fn CompiledDspTopologyController::apply_control(
  self : CompiledDspTopologyController,
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
  if !self.hot_swap.apply_control(control) {
    return false
  }
  self.authoring_nodes = updated_authoring_nodes
  true
}

///|
/// Apply a batch of runtime control messages to the active or in-flight mono
/// graph.
pub fn CompiledDspTopologyController::apply_controls(
  self : CompiledDspTopologyController,
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
  if !self.hot_swap.apply_controls(controls) {
    return false
  }
  self.authoring_nodes = updated_authoring_nodes
  true
}

///|
/// Queue one topology edit for the next hot-swap recompilation.
pub fn CompiledDspTopologyController::queue_topology_edit(
  self : CompiledDspTopologyController,
  edit : GraphTopologyEdit,
) -> Bool {
  self.queue_topology_edits([edit])
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
  let replacement = match CompiledDsp::compile(edited_nodes, compile_context) {
    Some(replacement) => replacement
    None => return false
  }
  if !self.hot_swap.queue_swap(replacement) {
    return false
  }
  self.authoring_nodes = edited_nodes
  true
}

///|
/// Process one block through the active or crossfading mono graph.
pub fn CompiledDspTopologyController::process(
  self : CompiledDspTopologyController,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  self.hot_swap.process(context, output)
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
fn topology_delete_marker(retarget_node_index : Int) -> DspNode {
  DspNode::output(retarget_node_index)
}

///|
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
fn make_compiled_dsp_topology_controller(
  authoring_nodes : Array[DspNode],
  compile_sample_rate : Double,
  compile_block_size : Int,
  hot_swap : CompiledDspHotSwap,
) -> CompiledDspTopologyController {
  { authoring_nodes, compile_sample_rate, compile_block_size, hot_swap }
}

///|
/// Terminal-stereo topology-edit wrapper that recompiles authoring nodes and
/// stages the replacement through `CompiledStereoDspHotSwap`.
///
/// This stereo parity slice keeps the same narrow semantics as the mono
/// controller: only `ReplaceNode` and `RewireInput` frames are supported,
/// graph length stays fixed, and only one staged topology replacement may be
/// pending at a time.
struct CompiledStereoDspTopologyController {
  mut authoring_nodes : Array[DspNode]
  compile_sample_rate : Double
  compile_block_size : Int
  hot_swap : CompiledStereoDspHotSwap
}

///|
/// Build a topology-edit wrapper from authoring-order terminal-stereo nodes.
pub fn CompiledStereoDspTopologyController::from_nodes(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspTopologyController? {
  let compiled = match CompiledStereoDsp::compile(nodes, context) {
    Some(compiled) => compiled
    None => return None
  }
  Some(
    make_compiled_stereo_dsp_topology_controller(
      nodes.copy(),
      context.sample_rate(),
      context.block_size(),
      CompiledStereoDspHotSwap::from_graph(compiled, crossfade_samples~),
    ),
  )
}

///|
/// Apply one runtime control message to the active or in-flight stereo graph.
pub fn CompiledStereoDspTopologyController::apply_control(
  self : CompiledStereoDspTopologyController,
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
  if !self.hot_swap.apply_control(control) {
    return false
  }
  self.authoring_nodes = updated_authoring_nodes
  true
}

///|
/// Apply a batch of runtime control messages to the active or in-flight stereo
/// graph.
pub fn CompiledStereoDspTopologyController::apply_controls(
  self : CompiledStereoDspTopologyController,
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
  if !self.hot_swap.apply_controls(controls) {
    return false
  }
  self.authoring_nodes = updated_authoring_nodes
  true
}

///|
/// Queue one topology edit for the next stereo hot-swap recompilation.
pub fn CompiledStereoDspTopologyController::queue_topology_edit(
  self : CompiledStereoDspTopologyController,
  edit : GraphTopologyEdit,
) -> Bool {
  self.queue_topology_edits([edit])
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
  if self.hot_swap.pending is Some(_) {
    return false
  }
  if !valid_stereo_topology_edits(edits) {
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
  let replacement = match
    CompiledStereoDsp::compile(edited_nodes, compile_context) {
    Some(replacement) => replacement
    None => return false
  }
  if !self.hot_swap.queue_swap(replacement) {
    return false
  }
  self.authoring_nodes = edited_nodes
  true
}

///|
fn valid_stereo_topology_edits(edits : Array[GraphTopologyEdit]) -> Bool {
  for index = 0; index < edits.length(); index = index + 1 {
    if edits[index].kind is InsertNode || edits[index].kind is DeleteNode {
      return false
    }
  }
  true
}

///|
/// Process one block through the active or crossfading stereo graph.
pub fn CompiledStereoDspTopologyController::process(
  self : CompiledStereoDspTopologyController,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  self.hot_swap.process(context, left_output, right_output)
}

///|
fn make_compiled_stereo_dsp_topology_controller(
  authoring_nodes : Array[DspNode],
  compile_sample_rate : Double,
  compile_block_size : Int,
  hot_swap : CompiledStereoDspHotSwap,
) -> CompiledStereoDspTopologyController {
  { authoring_nodes, compile_sample_rate, compile_block_size, hot_swap }
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
