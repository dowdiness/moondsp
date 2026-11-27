///|
const HELD_NOTE : String = "note(\"60\").slow(8)"

///|
const SILENT_PATTERN : String = "s(\"bd\").degradeBy(1)"

///|
test "mode and cycle status follow transport without sample-rate approximation" {
  let player = test_player()
  assert_true(player.mode() is None)
  assert_eq(player.cycle_position(), 0.0)
  assert_eq(submit(player, "bpm(120); note(\"60\").slow(8)"), None)
  assert_true(player.mode() is Some(Pattern))
  assert_eq(player.cycle_position(), 0.0)
  assert_eq(play(player), None)
  render_blocks(player, 4)
  let before_tempo = player.cycle_position()
  assert_true(before_tempo > 0.0)
  assert_eq(
    submit(player, "bpm(90); note(\"72\").slow(8)", restart=false),
    None,
  )
  assert_true((player.cycle_position() - before_tempo).abs() < 0.000000000001)
  assert_eq(pause(player), None)
  let paused = player.cycle_position()
  render_blocks(player, 20)
  assert_eq(player.cycle_position(), paused)
  assert_eq(play(player), None)
  assert_eq(submit(player, "bpm(90); note(\"72\").slow(8)"), None)
  assert_eq(player.cycle_position(), 0.0)
}

///|
test "finite Ended status reports the accepted song endpoint" {
  let player = test_player()
  let first = "song(section(\"a\",1/200,note(\"60\")),part(\"a1\",\"a\"))"
  assert_eq(submit(player, first), None)
  render_blocks(player, 4)
  assert_eq(player.state(), Ended)
  assert_true(player.mode() is Some(Song))
  assert_eq(player.cycle_position(), 0.005)
  assert_eq(submit(player, "silence()", restart=false), None)
  assert_eq(player.state(), Ended)
  assert_true(player.mode() is Some(Pattern))
  assert_eq(player.cycle_position(), 0.005)
  let second = "song(section(\"a\",1/100,note(\"72\")),part(\"a1\",\"a\"))"
  assert_eq(submit(player, second, restart=false), None)
  assert_eq(player.state(), Ended)
  assert_eq(player.cycle_position(), 0.005)
}

///|
test "update rejection preserves mode and cycle status" {
  let player = test_player()
  assert_eq(submit(player, "note(\"60\").slow(8)"), None)
  assert_eq(play(player), None)
  render_blocks(player, 4)
  let before = player.cycle_position()
  assert_rejected(submit(player, "note(", restart=false))
  assert_true(player.mode() is Some(Pattern))
  assert_true((player.cycle_position() - before).abs() < 0.000000000001)
}

///|
test "update accepts before rendering but does not start Ready" {
  let player = test_player()
  assert_rejected(play(player))
  assert_eq(submit(player, HELD_NOTE, restart=false), None)
  assert_eq(player.state(), Ready)
  assert_accepted(player, HELD_NOTE)
  render_blocks(player, 8)
  assert_position(player, 0)
  assert_eq(output_energy(), 0.0)
  assert_eq(play(player), None)
  render_blocks(player, 1)
  assert_position(player, 128)
  assert_true(output_energy() > 0.01)
}

///|
test "invalid update preserves the last accepted material reservation" {
  let player = test_player()
  assert_eq(submit(player, "note(\"60\").gain(0)"), None)
  render_blocks(player, 1)
  let next = "note(\"60\").gain(1)"
  assert_eq(submit(player, next, restart=false), None)
  assert_eq(player.pending_materials(), 1)
  assert_accepted(player, next)
  assert_position(player, 128)
  render_blocks(player, 748)
  assert_eq(output_energy(), 0.0)
  render_blocks(player, 2)
  assert_true(output_energy() > 0.01)
}

///|
test "invalid Restart cannot reset voices position or Current song" {
  let player = test_player()
  assert_eq(submit(player, HELD_NOTE), None)
  render_blocks(player, 8)
  assert_rejected(submit(player, "note("))
  assert_position(player, 1024)
  assert_accepted(player, HELD_NOTE)
  render_blocks(player, 1)
  assert_true(output_energy() > 0.01)
  assert_eq(submit(player, SILENT_PATTERN), None)
  assert_position(player, 0)
  render_blocks(player, 1)
  assert_eq(output_energy(), 0.0)
}

///|
test "Pause freezes voices effects and transport exactly" {
  fn sequence(paused : Bool) -> Array[Double] raise {
    let player = test_player()
    assert_eq(submit(player, "note(\"60\").slow(8).hold(0.1).room(1)"), None)
    render_blocks(player, 20)
    if paused {
      assert_eq(pause(player), None)
      render_blocks(player, 100)
      assert_eq(output_energy(), 0.0)
      assert_position(player, 2560)
      assert_eq(player.state(), Paused)
      assert_eq(play(player), None)
    }
    let samples : Array[Double] = []
    for _ in 0..<40 {
      render_blocks(player, 1)
      for i in 0..<128 {
        samples.push(out_left.get(i))
      }
    }
    samples
  }
  assert_eq(sequence(true), sequence(false))
}

///|
test "paused Update commits tempo and Current song without advancing" {
  let player = test_player()
  assert_eq(submit(player, HELD_NOTE), None)
  render_blocks(player, 8)
  assert_eq(pause(player), None)
  let changed = "bpm(90); note(\"72\").slow(8)"
  assert_eq(submit(player, changed, restart=false), None)
  assert_accepted(player, changed)
  assert_tempo(player, 90.0)
  assert_position(player, 1024)
  assert_true(player.pending_materials() > 0)
  render_blocks(player, 10)
  assert_position(player, 1024)
  assert_eq(player.state(), Paused)
  assert_eq(play(player), None)
  render_blocks(player, 1)
  assert_position(player, 1152)
}

///|
test "layout rejection changes neither tempo nor Current song" {
  let player = test_player()
  let original = test_song(length=8, bpm=120)
  let changed = test_song(length=9, bpm=90)
  assert_eq(submit(player, original), None)
  render_blocks(player, 4)
  assert_true(submit(player, changed, restart=false) is Some(RestartRequired))
  assert_position(player, 512)
  assert_tempo(player, 120.0)
  assert_accepted(player, original)
  assert_eq(submit(player, changed), None)
  assert_position(player, 0)
  assert_tempo(player, 90.0)
}

///|
test "Ended Update leaves tails and position while Play uses newest song" {
  let player = test_player()
  let finite = "song(section(\"a\",1/200,note(\"60\").release(1).room(1)),part(\"a1\",\"a\"))"
  assert_eq(submit(player, finite), None)
  render_blocks(player, 4)
  assert_eq(player.state(), Ended)
  assert_eq(player.sample_position(), 480.0)
  assert_eq(submit(player, "silence()", restart=false), None)
  assert_eq(player.state(), Ended)
  render_blocks(player, 10)
  assert_eq(player.sample_position(), 480.0)
  assert_true(output_energy() > 0.0)
  assert_eq(play(player), None)
  assert_position(player, 0)
  render_blocks(player, 1)
  assert_eq(output_energy(), 0.0)
}

///|
test "finite Play starts from its first onset again" {
  let player = test_player()
  assert_eq(
    submit(player, "song(section(\"a\",1,note(\"60\")),part(\"a1\",\"a\"))"),
    None,
  )
  render_blocks(player, 1000)
  assert_eq(player.state(), Ended)
  assert_eq(output_energy(), 0.0)
  assert_eq(play(player), None)
  render_blocks(player, 2)
  assert_position(player, 256)
  assert_true(output_energy() > 0.01)
}

///|
test "reverting a routed edit cancels pending material changes" {
  let player = test_player()
  assert_eq(submit(player, "note(\"60\").slow(3)"), None)
  render_blocks(player, 1)
  assert_eq(submit(player, "note(\"72\").slow(3)", restart=false), None)
  assert_true(player.pending_materials() > 0)
  assert_eq(submit(player, "note(\"60\").slow(3)", restart=false), None)
  assert_eq(player.pending_materials(), 0)
}

///|
test "workload rejection preserves the accepted song voices and all clocks" {
  let player = test_player()
  assert_eq(submit(player, HELD_NOTE), None)
  render_blocks(player, 1)
  let rejected = [
    "note(\"60\").fast(100000)", "note(\"60*1000 ~\")", "note(\"60\").every(1000000,fast(100000))",
    "song(section(\"a\",1,s(\"bd(1,100000)\")),part(\"r\",\"a\"))", "note(\"60\").slow(1000000000).slow(1000000000)",
  ]
  for source in rejected {
    assert_rejected(submit(player, source, restart=false))
    assert_tempo(player, 120.0)
    assert_position(player, 128)
    assert_accepted(player, HELD_NOTE)
  }
  render_blocks(player, 1)
  assert_position(player, 256)
  assert_true(output_energy() > 0.01)
}

///|
test "unrepresentable finite endpoints reject before publication or restart" {
  let player = test_player(sample_rate=192000.0)
  let invalid = "bpm(0.001); song(section(\"a\",2000000000,silence()),part(\"p\",\"a\"))"
  assert_rejected(submit(player, invalid, restart=false))
  assert_eq(player.state(), Empty)
  assert_eq(submit(player, HELD_NOTE), None)
  render_blocks(player, 8)
  assert_rejected(submit(player, invalid))
  assert_position(player, 1024)
  assert_tempo(player, 120.0)
  assert_accepted(player, HELD_NOTE)
  render_blocks(player, 1)
  assert_true(output_energy() > 0.01)
  let finite = "song(section(\"a\",1/2000,silence()),part(\"p\",\"a\"))"
  assert_eq(submit(player, finite), None)
  render_blocks(player, 2)
  assert_eq(player.state(), Ended)
  assert_rejected(submit(player, invalid, restart=false))
  assert_accepted(player, finite)
  assert_eq(player.state(), Ended)
}

///|
test "repeat admission rejects sub-block cycles without replacing music" {
  let player = test_player()
  assert_eq(submit(player, HELD_NOTE), None)
  render_blocks(player, 8)
  let too_short = "bpm(1000); song(section(\"a\",1/100000,silence()),part(\"p\",\"a\")).repeat()"
  assert_rejected(submit(player, too_short))
  assert_position(player, 1024)
  assert_tempo(player, 120.0)
  assert_accepted(player, HELD_NOTE)
  render_blocks(player, 1)
  assert_true(output_energy() > 0.01)
}

///|
test "one-block repeat is valid but faster source and demo tempos reject" {
  let player = test_player()
  let body = "song(section(\"a\",1/750,note(\"60\")),part(\"p\",\"a\")).repeat()"
  assert_eq(submit(player, body), None)
  render_blocks(player, 4)
  assert_eq(player.state(), Playing)
  assert_position(player, 512)
  assert_rejected(submit(player, "bpm(120.001); " + body, restart=false))
  assert_rejected(set_tempo(player, 120.001))
  assert_tempo(player, 120.0)
  assert_accepted(player, body)
  render_blocks(player, 4)
  assert_position(player, 1024)
  assert_eq(player.state(), Playing)
}

///|
test "unterminated comments cannot publish source tempo or stop sounding voices" {
  let player = test_player()
  let original = "bpm(90); " + HELD_NOTE
  assert_eq(submit(player, original), None)
  render_blocks(player, 8)
  assert_rejected(submit(player, "bpm(120); note(\"64\") /*", restart=false))
  assert_accepted(player, original)
  assert_tempo(player, 90.0)
  assert_position(player, 1024)
  render_blocks(player, 1)
  assert_true(output_energy() > 0.01)
}

///|
test "source material budget rejects future occurrences before publishing Ready" {
  let player = test_player()
  assert_eq(submit(player, HELD_NOTE, restart=false), None)
  let parts = [ for i in 0..<100 => "part(\"p\{i}\",\"a\")" ]
  let oversized = "song(section(\"a\",1,stack(note(\"60\"),note(\"62\"),note(\"64\")))," +
    parts.join(",") +
    ")"
  assert_rejected(submit(player, oversized, restart=false))
  assert_accepted(player, HELD_NOTE)
  assert_eq(player.state(), Ready)
  assert_position(player, 0)
  assert_eq(play(player), None)
  render_blocks(player, 1)
  assert_true(output_energy() > 0.01)
}

///|
/// Mean output energy per block over cycle `cycle`'s middle half, at 120 BPM
/// (750 blocks per cycle), rendering up to there.
fn cycle_energy(
  player : Player,
  rendered : Ref[Int32],
  cycle : Int32,
) -> Double raise {
  let begin = cycle * 750 + 188
  render_blocks(player, begin - rendered.val)
  let mut energy = 0.0
  for _ in 0..<375 {
    render_blocks(player, 1)
    energy = energy + output_energy()
  }
  rendered.val = begin + 375
  energy / 375.0
}

///|
test "a fade added by a live edit starts where the edit enters" {
  let player = test_player()
  let plain = "bpm(120); note(\"60 64\")"
  assert_eq(submit(player, plain), None)
  assert_eq(play(player), None)
  let rendered = Ref(0)
  let full = cycle_energy(player, rendered, 7)
  assert_true(full > 0.01)
  // The edit lands during cycle 8 and enters at cycle 9, after the material
  // has played for longer than the fade.
  render_blocks(player, 8 * 750 + 100 - rendered.val)
  rendered.val = 8 * 750 + 100
  assert_eq(submit(player, plain + ".fadeOut(4)", restart=false), None)
  let first = cycle_energy(player, rendered, 9)
  assert_true(first > full * 0.6)
  // Resubmitting the same text keeps the running fade.
  assert_eq(submit(player, plain + ".fadeOut(4)", restart=false), None)
  let middle = cycle_energy(player, rendered, 11)
  assert_true(middle < first * 0.7 && middle > full * 0.1)
  assert_true(cycle_energy(player, rendered, 14) < full * 0.001)
}
