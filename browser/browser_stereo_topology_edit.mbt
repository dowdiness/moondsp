///|
let stereo_topo_edit_level : @ref.Ref[Double] = @ref.new(1.0)

///|
let compiled_stereo_topology_edit : GraphSlot[
  @moondsp.CompiledStereoDspTopologyController,
  StereoOut,
] = GraphSlot::new(output=StereoOut::new(), compile=fn(ctx) {
  @moondsp.CompiledStereoDspTopologyController::from_nodes(
    [
      @moondsp.DspNode::constant(1.0),
      @moondsp.DspNode::pan(0, BROWSER_STEREO_TOPOLOGY_EDIT_OLD_PAN),
      @moondsp.DspNode::stereo_output(1),
    ],
    ctx,
    crossfade_samples=BROWSER_STEREO_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
  )
})

///|
/// Initialize the browser proof graph that runs through
/// `CompiledStereoDspTopologyController`.
pub fn init_compiled_stereo_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if compiled_stereo_topology_edit.ensure(sample_rate, block_size) {
    clear_browser_error()
    true
  } else {
    set_browser_init_error("compiled_stereo_topology_edit.init")
  }
}

///|
/// Queue the fixed browser stereo topology edit that replaces the pan node.
/// WHY no idempotency guard (unlike mono topology_edit's `inserted` bool):
/// replace_node is inherently idempotent — replacing with the same node is a no-op.
pub fn queue_compiled_stereo_topology_edit() -> Bool {
  let topology = match compiled_stereo_topology_edit.graph.val {
    Some(t) => t
    None =>
      return set_browser_not_initialized("compiled_stereo_topology_edit.queue")
  }
  match
    topology.queue_topology_edit_result(
      @moondsp.GraphTopologyEdit::replace_node(
        1,
        @moondsp.DspNode::pan(0, BROWSER_STEREO_TOPOLOGY_EDIT_NEW_PAN),
      ),
    ) {
    Ok(_) => {
      clear_browser_error()
      true
    }
    Err(error) =>
      set_browser_topology_queue_error(
        "compiled_stereo_topology_edit.queue", error,
      )
  }
}

///|
/// Update the fixed browser stereo topology-edit level control.
pub fn set_compiled_stereo_topology_edit_level(level : Double) -> Bool {
  if compiled_stereo_topology_edit.graph.val is None {
    return set_browser_not_initialized(
      "compiled_stereo_topology_edit.set_level",
    )
  }
  stereo_topo_edit_level.val = level
  clear_browser_error()
  true
}

///|
/// Run one render quantum through the browser proof
/// `CompiledStereoDspTopologyController` graph.
pub fn process_compiled_stereo_topology_edit_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_stereo_topology_edit.ensure(sample_rate, block_size) {
    return set_browser_init_error("compiled_stereo_topology_edit.process")
  }
  let topology = compiled_stereo_topology_edit.graph_val()
  match
    topology.apply_control_result(
      @moondsp.GraphControl::set_param(
        0,
        @moondsp.GraphParamSlot::Value0,
        stereo_topo_edit_level.val,
      ),
    ) {
    Ok(_) => ()
    Err(error) =>
      return set_browser_control_error(
        "compiled_stereo_topology_edit.process", error,
      )
  }
  topology.process(
    compiled_stereo_topology_edit.ctx_val(),
    compiled_stereo_topology_edit.output.left_buf(),
    compiled_stereo_topology_edit.output.right_buf(),
  )
  clear_browser_error()
  true
}

///|
/// Read one sample from the most recent stereo topology-edit browser left block.
pub fn compiled_stereo_topology_edit_left_sample(index : Int) -> Double {
  compiled_stereo_topology_edit.output.left_sample(index)
}

///|
/// Read one sample from the most recent stereo topology-edit browser right block.
pub fn compiled_stereo_topology_edit_right_sample(index : Int) -> Double {
  compiled_stereo_topology_edit.output.right_sample(index)
}

///|
fn reset_compiled_stereo_topology_edit_graph() -> Unit {
  compiled_stereo_topology_edit.reset()
  stereo_topo_edit_level.val = 1.0
  clear_browser_error()
}
