///|
/// Active pattern parsed from mini-notation text.
let sched_active_pattern : @ref.Ref[@pattern.Pat[@pattern.ControlMap]?] = @ref.new(
  None,
)

///|
/// Per-sound pool state: voice pool + scheduler + tmp buffers.
struct SoundPool {
  pool : @lib.VoicePool
  scheduler : @scheduler.PatternScheduler
  tmp_left : @lib.AudioBuffer
  tmp_right : @lib.AudioBuffer
}

///|
let sched_bd : @ref.Ref[SoundPool?] = @ref.new(None)

///|
let sched_sd : @ref.Ref[SoundPool?] = @ref.new(None)

///|
let sched_hh : @ref.Ref[SoundPool?] = @ref.new(None)

///|
let sched_synth : @ref.Ref[SoundPool?] = @ref.new(None)

///|
let sched_left : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let sched_right : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let sched_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
fn bd_template() -> Array[@lib.DspNode] {
  // [0] osc → [1] adsr (envelope) → [2] gain(input=0) → [3] output(input=2)
  // ADSR is standalone; gain reads from oscillator, not ADSR
  [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 60.0),
    @lib.DspNode::adsr(0.001, 0.15, 0.0, 0.1),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
}

///|
fn sd_template() -> Array[@lib.DspNode] {
  // [0] noise → [1] biquad(input=0) → [2] adsr (envelope) → [3] gain(input=1) → [4] output(input=3)
  // ADSR is standalone; gain reads from biquad, not ADSR
  [
    @lib.DspNode::noise(12345U),
    @lib.DspNode::biquad(0, @lib.BiquadMode::BandPass, 800.0, 2.0),
    @lib.DspNode::adsr(0.001, 0.08, 0.0, 0.05),
    @lib.DspNode::gain(1, 1.0),
    @lib.DspNode::output(3),
  ]
}

///|
fn hh_template() -> Array[@lib.DspNode] {
  // [0] noise → [1] biquad(input=0) → [2] adsr (envelope) → [3] gain(input=1) → [4] output(input=3)
  // ADSR is standalone; gain reads from biquad, not ADSR
  [
    @lib.DspNode::noise(67890U),
    @lib.DspNode::biquad(0, @lib.BiquadMode::HighPass, 8000.0, 1.0),
    @lib.DspNode::adsr(0.001, 0.03, 0.0, 0.02),
    @lib.DspNode::gain(1, 1.0),
    @lib.DspNode::output(3),
  ]
}

///|
fn synth_template() -> Array[@lib.DspNode] {
  // Same pattern as old sched_template: osc(0), adsr(1), gain(input=0), output(input=2)
  [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
}

///|
/// Create a SoundPool for a drum template (no control bindings needed).
fn make_drum_pool(
  template : Array[@lib.DspNode],
  ctx : @lib.DspContext,
  block_size : Int,
) -> SoundPool? {
  match @lib.VoicePool::new(template, ctx, max_voices=4) {
    None => None
    Some(pool) => {
      let bindings_result = @lib.ControlBindingBuilder::new().build(template)
      match bindings_result {
        Err(_) => None
        Ok(bindings) => {
          let scheduler = @scheduler.PatternScheduler::new(
            bpm=120.0,
            bindings~,
            ctx~,
          )
          Some({
            pool,
            scheduler,
            tmp_left: @lib.AudioBuffer::filled(block_size),
            tmp_right: @lib.AudioBuffer::filled(block_size),
          })
        }
      }
    }
  }
}

///|
/// Create a SoundPool for the synth template (with note->freq binding).
fn make_synth_pool(ctx : @lib.DspContext, block_size : Int) -> SoundPool? {
  let template = synth_template()
  match @lib.VoicePool::new(template, ctx, max_voices=8) {
    None => None
    Some(pool) => {
      let bindings_result = @lib.ControlBindingBuilder::new()
        .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
        .build(template)
      match bindings_result {
        Err(_) => None
        Ok(bindings) => {
          let scheduler = @scheduler.PatternScheduler::new(
            bpm=120.0,
            bindings~,
            ctx~,
          )
          Some({
            pool,
            scheduler,
            tmp_left: @lib.AudioBuffer::filled(block_size),
            tmp_right: @lib.AudioBuffer::filled(block_size),
          })
        }
      }
    }
  }
}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_graph()
    return false
  }
  let ctx = @lib.DspContext::new(sample_rate, block_size)
  let bd = make_drum_pool(bd_template(), ctx, block_size)
  let sd = make_drum_pool(sd_template(), ctx, block_size)
  let hh = make_drum_pool(hh_template(), ctx, block_size)
  let synth = make_synth_pool(ctx, block_size)
  guard bd is Some(_) && sd is Some(_) && hh is Some(_) && synth is Some(_) else {
    reset_scheduler_graph()
    return false
  }
  sched_bd.val = bd
  sched_sd.val = sd
  sched_hh.val = hh
  sched_synth.val = synth
  sched_left.val = Some(@lib.AudioBuffer::filled(block_size))
  sched_right.val = Some(@lib.AudioBuffer::filled(block_size))
  sched_gain.val = 0.3
  sched_active_pattern.val = None
  true
}

///|
fn reset_scheduler_graph() -> Unit {
  sched_bd.val = None
  sched_sd.val = None
  sched_hh.val = None
  sched_synth.val = None
  sched_left.val = None
  sched_right.val = None
  sched_gain.val = 0.3
  sched_active_pattern.val = None
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  checked_sample(index, sched_left.val)
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  checked_sample(index, sched_right.val)
}

///|
/// Keep events where "sound" key matches a specific MIDI number.
fn keep_sound(midi : Double) -> (@pattern.ControlMap) -> @pattern.ControlMap? {
  fn(cm) {
    match cm.0.get("sound") {
      Some(v) => if v == midi { Some(cm) } else { None }
      _ => None
    }
  }
}

///|
/// Keep events that have a "note" key.
fn keep_note(cm : @pattern.ControlMap) -> @pattern.ControlMap? {
  match cm.0.get("note") {
    Some(_) => Some(cm)
    _ => None
  }
}

///|
/// Process one sub-pattern through its sound pool, accumulating into main buffers.
fn process_sub_pool(
  sp : SoundPool,
  sub_pat : @pattern.Pat[@pattern.ControlMap],
  left : @lib.AudioBuffer,
  right : @lib.AudioBuffer,
) -> Unit {
  sp.tmp_left.fill(0.0)
  sp.tmp_right.fill(0.0)
  sp.scheduler.process_block(sub_pat, sp.pool, sp.tmp_left, sp.tmp_right)
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) + sp.tmp_left.get(i))
    right.set(i, right.get(i) + sp.tmp_right.get(i))
  }
}

///|
pub fn process_scheduler_block() -> Bool {
  let left = match sched_left.val {
    Some(b) => b
    None => return false
  }
  let right = match sched_right.val {
    Some(b) => b
    None => return false
  }
  // Clear main output buffers
  left.fill(0.0)
  right.fill(0.0)
  // Get active pattern; if none set, output silence
  let pat = match sched_active_pattern.val {
    Some(p) => p
    None => return true
  }
  // Process each drum pool with filtered sub-pattern
  // BD = MIDI 36, SD = MIDI 38, HH = MIDI 42
  match sched_bd.val {
    Some(sp) => {
      let sub = pat.filter_map(keep_sound(36.0))
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  match sched_sd.val {
    Some(sp) => {
      let sub = pat.filter_map(keep_sound(38.0))
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  match sched_hh.val {
    Some(sp) => {
      let sub = pat.filter_map(keep_sound(42.0))
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  // Synth pool gets events with "note" key
  match sched_synth.val {
    Some(sp) => {
      let sub = pat.filter_map(keep_note)
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  // Apply master gain
  let gain = sched_gain.val
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) * gain)
    right.set(i, right.get(i) * gain)
  }
  true
}

///|
let sched_last_error : @ref.Ref[String] = @ref.new("")

///|
let sched_input_chars : Array[Int] = []

///|
pub fn clear_pattern_input() -> Unit {
  sched_input_chars.clear()
}

///|
pub fn push_pattern_char(code : Int) -> Unit {
  sched_input_chars.push(code)
}

///|
pub fn eval_pattern_input() -> Int {
  let buf = StringBuilder::new()
  for c in sched_input_chars {
    buf.write_char(Char::from_int(c))
  }
  let text = buf.to_string()
  sched_input_chars.clear()
  match @mini.parse(text) {
    Ok(pat) => {
      sched_active_pattern.val = Some(pat)
      sched_last_error.val = ""
      0
    }
    Err(msg) => {
      sched_last_error.val = msg
      1
    }
  }
}

///|
pub fn parse_and_set_pattern(text : String) -> Int {
  match @mini.parse(text) {
    Ok(pat) => {
      sched_active_pattern.val = Some(pat)
      sched_last_error.val = ""
      0
    }
    Err(msg) => {
      sched_last_error.val = msg
      1
    }
  }
}

///|
pub fn get_scheduler_parse_error() -> String {
  sched_last_error.val
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  match sched_bd.val {
    Some(sp) => sp.scheduler.set_bpm(bpm)
    None => ()
  }
  match sched_sd.val {
    Some(sp) => sp.scheduler.set_bpm(bpm)
    None => ()
  }
  match sched_hh.val {
    Some(sp) => sp.scheduler.set_bpm(bpm)
    None => ()
  }
  match sched_synth.val {
    Some(sp) => sp.scheduler.set_bpm(bpm)
    None => ()
  }
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  sched_gain.val = if gain < 0.0 {
    0.0
  } else if gain > 1.0 {
    1.0
  } else {
    gain
  }
}
