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
test "scheduler probe triangle and sine use the real Mini scheduler path" {
  let block_size = 128
  let patterns = [
    "note(\"60\")", "note(\"60 64 67\")", "note(\"60,64,67\").fast(8)", "note(\"48,49,50,51,52,53,54,55,56,57,58,59,60\").fast(8)",
  ]
  for waveform in 0..<2 {
    for pattern in patterns {
      let initialized = if waveform == 0 {
        init_scheduler_graph(48000.0, block_size)
      } else {
        init_scheduler_sine_graph(48000.0, block_size)
      }
      assert_true(initialized)
      @debug.assert_eq(scheduler_probe_eval_pattern_for_test(pattern), 0)
      assert_true(process_scheduler_block())
      assert_true(scheduler_probe_peak_for_test(block_size) > 0.0)
      @debug.assert_eq(scheduler_last_sanitized_count(), 0)
      assert_true(scheduler_synth_active_voice_count() > 0)
      @debug.assert_eq(scheduler_synth_voice_capacity(), 24)
    }
  }
}

///|
test "scheduler probe real Mini silence stays silent" {
  for waveform in 0..<2 {
    let initialized = if waveform == 0 {
      init_scheduler_graph(48000.0, 128)
    } else {
      init_scheduler_sine_graph(48000.0, 128)
    }
    assert_true(initialized)
    @debug.assert_eq(scheduler_probe_eval_pattern_for_test("s(\"bd(0,8)\")"), 0)
    assert_true(process_scheduler_block())
    @debug.assert_eq(scheduler_probe_peak_for_test(128), 0.0)
    @debug.assert_eq(scheduler_last_sanitized_count(), 0)
  }
}
