///|
/// Failure reason for result-typed topology queue APIs.
pub(all) enum GraphTopologyEditError {
  InvalidNodeIndex(Int)
  InvalidSourceIndex(Int)
  UnsupportedInputSlot(Int, GraphTopologyInputSlot, DspNodeKind)
  UnsupportedInsertTemplate(DspNodeKind)
  EmptyInsertChain
  UnsupportedChainNode(Int, DspNodeKind)
  InvalidDeleteRange(Int, Int)
  ReplacementSourceInDeletedRange(Int)
  DeleteNodeRequiresUnary(Int, DspNodeKind)
  DeleteNodeRequiresSingleConsumer(Int)
  DeleteNodeConsumerMismatch(Int, Int)
  DeleteChainRequiresUnary(Int, DspNodeKind)
  DeleteChainRequiresSingleConsumer(Int)
  DeleteChainConsumerMismatch(Int, Int, Int)
} derive(Debug)

///|
pub impl Show for GraphTopologyEditError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Failure reason for result-typed topology queue APIs.
pub(all) enum GraphTopologyQueueError {
  PendingSwap
  InvalidEdit(Int, GraphTopologyEditError)
  RecompileRejected
  HotSwap(HotSwapQueueError)
} derive(Debug)

///|
pub impl Show for GraphTopologyQueueError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn graph_topology_edit_error_from_staging(
  error : @staging.GraphTopologyEditError,
) -> GraphTopologyEditError {
  match error {
    @staging.GraphTopologyEditError::InvalidNodeIndex(index) =>
      GraphTopologyEditError::InvalidNodeIndex(index)
    @staging.GraphTopologyEditError::InvalidSourceIndex(index) =>
      GraphTopologyEditError::InvalidSourceIndex(index)
    @staging.GraphTopologyEditError::UnsupportedInputSlot(index, slot, kind) =>
      GraphTopologyEditError::UnsupportedInputSlot(
        index,
        graph_topology_input_slot_from_staging(slot),
        dsp_node_kind_from_model(kind),
      )
    @staging.GraphTopologyEditError::UnsupportedInsertTemplate(kind) =>
      GraphTopologyEditError::UnsupportedInsertTemplate(
        dsp_node_kind_from_model(kind),
      )
    @staging.GraphTopologyEditError::EmptyInsertChain =>
      GraphTopologyEditError::EmptyInsertChain
    @staging.GraphTopologyEditError::UnsupportedChainNode(index, kind) =>
      GraphTopologyEditError::UnsupportedChainNode(
        index,
        dsp_node_kind_from_model(kind),
      )
    @staging.GraphTopologyEditError::InvalidDeleteRange(start_index, end_index) =>
      GraphTopologyEditError::InvalidDeleteRange(start_index, end_index)
    @staging.GraphTopologyEditError::ReplacementSourceInDeletedRange(index) =>
      GraphTopologyEditError::ReplacementSourceInDeletedRange(index)
    @staging.GraphTopologyEditError::DeleteNodeRequiresUnary(index, kind) =>
      GraphTopologyEditError::DeleteNodeRequiresUnary(
        index,
        dsp_node_kind_from_model(kind),
      )
    @staging.GraphTopologyEditError::DeleteNodeRequiresSingleConsumer(index) =>
      GraphTopologyEditError::DeleteNodeRequiresSingleConsumer(index)
    @staging.GraphTopologyEditError::DeleteNodeConsumerMismatch(
      consumer,
      retarget
    ) => GraphTopologyEditError::DeleteNodeConsumerMismatch(consumer, retarget)
    @staging.GraphTopologyEditError::DeleteChainRequiresUnary(index, kind) =>
      GraphTopologyEditError::DeleteChainRequiresUnary(
        index,
        dsp_node_kind_from_model(kind),
      )
    @staging.GraphTopologyEditError::DeleteChainRequiresSingleConsumer(index) =>
      GraphTopologyEditError::DeleteChainRequiresSingleConsumer(index)
    @staging.GraphTopologyEditError::DeleteChainConsumerMismatch(
      index,
      consumer,
      expected
    ) =>
      GraphTopologyEditError::DeleteChainConsumerMismatch(
        index, consumer, expected,
      )
  }
}

///|
fn graph_topology_queue_error_from_staging(
  error : @staging.GraphTopologyQueueError,
) -> GraphTopologyQueueError {
  match error {
    @staging.GraphTopologyQueueError::PendingSwap =>
      GraphTopologyQueueError::PendingSwap
    @staging.GraphTopologyQueueError::InvalidEdit(index, reason) =>
      GraphTopologyQueueError::InvalidEdit(
        index,
        graph_topology_edit_error_from_staging(reason),
      )
    @staging.GraphTopologyQueueError::RecompileRejected =>
      GraphTopologyQueueError::RecompileRejected
    @staging.GraphTopologyQueueError::HotSwap(error) =>
      GraphTopologyQueueError::HotSwap(hot_swap_queue_error_from_staging(error))
  }
}

///|
fn graph_topology_queue_result_from_staging(
  result : Result[Unit, @staging.GraphTopologyQueueError],
) -> Result[Unit, GraphTopologyQueueError] {
  match result {
    Ok(_) => Ok(())
    Err(error) => Err(graph_topology_queue_error_from_staging(error))
  }
}

///|
fn graph_topology_edits_to_staging(
  edits : Array[GraphTopologyEdit],
) -> Array[@staging.GraphTopologyEdit] {
  let raw_edits = Array::new(capacity=edits.length())
  for edit in edits {
    raw_edits.push(edit.to_staging())
  }
  raw_edits
}

///|
/// Mono topology-edit wrapper that recompiles authoring nodes and stages the
/// replacement through the internal hot-swap graph.
///
/// Public facade wrapper; implementation lives in `graph/internal/staging`.
struct CompiledDspTopologyController(@staging.CompiledDspTopologyController)

///|
/// Build a topology-edit wrapper from authoring-order mono nodes.
pub fn CompiledDspTopologyController::from_nodes(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples? : Int = 0,
) -> CompiledDspTopologyController? {
  @staging.CompiledDspTopologyController::from_nodes(
    dsp_nodes_to_model(nodes),
    context,
    crossfade_samples~,
  ).map(fn(raw) { CompiledDspTopologyController(raw) })
}

///|
/// Queue one topology edit for the next hot-swap recompilation.
pub fn CompiledDspTopologyController::queue_topology_edit(
  self : CompiledDspTopologyController,
  edit : GraphTopologyEdit,
) -> Result[Unit, GraphTopologyQueueError] {
  graph_topology_queue_result_from_staging(
    self.0.queue_topology_edit(edit.to_staging()),
  )
}

///|
/// Queue an ordered topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
pub fn CompiledDspTopologyController::queue_topology_edits(
  self : CompiledDspTopologyController,
  edits : Array[GraphTopologyEdit],
) -> Result[Unit, GraphTopologyQueueError] {
  graph_topology_queue_result_from_staging(
    self.0.queue_topology_edits(graph_topology_edits_to_staging(edits)),
  )
}

///|
/// Process one block through the active or crossfading mono graph.
pub fn CompiledDspTopologyController::process(
  self : CompiledDspTopologyController,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  self.0.process(context, output)
}

///|
/// Terminal-stereo topology-edit wrapper that recompiles authoring nodes and
/// stages the replacement through the internal hot-swap graph.
///
/// Public facade wrapper; implementation lives in `graph/internal/staging`.
struct CompiledStereoDspTopologyController(
  @staging.CompiledStereoDspTopologyController
)

///|
/// Build a topology-edit wrapper from authoring-order terminal-stereo nodes.
pub fn CompiledStereoDspTopologyController::from_nodes(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspTopologyController? {
  @staging.CompiledStereoDspTopologyController::from_nodes(
    dsp_nodes_to_model(nodes),
    context,
    crossfade_samples~,
  ).map(fn(raw) { CompiledStereoDspTopologyController(raw) })
}

///|
/// Queue one topology edit for the next stereo hot-swap recompilation.
pub fn CompiledStereoDspTopologyController::queue_topology_edit(
  self : CompiledStereoDspTopologyController,
  edit : GraphTopologyEdit,
) -> Result[Unit, GraphTopologyQueueError] {
  graph_topology_queue_result_from_staging(
    self.0.queue_topology_edit(edit.to_staging()),
  )
}

///|
/// Queue an ordered stereo topology-edit batch.
///
/// The batch is transactional: invalid node indices or a recompilation failure
/// reject the whole edit set and leave the current graph unchanged.
pub fn CompiledStereoDspTopologyController::queue_topology_edits(
  self : CompiledStereoDspTopologyController,
  edits : Array[GraphTopologyEdit],
) -> Result[Unit, GraphTopologyQueueError] {
  graph_topology_queue_result_from_staging(
    self.0.queue_topology_edits(graph_topology_edits_to_staging(edits)),
  )
}

///|
/// Process one block through the active or crossfading stereo graph.
pub fn CompiledStereoDspTopologyController::process(
  self : CompiledStereoDspTopologyController,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  self.0.process(context, left_output, right_output)
}
