///|
let compiled_stereo : GraphSlot[@moondsp.CompiledStereoDsp, StereoOut] = GraphSlot(
  output=StereoOut(),
  compile=fn(ctx) {
    @moondsp.CompiledStereoDsp::compile(
      [
        @moondsp.DspNode::constant(1.0),
        @moondsp.DspNode::oscillator(
          @moondsp.Waveform::Sine,
          BROWSER_COMPILED_DEFAULT_FREQ,
        ),
        @moondsp.DspNode::gain(1, BROWSER_COMPILED_OSC_GAIN),
        @moondsp.DspNode::mix(0, 2),
        @moondsp.DspNode::mix(3, 5),
        @moondsp.DspNode::gain(4, BROWSER_COMPILED_DEFAULT_GAIN),
        @moondsp.DspNode::pan(5, BROWSER_COMPILED_DEFAULT_PAN),
        @moondsp.DspNode::stereo_delay(
          6,
          BROWSER_COMPILED_DELAY_CAPACITY,
          delay_samples=BROWSER_COMPILED_DELAY_SAMPLES,
        ),
        @moondsp.DspNode::stereo_biquad(
          7,
          @moondsp.BiquadMode::LowPass,
          BROWSER_COMPILED_DEFAULT_CUTOFF,
          BROWSER_COMPILED_FILTER_Q,
        ),
        @moondsp.DspNode::stereo_clip(8, BROWSER_COMPILED_CLIP_THRESHOLD),
        @moondsp.DspNode::stereo_output(9),
      ],
      ctx,
    )
  },
)

///|
/// Initialize the browser proof graph that runs through `CompiledStereoDsp`.
pub fn init_compiled_stereo_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  compiled_stereo.ensure(sample_rate, block_size)
}

///|
/// Run one render quantum through the browser proof `CompiledStereoDsp` graph.
pub fn process_compiled_stereo_block(
  freq : Double,
  gain : Double,
  pan : Double,
  delay_samples : Double,
  cutoff : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !compiled_stereo.ensure(sample_rate, block_size) {
    return false
  }
  let graph = compiled_stereo.graph_val()
  if !graph.apply_controls([
      @moondsp.GraphControl::set_param(1, @moondsp.GraphParamSlot::Value0, freq),
      @moondsp.GraphControl::set_param(
        5,
        @moondsp.GraphParamSlot::Value0,
        bounded_feedback_gain(gain),
      ),
      @moondsp.GraphControl::set_param(6, @moondsp.GraphParamSlot::Value0, pan),
      @moondsp.GraphControl::set_param(
        7,
        @moondsp.GraphParamSlot::DelaySamples,
        delay_samples,
      ),
      @moondsp.GraphControl::set_param(
        8,
        @moondsp.GraphParamSlot::Value0,
        cutoff,
      ),
    ]) {
    return false
  }
  graph.process(
    compiled_stereo.ctx_val(),
    compiled_stereo.output.left_buf(),
    compiled_stereo.output.right_buf(),
  )
  true
}

///|
/// Read one sample from the most recent compiled stereo left block.
pub fn compiled_stereo_left_sample(index : Int) -> Double {
  compiled_stereo.output.left_sample(index)
}

///|
/// Read one sample from the most recent compiled stereo right block.
pub fn compiled_stereo_right_sample(index : Int) -> Double {
  compiled_stereo.output.right_sample(index)
}

///|
fn reset_compiled_stereo_graph() -> Unit {
  compiled_stereo.reset()
}
