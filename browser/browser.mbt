///|
/// Browser-export wrapper package that preserves the original Phase 0/1 wasm ABI.
fn main {
  ()
}

///|
const BROWSER_COMPILED_DEFAULT_FREQ : Double = 440.0

///|
const BROWSER_COMPILED_DEFAULT_GAIN : Double = 0.3

///|
const BROWSER_COMPILED_CLIP_THRESHOLD : Double = 0.95

///|
const BROWSER_COMPILED_DEFAULT_PAN : Double = 0.0

///|
const BROWSER_COMPILED_DEFAULT_CUTOFF : Double = 1800.0

///|
const BROWSER_COMPILED_FILTER_Q : Double = 0.707

///|
let compiled_graph : @ref.Ref[@lib.CompiledDsp?] = @ref.new(None)

///|
let compiled_context : @ref.Ref[@lib.DspContext?] = @ref.new(None)

///|
let compiled_output : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let compiled_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_block_size : @ref.Ref[Int] = @ref.new(0)

///|
let compiled_stereo_graph : @ref.Ref[@lib.CompiledStereoDsp?] = @ref.new(None)

///|
let compiled_stereo_context : @ref.Ref[@lib.DspContext?] = @ref.new(None)

///|
let compiled_stereo_left : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let compiled_stereo_right : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let compiled_stereo_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_stereo_block_size : @ref.Ref[Int] = @ref.new(0)

///|
/// Reset browser demo state.
pub fn reset_phase() -> Unit {
  @lib.reset_phase()
  reset_compiled_graph()
  reset_compiled_stereo_graph()
}

///|
/// Generate one sine sample for the browser demo.
pub fn tick(freq : Double, sample_rate : Double) -> Double {
  @lib.tick(freq, sample_rate)
}

///|
/// Generate one sample from the selected browser demo source.
pub fn tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  @lib.tick_source(source_id, freq, sample_rate)
}

///|
/// Initialize the browser proof graph that runs through `CompiledDsp`.
pub fn init_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  ensure_compiled_graph(sample_rate, block_size)
}

///|
/// Run one render quantum through the browser proof `CompiledDsp` graph.
pub fn process_compiled_block(
  freq : Double,
  gain : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_compiled_graph(sample_rate, block_size) {
    return false
  }
  let graph = compiled_graph.val.unwrap()
  if !graph.apply_controls([
      @lib.GraphControl::set_param(0, @lib.GraphParamSlot::Value0, freq),
      @lib.GraphControl::set_param(1, @lib.GraphParamSlot::Value0, gain),
    ]) {
    return false
  }
  graph.process(compiled_context.val.unwrap(), compiled_output.val.unwrap())
  true
}

///|
/// Read one sample from the most recent compiled browser output block.
pub fn compiled_output_sample(index : Int) -> Double {
  match compiled_output.val {
    Some(output) =>
      if index >= 0 && index < output.length() {
        output.get(index)
      } else {
        0.0
      }
    None => 0.0
  }
}

///|
/// Initialize the browser proof graph that runs through `CompiledStereoDsp`.
pub fn init_compiled_stereo_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  ensure_compiled_stereo_graph(sample_rate, block_size)
}

///|
/// Run one render quantum through the browser proof `CompiledStereoDsp` graph.
pub fn process_compiled_stereo_block(
  freq : Double,
  gain : Double,
  pan : Double,
  cutoff : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_compiled_stereo_graph(sample_rate, block_size) {
    return false
  }
  let graph = compiled_stereo_graph.val.unwrap()
  if !graph.apply_controls([
      @lib.GraphControl::set_param(0, @lib.GraphParamSlot::Value0, freq),
      @lib.GraphControl::set_param(1, @lib.GraphParamSlot::Value0, pan),
      @lib.GraphControl::set_param(2, @lib.GraphParamSlot::Value0, cutoff),
      @lib.GraphControl::set_param(3, @lib.GraphParamSlot::Value0, gain),
    ]) {
    return false
  }
  graph.process(
    compiled_stereo_context.val.unwrap(),
    compiled_stereo_left.val.unwrap(),
    compiled_stereo_right.val.unwrap(),
  )
  true
}

///|
/// Read one sample from the most recent compiled stereo left block.
pub fn compiled_stereo_left_sample(index : Int) -> Double {
  compiled_stereo_sample(index, compiled_stereo_left.val)
}

///|
/// Read one sample from the most recent compiled stereo right block.
pub fn compiled_stereo_right_sample(index : Int) -> Double {
  compiled_stereo_sample(index, compiled_stereo_right.val)
}

///|
fn ensure_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_compiled_graph()
    return false
  }
  if compiled_graph.val is Some(_) &&
    compiled_sample_rate.val == sample_rate &&
    compiled_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let output = @lib.AudioBuffer::filled(block_size)
  let nodes = [
    @lib.DspNode::oscillator(
      @lib.Waveform::Triangle,
      BROWSER_COMPILED_DEFAULT_FREQ,
    ),
    @lib.DspNode::gain(0, BROWSER_COMPILED_DEFAULT_GAIN),
    @lib.DspNode::clip(1, BROWSER_COMPILED_CLIP_THRESHOLD),
    @lib.DspNode::output(2),
  ]
  match @lib.CompiledDsp::compile(nodes, context) {
    Some(graph) => {
      compiled_graph.val = Some(graph)
      compiled_context.val = Some(context)
      compiled_output.val = Some(output)
      compiled_sample_rate.val = sample_rate
      compiled_block_size.val = block_size
      true
    }
    None => {
      reset_compiled_graph()
      false
    }
  }
}

///|
fn ensure_compiled_stereo_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_compiled_stereo_graph()
    return false
  }
  if compiled_stereo_graph.val is Some(_) &&
    compiled_stereo_sample_rate.val == sample_rate &&
    compiled_stereo_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let left = @lib.AudioBuffer::filled(block_size)
  let right = @lib.AudioBuffer::filled(block_size)
  let nodes = [
    @lib.DspNode::oscillator(
      @lib.Waveform::Triangle,
      BROWSER_COMPILED_DEFAULT_FREQ,
    ),
    @lib.DspNode::pan(0, BROWSER_COMPILED_DEFAULT_PAN),
    @lib.DspNode::stereo_biquad(
      1,
      @lib.BiquadMode::LowPass,
      BROWSER_COMPILED_DEFAULT_CUTOFF,
      BROWSER_COMPILED_FILTER_Q,
    ),
    @lib.DspNode::stereo_gain(2, BROWSER_COMPILED_DEFAULT_GAIN),
    @lib.DspNode::stereo_clip(3, BROWSER_COMPILED_CLIP_THRESHOLD),
    @lib.DspNode::stereo_output(4),
  ]
  match @lib.CompiledStereoDsp::compile(nodes, context) {
    Some(graph) => {
      compiled_stereo_graph.val = Some(graph)
      compiled_stereo_context.val = Some(context)
      compiled_stereo_left.val = Some(left)
      compiled_stereo_right.val = Some(right)
      compiled_stereo_sample_rate.val = sample_rate
      compiled_stereo_block_size.val = block_size
      true
    }
    None => {
      reset_compiled_stereo_graph()
      false
    }
  }
}

///|
fn compiled_stereo_sample(index : Int, output : @lib.AudioBuffer?) -> Double {
  match output {
    Some(buffer) =>
      if index >= 0 && index < buffer.length() {
        buffer.get(index)
      } else {
        0.0
      }
    None => 0.0
  }
}

///|
fn reset_compiled_graph() -> Unit {
  compiled_graph.val = None
  compiled_context.val = None
  compiled_output.val = None
  compiled_sample_rate.val = 0.0
  compiled_block_size.val = 0
}

///|
fn reset_compiled_stereo_graph() -> Unit {
  compiled_stereo_graph.val = None
  compiled_stereo_context.val = None
  compiled_stereo_left.val = None
  compiled_stereo_right.val = None
  compiled_stereo_sample_rate.val = 0.0
  compiled_stereo_block_size.val = 0
}
