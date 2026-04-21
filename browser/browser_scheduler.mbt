///|
/// Active pattern parsed from mini-notation text.
let sched_active_pattern : @ref.Ref[@pattern.Pat[@pattern.ControlMap]?] = @ref.new(
  None,
)

///|
/// Per-sound pool state: voice pool + scheduler + tmp buffers.
struct SoundPool {
  pool : @moondsp.VoicePool
  scheduler : @scheduler.PatternScheduler
  tmp_left : @moondsp.AudioBuffer
  tmp_right : @moondsp.AudioBuffer
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
let sched_left : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_right : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let sched_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
fn bd_template() -> Array[@moondsp.DspNode] {
  // Kick drum: pitch sweep 240→60 Hz + amplitude envelope
  // [0] pitch ADSR: fast decay creates frequency sweep
  // [1] scale pitch envelope by 180 Hz range
  // [2] base frequency 60 Hz
  // [3] mix = 60 + env*180 → frequency sweeps 240→60
  // [4] FM sine oscillator reading frequency from mix
  // [5] amplitude ADSR
  // [6] envelope_gain: signal * amp envelope
  // [7] output
  [
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=40.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::gain(0, 180.0),
    @moondsp.DspNode::constant(60.0),
    @moondsp.DspNode::mix(1, 2),
    @moondsp.DspNode::oscillator_from(3, @moondsp.Waveform::Sine),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=120.0,
      sustain=0.0,
      release_ms=80.0,
    ),
    @moondsp.DspNode::envelope_gain(4, 5, 1.0),
    @moondsp.DspNode::output(6),
  ]
}

///|
fn sd_template() -> Array[@moondsp.DspNode] {
  // Snare: bandpass noise + sine body, amplitude envelope
  // [0] noise source
  // [1] bandpass filter at 1.5 kHz (snare body)
  // [2] sine at 180 Hz (tonal body)
  // [3] mix noise + sine layers
  // [4] amplitude ADSR
  // [5] envelope_gain: signal * envelope
  // [6] output
  [
    @moondsp.DspNode::noise(12345U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::BandPass,
      cutoff_hz=1500.0,
      q=1.5,
    ),
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 180.0),
    @moondsp.DspNode::mix(1, 2),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=60.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::envelope_gain(3, 4, 1.0),
    @moondsp.DspNode::output(5),
  ]
}

///|
fn hh_template() -> Array[@moondsp.DspNode] {
  // Hi-hat: high-pass filtered noise, short envelope
  // [0] noise source
  // [1] high-pass filter at 7 kHz
  // [2] amplitude ADSR (very short)
  // [3] envelope_gain: signal * envelope
  // [4] output
  [
    @moondsp.DspNode::noise(67890U),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::HighPass,
      cutoff_hz=7000.0,
      q=1.5,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=25.0,
      sustain=0.0,
      release_ms=15.0,
    ),
    @moondsp.DspNode::envelope_gain(1, 2, 0.6),
    @moondsp.DspNode::output(3),
  ]
}

///|
fn synth_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=10.0,
      decay_ms=100.0,
      sustain=0.7,
      release_ms=300.0,
    ),
    @moondsp.DspNode::envelope_gain(0, 1, 1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
/// Create a SoundPool for a drum template (no control bindings needed).
fn make_drum_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
  block_size : Int,
) -> SoundPool? {
  match @moondsp.VoicePool::new(template, ctx, max_voices=4) {
    None => None
    Some(pool) => {
      let bindings_result = @moondsp.ControlBindingBuilder::new().build(
        @moondsp.CompiledTemplate::analyze(template),
      )
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
            tmp_left: @moondsp.AudioBuffer::filled(block_size),
            tmp_right: @moondsp.AudioBuffer::filled(block_size),
          })
        }
      }
    }
  }
}

///|
/// Create a SoundPool for the synth template (with note->freq binding).
fn make_synth_pool(ctx : @moondsp.DspContext, block_size : Int) -> SoundPool? {
  let template = synth_template()
  match @moondsp.VoicePool::new(template, ctx, max_voices=8) {
    None => None
    Some(pool) => {
      let bindings_result = @moondsp.ControlBindingBuilder::new()
        .bind(key="note", node_index=0, slot=@moondsp.GraphParamSlot::Value0)
        .build(@moondsp.CompiledTemplate::analyze(template))
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
            tmp_left: @moondsp.AudioBuffer::filled(block_size),
            tmp_right: @moondsp.AudioBuffer::filled(block_size),
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
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size~)
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
  sched_left.val = Some(@moondsp.AudioBuffer::filled(block_size))
  sched_right.val = Some(@moondsp.AudioBuffer::filled(block_size))
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
/// Process one sub-pattern through its sound pool, accumulating into main buffers.
fn process_sub_pool(
  sp : SoundPool,
  sub_pat : @pattern.Pat[@pattern.ControlMap],
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
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
  // Route drum events to their pools, note events to synth
  match sched_bd.val {
    Some(sp) => {
      let sub = pat.filter_map(fn(cm) {
        match cm.0.get("sound") {
          Some(v) => if v == 36.0 { Some(cm) } else { None }
          _ => None
        }
      })
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  match sched_sd.val {
    Some(sp) => {
      let sub = pat.filter_map(fn(cm) {
        match cm.0.get("sound") {
          Some(v) => if v == 38.0 { Some(cm) } else { None }
          _ => None
        }
      })
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  match sched_hh.val {
    Some(sp) => {
      let sub = pat.filter_map(fn(cm) {
        match cm.0.get("sound") {
          Some(v) => if v == 42.0 { Some(cm) } else { None }
          _ => None
        }
      })
      process_sub_pool(sp, sub, left, right)
    }
    None => ()
  }
  match sched_synth.val {
    Some(sp) => {
      let sub = pat.filter_map(fn(cm) {
        match cm.0.get("note") {
          Some(_) => Some(cm)
          _ => None
        }
      })
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
    buf.write_char(c.unsafe_to_char())
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
