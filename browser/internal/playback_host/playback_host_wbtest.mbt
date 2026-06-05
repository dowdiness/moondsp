///|
const BROWSER_SONG_TEST_INPUT : String = "song(bpm(72),section(\"intro\",1,s(\"bd\")),section(\"verse\",2,note(\"60\")),part(\"intro1\",\"intro\"),part(\"verse1\",\"verse\"))"

///|
fn test_drum_template(freq : Double) -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, freq),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=60.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
fn test_synth_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=10.0,
      decay_ms=100.0,
      sustain=0.7,
      release_ms=300.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
fn init_scheduler_graph_for_test() -> Bool {
  init_scheduler_graph_with_templates(
    48000.0,
    128,
    test_drum_template(60.0),
    test_drum_template(180.0),
    test_drum_template(8000.0),
    test_drum_template(1200.0),
    test_drum_template(6000.0),
    test_synth_template(),
  )
}

///|
fn push_pattern_text_for_test(text : String) -> Unit {
  clear_pattern_input()
  for i in 0..<text.length() {
    push_pattern_char(text[i].to_int())
  }
}

///|
fn push_song_text_for_test(text : String) -> Unit {
  clear_song_input()
  for i in 0..<text.length() {
    push_song_char(text[i].to_int())
  }
}

///|
fn active_playback_is_pattern_for_test() -> Bool {
  sched_active_playback.val is Some(ActivePattern(_))
}

///|
fn active_playback_is_song_for_test() -> Bool {
  sched_active_playback.val is Some(ActiveSong(_))
}

///|
fn active_song_route_count_for_test() -> Int? {
  match sched_active_playback.val {
    Some(ActiveSong(route_songs)) => Some(route_songs.length())
    _ => None
  }
}

///|
fn route_count_for_test() -> Int {
  sched_routes.val.length()
}

///|
fn routes_have_bpm_for_test(bpm : Double) -> Bool {
  for route in sched_routes.val {
    if route.pool.scheduler.bpm() != bpm {
      return false
    }
  }
  true
}

///|
fn route_sample_counters_for_test() -> Array[Int64] {
  let counters : Array[Int64] = []
  for route in sched_routes.val {
    counters.push(route.pool.scheduler.sample_counter())
  }
  counters
}

///|
fn assert_error_transport_for_test(
  message : String,
  length : () -> Int,
  char_at : (Int) -> Int,
) -> Unit raise {
  assert_true(message.length() > 0)
  @debug.assert_eq(length(), message.length())
  @debug.assert_eq(char_at(0), message[0].to_int())
  @debug.assert_eq(char_at(-1), 0)
  @debug.assert_eq(char_at(message.length()), 0)
}

///|
fn assert_pattern_error_transport_for_test(message : String) -> Unit raise {
  assert_error_transport_for_test(
    message, get_pattern_error_length, get_pattern_error_char,
  )
}

///|
fn assert_song_error_transport_for_test(message : String) -> Unit raise {
  assert_error_transport_for_test(
    message, get_song_error_length, get_song_error_char,
  )
}

///|
test "browser scheduler parse status values stay ABI compatible" {
  @debug.assert_eq(SCHEDULER_PARSE_STATUS_OK, 0)
  @debug.assert_eq(SCHEDULER_PARSE_STATUS_ERROR, 1)
}

///|
test "browser scheduler song input switches active playback explicitly" {
  assert_true(init_scheduler_graph_for_test())

  push_song_text_for_test(BROWSER_SONG_TEST_INPUT)
  @debug.assert_eq(eval_song_input(), SCHEDULER_PARSE_STATUS_OK)
  @debug.assert_eq(get_song_error_length(), 0)
  assert_true(active_playback_is_song_for_test())
  @debug.assert_eq(
    active_song_route_count_for_test(),
    Some(route_count_for_test()),
  )
  assert_true(routes_have_bpm_for_test(72.0))

  push_pattern_text_for_test("invalid!!!")
  @debug.assert_eq(eval_pattern_input(), SCHEDULER_PARSE_STATUS_ERROR)
  assert_true(active_playback_is_song_for_test())

  push_pattern_text_for_test("s(\"bd\")")
  @debug.assert_eq(eval_pattern_input(), SCHEDULER_PARSE_STATUS_OK)
  assert_true(active_playback_is_pattern_for_test())
}

///|
test "browser scheduler direct parse helpers use stable error transport" {
  assert_true(init_scheduler_graph_for_test())
  @debug.assert_eq(
    parse_and_set_song(BROWSER_SONG_TEST_INPUT),
    SCHEDULER_PARSE_STATUS_OK,
  )
  assert_true(active_playback_is_song_for_test())

  @debug.assert_eq(
    parse_and_set_pattern("s(\"bogus_drum\")"),
    SCHEDULER_PARSE_STATUS_ERROR,
  )
  assert_true(active_playback_is_song_for_test())
  let pattern_message = get_scheduler_parse_error()
  assert_true(pattern_message.contains("bogus_drum"))
  @debug.assert_eq(get_song_parse_error(), pattern_message)
  assert_pattern_error_transport_for_test(pattern_message)

  @debug.assert_eq(
    parse_and_set_pattern("s(\"bd\")"),
    SCHEDULER_PARSE_STATUS_OK,
  )
  assert_true(active_playback_is_pattern_for_test())
  @debug.assert_eq(get_pattern_error_length(), 0)

  @debug.assert_eq(
    parse_and_set_song(
      "song(section(\"intro\",0,s(\"bd\")),part(\"intro1\",\"intro\"))",
    ),
    SCHEDULER_PARSE_STATUS_ERROR,
  )
  assert_true(active_playback_is_pattern_for_test())
  let song_message = get_song_parse_error()
  assert_true(
    song_message.contains("section 'intro' requires a positive length"),
  )
  @debug.assert_eq(get_scheduler_parse_error(), song_message)
  assert_song_error_transport_for_test(song_message)
}

///|
test "browser scheduler song start resets route transport" {
  assert_true(init_scheduler_graph_for_test())
  push_pattern_text_for_test("s(\"bd\")")
  @debug.assert_eq(eval_pattern_input(), SCHEDULER_PARSE_STATUS_OK)
  assert_true(process_scheduler_block())
  for counter in route_sample_counters_for_test() {
    @debug.assert_eq(counter, 128L)
  }

  push_song_text_for_test(BROWSER_SONG_TEST_INPUT)
  @debug.assert_eq(eval_song_input(), SCHEDULER_PARSE_STATUS_OK)
  for counter in route_sample_counters_for_test() {
    @debug.assert_eq(counter, 0L)
  }
}

///|
test "browser scheduler song parse error accessors preserve last good pattern" {
  assert_true(init_scheduler_graph_for_test())
  @debug.assert_eq(
    parse_and_set_pattern("s(\"bd\")"),
    SCHEDULER_PARSE_STATUS_OK,
  )

  push_song_text_for_test(
    "song(section(\"intro\",0,s(\"bd\")),part(\"intro1\",\"intro\"))",
  )
  @debug.assert_eq(eval_song_input(), SCHEDULER_PARSE_STATUS_ERROR)
  assert_true(active_playback_is_pattern_for_test())
  let message = get_song_parse_error()
  assert_true(message.contains("section 'intro' requires a positive length"))
  assert_song_error_transport_for_test(message)
}
