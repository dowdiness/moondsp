///|
let compiled : GraphSlot[@moondsp.CompiledDsp, MonoOut] = GraphSlot(
  output=MonoOut(),
  compile=fn(ctx) {
    @moondsp.CompiledDsp::compile(
      [
        @moondsp.DspNode::oscillator(
          @moondsp.Waveform::Triangle,
          BROWSER_COMPILED_DEFAULT_FREQ,
        ),
        @moondsp.DspNode::gain(0, BROWSER_COMPILED_DEFAULT_GAIN),
        @moondsp.DspNode::clip(1, BROWSER_COMPILED_CLIP_THRESHOLD),
        @moondsp.DspNode::output(2),
      ],
      ctx,
    )
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledDsp`.
pub fn init_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  compiled.ensure(sample_rate, block_size)
}

///|
/// Run one render quantum through the browser proof `CompiledDsp` graph.
pub fn process_compiled_block(
  freq : Double,
  gain : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled.ensure(sample_rate, block_size) {
    return false
  }
  let graph = compiled.graph_val()
  if !graph.apply_controls([
      @moondsp.GraphControl::set_param(0, @moondsp.GraphParamSlot::Value0, freq),
      @moondsp.GraphControl::set_param(1, @moondsp.GraphParamSlot::Value0, gain),
    ]) {
    return false
  }
  graph.process(compiled.ctx_val(), compiled.output.get())
  true
}

///|
/// Read one sample from the most recent compiled browser output block.
pub fn compiled_output_sample(index : Int) -> Double {
  compiled.output.sample(index)
}

///|
fn reset_compiled_graph() -> Unit {
  compiled.reset()
}
