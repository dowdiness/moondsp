///|
const BROWSER_SONG_TEST_INPUT : String = "song(bpm(72),section(\"intro\",1,s(\"bd\")),section(\"verse\",2,note(\"60\")),part(\"intro1\",\"intro\"),part(\"verse1\",\"verse\"))"

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
test "browser scheduler song input switches active playback explicitly" {
  assert_true(init_scheduler_graph(48000.0, 128))

  push_song_text_for_test(BROWSER_SONG_TEST_INPUT)
  @debug.assert_eq(eval_song_input(), 0)
  @debug.assert_eq(get_song_error_length(), 0)
  assert_true(@playback_host.active_playback_is_song())
  @debug.assert_eq(
    @playback_host.active_song_route_count(),
    Some(@playback_host.route_count()),
  )
  assert_true(@playback_host.routes_have_bpm(72.0))

  push_pattern_text_for_test("invalid!!!")
  @debug.assert_eq(eval_pattern_input(), 1)
  assert_true(@playback_host.active_playback_is_song())

  push_pattern_text_for_test("s(\"bd\")")
  @debug.assert_eq(eval_pattern_input(), 0)
  assert_true(@playback_host.active_playback_is_pattern())
}

///|
test "browser scheduler song start resets route transport" {
  assert_true(init_scheduler_graph(48000.0, 128))
  push_pattern_text_for_test("s(\"bd\")")
  @debug.assert_eq(eval_pattern_input(), 0)
  assert_true(process_scheduler_block())
  for counter in @playback_host.route_sample_counters() {
    @debug.assert_eq(counter, 128L)
  }

  push_song_text_for_test(BROWSER_SONG_TEST_INPUT)
  @debug.assert_eq(eval_song_input(), 0)
  for counter in @playback_host.route_sample_counters() {
    @debug.assert_eq(counter, 0L)
  }
}

///|
test "browser scheduler song parse error accessors preserve last good pattern" {
  assert_true(init_scheduler_graph(48000.0, 128))
  @debug.assert_eq(parse_and_set_pattern("s(\"bd\")"), 0)

  push_song_text_for_test(
    "song(section(\"intro\",0,s(\"bd\")),part(\"intro1\",\"intro\"))",
  )
  @debug.assert_eq(eval_song_input(), 1)
  assert_true(@playback_host.active_playback_is_pattern())
  let message = get_song_parse_error()
  assert_true(message.contains("section 'intro' requires a positive length"))
  @debug.assert_eq(get_song_error_length(), message.length())
  @debug.assert_eq(get_song_error_char(0), message[0].to_int())
  @debug.assert_eq(get_song_error_char(-1), 0)
  @debug.assert_eq(get_song_error_char(message.length()), 0)
}
