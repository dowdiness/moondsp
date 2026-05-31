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
  guard sched_active_playback.val is Some(ActiveSong(route_songs)) else {
    fail("song eval did not activate song playback")
  }
  @debug.assert_eq(route_songs.length(), sched_routes.val.length())
  for route in sched_routes.val {
    @debug.assert_eq(route.pool.scheduler.bpm(), 72.0)
  }

  push_pattern_text_for_test("invalid!!!")
  @debug.assert_eq(eval_pattern_input(), 1)
  guard sched_active_playback.val is Some(ActiveSong(_)) else {
    fail("pattern parse failure should keep last good song playback")
  }

  push_pattern_text_for_test("s(\"bd\")")
  @debug.assert_eq(eval_pattern_input(), 0)
  guard sched_active_playback.val is Some(ActivePattern(_)) else {
    fail("valid pattern did not switch active playback back to pattern")
  }
}

///|
test "browser scheduler song start resets route transport" {
  assert_true(init_scheduler_graph(48000.0, 128))
  push_pattern_text_for_test("s(\"bd\")")
  @debug.assert_eq(eval_pattern_input(), 0)
  assert_true(process_scheduler_block())
  for route in sched_routes.val {
    @debug.assert_eq(route.pool.scheduler.sample_counter(), 128L)
  }

  push_song_text_for_test(BROWSER_SONG_TEST_INPUT)
  @debug.assert_eq(eval_song_input(), 0)
  for route in sched_routes.val {
    @debug.assert_eq(route.pool.scheduler.sample_counter(), 0L)
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
  guard sched_active_playback.val is Some(ActivePattern(_)) else {
    fail("song parse failure should keep last good pattern playback")
  }
  let message = get_song_parse_error()
  assert_true(message.contains("section 'intro' requires a positive length"))
  @debug.assert_eq(get_song_error_length(), message.length())
  @debug.assert_eq(get_song_error_char(0), message[0].to_int())
  @debug.assert_eq(get_song_error_char(-1), 0)
  @debug.assert_eq(get_song_error_char(message.length()), 0)
}
