///|
const HELD_NOTE : String = "note(\"60\").slow(8)"

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
test "exact wire rejects broken witnesses atomically and accepts UTF16 source spans" {
  fn stage(wire : String) {
    clear_playback_input()
    for i in 0..<wire.length() {
      push_playback_char(wire[i].to_int())
    }
  }
  assert_true(init_scheduler_graph_for_test())
  let original = "/* \u{10400} */ " + HELD_NOTE
  let draft = @mini.Draft(original)
  guard draft.prepare_playback() is Ok(input) else {
    fail("expected tracked input")
  }
  stage(input.encode_wire())
  assert_eq(player_restart_input(), 0)
  assert_eq(player.val.unwrap().view().source, Some(original))
  render_for_test(8)
  let next = "note(\"72\").slow(8)"
  let next_draft = @mini.Draft(next)
  guard next_draft.prepare_playback() is Ok(candidate) else {
    fail("expected candidate")
  }
  stage(candidate.encode_wire())
  assert_eq(player_update_input(), 0)
  let pending = player_pending_count()
  assert_true(pending > 0)
  let json = @json.parse(candidate.encode_wire())
  guard json is Object(fields) &&
    fields.get("sourceMap") is Some(Object(sources)) else {
    fail("missing exact witness")
  }
  sources["atoms"] = []
  stage(json.stringify())
  assert_eq(player_restart_input(), 1)
  assert_eq(player.val.unwrap().view().source, Some(next))
  assert_eq(player_pending_count(), pending)
  assert_position(1024)
  clear_playback_input()
  push_playback_char(0xD800)
  assert_eq(player_update_input(), 1)
  assert_eq(player_pending_count(), pending)
  assert_position(1024)
  render_for_test(1)
  assert_true(output_energy() > 0.01)
}

///|
/// The exports map the player's states, kinds and errors to the codes and
/// messages the Worklet reads: states 0-4 here (Fault is 5), modes, command
/// results 0/1/2, and the last diagnostic.
test "exports map player states, modes and errors to their codes" {
  assert_true(init_scheduler_graph_for_test())
  assert_eq(player_state(), 0)
  assert_true(player_mode() is None)
  assert_eq(submit_for_test(HELD_NOTE, restart=false), 0)
  assert_eq(player_state(), 1)
  assert_true(player_mode() is Pattern)
  assert_eq(player_play(), 0)
  assert_eq(player_state(), 2)
  assert_eq(player_pause(), 0)
  assert_eq(player_state(), 3)
  let song = "song(section(\"a\",8,note(\"60\")),part(\"a1\",\"a\"))"
  assert_eq(submit_for_test(song), 0)
  assert_eq(player_state(), 2)
  assert_true(player_mode() is Song)
  let longer = "song(section(\"a\",9,note(\"60\")),part(\"a1\",\"a\"))"
  assert_eq(submit_for_test(longer, restart=false), 2)
  assert_eq(get_playback_error(), "song layout changed; restart required")
  assert_eq(set_scheduler_bpm(0.0), 1)
  assert_eq(get_playback_error(), "tempo must be 0.001..1000 BPM")
  assert_eq(scheduler_bpm(), 120.0)
  assert_eq(set_scheduler_bpm(90.0), 0)
  assert_eq(get_playback_error(), "")
  assert_eq(scheduler_bpm(), 90.0)
  let short = "song(section(\"a\",1/200,note(\"60\")),part(\"a1\",\"a\"))"
  assert_eq(submit_for_test(short), 0)
  for _ in 0..<4 {
    assert_true(process_scheduler_block())
  }
  assert_eq(player_state(), 4)
  assert_eq(submit_for_test("note(\"60\""), 1)
  assert_true(get_playback_error() != "")
}
