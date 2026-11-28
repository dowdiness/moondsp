///|
/// Restart the player on the tracked draft `text`.
fn restart_tracked_for_test(text : String) -> Unit raise {
  guard @mini.Draft(text).prepare_playback() is Ok(input) else {
    fail("expected tracked input")
  }
  clear_playback_input()
  let wire = input.encode_wire()
  for i in 0..<wire.length() {
    push_playback_char(wire[i].to_int())
  }
  assert_eq(player_restart_input(), 0)
}

///|
test "onset rows encode the player's onsets, and the count and clear bound them" {
  assert_true(init_scheduler_graph_for_test())
  restart_tracked_for_test("bpm(240); stack(note(\"60*32\"), s(\"bd\"))")
  assert_eq(player_play(), 0)
  // Off at first.
  render_for_test(1)
  assert_eq(player_onset_count(), 0)
  player_onset_enable(1)
  // One cycle is 375 blocks: 33 onsets per cycle, 297 in nine.
  render_for_test(375 * 9)
  guard player.val is Some(owner) else { fail("expected a player") }
  let onsets = owner.onsets()
  let count = player_onset_count()
  assert_eq(count, 256)
  assert_eq(player_onset_dropped(), onsets.dropped().to_double())
  assert_true(onsets.dropped() > 0)
  let mut hits = 0
  for index in 0..<count {
    let source = onsets.source(index)
    let origin = source.origin()
    assert_eq(player_onset_field(index, 0), onsets.sample(index).to_double())
    assert_eq(
      player_onset_field(index, 1),
      origin.atom().epoch().serial().to_double(),
    )
    assert_eq(player_onset_field(index, 2), origin.atom().serial().to_double())
    match source.source_frame() {
      Some(frame) => {
        assert_eq(player_onset_field(index, 3), frame.serial().to_double())
        assert_eq(player_onset_field(index, 4), source.source_start())
      }
      None => {
        assert_eq(player_onset_field(index, 3), 0.0)
        assert_eq(player_onset_field(index, 4), -1.0)
      }
    }
    match source.event().value.sound {
      Hit(_) => {
        hits += 1
        assert_true(player_onset_field(index, 5).is_nan())
      }
      _ => assert_eq(player_onset_field(index, 5), 60.0)
    }
    // No binding path: nothing after the count.
    assert_eq(player_onset_field(index, 6), 0.0)
    assert_eq(player_onset_field(index, 7), 0.0)
  }
  assert_true(hits > 0)
  for outside in [(-1, 0), (count, 0), (0, -1), (0, 103)] {
    assert_eq(player_onset_field(outside.0, outside.1), 0.0)
  }
  player_onset_clear()
  assert_eq(player_onset_count(), 0)
  assert_eq(player_onset_dropped(), 0.0)
}

///|
test "signal rows encode the values voices read from the signals they follow" {
  assert_true(init_scheduler_graph_for_test())
  restart_tracked_for_test("bpm(240); note(\"G3*4\").pan(sine)")
  assert_eq(player_play(), 0)
  player_signal_enable(1)
  render_for_test(40)
  guard player.val is Some(owner) else { fail("expected a player") }
  let signals = owner.signals()
  let count = player_signal_count()
  assert_true(count > 0)
  assert_eq(count, signals.count())
  for index in 0..<count {
    let signal = signals.signal(index)
    assert_eq([0, 1, 2, 3, 4].map(field => player_signal_field(index, field)), [
      signals.sample(index).to_double(),
      signal.epoch().serial().to_double(),
      signal.serial().to_double(),
      signals.material(index),
      signals.value(index),
    ])
  }
  assert_eq(player_signal_field(count, 0), 0.0)
  assert_eq(player_signal_field(0, 5), 0.0)
  player_signal_clear()
  assert_eq(player_signal_count(), 0)
}
