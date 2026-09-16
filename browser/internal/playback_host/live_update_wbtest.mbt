///|
const HELD_NOTE : String = "note(\"60\").slow(8)"

///|
const SILENT_PATTERN : String = "s(\"bd\").degradeBy(1)"

///|
test "update accepts before rendering but does not start Ready" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(player_play(), 1)
  assert_eq(submit_for_test(HELD_NOTE, restart=false), 0)
  assert_eq(player_state(), 1)
  assert_eq(player.val.unwrap().view().source, Some(HELD_NOTE))
  render_for_test(8)
  assert_position(0)
  assert_eq(output_energy(), 0.0)
  assert_eq(player_play(), 0)
  render_for_test(1)
  assert_position(128)
  assert_true(output_energy() > 0.01)
}

///|
test "invalid update preserves the last accepted material reservation" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("note(\"60\").gain(0)"), 0)
  render_for_test(1)
  let next = "note(\"60\").gain(1)"
  assert_eq(submit_for_test(next, restart=false), 0)
  assert_true(player_pending_count() > 0)
  assert_eq(submit_for_test("note(", restart=false), 1)
  assert_eq(player.val.unwrap().view().source, Some(next))
  assert_position(128)
  render_for_test(373)
  assert_eq(output_energy(), 0.0)
  render_for_test(2)
  assert_true(output_energy() > 0.01)
}

///|
test "invalid Restart cannot reset voices position or Current song" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(8)
  assert_eq(submit_for_test("note("), 1)
  assert_position(1024)
  assert_eq(player.val.unwrap().view().source, Some(HELD_NOTE))
  render_for_test(1)
  assert_true(output_energy() > 0.01)
  assert_eq(submit_for_test(SILENT_PATTERN), 0)
  assert_position(0)
  render_for_test(1)
  assert_eq(output_energy(), 0.0)
}

///|
test "Pause freezes voices effects and transport exactly" {
  fn sequence(paused : Bool) -> Array[Double] raise {
    assert_true(init_scheduler_graph_for_test())
    assert_eq(submit_for_test("note(\"60\").slow(8).hold(0.1).room(1)"), 0)
    render_for_test(20)
    if paused {
      assert_eq(player_pause(), 0)
      render_for_test(100)
      assert_eq(output_energy(), 0.0)
      assert_position(2560)
      assert_eq(player_state(), 3)
      assert_eq(player_play(), 0)
    }
    let samples : Array[Double] = []
    for _ in 0..<40 {
      render_for_test(1)
      for i in 0..<128 {
        samples.push(scheduler_left_sample(i))
      }
    }
    samples
  }
  assert_eq(sequence(true), sequence(false))
}

///|
test "paused Update commits tempo and Current song without advancing" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(8)
  assert_eq(player_pause(), 0)
  let changed = "bpm(90); note(\"72\").slow(8)"
  assert_eq(submit_for_test(changed, restart=false), 0)
  assert_eq(player.val.unwrap().view().source, Some(changed))
  assert_tempo(90.0)
  assert_position(1024)
  assert_true(player_pending_count() > 0)
  render_for_test(10)
  assert_position(1024)
  assert_eq(player_state(), 3)
  assert_eq(player_play(), 0)
  render_for_test(1)
  assert_position(1152)
}

///|
test "layout rejection changes neither tempo nor Current song" {
  assert_true(init_scheduler_graph_for_test())
  let original = test_song(length=8, bpm=120)
  let changed = test_song(length=9, bpm=90)
  assert_eq(submit_for_test(original), 0)
  render_for_test(4)
  assert_eq(submit_for_test(changed, restart=false), 2)
  assert_position(512)
  assert_tempo(120.0)
  assert_eq(player.val.unwrap().view().source, Some(original))
  assert_eq(submit_for_test(changed), 0)
  assert_position(0)
  assert_tempo(90.0)
}

///|
test "source tempo commits on all routes at unchanged musical position" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(test_song(length=8, bpm=120)), 0)
  render_for_test(4)
  assert_eq(submit_for_test(test_song(length=8, bpm=90), restart=false), 0)
  assert_position(512)
  assert_tempo(90.0)
  render_for_test(1)
  for scheduler in player.val.unwrap().schedulers {
    assert_eq(
      scheduler.current_block().unwrap().logical_arc.begin,
      @pattern.Rational::new(512L * 120L + 128L * 90L, 2880000L),
    )
  }
}

///|
test "Ended Update leaves tails and position while Play uses newest song" {
  assert_true(init_scheduler_graph_for_test())
  let finite = "song(section(\"a\",1/100,note(\"60\").release(1).room(1)),part(\"a1\",\"a\"))"
  assert_eq(submit_for_test(finite), 0)
  render_for_test(4)
  assert_eq(player_state(), 4)
  assert_eq(scheduler_sample_position(), 480.0)
  assert_eq(submit_for_test("silence()", restart=false), 0)
  assert_eq(player_state(), 4)
  render_for_test(10)
  assert_eq(scheduler_sample_position(), 480.0)
  assert_true(output_energy() > 0.0)
  assert_eq(player_play(), 0)
  assert_position(0)
  render_for_test(1)
  assert_eq(output_energy(), 0.0)
}

///|
test "finite Play starts from its first onset again" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(
    submit_for_test("song(section(\"a\",1,note(\"60\")),part(\"a1\",\"a\"))"),
    0,
  )
  render_for_test(1000)
  assert_eq(player_state(), 4)
  assert_eq(output_energy(), 0.0)
  assert_eq(player_play(), 0)
  render_for_test(2)
  assert_position(256)
  assert_true(output_energy() > 0.01)
}

///|
test "reverting a routed edit cancels pending material changes" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test("note(\"60\").slow(3)"), 0)
  render_for_test(1)
  assert_eq(submit_for_test("note(\"72\").slow(3)", restart=false), 0)
  assert_true(player_pending_count() > 0)
  assert_eq(submit_for_test("note(\"60\").slow(3)", restart=false), 0)
  assert_eq(player_pending_count(), 0)
}

///|
test "workload rejection preserves the accepted song voices and all clocks" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(1)
  let rejected = [
    "note(\"60\").fast(100000)", "note(\"60*1000 ~\")", "note(\"60\").every(1000000,fast(100000))",
    "song(section(\"a\",1,s(\"bd(1,100000)\")),part(\"r\",\"a\"))", "note(\"60\").slow(1000000000).slow(1000000000)",
  ]
  for source in rejected {
    assert_eq(submit_for_test(source, restart=false), 1)
    assert_tempo(60.0)
    assert_position(128)
    assert_eq(player.val.unwrap().view().source, Some(HELD_NOTE))
  }
  render_for_test(1)
  assert_position(256)
  assert_true(output_energy() > 0.01)
}

///|
test "closing the owner discards source and subsequent operations reject" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  reset_scheduler_graph()
  assert_eq(player_play(), 1)
  assert_eq(submit_for_test(HELD_NOTE, restart=false), 1)
  assert_true(init_scheduler_graph_for_test())
  assert_eq(player_play(), 1)
  render_for_test(1)
  assert_eq(output_energy(), 0.0)
}

///|
test "playback diagnostics preserve UTF-16 code units" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(
    submit_for_test("song(section(\"a\",0,s(\"bd\")),part(\"a1\",\"a\"))"),
    1,
  )
  let message = get_playback_error()
  assert_true(message.contains("positive length"))
  assert_eq(get_playback_error_length(), message.length())
  for i in 0..<message.length() {
    assert_eq(get_playback_error_char(i), message[i].to_int())
  }
}

///|
test "unrepresentable finite endpoints reject before publication or restart" {
  assert_true(
    init_scheduler_graph_with_templates(
      192000.0,
      128,
      test_drum_template(60.0),
      test_drum_template(180.0),
      test_drum_template(8000.0),
      test_drum_template(1200.0),
      test_drum_template(6000.0),
      test_synth_template(),
    ),
  )
  let invalid = "bpm(0.001); song(section(\"a\",2000000000,silence()),part(\"p\",\"a\"))"
  assert_eq(submit_for_test(invalid, restart=false), 1)
  assert_eq(player_state(), 0)
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(8)
  assert_eq(submit_for_test(invalid), 1)
  assert_position(1024)
  assert_tempo(60.0)
  assert_eq(player.val.unwrap().view().source, Some(HELD_NOTE))
  render_for_test(1)
  assert_true(output_energy() > 0.01)
  let finite = "song(section(\"a\",1/1000,silence()),part(\"p\",\"a\"))"
  assert_eq(submit_for_test(finite), 0)
  render_for_test(2)
  assert_eq(player_state(), 4)
  assert_eq(submit_for_test(invalid, restart=false), 1)
  assert_eq(player.val.unwrap().view().source, Some(finite))
  assert_eq(player_state(), 4)
}

///|
test "repeat admission rejects sub-block cycles without replacing music" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(submit_for_test(HELD_NOTE), 0)
  render_for_test(8)
  let too_short = "bpm(1000); song(section(\"a\",1/100000,silence()),part(\"p\",\"a\")).repeat()"
  assert_eq(submit_for_test(too_short), 1)
  assert_position(1024)
  assert_tempo(60.0)
  assert_eq(player.val.unwrap().view().source, Some(HELD_NOTE))
  render_for_test(1)
  assert_true(output_energy() > 0.01)
}

///|
test "one-block repeat is valid but faster source and demo tempos reject" {
  assert_true(init_scheduler_graph_for_test())
  let body = "song(section(\"a\",1/375,note(\"60\")),part(\"p\",\"a\")).repeat()"
  assert_eq(submit_for_test(body), 0)
  render_for_test(4)
  assert_eq(player_state(), 2)
  assert_position(512)
  assert_eq(submit_for_test("bpm(60.001); " + body, restart=false), 1)
  assert_eq(set_scheduler_bpm(60.001), 1)
  assert_tempo(60.0)
  assert_eq(player.val.unwrap().view().source, Some(body))
  render_for_test(4)
  assert_position(1024)
  assert_eq(player_state(), 2)
}
