///|
/// Narrow topology-edit kinds for compiled mono graphs.
pub(all) enum GraphTopologyEditKind {
  ReplaceNode
}

///|
/// Declarative topology edit applied in authoring order before recompilation.
pub struct GraphTopologyEdit {
  kind : GraphTopologyEditKind
  node_index : Int
  replacement : DspNode

  fn new(
    kind : GraphTopologyEditKind,
    node_index : Int,
    replacement : DspNode,
  ) -> GraphTopologyEdit
}

///|
fn GraphTopologyEdit::new(
  kind : GraphTopologyEditKind,
  node_index : Int,
  replacement : DspNode,
) -> GraphTopologyEdit {
  { kind, node_index, replacement }
}

///|
/// Replace one authoring-order node, including its kind and input wiring.
pub fn GraphTopologyEdit::replace_node(
  node_index : Int,
  replacement : DspNode,
) -> GraphTopologyEdit {
  GraphTopologyEdit(GraphTopologyEditKind::ReplaceNode, node_index, replacement)
}

///|
/// Mono topology-edit wrapper that recompiles authoring nodes and stages the
/// replacement through `CompiledDspHotSwap`.
///
/// This first slice keeps edits narrow and deterministic: only `ReplaceNode`
/// frames are supported, the graph length stays fixed, and only one staged
/// topology replacement may be pending at a time.
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
  self.hot_swap.apply_control(control)
}

///|
/// Apply a batch of runtime control messages to the active or in-flight mono
/// graph.
pub fn CompiledDspTopologyController::apply_controls(
  self : CompiledDspTopologyController,
  controls : Array[GraphControl],
) -> Bool {
  self.hot_swap.apply_controls(controls)
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
