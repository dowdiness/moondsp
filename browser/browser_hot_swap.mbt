///|
let compiled_hot_swap : GraphSlot[@moondsp.CompiledDspHotSwap, MonoOut] = GraphSlot::new(
  output=MonoOut::new(),
  compile=fn(ctx) {
    match
      @moondsp.CompiledDsp::compile_template(
        @moondsp.CompiledTemplate::analyze([
          @moondsp.DspNode::constant(BROWSER_HOT_SWAP_OLD_CONSTANT),
          @moondsp.DspNode::output(0),
        ]),
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
  if compiled_hot_swap.ensure(sample_rate, block_size) {
    clear_browser_error()
    true
  } else {
    set_browser_init_error("compiled_hot_swap.init")
  }
}

///|
/// Queue the fixed browser hot-swap replacement graph.
pub fn queue_compiled_hot_swap() -> Bool {
  let ctx = match compiled_hot_swap.context.val {
    Some(c) => c
    None => return set_browser_not_initialized("compiled_hot_swap.queue")
  }
  let hot_swap = match compiled_hot_swap.graph.val {
    Some(h) => h
    None => return set_browser_not_initialized("compiled_hot_swap.queue")
  }
  let replacement = match
    @moondsp.CompiledDsp::compile_template(
      @moondsp.CompiledTemplate::analyze([
        @moondsp.DspNode::constant(BROWSER_HOT_SWAP_NEW_CONSTANT),
        @moondsp.DspNode::output(0),
      ]),
      ctx,
    ) {
    Some(r) => r
    None => return set_browser_compile_error("compiled_hot_swap.queue")
  }
  match hot_swap.queue_swap_result(replacement) {
    Ok(_) => {
      clear_browser_error()
      true
    }
    Err(error) =>
      set_browser_hot_swap_queue_error("compiled_hot_swap.queue", error)
  }
}

///|
/// Run one render quantum through the browser proof `CompiledDspHotSwap` graph.
pub fn process_compiled_hot_swap_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_hot_swap.ensure(sample_rate, block_size) {
    return set_browser_init_error("compiled_hot_swap.process")
  }
  let hot_swap = compiled_hot_swap.graph_val()
  hot_swap.process(compiled_hot_swap.ctx_val(), compiled_hot_swap.output.get())
  clear_browser_error()
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
  clear_browser_error()
}
