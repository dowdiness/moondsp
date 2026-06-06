///|
fn create_test_handle() -> Int {
  let handle = @clap_host.engine_create(48000.0, 128, 8)
  guard handle > 0 else { abort("expected positive engine handle") }
  handle
}

///|
fn destroy_test_handle(handle : Int) -> Unit {
  guard @clap_host.engine_destroy(handle) else {
    abort("expected engine destroy to succeed")
  }
}

///|
fn abs_double(value : Double) -> Double {
  if value < 0.0 {
    -value
  } else {
    value
  }
}

///|
fn rendered_peak(handle : Int, frames : Int) -> Double {
  let processed = @clap_host.engine_process(handle, frames)
  for i in 0..<processed; peak = 0.0 {
    let l = abs_double(@clap_host.engine_left_sample(handle, i))
    let r = abs_double(@clap_host.engine_right_sample(handle, i))
    let next_l = if l > peak { l } else { peak }
    let next_peak = if r > next_l { r } else { next_l }
    continue next_peak
  } nobreak {
    peak
  }
}

///|
test "flat host API creates and destroys primitive handles" {
  let handle = create_test_handle()
  @debug.assert_eq(@clap_host.engine_process(handle, 1), 1)
  destroy_test_handle(handle)
  @debug.assert_eq(@clap_host.engine_process(handle, 1), 0)
  assert_true(!@clap_host.engine_destroy(handle))
}

///|
test "flat host API does not resurrect destroyed handles" {
  let stale = create_test_handle()
  destroy_test_handle(stale)
  let next = create_test_handle()
  assert_true(next != stale)
  @debug.assert_eq(@clap_host.engine_process(stale, 1), 0)
  destroy_test_handle(next)
}

///|
test "flat host API renders silence before note events" {
  let handle = create_test_handle()
  @debug.assert_eq(@clap_host.engine_process(handle, 128), 128)
  @debug.assert_eq(@clap_host.engine_left_sample(handle, 0), 0.0)
  @debug.assert_eq(@clap_host.engine_right_sample(handle, 0), 0.0)
  destroy_test_handle(handle)
}

///|
test "flat host API accepts CLAP note events and renders audio" {
  let handle = create_test_handle()
  assert_true(@clap_host.engine_note_on(handle, 11, 69, 1.0))
  assert_true(rendered_peak(handle, 128) > 0.000001)
  assert_true(@clap_host.engine_note_off(handle, 11, 69))
  assert_true(!@clap_host.engine_note_off(handle, 11, 69))
  destroy_test_handle(handle)
}

///|
test "flat host API clamps process size and rejects invalid handles" {
  let handle = create_test_handle()
  @debug.assert_eq(@clap_host.engine_process(handle, 1024), 128)
  @debug.assert_eq(@clap_host.engine_left_sample(handle, 128), 0.0)
  destroy_test_handle(handle)
  @debug.assert_eq(@clap_host.engine_process(handle, 128), 0)
  @debug.assert_eq(@clap_host.engine_left_sample(handle, 0), 0.0)
}

///|
test "flat host API dispatches parameters" {
  let handle = create_test_handle()
  assert_true(
    @clap_host.engine_set_param(handle, @engine.CLAP_PARAM_MASTER_GAIN, 9.0),
  )
  @debug.assert_eq(@clap_host.engine_master_gain(handle), 4.0)
  assert_true(@clap_host.engine_set_param(handle, @engine.CLAP_PARAM_PAN, 2.0))
  @debug.assert_eq(@clap_host.engine_pan(handle), 1.0)
  assert_true(!@clap_host.engine_set_param(handle, 999, 0.0))
  destroy_test_handle(handle)
}
