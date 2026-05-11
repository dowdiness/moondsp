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
/// Failure reason for result-typed topology queue APIs.
pub(all) enum GraphTopologyQueueError {
  PendingSwap
  InvalidEdit(Int)
  RecompileRejected
  HotSwap(HotSwapQueueError)
} derive(Debug)

///|
pub impl Show for GraphTopologyQueueError with output(self, logger) {
  logger.write_string(@debug.to_string(self))
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
  self.apply_control_result_impl(control) is Ok(_)
}

///|
/// Apply one runtime control message to the active or in-flight graph.
fn TopologyGraph::apply_control_result_impl(
  self : TopologyGraph,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  let updated_authoring_nodes = match
    topology_control_updated_nodes_result(
      self.authoring_nodes,
      self.compile_sample_rate,
      [control],
    ) {
    Ok(updated_authoring_nodes) => updated_authoring_nodes
    Err(error) => return Err(error)
  }
  match self.hot_swap.apply_control_result_impl(control) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  self.authoring_nodes = updated_authoring_nodes
  Ok(())
}

///|
/// Apply a batch of runtime control messages to the active or in-flight graph.
fn TopologyGraph::apply_controls_impl(
  self : TopologyGraph,
  controls : Array[GraphControl],
) -> Bool {
  self.apply_controls_result_impl(controls) is Ok(_)
}

///|
/// Apply a batch of runtime control messages to the active or in-flight graph.
fn TopologyGraph::apply_controls_result_impl(
  self : TopologyGraph,
  controls : Array[GraphControl],
) -> Result[Unit, GraphControlError] {
  let updated_authoring_nodes = match
    topology_control_updated_nodes_result(
      self.authoring_nodes,
      self.compile_sample_rate,
      controls,
    ) {
    Ok(updated_authoring_nodes) => updated_authoring_nodes
    Err(error) => return Err(error)
  }
  match self.hot_swap.apply_controls_result_impl(controls) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  self.authoring_nodes = updated_authoring_nodes
  Ok(())
}

///|
/// Queue one topology edit for the next hot-swap recompilation.
fn TopologyGraph::queue_topology_edit_impl(
  self : TopologyGraph,
  edit : GraphTopologyEdit,
  compile_fn : (Array[DspNode], DspContext) -> CompiledGraph?,
) -> Bool {
  self.queue_topology_edit_result_impl(edit, compile_fn) is Ok(_)
}

///|
/// Queue one topology edit for the next hot-swap recompilation.
fn TopologyGraph::queue_topology_edit_result_impl(
  self : TopologyGraph,
  edit : GraphTopologyEdit,
  compile_fn : (Array[DspNode], DspContext) -> CompiledGraph?,
) -> Result[Unit, GraphTopologyQueueError] {
  self.queue_topology_edits_result_impl([edit], compile_fn)
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
  self.queue_topology_edits_result_impl(edits, compile_fn) is Ok(_)
}

///|
/// Queue an ordered topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
fn TopologyGraph::queue_topology_edits_result_impl(
  self : TopologyGraph,
  edits : Array[GraphTopologyEdit],
  compile_fn : (Array[DspNode], DspContext) -> CompiledGraph?,
) -> Result[Unit, GraphTopologyQueueError] {
  if self.hot_swap.pending is Some(_) {
    return Err(GraphTopologyQueueError::PendingSwap)
  }
  let edited_nodes = self.authoring_nodes.copy()
  match apply_topology_edits_result(edited_nodes, edits) {
    Ok(_) => ()
    Err(index) => return Err(GraphTopologyQueueError::InvalidEdit(index))
  }
  let compile_context = DspContext::new(
    sample_rate=self.compile_sample_rate,
    block_size=self.compile_block_size,
  )
  let replacement = match compile_fn(edited_nodes, compile_context) {
    Some(replacement) => replacement
    None => return Err(GraphTopologyQueueError::RecompileRejected)
  }
  // Skip state copy after delete operations — authoring indices shift,
  // so position-based matching may copy state from the wrong node.
  // The crossfade smooths the transition with fresh state.
  let has_delete = edits
    .iter()
    .any(fn(e) { e is DeleteNode(_) || e is DeleteChain(_) })
  if !has_delete {
    copy_compiled_graph_state(self.hot_swap.active, replacement)
  }
  match self.hot_swap.queue_swap_result_impl(replacement) {
    Ok(_) => ()
    Err(error) => return Err(GraphTopologyQueueError::HotSwap(error))
  }
  self.authoring_nodes = edited_nodes
  Ok(())
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
/// Queue one topology edit for the next hot-swap recompilation.
pub fn CompiledDspTopologyController::queue_topology_edit_result(
  self : CompiledDspTopologyController,
  edit : GraphTopologyEdit,
) -> Result[Unit, GraphTopologyQueueError] {
  self.0.queue_topology_edit_result_impl(edit, compile_mono_graph)
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
/// Queue an ordered topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
pub fn CompiledDspTopologyController::queue_topology_edits_result(
  self : CompiledDspTopologyController,
  edits : Array[GraphTopologyEdit],
) -> Result[Unit, GraphTopologyQueueError] {
  self.0.queue_topology_edits_result_impl(edits, compile_mono_graph)
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
/// Terminal-stereo topology-edit wrapper that recompiles authoring nodes and
/// stages the replacement through `HotSwapGraph`.
///
/// Supports the same edit kinds as the mono controller (all six variants
/// of `GraphTopologyEdit`). Only one staged topology replacement may be
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
/// Queue one topology edit for the next stereo hot-swap recompilation.
pub fn CompiledStereoDspTopologyController::queue_topology_edit(
  self : CompiledStereoDspTopologyController,
  edit : GraphTopologyEdit,
) -> Bool {
  self.0.queue_topology_edit_impl(edit, compile_stereo_graph)
}

///|
/// Queue one topology edit for the next stereo hot-swap recompilation.
pub fn CompiledStereoDspTopologyController::queue_topology_edit_result(
  self : CompiledStereoDspTopologyController,
  edit : GraphTopologyEdit,
) -> Result[Unit, GraphTopologyQueueError] {
  self.0.queue_topology_edit_result_impl(edit, compile_stereo_graph)
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
/// Queue an ordered stereo topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
pub fn CompiledStereoDspTopologyController::queue_topology_edits_result(
  self : CompiledStereoDspTopologyController,
  edits : Array[GraphTopologyEdit],
) -> Result[Unit, GraphTopologyQueueError] {
  self.0.queue_topology_edits_result_impl(edits, compile_stereo_graph)
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
fn topology_control_updated_nodes_result(
  authoring_nodes : Array[DspNode],
  compile_sample_rate : Double,
  controls : Array[GraphControl],
) -> Result[Array[DspNode], GraphControlError] {
  let updated_nodes = authoring_nodes.copy()
  for control in controls {
    match
      apply_topology_runtime_control_result(
        updated_nodes, compile_sample_rate, control,
      ) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(updated_nodes)
}

///|
fn apply_topology_runtime_control_result(
  nodes : Array[DspNode],
  compile_sample_rate : Double,
  control : GraphControl,
) -> Result[Unit, GraphControlError] {
  match control.kind {
    SetParam => {
      if control.node_index < 0 || control.node_index >= nodes.length() {
        return Err(GraphControlError::InvalidNodeIndex(control.node_index))
      }
      let updated = match
        updated_node_param_result(
          nodes[control.node_index],
          control.node_index,
          control.slot,
          control.value,
          compile_sample_rate,
        ) {
        Ok(updated) => updated
        Err(error) => return Err(error)
      }
      nodes[control.node_index] = updated
      Ok(())
    }
    _ => Ok(())
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
