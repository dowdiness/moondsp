///|
/// The browser's one player, made by `init_scheduler_graph_with_sounds`.
let player : @ref.Ref[@player.Player?] = Ref(None)

///|
/// The block the player last rendered, which the Worklet reads sample by
/// sample. Empty while there is no player.
let output_left : @ref.Ref[@moondsp.AudioBuffer] = Ref(
  @moondsp.AudioBuffer::filled(0),
)

///|
let output_right : @ref.Ref[@moondsp.AudioBuffer] = Ref(
  @moondsp.AudioBuffer::filled(0),
)

///|
/// Give every drum and instrument a voice pool, built from `drum` and
/// `instrument`, and the samples one pool, built from `sampler`. Pools read
/// samples from the store `init_sample_store` made, if it made one.
pub fn init_scheduler_graph_with_sounds(
  sample_rate : Double,
  block_size : Int32,
  drum~ : (@score.Drum) -> Array[@moondsp.DspNode],
  instrument~ : (@score.Instrument) -> @player.NoteVoice,
  sampler~ : @player.SamplerVoice,
) -> Bool {
  // The scheduler and its voice pools refuse any format they cannot run.
  let ctx = sample_context(sample_rate, block_size)
  let sounds : @player.Sounds = {
    drum: d => @moondsp.AnalyzedGraph::analyze(drum(d)),
    instrument,
    sampler,
  }
  let owner = @player.Player(ctx, sounds) catch {
    _ => {
      reset_scheduler_graph()
      return false
    }
  }
  player.val = Some(owner)
  output_left.val = @moondsp.AudioBuffer::filled(block_size)
  output_right.val = @moondsp.AudioBuffer::filled(block_size)
  playback_input_chars.clear()
  true
}

///|
pub fn reset_scheduler_graph() -> Unit {
  player.val = None
  output_left.val = @moondsp.AudioBuffer::filled(0)
  output_right.val = @moondsp.AudioBuffer::filled(0)
  playback_input_chars.clear()
}

///|
fn checked_sample(index : Int32, buffer : @moondsp.AudioBuffer) -> Double {
  guard index >= 0 && index < buffer.length() else { return 0.0 }
  buffer.get(index)
}

///|
pub fn scheduler_left_sample(index : Int32) -> Double {
  checked_sample(index, output_left.val)
}

///|
pub fn scheduler_right_sample(index : Int32) -> Double {
  checked_sample(index, output_right.val)
}

///|
pub fn process_scheduler_block() -> Bool {
  guard player.val is Some(owner) else {
    ignore(set_scheduler_parse_error("Player is not initialized"))
    return false
  }
  match owner.process(output_left.val, output_right.val) {
    None => true
    Some(error) => {
      ignore(set_scheduler_parse_error(error.message()))
      false
    }
  }
}

///|
const SCHEDULER_PARSE_STATUS_OK : Int32 = 0

///|
const SCHEDULER_PARSE_STATUS_ERROR : Int32 = 1

///|
let sched_last_error : @ref.Ref[String] = Ref("")

///|
fn set_scheduler_parse_success() -> Int32 {
  sched_last_error.val = ""
  SCHEDULER_PARSE_STATUS_OK
}

///|
fn set_scheduler_parse_error(message : String) -> Int32 {
  sched_last_error.val = message
  SCHEDULER_PARSE_STATUS_ERROR
}

///|
const MAX_PLAYBACK_INPUT_CODE_UNITS : Int32 = 2097152

///|
let playback_input_chars : Array[Int32] = []

///|
let playback_input_overflow : @ref.Ref[Bool] = Ref(false)

///|
fn input_chars_to_string(chars : Array[Int32]) -> Result[String, String] {
  let buf = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let code = chars[i]
    guard code >= 0 && code <= 0xffff else {
      return Err("invalid UTF-16 code unit")
    }
    if code >= 0xd800 && code <= 0xdbff {
      guard i + 1 < chars.length() else {
        return Err("invalid UTF-16 surrogate pair")
      }
      let next = chars[i + 1]
      guard next >= 0xdc00 && next <= 0xdfff else {
        return Err("invalid UTF-16 surrogate pair")
      }
      buf.write_char(code.unsafe_to_char())
      buf.write_char(next.unsafe_to_char())
      i += 2
    } else {
      guard code < 0xdc00 || code > 0xdfff else {
        return Err("invalid UTF-16 surrogate pair")
      }
      buf.write_char(code.unsafe_to_char())
      i += 1
    }
  }
  Ok(buf.to_string())
}

///|
pub fn clear_playback_input() -> Unit {
  playback_input_chars.clear()
  playback_input_overflow.val = false
}

///|
pub fn push_playback_char(code : Int32) -> Unit {
  if code < 0 ||
    code > 0xffff ||
    playback_input_chars.length() >= MAX_PLAYBACK_INPUT_CODE_UNITS {
    playback_input_overflow.val = true
  } else {
    playback_input_chars.push(code)
  }
}

///|
pub fn get_playback_error() -> String {
  sched_last_error.val
}

///|
pub fn get_playback_error_length() -> Int32 {
  sched_last_error.val.length()
}

///|
pub fn get_playback_error_char(i : Int32) -> Int32 {
  let s = sched_last_error.val
  if i < 0 || i >= s.length() {
    0
  } else {
    s[i].to_int()
  }
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Int32 {
  guard player.val is Some(owner) else {
    return set_scheduler_parse_error("Player is not initialized")
  }
  let tempo = @player.Tempo(bpm) catch {
    error => return set_scheduler_parse_error(error.message())
  }
  owner.set_tempo(tempo) catch {
    error => return set_scheduler_parse_error(error.message())
  }
  set_scheduler_parse_success()
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  if player.val is Some(owner) {
    owner.set_gain(gain)
  }
}
