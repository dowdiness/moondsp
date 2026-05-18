///|
let topo_edit_gain : @ref.Ref[Double] = @ref.new(BROWSER_COMPILED_DEFAULT_GAIN)

///|
let topo_edit_inserted : @ref.Ref[Bool] = @ref.new(false)

///|
let compiled_topology_edit : GraphSlot[
  @moondsp.CompiledDspTopologyController,
  MonoOut,
] = GraphSlot::new(output=MonoOut::new(), compile=fn(ctx) {
  @moondsp.CompiledDspTopologyController::from_nodes(
    [
      @moondsp.DspNode::constant(BROWSER_COMPILED_DEFAULT_GAIN),
      @moondsp.DspNode::output(0),
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
  if compiled_topology_edit.ensure(sample_rate, block_size, on_rebuild=() => {
      topo_edit_inserted.val = false
    }) {
    clear_browser_error()
    true
  } else {
    set_browser_init_error("compiled_topology_edit.init")
  }
}

///|
/// Queue the fixed browser topology edit insertion that appends one gain node
/// before the output.
pub fn queue_compiled_topology_edit() -> Bool {
  let topology = match compiled_topology_edit.graph.val {
    Some(t) => t
    None => return set_browser_not_initialized("compiled_topology_edit.queue")
  }
  if topo_edit_inserted.val {
    return set_browser_error(
      BROWSER_ERROR_TOPOLOGY_QUEUE,
      "compiled_topology_edit.queue: insert already queued",
    )
  }
  match
    topology.queue_topology_edit(
      @moondsp.GraphTopologyEdit::insert_node(
        1,
        @moondsp.GraphTopologyInputSlot::Input0,
        @moondsp.DspNode::gain(0, BROWSER_TOPOLOGY_EDIT_INSERTED_GAIN),
      ),
    ) {
    Ok(_) => {
      topo_edit_inserted.val = true
      clear_browser_error()
      true
    }
    Err(error) =>
      set_browser_topology_queue_error("compiled_topology_edit.queue", error)
  }
}

///|
/// Queue the fixed browser topology edit deletion that removes the inserted
/// gain node and returns to the baseline graph.
pub fn queue_compiled_topology_delete_edit() -> Bool {
  let topology = match compiled_topology_edit.graph.val {
    Some(t) => t
    None => return set_browser_not_initialized("compiled_topology_delete.queue")
  }
  if !topo_edit_inserted.val {
    return set_browser_error(
      BROWSER_ERROR_TOPOLOGY_QUEUE,
      "compiled_topology_delete.queue: no inserted node to delete",
    )
  }
  match
    topology.queue_topology_edit(
      @moondsp.GraphTopologyEdit::delete_node(
        2,
        1,
        @moondsp.GraphTopologyInputSlot::Input0,
        2,
      ),
    ) {
    Ok(_) => {
      topo_edit_inserted.val = false
      clear_browser_error()
      true
    }
    Err(error) =>
      set_browser_topology_queue_error("compiled_topology_delete.queue", error)
  }
}

///|
/// Update the fixed browser topology-edit gain control.
pub fn set_compiled_topology_edit_gain(gain : Double) -> Bool {
  if compiled_topology_edit.graph.val is None {
    return set_browser_not_initialized("compiled_topology_edit.set_gain")
  }
  topo_edit_gain.val = gain
  clear_browser_error()
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
    return set_browser_init_error("compiled_topology_edit.process")
  }
  let topology = compiled_topology_edit.graph_val()
  match
    topology.apply_control(
      @moondsp.GraphControl::set_param(
        0,
        @moondsp.GraphParamSlot::Value0,
        topo_edit_gain.val,
      ),
    ) {
    Ok(_) => ()
    Err(error) =>
      return set_browser_control_error("compiled_topology_edit.process", error)
  }
  topology.process(
    compiled_topology_edit.ctx_val(),
    compiled_topology_edit.output.get(),
  )
  clear_browser_error()
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
  clear_browser_error()
}
