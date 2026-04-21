///|
let demo : @ref.Ref[@moondsp.DemoSource] = @ref.new(@moondsp.DemoSource::new())

///|
/// Browser test wrapper package that proves mono compiled fallback when
/// stereo initialization fails from the wasm side.
fn main {
  ()
}

///|
const BROWSER_TEST_FEEDBACK_FREQ_SCALE : Double = 440.0

///|
const BROWSER_TEST_FEEDBACK_DEFAULT_CONSTANT : Double = 1.0

///|
const BROWSER_TEST_FEEDBACK_DEFAULT_GAIN : Double = 0.3

///|
const BROWSER_TEST_FEEDBACK_CLIP_THRESHOLD : Double = 1.0

///|
const BROWSER_TEST_FEEDBACK_MAX_GAIN : Double = 0.95

///|
let compiled_graph : @ref.Ref[@moondsp.CompiledDsp?] = @ref.new(None)

///|
let compiled_context : @ref.Ref[@moondsp.DspContext?] = @ref.new(None)

///|
let compiled_output : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let compiled_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_block_size : @ref.Ref[Int] = @ref.new(0)

///|
pub fn reset_phase() -> Unit {
  demo.val.reset()
  reset_compiled_graph()
}

///|
pub fn tick(freq : Double, sample_rate : Double) -> Double {
  demo.val.tick_source(0, freq, sample_rate)
}

///|
pub fn tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  demo.val.tick_source(source_id, freq, sample_rate)
}

///|
pub fn init_compiled_graph(sample_rate : Double, block_size : Int) -> Bool {
  ensure_compiled_graph(sample_rate, block_size)
}

///|
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
      @moondsp.GraphControl::set_param(
        0,
        @moondsp.GraphParamSlot::Value0,
        bounded_feedback_constant(freq),
      ),
      @moondsp.GraphControl::set_param(
        2,
        @moondsp.GraphParamSlot::Value0,
        bounded_feedback_gain(gain),
      ),
    ]) {
    return false
  }
  graph.process(compiled_context.val.unwrap(), compiled_output.val.unwrap())
  true
}

///|
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
pub fn init_compiled_stereo_graph(
  _sample_rate : Double,
  _block_size : Int,
) -> Bool {
  false
}

///|
pub fn process_compiled_stereo_block(
  _freq : Double,
  _gain : Double,
  _pan : Double,
  _delay_samples : Double,
  _cutoff : Double,
  _sample_rate : Double,
  _block_size : Int,
) -> Bool {
  false
}

///|
pub fn compiled_stereo_left_sample(_index : Int) -> Double {
  0.0
}

///|
pub fn compiled_stereo_right_sample(_index : Int) -> Double {
  0.0
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

  let context = @moondsp.DspContext::new(sample_rate~, block_size~)
  let output = @moondsp.AudioBuffer::filled(block_size)
  let nodes = [
    @moondsp.DspNode::constant(BROWSER_TEST_FEEDBACK_DEFAULT_CONSTANT),
    @moondsp.DspNode::mix(0, 3),
    @moondsp.DspNode::gain(1, BROWSER_TEST_FEEDBACK_DEFAULT_GAIN),
    @moondsp.DspNode::clip(2, BROWSER_TEST_FEEDBACK_CLIP_THRESHOLD),
    @moondsp.DspNode::output(3),
  ]
  match @moondsp.CompiledDsp::compile(nodes, context) {
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
fn bounded_feedback_constant(freq : Double) -> Double {
  if freq.is_nan() || freq.is_inf() {
    BROWSER_TEST_FEEDBACK_DEFAULT_CONSTANT
  } else {
    let normalized = freq / BROWSER_TEST_FEEDBACK_FREQ_SCALE
    if normalized < 0.0 {
      0.0
    } else if normalized > 1.0 {
      1.0
    } else {
      normalized
    }
  }
}

///|
fn bounded_feedback_gain(gain : Double) -> Double {
  if gain.is_nan() || gain.is_inf() {
    BROWSER_TEST_FEEDBACK_DEFAULT_GAIN
  } else if gain < 0.0 {
    0.0
  } else if gain > BROWSER_TEST_FEEDBACK_MAX_GAIN {
    BROWSER_TEST_FEEDBACK_MAX_GAIN
  } else {
    gain
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
/// Peak magnitude of one block from `[osc(Sine, 440Hz), adsr(5,5,0.5,50) ms,
/// mul(0,1), output(2)]` with gate_on fired. Proves that `DspNode::mul` in a
/// wasm-gc release build produces non-trivial audio — counter-evidence to the
/// former "Mul wasm-gc bug" memory. Returns -1.0 if compile fails.
pub fn mul_adsr_peak(sample_rate : Double, block_size : Int) -> Double {
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size~)
  let nodes = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=5.0,
      decay_ms=5.0,
      sustain=0.5,
      release_ms=50.0,
    ),
    @moondsp.DspNode::mul(0, 1),
    @moondsp.DspNode::output(2),
  ]
  match @moondsp.CompiledDsp::compile(nodes, ctx) {
    Some(graph) => {
      ignore(graph.gate_on(1))
      let buf = @moondsp.AudioBuffer::filled(block_size)
      graph.process(ctx, buf)
      let mut peak = 0.0
      for i = 0; i < block_size; i = i + 1 {
        let s = buf.get(i).abs()
        if s > peak {
          peak = s
        }
      }
      peak
    }
    None => -1.0
  }
}
