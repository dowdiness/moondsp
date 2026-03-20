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
const BROWSER_COMPILED_DELAY_CAPACITY : Int = 128

///|
const BROWSER_COMPILED_DELAY_SAMPLES : Int = 0

///|
const BROWSER_COMPILED_OSC_GAIN : Double = 0.2

///|
const BROWSER_COMPILED_MAX_FEEDBACK_GAIN : Double = 0.95

///|
const BROWSER_HOT_SWAP_OLD_CONSTANT : Double = 0.25

///|
const BROWSER_HOT_SWAP_NEW_CONSTANT : Double = 0.75

///|
const BROWSER_HOT_SWAP_CROSSFADE_SAMPLES : Int = 128

///|
const BROWSER_TOPOLOGY_EDIT_INSERTED_GAIN : Double = 0.5

///|
const BROWSER_TOPOLOGY_EDIT_CROSSFADE_SAMPLES : Int = 1024

///|
const BROWSER_STEREO_HOT_SWAP_OLD_CONSTANT : Double = 0.25

///|
const BROWSER_STEREO_HOT_SWAP_NEW_CONSTANT : Double = 0.75

///|
const BROWSER_STEREO_HOT_SWAP_CROSSFADE_SAMPLES : Int = 128

///|
const BROWSER_STEREO_TOPOLOGY_EDIT_OLD_PAN : Double = 0.0

///|
const BROWSER_STEREO_TOPOLOGY_EDIT_NEW_PAN : Double = 1.0

///|
const BROWSER_STEREO_TOPOLOGY_EDIT_CROSSFADE_SAMPLES : Int = 128

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
let compiled_hot_swap : @ref.Ref[@lib.CompiledDspHotSwap?] = @ref.new(None)

///|
let compiled_hot_swap_context : @ref.Ref[@lib.DspContext?] = @ref.new(None)

///|
let compiled_hot_swap_output : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let compiled_hot_swap_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_hot_swap_block_size : @ref.Ref[Int] = @ref.new(0)

///|
let compiled_topology_edit : @ref.Ref[@lib.CompiledDspTopologyController?] = @ref.new(
  None,
)

///|
let compiled_topology_edit_context : @ref.Ref[@lib.DspContext?] = @ref.new(None)

///|
let compiled_topology_edit_output : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let compiled_topology_edit_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_topology_edit_block_size : @ref.Ref[Int] = @ref.new(0)

///|
let compiled_topology_edit_gain : @ref.Ref[Double] = @ref.new(
  BROWSER_COMPILED_DEFAULT_GAIN,
)

///|
let compiled_topology_edit_inserted : @ref.Ref[Bool] = @ref.new(false)

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
let compiled_stereo_hot_swap : @ref.Ref[@lib.CompiledStereoDspHotSwap?] = @ref.new(
  None,
)

///|
let compiled_stereo_hot_swap_context : @ref.Ref[@lib.DspContext?] = @ref.new(
  None,
)

///|
let compiled_stereo_hot_swap_left : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let compiled_stereo_hot_swap_right : @ref.Ref[@lib.AudioBuffer?] = @ref.new(
  None,
)

///|
let compiled_stereo_hot_swap_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_stereo_hot_swap_block_size : @ref.Ref[Int] = @ref.new(0)

///|
let compiled_stereo_topology_edit : @ref.Ref[
  @lib.CompiledStereoDspTopologyController?,
] = @ref.new(None)

///|
let compiled_stereo_topology_edit_context : @ref.Ref[@lib.DspContext?] = @ref.new(
  None,
)

///|
let compiled_stereo_topology_edit_left : @ref.Ref[@lib.AudioBuffer?] = @ref.new(
  None,
)

///|
let compiled_stereo_topology_edit_right : @ref.Ref[@lib.AudioBuffer?] = @ref.new(
  None,
)

///|
let compiled_stereo_topology_edit_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let compiled_stereo_topology_edit_block_size : @ref.Ref[Int] = @ref.new(0)

///|
let compiled_stereo_topology_edit_level : @ref.Ref[Double] = @ref.new(1.0)

///|
/// Reset browser demo state.
pub fn reset_phase() -> Unit {
  @lib.reset_phase()
  reset_compiled_graph()
  reset_compiled_hot_swap_graph()
  reset_compiled_topology_edit_graph()
  reset_compiled_stereo_graph()
  reset_compiled_stereo_hot_swap_graph()
  reset_compiled_stereo_topology_edit_graph()
  reset_exit_deliverable_graph()
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
/// Initialize the browser proof graph that runs through `CompiledDspHotSwap`.
pub fn init_compiled_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  ensure_compiled_hot_swap_graph(sample_rate, block_size)
}

///|
/// Queue the fixed browser hot-swap replacement graph.
pub fn queue_compiled_hot_swap() -> Bool {
  let context = match compiled_hot_swap_context.val {
    Some(context) => context
    None => return false
  }
  let hot_swap = match compiled_hot_swap.val {
    Some(hot_swap) => hot_swap
    None => return false
  }
  let replacement = match
    @lib.CompiledDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_HOT_SWAP_NEW_CONSTANT),
        @lib.DspNode::output(0),
      ],
      context,
    ) {
    Some(replacement) => replacement
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
  if !ensure_compiled_hot_swap_graph(sample_rate, block_size) {
    return false
  }
  let hot_swap = compiled_hot_swap.val.unwrap()
  hot_swap.process(
    compiled_hot_swap_context.val.unwrap(),
    compiled_hot_swap_output.val.unwrap(),
  )
  true
}

///|
/// Read one sample from the most recent hot-swap browser output block.
pub fn compiled_hot_swap_output_sample(index : Int) -> Double {
  match compiled_hot_swap_output.val {
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
/// Initialize the browser proof graph that runs through
/// `CompiledDspTopologyController`.
pub fn init_compiled_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  ensure_compiled_topology_edit_graph(sample_rate, block_size)
}

///|
/// Queue the fixed browser topology edit insertion that appends one gain node
/// before the output.
pub fn queue_compiled_topology_edit() -> Bool {
  let topology = match compiled_topology_edit.val {
    Some(topology) => topology
    None => return false
  }
  if compiled_topology_edit_inserted.val {
    return false
  }
  let queued = topology.queue_topology_edit(
    @lib.GraphTopologyEdit::insert_node(
      1,
      @lib.GraphTopologyInputSlot::Input0,
      @lib.DspNode::gain(0, BROWSER_TOPOLOGY_EDIT_INSERTED_GAIN),
    ),
  )
  if queued {
    compiled_topology_edit_inserted.val = true
  }
  queued
}

///|
/// Queue the fixed browser topology edit deletion that removes the inserted
/// gain node and returns to the baseline graph.
pub fn queue_compiled_topology_delete_edit() -> Bool {
  let topology = match compiled_topology_edit.val {
    Some(topology) => topology
    None => return false
  }
  if !compiled_topology_edit_inserted.val {
    return false
  }
  let queued = topology.queue_topology_edit(
    @lib.GraphTopologyEdit::delete_node(
      2,
      1,
      @lib.GraphTopologyInputSlot::Input0,
      2,
    ),
  )
  if queued {
    compiled_topology_edit_inserted.val = false
  }
  queued
}

///|
/// Update the fixed browser topology-edit gain control.
pub fn set_compiled_topology_edit_gain(gain : Double) -> Bool {
  if compiled_topology_edit.val is None {
    return false
  }
  compiled_topology_edit_gain.val = gain
  true
}

///|
/// Run one render quantum through the browser proof `CompiledDspTopologyController`
/// graph.
pub fn process_compiled_topology_edit_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_compiled_topology_edit_graph(sample_rate, block_size) {
    return false
  }
  let topology = compiled_topology_edit.val.unwrap()
  if !topology.apply_control(
      @lib.GraphControl::set_param(
        0,
        @lib.GraphParamSlot::Value0,
        compiled_topology_edit_gain.val,
      ),
    ) {
    return false
  }
  topology.process(
    compiled_topology_edit_context.val.unwrap(),
    compiled_topology_edit_output.val.unwrap(),
  )
  true
}

///|
/// Read one sample from the most recent topology-edit browser output block.
pub fn compiled_topology_edit_output_sample(index : Int) -> Double {
  match compiled_topology_edit_output.val {
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
  delay_samples : Double,
  cutoff : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_compiled_stereo_graph(sample_rate, block_size) {
    return false
  }
  let graph = compiled_stereo_graph.val.unwrap()
  if !graph.apply_controls([
      @lib.GraphControl::set_param(1, @lib.GraphParamSlot::Value0, freq),
      @lib.GraphControl::set_param(
        5,
        @lib.GraphParamSlot::Value0,
        bounded_feedback_gain(gain),
      ),
      @lib.GraphControl::set_param(6, @lib.GraphParamSlot::Value0, pan),
      @lib.GraphControl::set_param(
        7,
        @lib.GraphParamSlot::DelaySamples,
        delay_samples,
      ),
      @lib.GraphControl::set_param(8, @lib.GraphParamSlot::Value0, cutoff),
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
/// Initialize the browser proof graph that runs through `CompiledStereoDspHotSwap`.
pub fn init_compiled_stereo_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  ensure_compiled_stereo_hot_swap_graph(sample_rate, block_size)
}

///|
/// Queue the fixed browser stereo hot-swap replacement graph.
pub fn queue_compiled_stereo_hot_swap() -> Bool {
  let context = match compiled_stereo_hot_swap_context.val {
    Some(context) => context
    None => return false
  }
  let hot_swap = match compiled_stereo_hot_swap.val {
    Some(hot_swap) => hot_swap
    None => return false
  }
  let replacement = match
    @lib.CompiledStereoDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_STEREO_HOT_SWAP_NEW_CONSTANT),
        @lib.DspNode::pan(0, 0.0),
        @lib.DspNode::stereo_output(1),
      ],
      context,
    ) {
    Some(replacement) => replacement
    None => return false
  }
  hot_swap.queue_swap(replacement)
}

///|
/// Run one render quantum through the browser proof `CompiledStereoDspHotSwap`
/// graph.
pub fn process_compiled_stereo_hot_swap_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_compiled_stereo_hot_swap_graph(sample_rate, block_size) {
    return false
  }
  let hot_swap = compiled_stereo_hot_swap.val.unwrap()
  hot_swap.process(
    compiled_stereo_hot_swap_context.val.unwrap(),
    compiled_stereo_hot_swap_left.val.unwrap(),
    compiled_stereo_hot_swap_right.val.unwrap(),
  )
  true
}

///|
/// Read one sample from the most recent stereo hot-swap browser left block.
pub fn compiled_stereo_hot_swap_left_sample(index : Int) -> Double {
  compiled_stereo_sample(index, compiled_stereo_hot_swap_left.val)
}

///|
/// Read one sample from the most recent stereo hot-swap browser right block.
pub fn compiled_stereo_hot_swap_right_sample(index : Int) -> Double {
  compiled_stereo_sample(index, compiled_stereo_hot_swap_right.val)
}

///|
/// Initialize the browser proof graph that runs through
/// `CompiledStereoDspTopologyController`.
pub fn init_compiled_stereo_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  ensure_compiled_stereo_topology_edit_graph(sample_rate, block_size)
}

///|
/// Queue the fixed browser stereo topology edit that replaces the pan node.
pub fn queue_compiled_stereo_topology_edit() -> Bool {
  let topology = match compiled_stereo_topology_edit.val {
    Some(topology) => topology
    None => return false
  }
  topology.queue_topology_edit(
    @lib.GraphTopologyEdit::replace_node(
      1,
      @lib.DspNode::pan(0, BROWSER_STEREO_TOPOLOGY_EDIT_NEW_PAN),
    ),
  )
}

///|
/// Update the fixed browser stereo topology-edit level control.
pub fn set_compiled_stereo_topology_edit_level(level : Double) -> Bool {
  if compiled_stereo_topology_edit.val is None {
    return false
  }
  compiled_stereo_topology_edit_level.val = level
  true
}

///|
/// Run one render quantum through the browser proof
/// `CompiledStereoDspTopologyController` graph.
pub fn process_compiled_stereo_topology_edit_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_compiled_stereo_topology_edit_graph(sample_rate, block_size) {
    return false
  }
  let topology = compiled_stereo_topology_edit.val.unwrap()
  if !topology.apply_control(
      @lib.GraphControl::set_param(
        0,
        @lib.GraphParamSlot::Value0,
        compiled_stereo_topology_edit_level.val,
      ),
    ) {
    return false
  }
  topology.process(
    compiled_stereo_topology_edit_context.val.unwrap(),
    compiled_stereo_topology_edit_left.val.unwrap(),
    compiled_stereo_topology_edit_right.val.unwrap(),
  )
  true
}

///|
/// Read one sample from the most recent stereo topology-edit browser left block.
pub fn compiled_stereo_topology_edit_left_sample(index : Int) -> Double {
  compiled_stereo_sample(index, compiled_stereo_topology_edit_left.val)
}

///|
/// Read one sample from the most recent stereo topology-edit browser right block.
pub fn compiled_stereo_topology_edit_right_sample(index : Int) -> Double {
  compiled_stereo_sample(index, compiled_stereo_topology_edit_right.val)
}

// ---------------------------------------------------------------------------
// Exit deliverable graph
// ---------------------------------------------------------------------------

///|
let exit_deliverable_graph : @ref.Ref[@lib.CompiledDsp?] = @ref.new(None)

///|
let exit_deliverable_context : @ref.Ref[@lib.DspContext?] = @ref.new(None)

///|
let exit_deliverable_output : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let exit_deliverable_sample_rate : @ref.Ref[Double] = @ref.new(0.0)

///|
let exit_deliverable_block_size : @ref.Ref[Int] = @ref.new(0)

///|
// Node indices in the exit deliverable graph (after GraphBuilder construction):
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
/// Initialize the exit deliverable graph: FM synthesis via tagless composition.
pub fn init_exit_deliverable_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  ensure_exit_deliverable_graph(sample_rate, block_size)
}

///|
/// Set the LFO rate (Hz) for the exit deliverable.
pub fn set_exit_deliverable_lfo_rate(rate : Double) -> Bool {
  exit_lfo_rate.val = rate
  true
}

///|
/// Set the filter cutoff (Hz) for the exit deliverable.
pub fn set_exit_deliverable_cutoff(cutoff : Double) -> Bool {
  exit_cutoff.val = cutoff
  true
}

///|
/// Set the master gain for the exit deliverable.
pub fn set_exit_deliverable_gain(gain : Double) -> Bool {
  exit_gain.val = gain
  true
}

///|
/// Run one render quantum through the exit deliverable graph.
pub fn process_exit_deliverable_block(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if !ensure_exit_deliverable_graph(sample_rate, block_size) {
    return false
  }
  let graph = exit_deliverable_graph.val.unwrap()
  // Apply controls individually — batch is transactional and one failure
  // rejects all. Individual controls are independent.
  ignore(
    graph.apply_control(
      @lib.GraphControl::set_param(
        EXIT_LFO_RATE_NODE,
        @lib.GraphParamSlot::Value0,
        exit_lfo_rate.val,
      ),
    ),
  )
  ignore(
    graph.apply_control(
      @lib.GraphControl::set_param(
        EXIT_BIQUAD_NODE,
        @lib.GraphParamSlot::Value0,
        exit_cutoff.val,
      ),
    ),
  )
  ignore(
    graph.apply_control(
      @lib.GraphControl::set_param(
        EXIT_GAIN_NODE,
        @lib.GraphParamSlot::Value0,
        exit_gain.val,
      ),
    ),
  )
  graph.process(
    exit_deliverable_context.val.unwrap(),
    exit_deliverable_output.val.unwrap(),
  )
  true
}

///|
/// Read one sample from the most recent exit deliverable output block.
pub fn exit_deliverable_output_sample(index : Int) -> Double {
  match exit_deliverable_output.val {
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
fn ensure_exit_deliverable_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_exit_deliverable_graph()
    return false
  }
  if exit_deliverable_graph.val is Some(_) &&
    exit_deliverable_sample_rate.val == sample_rate &&
    exit_deliverable_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let output = @lib.AudioBuffer::filled(block_size)
  let builder : @lib.GraphBuilder = @lib.exit_deliverable()
  match @lib.CompiledDsp::compile(builder.nodes(), context) {
    Some(graph) => {
      exit_deliverable_graph.val = Some(graph)
      exit_deliverable_context.val = Some(context)
      exit_deliverable_output.val = Some(output)
      exit_deliverable_sample_rate.val = sample_rate
      exit_deliverable_block_size.val = block_size
      true
    }
    None => {
      reset_exit_deliverable_graph()
      false
    }
  }
}

///|
fn reset_exit_deliverable_graph() -> Unit {
  exit_deliverable_graph.val = None
  exit_deliverable_context.val = None
  exit_deliverable_output.val = None
  exit_deliverable_sample_rate.val = 0.0
  exit_deliverable_block_size.val = 0
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
fn ensure_compiled_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_compiled_hot_swap_graph()
    return false
  }
  if compiled_hot_swap.val is Some(_) &&
    compiled_hot_swap_sample_rate.val == sample_rate &&
    compiled_hot_swap_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let output = @lib.AudioBuffer::filled(block_size)
  let active = match
    @lib.CompiledDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_HOT_SWAP_OLD_CONSTANT),
        @lib.DspNode::output(0),
      ],
      context,
    ) {
    Some(active) => active
    None => {
      reset_compiled_hot_swap_graph()
      return false
    }
  }
  let hot_swap = @lib.CompiledDspHotSwap::from_graph(
    active,
    crossfade_samples=BROWSER_HOT_SWAP_CROSSFADE_SAMPLES,
  )
  compiled_hot_swap.val = Some(hot_swap)
  compiled_hot_swap_context.val = Some(context)
  compiled_hot_swap_output.val = Some(output)
  compiled_hot_swap_sample_rate.val = sample_rate
  compiled_hot_swap_block_size.val = block_size
  true
}

///|
fn ensure_compiled_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_compiled_topology_edit_graph()
    return false
  }
  if compiled_topology_edit.val is Some(_) &&
    compiled_topology_edit_sample_rate.val == sample_rate &&
    compiled_topology_edit_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let output = @lib.AudioBuffer::filled(block_size)
  let topology = match
    @lib.CompiledDspTopologyController::from_nodes(
      [
        @lib.DspNode::constant(BROWSER_COMPILED_DEFAULT_GAIN),
        @lib.DspNode::output(0),
      ],
      context,
      crossfade_samples=BROWSER_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
    ) {
    Some(topology) => topology
    None => {
      reset_compiled_topology_edit_graph()
      return false
    }
  }
  compiled_topology_edit.val = Some(topology)
  compiled_topology_edit_context.val = Some(context)
  compiled_topology_edit_output.val = Some(output)
  compiled_topology_edit_sample_rate.val = sample_rate
  compiled_topology_edit_block_size.val = block_size
  compiled_topology_edit_gain.val = BROWSER_COMPILED_DEFAULT_GAIN
  compiled_topology_edit_inserted.val = false
  true
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
    @lib.DspNode::constant(1.0),
    @lib.DspNode::oscillator(@lib.Waveform::Sine, BROWSER_COMPILED_DEFAULT_FREQ),
    @lib.DspNode::gain(1, BROWSER_COMPILED_OSC_GAIN),
    @lib.DspNode::mix(0, 2),
    @lib.DspNode::mix(3, 5),
    @lib.DspNode::gain(4, BROWSER_COMPILED_DEFAULT_GAIN),
    @lib.DspNode::pan(5, BROWSER_COMPILED_DEFAULT_PAN),
    @lib.DspNode::stereo_delay(
      6,
      BROWSER_COMPILED_DELAY_CAPACITY,
      delay_samples=BROWSER_COMPILED_DELAY_SAMPLES,
    ),
    @lib.DspNode::stereo_biquad(
      7,
      @lib.BiquadMode::LowPass,
      BROWSER_COMPILED_DEFAULT_CUTOFF,
      BROWSER_COMPILED_FILTER_Q,
    ),
    @lib.DspNode::stereo_clip(8, BROWSER_COMPILED_CLIP_THRESHOLD),
    @lib.DspNode::stereo_output(9),
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
fn ensure_compiled_stereo_hot_swap_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_compiled_stereo_hot_swap_graph()
    return false
  }
  if compiled_stereo_hot_swap.val is Some(_) &&
    compiled_stereo_hot_swap_sample_rate.val == sample_rate &&
    compiled_stereo_hot_swap_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let left = @lib.AudioBuffer::filled(block_size)
  let right = @lib.AudioBuffer::filled(block_size)
  let active = match
    @lib.CompiledStereoDsp::compile(
      [
        @lib.DspNode::constant(BROWSER_STEREO_HOT_SWAP_OLD_CONSTANT),
        @lib.DspNode::pan(0, 0.0),
        @lib.DspNode::stereo_output(1),
      ],
      context,
    ) {
    Some(active) => active
    None => {
      reset_compiled_stereo_hot_swap_graph()
      return false
    }
  }
  let hot_swap = @lib.CompiledStereoDspHotSwap::from_graph(
    active,
    crossfade_samples=BROWSER_STEREO_HOT_SWAP_CROSSFADE_SAMPLES,
  )
  compiled_stereo_hot_swap.val = Some(hot_swap)
  compiled_stereo_hot_swap_context.val = Some(context)
  compiled_stereo_hot_swap_left.val = Some(left)
  compiled_stereo_hot_swap_right.val = Some(right)
  compiled_stereo_hot_swap_sample_rate.val = sample_rate
  compiled_stereo_hot_swap_block_size.val = block_size
  true
}

///|
fn ensure_compiled_stereo_topology_edit_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_compiled_stereo_topology_edit_graph()
    return false
  }
  if compiled_stereo_topology_edit.val is Some(_) &&
    compiled_stereo_topology_edit_sample_rate.val == sample_rate &&
    compiled_stereo_topology_edit_block_size.val == block_size {
    return true
  }

  let context = @lib.DspContext::new(sample_rate, block_size)
  let left = @lib.AudioBuffer::filled(block_size)
  let right = @lib.AudioBuffer::filled(block_size)
  let topology = match
    @lib.CompiledStereoDspTopologyController::from_nodes(
      [
        @lib.DspNode::constant(1.0),
        @lib.DspNode::pan(0, BROWSER_STEREO_TOPOLOGY_EDIT_OLD_PAN),
        @lib.DspNode::stereo_output(1),
      ],
      context,
      crossfade_samples=BROWSER_STEREO_TOPOLOGY_EDIT_CROSSFADE_SAMPLES,
    ) {
    Some(topology) => topology
    None => {
      reset_compiled_stereo_topology_edit_graph()
      return false
    }
  }
  compiled_stereo_topology_edit.val = Some(topology)
  compiled_stereo_topology_edit_context.val = Some(context)
  compiled_stereo_topology_edit_left.val = Some(left)
  compiled_stereo_topology_edit_right.val = Some(right)
  compiled_stereo_topology_edit_sample_rate.val = sample_rate
  compiled_stereo_topology_edit_block_size.val = block_size
  compiled_stereo_topology_edit_level.val = 1.0
  true
}

///|
fn bounded_feedback_gain(gain : Double) -> Double {
  if gain.is_nan() || gain.is_inf() {
    BROWSER_COMPILED_DEFAULT_GAIN
  } else if gain < 0.0 {
    0.0
  } else if gain > BROWSER_COMPILED_MAX_FEEDBACK_GAIN {
    BROWSER_COMPILED_MAX_FEEDBACK_GAIN
  } else {
    gain
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
fn reset_compiled_hot_swap_graph() -> Unit {
  compiled_hot_swap.val = None
  compiled_hot_swap_context.val = None
  compiled_hot_swap_output.val = None
  compiled_hot_swap_sample_rate.val = 0.0
  compiled_hot_swap_block_size.val = 0
}

///|
fn reset_compiled_topology_edit_graph() -> Unit {
  compiled_topology_edit.val = None
  compiled_topology_edit_context.val = None
  compiled_topology_edit_output.val = None
  compiled_topology_edit_sample_rate.val = 0.0
  compiled_topology_edit_block_size.val = 0
  compiled_topology_edit_gain.val = BROWSER_COMPILED_DEFAULT_GAIN
  compiled_topology_edit_inserted.val = false
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

///|
fn reset_compiled_stereo_hot_swap_graph() -> Unit {
  compiled_stereo_hot_swap.val = None
  compiled_stereo_hot_swap_context.val = None
  compiled_stereo_hot_swap_left.val = None
  compiled_stereo_hot_swap_right.val = None
  compiled_stereo_hot_swap_sample_rate.val = 0.0
  compiled_stereo_hot_swap_block_size.val = 0
}

///|
fn reset_compiled_stereo_topology_edit_graph() -> Unit {
  compiled_stereo_topology_edit.val = None
  compiled_stereo_topology_edit_context.val = None
  compiled_stereo_topology_edit_left.val = None
  compiled_stereo_topology_edit_right.val = None
  compiled_stereo_topology_edit_sample_rate.val = 0.0
  compiled_stereo_topology_edit_block_size.val = 0
  compiled_stereo_topology_edit_level.val = 1.0
}
