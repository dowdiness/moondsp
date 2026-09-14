///|
const GRAPH_HOST_CAPACITY : Int = 16

///|
const GRAPH_HOST_NODE_CAPACITY : Int = 64

///|
const GRAPH_HOST_BLOCK_SIZE : Int = 128

///|
priv struct HostedGraph {
  handle : Int
  graph : @moondsp.CompiledDsp
  output : @moondsp.AudioBuffer
  mut playing : Bool
}

///|
fn HostedGraph::HostedGraph(
  handle : Int,
  graph : @moondsp.CompiledDsp,
) -> HostedGraph {
  {
    handle,
    graph,
    output: @moondsp.AudioBuffer::filled(GRAPH_HOST_BLOCK_SIZE),
    playing: false,
  }
}

///|
let hosted_graphs : FixedArray[HostedGraph?] = FixedArray::make(
  GRAPH_HOST_CAPACITY,
  None,
)

///|
let hosted_nodes : Array[@moondsp.DspNode] = []

///|
let hosted_context : @ref.Ref[@moondsp.DspContext?] = @ref.new(None)

///|
let hosted_output : @moondsp.AudioBuffer = @moondsp.AudioBuffer::filled(
  GRAPH_HOST_BLOCK_SIZE,
)

///|
let hosted_next_handle : @ref.Ref[Int] = @ref.new(1)

///|
let hosted_sealed : @ref.Ref[Bool] = @ref.new(false)

///|
let hosted_building : @ref.Ref[Bool] = @ref.new(false)

///|
fn graph_host_reject(message : String) -> Bool {
  set_browser_error(BROWSER_ERROR_COMPILE_REJECTED, message)
}

///|
/// Begin a bounded graph description before any source has started.
pub fn graph_host_begin(sample_rate : Double) -> Bool {
  hosted_nodes.clear()
  hosted_building.val = false
  guard !hosted_sealed.val else {
    return graph_host_reject("Preparation is closed after the first start")
  }
  guard @moondsp.is_finite_positive(sample_rate) else {
    return graph_host_reject("Invalid sample rate")
  }
  match hosted_context.val {
    Some(ctx) => {
      guard ctx.sample_rate() == sample_rate else {
        return graph_host_reject("Sample rate cannot change")
      }
    }
    None =>
      hosted_context.val = Some(
        @moondsp.DspContext::DspContext(
          sample_rate~,
          block_size=GRAPH_HOST_BLOCK_SIZE,
        ),
      )
  }
  hosted_building.val = true
  clear_browser_error()
  true
}

///|
/// Kinds: 0 oscillator, 1 gain, 2 output. Waveforms: sine/saw/square/triangle = 0..3.
pub fn graph_host_push(
  kind : Int,
  input : Int,
  value : Double,
  waveform : Int,
) -> Bool {
  guard hosted_building.val else {
    return graph_host_reject("Begin a graph before adding nodes")
  }
  guard hosted_nodes.length() < GRAPH_HOST_NODE_CAPACITY else {
    hosted_building.val = false
    return graph_host_reject("Graph exceeds 64 nodes")
  }
  guard @moondsp.is_finite(value) else {
    hosted_building.val = false
    return graph_host_reject("Node value must be finite")
  }
  let node = match kind {
    0 => {
      let wave = match waveform {
        0 => @moondsp.Waveform::Sine
        1 => @moondsp.Waveform::Saw
        2 => @moondsp.Waveform::Square
        3 => @moondsp.Waveform::Triangle
        _ => {
          hosted_building.val = false
          return graph_host_reject("Unknown waveform")
        }
      }
      @moondsp.DspNode::oscillator(wave, value)
    }
    1 => @moondsp.DspNode::gain(input, value)
    2 => @moondsp.DspNode::output(input)
    _ => {
      hosted_building.val = false
      return graph_host_reject("Unknown node kind")
    }
  }
  hosted_nodes.push(node)
  true
}

///|
/// Returns a positive, never-reused handle, or zero with a browser error.
pub fn graph_host_prepare() -> Int {
  guard hosted_building.val && !hosted_sealed.val else {
    let _ = graph_host_reject("No valid graph preparation in progress")
    return 0
  }
  hosted_building.val = false
  guard hosted_context.val is Some(ctx) else { return 0 }
  let mut free_slot = -1
  for i in 0..<GRAPH_HOST_CAPACITY {
    if hosted_graphs[i] is None {
      free_slot = i
      break
    }
  }
  guard free_slot >= 0 && hosted_next_handle.val < 2147483647 else {
    let _ = graph_host_reject("Graph handle capacity exhausted")
    return 0
  }
  let template = @moondsp.CompiledTemplate::analyze(hosted_nodes)
  let graph = match @moondsp.CompiledDsp::compile_result(template, ctx) {
    Ok(graph) => graph
    Err(error) => {
      let _ = graph_host_reject(@debug.to_string(error))
      return 0
    }
  }
  let handle = hosted_next_handle.val
  hosted_next_handle.val += 1
  hosted_graphs[free_slot] = Some(HostedGraph(handle, graph))
  hosted_nodes.clear()
  clear_browser_error()
  handle
}

///|
/// Commands: 0 start/resume, 1 pause, 2 release. Released handles never revive.
pub fn graph_host_command(handle : Int, command : Int) -> Bool {
  for i in 0..<GRAPH_HOST_CAPACITY {
    if hosted_graphs[i] is Some(instance) && instance.handle == handle {
      match command {
        0 => {
          hosted_sealed.val = true
          hosted_building.val = false
          instance.playing = true
        }
        1 => instance.playing = false
        2 => hosted_graphs[i] = None
        _ => return graph_host_reject("Unknown graph command")
      }
      clear_browser_error()
      return true
    }
  }
  set_browser_error(
    BROWSER_ERROR_NOT_INITIALIZED,
    "Invalid or released graph handle",
  )
}

///|
/// Render the prepared graphs without constructing graphs or buffers here.
pub fn graph_host_process(block_size : Int) -> Bool {
  hosted_output.fill(0.0)
  guard block_size == GRAPH_HOST_BLOCK_SIZE else { return false }
  guard hosted_context.val is Some(ctx) else { return true }
  for entry in hosted_graphs {
    if entry is Some(instance) && instance.playing {
      instance.graph.process(ctx, instance.output)
      for i in 0..<GRAPH_HOST_BLOCK_SIZE {
        hosted_output.set(i, hosted_output.get(i) + instance.output.get(i))
      }
    }
  }
  true
}

///|
pub fn graph_host_sample(index : Int) -> Double {
  guard index >= 0 && index < GRAPH_HOST_BLOCK_SIZE else { return 0.0 }
  hosted_output.get(index)
}
