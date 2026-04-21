///|
let compiled_hot_swap : GraphSlot[@moondsp.CompiledDspHotSwap, MonoOut] = GraphSlot(
  output=MonoOut(),
  compile=fn(ctx) {
    match
      @moondsp.CompiledDsp::compile(
        [
          @moondsp.DspNode::constant(BROWSER_HOT_SWAP_OLD_CONSTANT),
          @moondsp.DspNode::output(0),
        ],
        ctx,
      ) {
      Some(active) =>
        Some(
          @moondsp.CompiledDspHotSwap::from_graph(
            active,
            crossfade_samples=BROWSER_HOT_SWAP_CROSSFADE_SAMPLES,
          ),
        )
      None => None
    }
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledDspHotSwap`.
pub fn init_compiled_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_hot_swap.ensure(sample_rate, block_size)
}

///|
/// Queue the fixed browser hot-swap replacement graph.
pub fn queue_compiled_hot_swap() -> Bool {
  let ctx = match compiled_hot_swap.context.val {
    Some(c) => c
    None => return false
  }
  let hot_swap = match compiled_hot_swap.graph.val {
    Some(h) => h
    None => return false
  }
  let replacement = match
    @moondsp.CompiledDsp::compile(
      [
        @moondsp.DspNode::constant(BROWSER_HOT_SWAP_NEW_CONSTANT),
        @moondsp.DspNode::output(0),
      ],
      ctx,
    ) {
    Some(r) => r
    None => return false
  }
  hot_swap.queue_swap(replacement)
}

///|
/// Run one render quantum through the browser proof `CompiledDspHotSwap` graph.
pub fn process_compiled_hot_swap_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_hot_swap.ensure(sample_rate, block_size) {
    return false
  }
  let hot_swap = compiled_hot_swap.graph_val()
  hot_swap.process(compiled_hot_swap.ctx_val(), compiled_hot_swap.output.get())
  true
}

///|
/// Read one sample from the most recent hot-swap browser output block.
pub fn compiled_hot_swap_output_sample(index : Int) -> Double {
  compiled_hot_swap.output.sample(index)
}

///|
fn reset_compiled_hot_swap_graph() -> Unit {
  compiled_hot_swap.reset()
}
