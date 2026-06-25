///|
fn scheduler_probe_eval_pattern_for_test(text : String) -> Int {
  clear_pattern_input()
  for i in 0..<text.length() {
    push_pattern_char(text[i].to_int())
  }
  eval_pattern_input()
}

///|
fn scheduler_probe_peak_for_test(block_size : Int) -> Double {
  for i in 0..<block_size; peak = 0.0 {
    let left = scheduler_left_sample(i).abs()
    let right = scheduler_right_sample(i).abs()
    let sample_peak = if left > right { left } else { right }
    continue if sample_peak > peak { sample_peak } else { peak }
  } nobreak {
    peak
  }
}

///|
test "scheduler probe triangle and sine synth templates render note patterns" {
  let block_size = 128
  assert_true(init_scheduler_graph(48000.0, block_size))
  @debug.assert_eq(
    scheduler_probe_eval_pattern_for_test("note(\"60 64 67\")"),
    0,
  )
  assert_true(process_scheduler_block())
  let triangle_peak = scheduler_probe_peak_for_test(block_size)
  assert_true(triangle_peak > 0.0)

  assert_true(init_scheduler_sine_graph(48000.0, block_size))
  @debug.assert_eq(
    scheduler_probe_eval_pattern_for_test("note(\"60 64 67\")"),
    0,
  )
  assert_true(process_scheduler_block())
  let sine_peak = scheduler_probe_peak_for_test(block_size)
  assert_true(sine_peak > 0.0)
  assert_true((sine_peak - triangle_peak).abs() > 0.0)
}
