// Drives one test player the way the browser host's exports do, so the
// session tests read like the host's while asserting on the scheduler itself.
// Sources are untracked text, as the host's `kind: "text"` wire sends them.

///|
let player : Ref[Player?] = Ref(None)

///|
let last_error : Ref[String] = Ref("")

///|
fn init_scheduler_graph_for_test(
  sample_rate~ : Double = 48000.0,
  block_size~ : Int32 = 128,
) -> Bool {
  player.val = Some(test_player(sample_rate~, block_size~)) catch {
    _ => {
      player.val = None
      return false
    }
  }
  true
}

///|
/// 0 on success, 2 when the layout needs a restart, otherwise 1, as the
/// host's commands return.
fn command(f : (Player) -> Unit raise PlayerError) -> Int32 {
  guard player.val is Some(owner) else { return 1 }
  f(owner) catch {
    error => {
      last_error.val = error.message()
      return if error is RestartRequired { 2 } else { 1 }
    }
  }
  0
}

///|
fn submit_for_test(text : String, restart~ : Bool = true) -> Int32 {
  let input = @mini.PlaybackInput::text(text)
  command(owner => {
    if restart {
      owner.restart(input)
    } else {
      owner.update(input)
    }
  })
}

///|
fn render_for_test(count : Int32) -> Unit raise {
  for _ in 0..<count {
    guard player.val.unwrap().process() else {
      fail("expected a rendered block")
    }
  }
}

///|
fn output_energy() -> Double {
  block_energy(player.val.unwrap())
}

///|
fn scheduler_left_sample(index : Int32) -> Double {
  player.val.unwrap().left.get(index)
}

///|
fn player_play() -> Int32 {
  command(owner => owner.play())
}

///|
fn player_pause() -> Int32 {
  command(owner => owner.pause())
}

///|
fn set_scheduler_bpm(bpm : Double) -> Int32 {
  command(owner => owner.set_tempo(bpm))
}

///|
fn player_state() -> Int32 {
  match player.val.unwrap().state() {
    Empty => 0
    Ready => 1
    Playing => 2
    Paused => 3
    Ended => 4
    Fault => 5
  }
}

///|
fn player_mode() -> PlaybackMode {
  player.val.unwrap().mode()
}

///|
fn player_pending_count() -> Int32 {
  player.val.unwrap().view().pending_materials
}

///|
fn scheduler_cycle_position() -> Double {
  player.val.unwrap().cycle_position()
}

///|
fn scheduler_sample_position() -> Double {
  player.val.unwrap().view().sample_position
}

///|
/// The scheduler's own sample clock, in every state.
fn assert_position(position : Int32) -> Unit raise {
  assert_eq(player.val.unwrap().scheduler.sample_counter(), position.to_int64())
}

///|
/// The tempo the scheduler runs at, not the tempo the session reports.
fn assert_tempo(bpm : Double) -> Unit raise {
  assert_eq(player.val.unwrap().scheduler.bpm(), bpm)
}

///|
fn test_song(length~ : Int32, bpm~ : Int32) -> String {
  "song(bpm(\{bpm}),section(\"a\",\{length},note(\"60\")),part(\"a1\",\"a\"))"
}
