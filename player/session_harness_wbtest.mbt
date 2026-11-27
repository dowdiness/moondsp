// Helpers that call a test player directly and return what it raised, so the
// tests assert on the player's states and errors.

///|
/// The block the last `render_blocks` rendered.
let out_left : @moondsp.AudioBuffer = @moondsp.AudioBuffer::filled(128)

///|
let out_right : @moondsp.AudioBuffer = @moondsp.AudioBuffer::filled(128)

///|
fn render_blocks(player : Player, count : Int32) -> Unit raise {
  for _ in 0..<count {
    guard player.process(out_left, out_right) is None else {
      fail("expected a rendered block")
    }
  }
}

///|
/// Energy of the left channel of the last rendered block.
fn output_energy() -> Double {
  let mut energy = 0.0
  for i in 0..<out_left.length() {
    energy += out_left.get(i).abs()
  }
  energy
}

///|
/// What `f` raised, if it raised.
fn raised(f : () -> Unit raise) -> Error? {
  try {
    f()
    None
  } catch {
    error => Some(error)
  }
}

///|
/// Compile untracked `text`, as the host's `kind: "text"` wire sends it, and
/// accept it by restart or update.
fn submit(player : Player, text : String, restart~ : Bool = true) -> Error? {
  raised(() => {
    let score = player.compile(@mini.PlaybackInput::text(text))
    compiled[text] = score
    if restart {
      player.restart(score)
    } else {
      player.update(score)
    }
  })
}

///|
/// The score each text compiled to last, so a test can tell which one the
/// player holds.
let compiled : Map[String, Score] = Map([])

///|
/// The player holds the score `text` compiled to last.
fn assert_accepted(player : Player, text : String) -> Unit raise {
  guard player.session.score() is Some(accepted) &&
    compiled.get(text) is Some(score) &&
    physical_equal(accepted, score) else {
    fail("expected the accepted score to be \{text}")
  }
}

///|
fn play(player : Player) -> Error? {
  raised(() => player.play())
}

///|
fn pause(player : Player) -> Error? {
  raised(() => player.pause())
}

///|
fn set_tempo(player : Player, bpm : Double) -> Error? {
  raised(() => player.set_tempo(tempo(bpm)))
}

///|
/// The player refused, for any reason but a layout that needs a restart.
fn assert_rejected(error : Error?) -> Unit raise {
  guard error is Some(error) && !(error is RestartRequired) else {
    fail("expected a refusal other than RestartRequired")
  }
}

///|
/// The scheduler's own sample clock, in every state.
fn assert_position(player : Player, position : Int32) -> Unit raise {
  assert_eq(player.scheduler.sample_counter(), position.to_int64())
}

///|
/// The tempo the scheduler runs at, not the tempo the session reports.
fn assert_tempo(player : Player, bpm : Double) -> Unit raise {
  assert_eq(player.scheduler.bpm(), bpm)
}

///|
fn test_song(length~ : Int32, bpm~ : Int32) -> String {
  "song(bpm(\{bpm}),section(\"a\",\{length},note(\"60\")),part(\"a1\",\"a\"))"
}
