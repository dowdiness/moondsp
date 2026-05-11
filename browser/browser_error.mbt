///|
const BROWSER_ERROR_NONE : Int = 0

///|
const BROWSER_ERROR_NOT_INITIALIZED : Int = 1

///|
const BROWSER_ERROR_COMPILE_REJECTED : Int = 2

///|
const BROWSER_ERROR_HOT_SWAP_QUEUE : Int = 3

///|
const BROWSER_ERROR_TOPOLOGY_QUEUE : Int = 4

///|
const BROWSER_ERROR_RUNTIME_CONTROL : Int = 5

///|
const BROWSER_ERROR_INIT : Int = 6

///|
let browser_last_error : @ref.Ref[String] = @ref.new("")

///|
let browser_last_error_code : @ref.Ref[Int] = @ref.new(BROWSER_ERROR_NONE)

///|
fn clear_browser_error() -> Unit {
  browser_last_error.val = ""
  browser_last_error_code.val = BROWSER_ERROR_NONE
}

///|
fn set_browser_error(code : Int, message : String) -> Bool {
  browser_last_error.val = message
  browser_last_error_code.val = code
  false
}

///|
fn set_browser_error_detail(
  code : Int,
  context : String,
  detail : String,
) -> Bool {
  set_browser_error(code, "\{context}: \{detail}")
}

///|
fn set_browser_not_initialized(context : String) -> Bool {
  set_browser_error(
    BROWSER_ERROR_NOT_INITIALIZED,
    "\{context}: graph not initialized",
  )
}

///|
fn set_browser_init_error(context : String) -> Bool {
  set_browser_error(
    BROWSER_ERROR_INIT,
    "\{context}: graph initialization failed",
  )
}

///|
fn set_browser_compile_error(context : String) -> Bool {
  set_browser_error(
    BROWSER_ERROR_COMPILE_REJECTED,
    "\{context}: replacement graph rejected",
  )
}

///|
fn set_browser_control_error(
  context : String,
  error : @moondsp.GraphControlError,
) -> Bool {
  set_browser_error_detail(
    BROWSER_ERROR_RUNTIME_CONTROL,
    context,
    @debug.to_string(error),
  )
}

///|
fn set_browser_hot_swap_queue_error(
  context : String,
  error : @moondsp.HotSwapQueueError,
) -> Bool {
  set_browser_error_detail(
    BROWSER_ERROR_HOT_SWAP_QUEUE,
    context,
    @debug.to_string(error),
  )
}

///|
fn set_browser_topology_queue_error(
  context : String,
  error : @moondsp.GraphTopologyQueueError,
) -> Bool {
  set_browser_error_detail(
    BROWSER_ERROR_TOPOLOGY_QUEUE,
    context,
    @debug.to_string(error),
  )
}

///|
pub fn get_browser_last_error() -> String {
  browser_last_error.val
}

///|
pub fn get_browser_error_code() -> Int {
  browser_last_error_code.val
}

///|
pub fn get_browser_error_length() -> Int {
  browser_last_error.val.length()
}

///|
pub fn get_browser_error_char(i : Int) -> Int {
  let s = browser_last_error.val
  if i < 0 || i >= s.length() {
    0
  } else {
    s[i].to_int()
  }
}
