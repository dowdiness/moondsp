///|
/// Run `command` on the player and record its diagnostic. Returns 0 on
/// success, 2 when the song layout changed and needs a restart, otherwise 1.
fn player_command(
  command : (@player.Player) -> Unit raise @player.PlayerError,
) -> Int32 {
  guard player.val is Some(owner) else {
    return set_scheduler_parse_error("Player is not initialized")
  }
  command(owner) catch {
    error => {
      ignore(set_scheduler_parse_error(error.message()))
      return if error is RestartRequired { 2 } else { 1 }
    }
  }
  set_scheduler_parse_success()
}

///|
fn take_playback_input() -> Result[@mini.PlaybackInput, String] {
  let result = if playback_input_overflow.val {
    Err("playback input exceeds 2097152 UTF-16 code units")
  } else {
    match input_chars_to_string(playback_input_chars) {
      Err(message) => Err(message)
      Ok(wire) => @mini.PlaybackInput::decode_wire(wire)
    }
  }
  playback_input_chars.clear()
  playback_input_overflow.val = false
  result
}

///|
pub fn player_update_input() -> Int32 {
  match take_playback_input() {
    Err(message) => set_scheduler_parse_error(message)
    Ok(input) => player_accept(input, restart=false)
  }
}

///|
pub fn player_restart_input() -> Int32 {
  match take_playback_input() {
    Err(message) => set_scheduler_parse_error(message)
    Ok(input) => player_accept(input, restart=true)
  }
}

///|
/// Compile `input` for the player, then accept it by update or restart. A
/// score the player cannot compile changes nothing and returns 1.
fn player_accept(input : @mini.PlaybackInput, restart~ : Bool) -> Int32 {
  guard player.val is Some(owner) else {
    return set_scheduler_parse_error("Player is not initialized")
  }
  let score = owner.compile(input) catch {
    error => return set_scheduler_parse_error(error.message())
  }
  player_command(owner => {
    if restart {
      owner.restart(score)
    } else {
      owner.update(score)
    }
  })
}

///|
pub fn player_play() -> Int32 {
  player_command(owner => owner.play())
}

///|
pub fn player_pause() -> Int32 {
  player_command(owner => owner.pause())
}

///|
pub fn player_state() -> Int32 {
  match player.val {
    None => 0
    Some(owner) =>
      match owner.state() {
        Empty => 0
        Ready => 1
        Playing => 2
        Paused => 3
        Ended => 4
        Fault => 5
      }
  }
}

///|
pub fn player_mode() -> @player.ScoreKind? {
  match player.val {
    Some(owner) => owner.mode()
    None => None
  }
}

///|
pub fn scheduler_cycle_position() -> Double {
  match player.val {
    Some(owner) => owner.cycle_position()
    None => 0.0
  }
}

///|
pub fn player_pending_count() -> Int32 {
  match player.val {
    Some(owner) => owner.pending_materials()
    None => 0
  }
}

///|
pub fn player_skipped_count() -> Int32 {
  match player.val {
    Some(owner) => owner.skipped_materials()
    None => 0
  }
}

///|
pub fn scheduler_bpm() -> Double {
  match player.val {
    Some(owner) => owner.bpm()
    None => 0.0
  }
}

///|
pub fn scheduler_sample_position() -> Double {
  match player.val {
    Some(owner) => owner.sample_position()
    None => 0.0
  }
}

///|
pub fn player_onset_enable(enabled : Int32) -> Unit {
  if player.val is Some(owner) {
    owner.onsets().enable(enabled == 1)
  }
}

///|
pub fn player_onset_count() -> Int32 {
  match player.val {
    Some(owner) => owner.onsets().count()
    None => 0
  }
}

///|
/// Read the shared bounded ring; no array or binding path is copied.
pub fn player_onset_field(index : Int32, field : Int32) -> Double {
  guard index >= 0 else { return 0.0 }
  match player.val {
    None => 0.0
    Some(owner) => owner.onsets().field(index, field)
  }
}

///|
pub fn player_onset_clear() -> Unit {
  if player.val is Some(owner) {
    owner.onsets().clear()
  }
}

///|
pub fn player_onset_dropped() -> Double {
  match player.val {
    Some(owner) => owner.onsets().dropped()
    None => 0.0
  }
}

///|
pub fn player_signal_enable(enabled : Int32) -> Unit {
  if player.val is Some(owner) {
    owner.signals().enable(enabled == 1)
  }
}

///|
pub fn player_signal_count() -> Int32 {
  match player.val {
    Some(owner) => owner.signals().count()
    None => 0
  }
}

///|
/// Read one scalar field of the bounded signal-value ring.
pub fn player_signal_field(index : Int32, field : Int32) -> Double {
  match player.val {
    None => 0.0
    Some(owner) => owner.signals().field(index, field)
  }
}

///|
pub fn player_signal_clear() -> Unit {
  if player.val is Some(owner) {
    owner.signals().clear()
  }
}

///|
pub fn player_signal_dropped() -> Double {
  match player.val {
    Some(owner) => owner.signals().dropped()
    None => 0.0
  }
}
