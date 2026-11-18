///|
// Foreign exports require local functions: `pub using` alone is not linked
// into the WASM export table by the pinned compiler. Only primitives cross.
pub fn graph_host_init(sample_rate : Double) -> Bool {
  @graph_host.graph_host_init(sample_rate)
}

///|
pub fn graph_host_clear_input() -> Unit {
  @graph_host.graph_host_clear_input()
}

///|
pub fn graph_host_push_char(code : Int32) -> Unit {
  @graph_host.graph_host_push_char(code)
}

///|
pub fn graph_host_mount() -> Int32 {
  @graph_host.graph_host_mount()
}

///|
pub fn graph_host_bindings_length() -> Int32 {
  @graph_host.graph_host_bindings_length()
}

///|
pub fn graph_host_bindings_char(index : Int32) -> Int32 {
  @graph_host.graph_host_bindings_char(index)
}

///|
pub fn graph_host_begin_update() -> Unit {
  @graph_host.graph_host_begin_update()
}

///|
pub fn graph_host_push_update(target : Int32, value : Double) -> Bool {
  @graph_host.graph_host_push_update(target, value)
}

///|
pub fn graph_host_update(handle : Int32) -> Bool {
  @graph_host.graph_host_update(handle)
}

///|
pub fn graph_host_command(handle : Int32, command : Int32) -> Bool {
  @graph_host.graph_host_command(handle, command)
}

///|
pub fn graph_host_close() -> Unit {
  @graph_host.graph_host_close()
}

///|
pub fn graph_host_process(block_size : Int32) -> Bool {
  @graph_host.graph_host_process(block_size)
}

///|
pub fn graph_host_sample(index : Int32) -> Double {
  @graph_host.graph_host_sample(index)
}

///|
pub fn graph_host_error_length() -> Int32 {
  @graph_host.graph_host_error_length()
}

///|
pub fn graph_host_error_char(index : Int32) -> Int32 {
  @graph_host.graph_host_error_char(index)
}

///|
pub fn graph_host_error_code() -> Int32 {
  @graph_host.graph_host_error_code()
}

///|
pub fn graph_host_error_node_index() -> Int32 {
  @graph_host.graph_host_error_node_index()
}
