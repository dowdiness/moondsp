///|
// This file owns only one WASM instance's transport state. Graph lifecycle,
// compilation, capacity, mixing, and errors belong to @moondsp.GraphEngine.
const GRAPH_HOST_BLOCK_SIZE : Int = 128

///|
let graph_host_engine : @ref.Ref[@moondsp.GraphEngine?] = @ref.new(None)

///|
let graph_host_handles : Map[Int, @moondsp.MountedGraph] = Map([])

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
fn graph_host_reject(
  code : String,
  message : String,
  node_index? : Int = -1,
) -> Bool {
  let fields : Map[String, Json] = Map([
    ("code", Json::string(code)),
    ("message", Json::string(message)),
  ])
  if node_index >= 0 {
    fields["nodeIndex"] = Json::number(node_index.to_double())
  }
  graph_host_error.val = Json::object(fields).stringify()
  false
}

///|
fn graph_control_error_node_index(error : @moondsp.GraphControlError) -> Int {
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
fn graph_host_control_error(error : @moondsp.GraphControlError) -> Bool {
  graph_host_reject(
    "INVALID_CONTROL",
    @debug.to_string(error),
    node_index=graph_control_error_node_index(error),
  )
}

///|
fn graph_host_engine_error(error : @moondsp.GraphEngineError) -> Bool {
  let code = match error {
    InvalidConfiguration => "INVALID_STATE"
    EngineClosed => "ENGINE_CLOSED"
    MountClosed => "MOUNT_CLOSED"
    CapacityExceeded => "MOUNT_REJECTED"
    InvalidHandle => "INVALID_HANDLE"
    InvalidGraph(_) => "INVALID_GRAPH"
    BufferSizeMismatch(..) => "PROCESSOR_FAILED"
    ControlRejected(control_error) =>
      return graph_host_control_error(control_error)
  }
  graph_host_reject(code, @debug.to_string(error))
}

///|
pub fn graph_host_init(sample_rate : Double) -> Bool {
  guard graph_host_engine.val is None else {
    return graph_host_reject("INVALID_STATE", "Engine already initialized")
  }
  let context = @moondsp.DspContext::DspContext(
    sample_rate~,
    block_size=GRAPH_HOST_BLOCK_SIZE,
  )
  try {
    graph_host_engine.val = Some(@moondsp.GraphEngine::GraphEngine(context))
    true
  } catch {
    error => graph_host_engine_error(error)
  }
}

///|
pub fn graph_host_clear_input() -> Unit {
  graph_host_input.reset()
  graph_host_error.val = ""
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
    let _ = graph_host_reject("INVALID_STATE", "Engine not initialized")
    return 0
  }
  guard graph_host_next_handle.val < 2147483647 else {
    let _ = graph_host_reject(
      "MOUNT_REJECTED", "Transport handle range exhausted",
    )
    return 0
  }
  let text = graph_host_input.to_string()
  graph_host_input.reset()
  let nodes = decode_browser_graph(text) catch {
    InvalidDescription(message, node_index) => {
      let _ = graph_host_reject("INVALID_GRAPH", message, node_index~)
      return 0
    }
  }
  try {
    let sound = engine.mount(nodes)
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
/// Decode and apply a control batch before the next render boundary.
pub fn graph_host_apply_controls(handle : Int) -> Bool {
  guard graph_host_handles.get(handle) is Some(sound) else {
    return graph_host_reject("INVALID_HANDLE", "Invalid graph handle")
  }
  let text = graph_host_input.to_string()
  graph_host_input.reset()
  let controls = decode_browser_controls(text) catch {
    InvalidDescription(message, node_index) =>
      return graph_host_reject("INVALID_CONTROL", message, node_index~)
  }
  try {
    sound.apply_controls(controls)
    true
  } catch {
    error => graph_host_engine_error(error)
  }
}

///|
/// Primitive transport commands; native MoonBit callers use handle methods.
pub fn graph_host_command(handle : Int, command : Int) -> Bool {
  guard graph_host_handles.get(handle) is Some(sound) else {
    return graph_host_reject("INVALID_HANDLE", "Invalid transport handle")
  }
  try {
    match command {
      0 => sound.play()
      1 => sound.pause()
      2 => {
        sound.unmount()
        graph_host_handles.remove(handle)
      }
      _ =>
        return graph_host_reject("INVALID_HANDLE", "Unknown transport command")
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
}

///|
pub fn graph_host_process(block_size : Int) -> Bool {
  guard graph_host_engine.val is Some(engine) else { return false }
  guard block_size == GRAPH_HOST_BLOCK_SIZE else {
    return graph_host_reject(
      "PROCESSOR_FAILED", "Unsupported render quantum: expected 128 frames",
    )
  }
  try {
    engine.process(graph_host_output)
    true
  } catch {
    error => graph_host_engine_error(error)
  }
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
