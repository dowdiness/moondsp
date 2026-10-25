///|
// Primitive-only adapter boundary; no binding types escape this package.
// This file owns only one WASM instance's transport state. Graph lifecycle,
// capacity and mixing share the same internal lifecycle as GraphEngine.
const GRAPH_HOST_BLOCK_SIZE : Int = 128

///|
let graph_host_engine : @ref.Ref[@lifecycle.Engine[@runtime.BoundDsp]?] = @ref.new(
  None,
)

///|
let graph_host_context : @ref.Ref[@moondsp.DspContext?] = @ref.new(None)

///|
let graph_host_handles : Map[Int, @lifecycle.Mount[@runtime.BoundDsp]] = Map([])

///|
// 64 nodes × at most four parameter fields, followed by 64 gate actions.
let graph_host_batch : @runtime.GraphControlBatch = @runtime.GraphControlBatch::GraphControlBatch(
  320,
)

///|
let graph_host_bindings : @ref.Ref[String] = @ref.new("")

///|
let graph_host_next_handle : @ref.Ref[Int] = @ref.new(1)

///|
let graph_host_input : StringBuilder = StringBuilder()

///|
let graph_host_output : @moondsp.AudioBuffer = @moondsp.AudioBuffer::filled(
  GRAPH_HOST_BLOCK_SIZE,
)

///|
let graph_host_error : @ref.Ref[String] = @ref.new("")

///|
priv enum HostErrorCode {
  None
  InvalidState
  EngineClosed
  MountClosed
  MountRejected
  InvalidHandle
  ProcessorFailed
  InvalidControl
  InvalidGraph
}

///|
let graph_host_error_kind : @ref.Ref[HostErrorCode] = @ref.new(None)

///|
let graph_host_error_node : @ref.Ref[Int] = @ref.new(-1)

///|
fn graph_host_reject(
  code : HostErrorCode,
  message : String,
  node_index? : Int = -1,
) -> Bool {
  graph_host_error_kind.val = code
  graph_host_error_node.val = node_index
  graph_host_error.val = message
  false
}

///|
fn graph_control_error_node_index(error : @runtime.GraphControlError) -> Int {
  match error {
    InvalidNodeIndex(index) => index
    OrphanNode(index) => index
    InvalidGateNode(index, _) => index
    InvalidSlotForNode(index, _, _) => index
    InvalidParamValue(index, _, _, _) => index
    MissingRuntimeState(index, _) => index
  }
}

///|
fn graph_host_batch_error(error : @runtime.GraphControlBatchError) -> Bool {
  let message = match error {
    BatchCapacityExceeded => "Update capacity exceeded"
    InvalidBindingIndex(_) => "Unknown control binding"
    InvalidGateValue(_, _) => "Gate value must be 0 or 1"
    InvalidParamValue(_, _, _, _) =>
      "Parameter value is outside its valid range"
  }
  let node_index = match error {
    BatchCapacityExceeded | InvalidBindingIndex(_) => -1
    InvalidGateValue(index, _) | InvalidParamValue(index, _, _, _) => index
  }
  graph_host_reject(InvalidControl, message, node_index~)
}

///|
fn graph_host_engine_error(error : @lifecycle.LifecycleError) -> Bool {
  let code = match error {
    InvalidConfiguration => InvalidState
    EngineClosed => EngineClosed
    MountClosed => MountClosed
    CapacityExceeded => MountRejected
    InvalidHandle => InvalidHandle
    BufferSizeMismatch(..) => ProcessorFailed
  }
  graph_host_reject(code, @debug.to_string(error))
}

///|
pub fn graph_host_init(sample_rate : Double) -> Bool {
  guard graph_host_engine.val is None else {
    return graph_host_reject(InvalidState, "Engine already initialized")
  }
  let context = @moondsp.DspContext::DspContext(
    sample_rate~,
    block_size=GRAPH_HOST_BLOCK_SIZE,
  )
  try {
    graph_host_engine.val = Some(
      @lifecycle.Engine::Engine(context, @runtime.BoundDsp::process),
    )
    graph_host_context.val = Some(context)
    true
  } catch {
    error => graph_host_engine_error(error)
  }
}

///|
pub fn graph_host_clear_input() -> Unit {
  graph_host_input.reset()
  graph_host_error.val = ""
  graph_host_error_kind.val = None
  graph_host_error_node.val = -1
}

///|
/// The JS adapter sends Unicode scalar values, not UTF-16 code units.
pub fn graph_host_push_char(code : Int) -> Unit {
  if code >= 0 && code <= 0x10FFFF && !(code >= 0xD800 && code <= 0xDFFF) {
    graph_host_input.write_char(code.unsafe_to_char())
  }
}

///|
pub fn graph_host_mount() -> Int {
  guard graph_host_engine.val is Some(engine) else {
    let _ = graph_host_reject(InvalidState, "Engine not initialized")
    return 0
  }
  guard graph_host_next_handle.val < 2147483647 else {
    let _ = graph_host_reject(MountRejected, "Transport handle range exhausted")
    return 0
  }
  let text = graph_host_input.to_string()
  graph_host_input.reset()
  let bindings : Map[String, Array[Int]] = Map([])
  let gates : Map[String, Int] = Map([])
  let targets : Array[@runtime.GraphControlTarget] = []
  let nodes = decode_browser_graph(text, bindings~, gates~, targets~) catch {
    InvalidDescription(message, node_index) => {
      let _ = graph_host_reject(InvalidGraph, message, node_index~)
      return 0
    }
  }
  engine.check_mount() catch {
    error => {
      let _ = graph_host_engine_error(error)
      return 0
    }
  }
  guard graph_host_context.val is Some(context) else { return 0 }
  let compiled = @runtime.BoundDsp::BoundDsp(
    @template.AnalyzedGraph::analyze(nodes),
    context,
    targets,
  ) catch {
    ControlRejected(error) => {
      let _ = graph_host_reject(
        InvalidGraph,
        @debug.to_string(error),
        node_index=graph_control_error_node_index(error),
      )
      return 0
    }
    InvalidGraph(error) => {
      let _ = graph_host_reject(InvalidGraph, @debug.to_string(error))
      return 0
    }
  }
  try {
    let sound = engine.register(compiled)
    let params_json : Map[String, Json] = Map([])
    for name, ids in bindings {
      params_json[name] = Json::array(
        ids.map(id => Json::number(id.to_double())),
      )
    }
    let gates_json : Map[String, Json] = Map([])
    for name, id in gates {
      gates_json[name] = Json::number(id.to_double())
    }
    graph_host_bindings.val = Json::object(
      Map([
        ("params", Json::object(params_json)),
        ("gates", Json::object(gates_json)),
      ]),
    ).stringify()
    let handle = graph_host_next_handle.val
    graph_host_next_handle.val += 1
    graph_host_handles[handle] = sound
    handle
  } catch {
    error => {
      let _ = graph_host_engine_error(error)
      0
    }
  }
}

///|
/// Reset the fixed-capacity numeric batch. Overflow poisons it until reset.
pub fn graph_host_begin_update() -> Unit {
  graph_host_batch.clear()
  graph_host_error.val = ""
  graph_host_error_kind.val = None
  graph_host_error_node.val = -1
}

///|
pub fn graph_host_push_update(target : Int, value : Double) -> Bool {
  if !graph_host_batch.push(target, value) {
    return graph_host_reject(InvalidControl, "Update capacity exceeded")
  }
  true
}

///|
/// Validate and apply the numeric batch against this mount's bound targets.
pub fn graph_host_update(handle : Int) -> Bool {
  // Unmount and close remove registry entries; nullable live projection keeps
  // the successful path free of raising-return Result boxes.
  guard graph_host_handles.get(handle) is Some(sound) &&
    sound.live_graph() is Some(graph) else {
    return graph_host_reject(InvalidHandle, "Invalid graph handle")
  }
  if graph.update(graph_host_batch) is Some(error) {
    return graph_host_batch_error(error)
  }
  graph_host_batch.clear()
  true
}

///|
/// Primitive transport commands; native MoonBit callers use handle methods.
pub fn graph_host_command(handle : Int, command : Int) -> Bool {
  guard graph_host_handles.get(handle) is Some(sound) else {
    return graph_host_reject(InvalidHandle, "Invalid transport handle")
  }
  try {
    match command {
      0 => sound.play()
      1 => sound.pause()
      2 => {
        sound.unmount()
        graph_host_handles.remove(handle)
      }
      _ => return graph_host_reject(InvalidHandle, "Unknown transport command")
    }
    true
  } catch {
    error => graph_host_engine_error(error)
  }
}

///|
pub fn graph_host_close() -> Unit {
  if graph_host_engine.val is Some(engine) {
    engine.close()
  }
  graph_host_handles.clear()
  graph_host_input.reset()
  graph_host_batch.clear()
  graph_host_bindings.val = ""
}

///|
pub fn graph_host_process(block_size : Int) -> Bool {
  guard graph_host_engine.val is Some(engine) else { return false }
  guard block_size == GRAPH_HOST_BLOCK_SIZE else {
    return graph_host_reject(
      ProcessorFailed,
      "Unsupported render quantum: expected 128 frames",
    )
  }
  if engine.process(graph_host_output) is Some(error) {
    return graph_host_engine_error(error)
  }
  true
}

///|
pub fn graph_host_sample(index : Int) -> Double {
  guard index >= 0 && index < GRAPH_HOST_BLOCK_SIZE else { return 0.0 }
  graph_host_output.get(index)
}

///|
pub fn graph_host_error_length() -> Int {
  graph_host_error.val.length()
}

///|
pub fn graph_host_error_char(index : Int) -> Int {
  guard index >= 0 && index < graph_host_error.val.length() else { return 0 }
  graph_host_error.val[index].to_int()
}

///|
pub fn graph_host_error_code() -> Int {
  match graph_host_error_kind.val {
    None => 0
    InvalidState => 1
    EngineClosed => 2
    MountClosed => 3
    MountRejected => 4
    InvalidHandle => 5
    ProcessorFailed => 6
    InvalidControl => 7
    InvalidGraph => 8
  }
}

///|
pub fn graph_host_error_node_index() -> Int {
  graph_host_error_node.val
}

///|
/// Mount-only result, read synchronously before another mount.
pub fn graph_host_bindings_length() -> Int {
  graph_host_bindings.val.length()
}

///|
pub fn graph_host_bindings_char(index : Int) -> Int {
  guard index >= 0 && index < graph_host_bindings.val.length() else { return 0 }
  graph_host_bindings.val[index].to_int()
}
