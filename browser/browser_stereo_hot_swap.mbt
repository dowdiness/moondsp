///|
let compiled_stereo_hot_swap : GraphSlot[
  @lib.CompiledStereoDspHotSwap,
  StereoOut,
] = GraphSlot::new(output=StereoOut::new(), compile=fn(ctx) {
  match
    @lib.CompiledStereoDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_STEREO_HOT_SWAP_OLD_CONSTANT),
        @lib.DspNode::pan(0, 0.0),
        @lib.DspNode::stereo_output(1),
      ],
      ctx,
    ) {
    Some(active) =>
      Some(
        @lib.CompiledStereoDspHotSwap::from_graph(
          active,
          crossfade_samples=BROWSER_STEREO_HOT_SWAP_CROSSFADE_SAMPLES,
        ),
      )
    None => None
  }
})

///|
/// Initialize the browser proof graph that runs through `CompiledStereoDspHotSwap`.
pub fn init_compiled_stereo_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_stereo_hot_swap.ensure(sample_rate, block_size)
}

///|
/// Queue the fixed browser stereo hot-swap replacement graph.
pub fn queue_compiled_stereo_hot_swap() -> Bool {
  let ctx = match compiled_stereo_hot_swap.context.val {
    Some(c) => c
    None => return false
  }
  let hot_swap = match compiled_stereo_hot_swap.graph.val {
    Some(h) => h
    None => return false
  }
  let replacement = match
    @lib.CompiledStereoDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_STEREO_HOT_SWAP_NEW_CONSTANT),
        @lib.DspNode::pan(0, 0.0),
        @lib.DspNode::stereo_output(1),
      ],
      ctx,
    ) {
    Some(r) => r
    None => return false
  }
  hot_swap.queue_swap(replacement)
}

///|
/// Run one render quantum through the browser proof `CompiledStereoDspHotSwap` graph.
pub fn process_compiled_stereo_hot_swap_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_stereo_hot_swap.ensure(sample_rate, block_size) {
    return false
  }
  let hot_swap = compiled_stereo_hot_swap.graph_val()
  hot_swap.process(
    compiled_stereo_hot_swap.ctx_val(),
    compiled_stereo_hot_swap.output.left_buf(),
    compiled_stereo_hot_swap.output.right_buf(),
  )
  true
}

///|
/// Read one sample from the most recent stereo hot-swap browser left block.
pub fn compiled_stereo_hot_swap_left_sample(index : Int) -> Double {
  compiled_stereo_hot_swap.output.left_sample(index)
}

///|
/// Read one sample from the most recent stereo hot-swap browser right block.
pub fn compiled_stereo_hot_swap_right_sample(index : Int) -> Double {
  compiled_stereo_hot_swap.output.right_sample(index)
}

///|
fn reset_compiled_stereo_hot_swap_graph() -> Unit {
  compiled_stereo_hot_swap.reset()
}
