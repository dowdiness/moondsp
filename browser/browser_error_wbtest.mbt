///|
test "browser graph error code values stay ABI compatible" {
  @debug.assert_eq(BROWSER_ERROR_NONE, 0)
  @debug.assert_eq(BROWSER_ERROR_NOT_INITIALIZED, 1)
  @debug.assert_eq(BROWSER_ERROR_COMPILE_REJECTED, 2)
  @debug.assert_eq(BROWSER_ERROR_HOT_SWAP_QUEUE, 3)
  @debug.assert_eq(BROWSER_ERROR_TOPOLOGY_QUEUE, 4)
  @debug.assert_eq(BROWSER_ERROR_RUNTIME_CONTROL, 5)
  @debug.assert_eq(BROWSER_ERROR_INIT, 6)
}

///|
test "browser error reports queue before initialization" {
  reset_phase()

  assert_false(queue_compiled_hot_swap())

  let message = get_browser_last_error()
  @debug.assert_eq(get_browser_error_code(), BROWSER_ERROR_NOT_INITIALIZED)
  assert_true(message.contains("compiled_hot_swap.queue"))
  assert_true(message.contains("graph not initialized"))
  @debug.assert_eq(get_browser_error_length(), message.length())
  @debug.assert_eq(get_browser_error_char(0), message[0].to_int())
  @debug.assert_eq(get_browser_error_char(-1), 0)
  @debug.assert_eq(get_browser_error_char(message.length()), 0)
}

///|
test "browser error reports compiled runtime control failure" {
  reset_phase()
  assert_true(init_compiled_graph(48000.0, 4))

  assert_false(process_compiled_block(0.0 / 0.0, 0.3, 48000.0, 4))

  let message = get_browser_last_error()
  @debug.assert_eq(get_browser_error_code(), BROWSER_ERROR_RUNTIME_CONTROL)
  assert_true(message.contains("compiled.process"))
  assert_true(message.contains("InvalidParamValue"))
}

///|
test "browser error reports invalid topology queue state" {
  reset_phase()
  assert_true(init_compiled_topology_edit_graph(48000.0, 4))

  assert_false(queue_compiled_topology_delete_edit())

  let message = get_browser_last_error()
  @debug.assert_eq(get_browser_error_code(), BROWSER_ERROR_TOPOLOGY_QUEUE)
  assert_true(message.contains("compiled_topology_delete.queue"))
  assert_true(message.contains("no inserted node to delete"))
}
