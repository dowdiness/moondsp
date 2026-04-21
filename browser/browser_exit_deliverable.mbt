///|
// WHY this map: node indices are positional after GraphBuilder flattening.
// apply_control targets nodes by index, so this map is needed to aim correctly.
// [0] Constant(2.0)       — LFO rate
// [1] Oscillator(Sine)    — LFO
// [2] Constant(1.0)       — range offset
// [3] Mix(1,2)            — lfo + 1
// [4] Constant(100.0)     — range scale = 0.5*(hi-lo)
// [5] Mul(3,4)            — (lfo+1)*scale
// [6] Constant(200.0)     — range lo
// [7] Mix(5,6)            — modulated freq
// [8] Oscillator(Sine)    — carrier
// [9] Biquad(LowPass)     — filter
// [10] Gain(0.3)          — master gain
// [11] Output
const EXIT_LFO_RATE_NODE : Int = 0

///|
const EXIT_BIQUAD_NODE : Int = 9

///|
const EXIT_GAIN_NODE : Int = 10

///|
let exit_lfo_rate : @ref.Ref[Double] = @ref.new(2.0)

///|
let exit_cutoff : @ref.Ref[Double] = @ref.new(800.0)

///|
let exit_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
let exit_deliverable : GraphSlot[@moondsp.CompiledDsp, MonoOut] = GraphSlot(
  output=MonoOut(),
  compile=fn(ctx) {
    let builder : @moondsp.GraphBuilder = @moondsp.exit_deliverable()
    @moondsp.CompiledDsp::compile(builder.nodes(), ctx)
  },
)

///|
/// Initialize the exit deliverable graph: FM synthesis via tagless composition.
pub fn init_exit_deliverable_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  exit_deliverable.ensure(sample_rate, block_size)
}

///|
/// Set the LFO rate (Hz) for the exit deliverable.
pub fn set_exit_deliverable_lfo_rate(rate : Double) -> Bool {
  if rate.is_nan() || rate.is_inf() {
    return false
  }
  exit_lfo_rate.val = rate
  true
}

///|
/// Set the filter cutoff (Hz) for the exit deliverable.
pub fn set_exit_deliverable_cutoff(cutoff : Double) -> Bool {
  if cutoff.is_nan() || cutoff.is_inf() || cutoff < 0.0 {
    return false
  }
  exit_cutoff.val = cutoff
  true
}

///|
/// Set the master gain for the exit deliverable.
pub fn set_exit_deliverable_gain(gain : Double) -> Bool {
  if gain.is_nan() || gain.is_inf() || gain < 0.0 {
    return false
  }
  exit_gain.val = gain
  true
}

///|
/// Run one render quantum through the exit deliverable graph.
pub fn process_exit_deliverable_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !exit_deliverable.ensure(sample_rate, block_size) {
    return false
  }
  let graph = exit_deliverable.graph_val()
  // Apply controls individually — batch is transactional and one failure
  // rejects all. Individual controls are independent.
  ignore(
    graph.apply_control(
      @moondsp.GraphControl::set_param(
        EXIT_LFO_RATE_NODE,
        @moondsp.GraphParamSlot::Value0,
        exit_lfo_rate.val,
      ),
    ),
  )
  ignore(
    graph.apply_control(
      @moondsp.GraphControl::set_param(
        EXIT_BIQUAD_NODE,
        @moondsp.GraphParamSlot::Value0,
        exit_cutoff.val,
      ),
    ),
  )
  ignore(
    graph.apply_control(
      @moondsp.GraphControl::set_param(
        EXIT_GAIN_NODE,
        @moondsp.GraphParamSlot::Value0,
        exit_gain.val,
      ),
    ),
  )
  graph.process(exit_deliverable.ctx_val(), exit_deliverable.output.get())
  true
}

///|
/// Read one sample from the most recent exit deliverable output block.
pub fn exit_deliverable_output_sample(index : Int) -> Double {
  exit_deliverable.output.sample(index)
}

///|
fn reset_exit_deliverable_graph() -> Unit {
  exit_deliverable.reset()
  exit_lfo_rate.val = 2.0
  exit_cutoff.val = 800.0
  exit_gain.val = 0.3
}
