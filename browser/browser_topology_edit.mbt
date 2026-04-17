///|
let topo_edit_gain : @ref.Ref[Double] = @ref.new(BROWSER_COMPILED_DEFAULT_GAIN)

///|
let topo_edit_inserted : @ref.Ref[Bool] = @ref.new(false)

///|
let compiled_topology_edit : GraphSlot[
  @lib.CompiledDspTopologyController,
  MonoOut,
] = GraphSlot::new(output=MonoOut::new(), compile=fn(ctx) {
  @lib.CompiledDspTopologyController::from_nodes(
    [
      @lib.DspNode::constant(BROWSER_COMPILED_DEFAULT_GAIN),
      @lib.DspNode::output(0),
    ],
    ctx,
    crossfade_samples=BROWSER_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
  )
})

///|
/// Initialize the browser proof graph that runs through
/// `CompiledDspTopologyController`.
pub fn init_compiled_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_topology_edit.ensure(sample_rate, block_size, on_rebuild=() => {
    topo_edit_inserted.val = false
  })
}

///|
/// Queue the fixed browser topology edit insertion that appends one gain node
/// before the output.
pub fn queue_compiled_topology_edit() -> Bool {
  let topology = match compiled_topology_edit.graph.val {
    Some(t) => t
    None => return false
  }
  if topo_edit_inserted.val {
    return false
  }
  let queued = topology.queue_topology_edit(
    @lib.GraphTopologyEdit::insert_node(
      1,
      @lib.GraphTopologyInputSlot::Input0,
      @lib.DspNode::gain(0, BROWSER_TOPOLOGY_EDIT_INSERTED_GAIN),
    ),
  )
  if queued {
    topo_edit_inserted.val = true
  }
  queued
}

///|
/// Queue the fixed browser topology edit deletion that removes the inserted
/// gain node and returns to the baseline graph.
pub fn queue_compiled_topology_delete_edit() -> Bool {
  let topology = match compiled_topology_edit.graph.val {
    Some(t) => t
    None => return false
  }
  if !topo_edit_inserted.val {
    return false
  }
  let queued = topology.queue_topology_edit(
    @lib.GraphTopologyEdit::delete_node(
      2,
      1,
      @lib.GraphTopologyInputSlot::Input0,
      2,
    ),
  )
  if queued {
    topo_edit_inserted.val = false
  }
  queued
}

///|
/// Update the fixed browser topology-edit gain control.
pub fn set_compiled_topology_edit_gain(gain : Double) -> Bool {
  if compiled_topology_edit.graph.val is None {
    return false
  }
  topo_edit_gain.val = gain
  true
}

///|
/// Run one render quantum through the browser proof
/// `CompiledDspTopologyController` graph.
pub fn process_compiled_topology_edit_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_topology_edit.ensure(sample_rate, block_size, on_rebuild=() => {
      topo_edit_inserted.val = false
    }) {
    return false
  }
  let topology = compiled_topology_edit.graph_val()
  if !topology.apply_control(
      @lib.GraphControl::set_param(
        0,
        @lib.GraphParamSlot::Value0,
        topo_edit_gain.val,
      ),
    ) {
    return false
  }
  topology.process(
    compiled_topology_edit.ctx_val(),
    compiled_topology_edit.output.get(),
  )
  true
}

///|
/// Read one sample from the most recent topology-edit browser output block.
pub fn compiled_topology_edit_output_sample(index : Int) -> Double {
  compiled_topology_edit.output.sample(index)
}

///|
fn reset_compiled_topology_edit_graph() -> Unit {
  compiled_topology_edit.reset()
  topo_edit_gain.val = BROWSER_COMPILED_DEFAULT_GAIN
  topo_edit_inserted.val = false
}
