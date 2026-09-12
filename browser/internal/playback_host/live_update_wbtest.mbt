// Integration tests observe transport, sound and API results. Admission rules
// are separate from reset/tempo effects so a failure names one contract.

///|
const HELD_NOTE : String = "note(\"60\").slow(8)"

///|
const SILENT_PATTERN : String = "s(\"bd\").degradeBy(1)"

///|
// At 120 BPM this emits every 64 samples, guaranteeing an onset in a 128-sample block.
const REPEATING_NOTE : String = "note(\"60\").fast(375)"

///|
test "preparation does not change playback even when applied later" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(8)
  let token = prepare_for_test(SILENT_PATTERN)
  assert_true(token > 0)
  assert_position(1024)
  render_for_test(1)
  assert_true(output_energy() > 0.01)
  assert_eq(apply_prepared_playback(token, false), 0)
  assert_position(1152)
  render_for_test(1)
  assert_position(1280)
  assert_true(output_energy() > 0.01)
}

///|
test "failed preparation preserves active and accepted pending state" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(SILENT_PATTERN), 0)
  render_for_test(1)
  assert_eq(submit_for_test(REPEATING_NOTE, restart=false), 0)
  assert_eq(prepare_for_test("note("), 0)
  assert_position(128)
  render_for_test(1)
  assert_position(256)
  assert_eq(output_energy(), 0.0)
  // The silent material's current cycle finishes before the accepted edit.
  render_for_test(186)
  assert_position(24064)
  assert_true(output_energy() > 0.01)
}

///|
test "prepared tokens reject stale consumed discarded and failed results" {
  assert_true(init_scheduler_graph_for_test())
  let a = prepare_for_test("note(\"60\")")
  let b = prepare_for_test("note(\"72\")")
  assert_true(apply_prepared_playback(a, true) != 0)
  assert_eq(apply_prepared_playback(b, true), 0)
  assert_true(apply_prepared_playback(b, true) != 0)
  let c = prepare_for_test("note(\"60\")")
  assert_true(discard_prepared_playback(c))
  assert_true(apply_prepared_playback(c, true) != 0)
  let d = prepare_for_test("note(\"60\")")
  assert_eq(prepare_for_test("note("), 0)
  assert_true(apply_prepared_playback(d, true) != 0)
}

///|
test "restart keeps the applied score despite a pending replacement and invalid input" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(SILENT_PATTERN), 0)
  render_for_test(8)
  assert_eq(submit_for_test(REPEATING_NOTE, restart=false), 0)
  clear_playback_input()
  push_playback_char(33)
  assert_eq(restart_playback(), 0)
  assert_position(1024)
  render_for_test(1)
  assert_position(128)
  assert_eq(output_energy(), 0.0)
  render_for_test(1)
  assert_eq(output_energy(), 0.0)
}

///|
test "replacement and reset apply atomically and kill previous voices" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(8)
  assert_true(output_energy() > 0.01)
  assert_eq(submit_for_test(SILENT_PATTERN), 0)
  assert_position(1024)
  render_for_test(1)
  assert_position(128)
  assert_eq(output_energy(), 0.0)
}

///|
test "continuing a song rejects layout changes" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(test_song(length=8, bpm=120), song=true), 0)
  render_for_test(4)
  let token = prepare_for_test(test_song(length=9, bpm=120), song=true)
  assert_true(token > 0)
  assert_eq(apply_prepared_playback(token, false), 2)
  assert_position(512)
  assert_tempo(120.0)
}

///|
test "reset applies song layout and tempo together at the next block" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(test_song(length=8, bpm=120), song=true), 0)
  render_for_test(4)
  let token = prepare_for_test(test_song(length=9, bpm=90), song=true)
  assert_eq(apply_prepared_playback(token, false), 2)
  // Rejection leaves the token available for an explicit reset.
  assert_eq(apply_prepared_playback(token, true), 0)
  assert_position(512)
  assert_tempo(120.0)
  render_for_test(1)
  assert_position(128)
  assert_tempo(90.0)
}

///|
test "restart preserves the current global tempo" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(test_song(length=8, bpm=90), song=true), 0)
  render_for_test(4)
  assert_eq(set_scheduler_bpm(100.0), 0)
  assert_eq(restart_playback(), 0)
  render_for_test(1)
  assert_tempo(100.0)
}

///|
test "latest accepted apply wins and new preparation alone cannot replace it" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("note(\"60\")"), 0)
  assert_eq(submit_for_test(SILENT_PATTERN), 0)
  assert_true(prepare_for_test("note(\"72\")") > 0)
  render_for_test(1)
  assert_eq(output_energy(), 0.0)
}

///|
test "before first application continue and restart fail without cancelling start" {
  assert_true(init_scheduler_graph_for_test())
  assert_true(restart_playback() != 0)
  let token = prepare_for_test("note(\"60\")")
  assert_eq(apply_prepared_playback(token, false), 2)
  assert_eq(apply_prepared_playback(token, true), 0)
  assert_true(restart_playback() != 0)
  render_for_test(1)
  assert_position(128)
  assert_true(output_energy() > 0.01)
}

///|
test "reset invalidates prepared handles and clears queued playback" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(REPEATING_NOTE), 0)
  let token = prepare_for_test("note(\"60\")")
  reset_scheduler_graph()
  assert_true(init_scheduler_graph_for_test())
  assert_true(apply_prepared_playback(token, true) != 0)
  assert_eq(restart_playback(), 1)
  render_for_test(1)
  assert_eq(output_energy(), 0.0)
}

///|
test "playback errors are readable through the UTF-16 API" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(
    prepare_for_test(
      "song(section(\"a\",0,s(\"bd\")),part(\"a1\",\"a\"))",
      song=true,
    ),
    0,
  )
  let message = get_playback_error()
  assert_true(message.contains("positive length"))
  assert_eq(get_playback_error_length(), message.length())
  for i in 0..<message.length() {
    assert_eq(get_playback_error_char(i), message[i].to_int())
  }
  assert_eq(get_playback_error_char(-1), 0)
}

///|
test "finite playback ends and restart returns to the first onset" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(
    submit_for_test(
      "song(section(\"a\",1,note(\"60\")),part(\"a1\",\"a\"))",
      song=true,
    ),
    0,
  )
  render_for_test(1000)
  assert_eq(output_energy(), 0.0)
  assert_eq(restart_playback(), 0)
  render_for_test(2)
  assert_position(256)
  assert_true(output_energy() > 0.01)
}

///|
test "song tempo commits on all routes without restarting or moving the anchor" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(test_song(length=8, bpm=120), song=true), 0)
  render_for_test(4)
  let token = prepare_for_test(test_song(length=8, bpm=90), song=true)
  assert_eq(apply_prepared_playback(token, false), 0)
  assert_position(512)
  assert_tempo(120.0)
  render_for_test(1)
  assert_position(640)
  assert_tempo(90.0)
  for route in sched_routes.val {
    let frame = route.pool.scheduler.current_block().unwrap()
    assert_true(
      frame.logical_arc.begin ==
      @pattern.Rational::new(512L * 120L + 128L * 90L, 2880000L),
    )
  }
  assert_eq(set_scheduler_bpm(0.0), 1)
  assert_tempo(90.0)
  assert_position(640)
}

///|
test "a pending pattern entry follows tempo without choosing another entry" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("note(\"60\")"), 0)
  render_for_test(1)
  assert_eq(submit_for_test("note(\"72\")", restart=false), 0)
  render_for_test(1)
  for route in sched_routes.val {
    assert_true(route.pool.scheduler.has_pending_playback_snapshot())
  }
  assert_eq(set_scheduler_bpm(60.0), 0)
  assert_eq(
    sched_routes.val[0].pool.scheduler
    .sample_at(@pattern.Rational::from_int(1))
    .unwrap(),
    47744L,
  )
  render_for_test(371)
  assert_position(47744)
  for route in sched_routes.val {
    assert_true(route.pool.scheduler.has_pending_playback_snapshot())
  }
  render_for_test(1)
  for route in sched_routes.val {
    assert_false(route.pool.scheduler.has_pending_playback_snapshot())
  }
}

///|
test "reverting a routed edit cancels its pending material replacement" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("note(\"60\").slow(3)"), 0)
  render_for_test(1)
  assert_eq(submit_for_test("note(\"72\").slow(3)", restart=false), 0)
  render_for_test(1)
  for route in sched_routes.val {
    assert_true(route.pool.scheduler.has_pending_playback_snapshot())
  }
  assert_eq(submit_for_test("note(\"60\").slow(3)", restart=false), 0)
  render_for_test(1)
  for route in sched_routes.val {
    assert_false(route.pool.scheduler.has_pending_playback_snapshot())
  }
}

///|
test "tempo rejection preserves an accepted request across intervening messages" {
  assert_true(init_scheduler_graph_for_test())
  // The gate lasts about 288 samples at 0.001 BPM; its denominator makes
  // retiming to 1000 BPM exceed the checked conversion range.
  let body = "section(\"a\",1,note(\"60\").fast(10000019).fast(100000003).slow(100000000)),part(\"r\",\"a\"))"
  let original = "song(bpm(0.001)," + body
  assert_eq(submit_for_test(original, song=true), 0)
  render_for_test(1)
  assert_true(
    sched_routes.val.any(route => route.pool.scheduler.active_note_count() > 0),
  )
  assert_eq(submit_for_test(original, song=true, restart=false), 0)
  assert_eq(
    submit_for_test("song(bpm(1000)," + body, song=true, restart=false),
    1,
  )
  assert_eq(prepare_for_test("song(", song=true), 0)
  assert_eq(set_scheduler_bpm(0.002), 0)
  assert_tempo(0.002)
  render_for_test(1)
  assert_tempo(0.001)
}
