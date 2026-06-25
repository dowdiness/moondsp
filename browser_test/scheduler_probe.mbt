// Test-only browser synth-shape wrappers for #212. These exports live in
// moonbit_dsp_test.wasm so Playwright can compare the production Triangle
// browser synth shape with an equivalent true-Sine shape without changing
// production browser playback.
//
// The production wasm scheduler probe still drives the real Mini -> scheduler
// path. This browser_test helper intentionally stays behind the repository's
// browser_test boundary by using only the root @moondsp facade; it accepts the
// fixed note pattern used by the Triangle-vs-Sine comparison and renders it
// through BoundVoicePool with the browser synth shape.

///|
const SCHEDULER_PROBE_DEFAULT_GAIN : Double = 0.5

///|
const SCHEDULER_PROBE_SUPPORTED_PATTERN : String = "note(\"60 64 67\")"

///|
const SCHEDULER_PROBE_UNSUPPORTED_PATTERN_ERROR : String = "browser_test scheduler comparison supports note(\"60 64 67\") only"

///|
priv struct SchedulerProbeRuntime {
  context : @moondsp.DspContext
  pool : @moondsp.BoundVoicePool
  left : @moondsp.AudioBuffer
  right : @moondsp.AudioBuffer
}

///|
let scheduler_probe_runtime : @ref.Ref[SchedulerProbeRuntime?] = @ref.new(None)

///|
let scheduler_probe_active_notes : @ref.Ref[Array[Double]?] = @ref.new(None)

///|
let scheduler_probe_voices_started : @ref.Ref[Bool] = @ref.new(false)

///|
let scheduler_probe_gain : @ref.Ref[Double] = @ref.new(
  SCHEDULER_PROBE_DEFAULT_GAIN,
)

///|
let scheduler_probe_pattern_input_chars : Array[Int] = []

///|
let scheduler_probe_last_error : @ref.Ref[String] = @ref.new("")

///|
fn scheduler_probe_synth_template(
  waveform : @moondsp.Waveform,
) -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(waveform, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=2.0,
      decay_ms=800.0,
      sustain=0.08,
      release_ms=20.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=0.5),
    @moondsp.DspNode::biquad(
      input=2,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=8000.0,
      q=0.707,
    ),
    @moondsp.DspNode::output(3),
  ]
}

///|
fn reset_scheduler_probe_graph() -> Unit {
  scheduler_probe_runtime.val = None
  scheduler_probe_active_notes.val = None
  scheduler_probe_voices_started.val = false
  scheduler_probe_gain.val = SCHEDULER_PROBE_DEFAULT_GAIN
  scheduler_probe_pattern_input_chars.clear()
  scheduler_probe_last_error.val = ""
}

///|
fn init_scheduler_probe_graph_with_waveform(
  sample_rate : Double,
  block_size : Int,
  waveform : @moondsp.Waveform,
) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_probe_graph()
    return false
  }
  let ctx = @moondsp.DspContext::new(sample_rate~, block_size~)
  match
    @moondsp.BoundVoicePool::new(
      @moondsp.CompiledTemplate::analyze(
        scheduler_probe_synth_template(waveform),
      ),
      ctx,
      @moondsp.ControlBindingBuilder::new().bind(
        key="note",
        node_index=0,
        slot=@moondsp.GraphParamSlot::Value0,
      ),
      max_voices=24,
    ) {
    Ok(pool) => {
      scheduler_probe_runtime.val = Some({
        context: ctx,
        pool,
        left: @moondsp.AudioBuffer::filled(block_size),
        right: @moondsp.AudioBuffer::filled(block_size),
      })
      scheduler_probe_active_notes.val = None
      scheduler_probe_voices_started.val = false
      scheduler_probe_gain.val = SCHEDULER_PROBE_DEFAULT_GAIN
      scheduler_probe_last_error.val = ""
      true
    }
    Err(_) => {
      reset_scheduler_probe_graph()
      false
    }
  }
}

///|
/// Initialize the test scheduler-compatible wrapper with the same Triangle
/// synth waveform used by production browser playback.
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  init_scheduler_probe_graph_with_waveform(
    sample_rate,
    block_size,
    @moondsp.Waveform::Triangle,
  )
}

///|
/// Initialize the test scheduler-compatible wrapper with a true-Sine synth
/// waveform while keeping the browser synth shape otherwise identical to
/// production.
pub fn init_scheduler_sine_graph(
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  init_scheduler_probe_graph_with_waveform(
    sample_rate,
    block_size,
    @moondsp.Waveform::Sine,
  )
}

///|
fn scheduler_probe_input_chars_to_string(chars : Array[Int]) -> String {
  let buf = StringBuilder::new()
  for c in chars {
    buf.write_char(c.unsafe_to_char())
  }
  buf.to_string()
}

///|
fn scheduler_probe_pattern_notes(text : String) -> Array[Double]? {
  if text == SCHEDULER_PROBE_SUPPORTED_PATTERN {
    // MIDI 60, 64, 67. Use constants to keep this boundary-compatible helper
    // independent of the pattern/mini packages under test by production wasm.
    Some([261.6255653005986, 329.6275569128699, 391.99543598174927])
  } else {
    None
  }
}

///|
fn set_scheduler_probe_pattern_text(text : String) -> Int {
  match scheduler_probe_pattern_notes(text) {
    Some(notes) => {
      match scheduler_probe_runtime.val {
        Some(runtime) => runtime.pool.note_off_all()
        None => ()
      }
      scheduler_probe_active_notes.val = Some(notes)
      scheduler_probe_voices_started.val = false
      scheduler_probe_last_error.val = ""
      0
    }
    None => {
      scheduler_probe_last_error.val = SCHEDULER_PROBE_UNSUPPORTED_PATTERN_ERROR
      1
    }
  }
}

///|
pub fn clear_pattern_input() -> Unit {
  scheduler_probe_pattern_input_chars.clear()
}

///|
pub fn push_pattern_char(code : Int) -> Unit {
  scheduler_probe_pattern_input_chars.push(code)
}

///|
pub fn eval_pattern_input() -> Int {
  let text = scheduler_probe_input_chars_to_string(
    scheduler_probe_pattern_input_chars,
  )
  scheduler_probe_pattern_input_chars.clear()
  set_scheduler_probe_pattern_text(text)
}

///|
fn scheduler_probe_start_notes(
  runtime : SchedulerProbeRuntime,
  notes : Array[Double],
) -> Bool {
  if scheduler_probe_voices_started.val {
    return true
  }
  for freq in notes {
    let controls : Map[String, Double] = { "note": freq }
    if runtime.pool.note_on_controls(controls) is None {
      scheduler_probe_last_error.val = "browser_test scheduler comparison note_on failed"
      return false
    }
  }
  scheduler_probe_voices_started.val = true
  true
}

///|
pub fn process_scheduler_block() -> Bool {
  match scheduler_probe_runtime.val {
    Some(runtime) => {
      match scheduler_probe_active_notes.val {
        Some(notes) => {
          if !scheduler_probe_start_notes(runtime, notes) {
            return false
          }
          runtime.pool.process(runtime.context, runtime.left, runtime.right)
        }
        None => {
          runtime.left.fill(0.0)
          runtime.right.fill(0.0)
        }
      }
      let gain = scheduler_probe_gain.val
      for i in 0..<runtime.left.length() {
        runtime.left.set(i, runtime.left.get(i) * gain)
        runtime.right.set(i, runtime.right.get(i) * gain)
      }
      true
    }
    None => false
  }
}

///|
fn scheduler_probe_checked_sample(
  index : Int,
  buffer : @moondsp.AudioBuffer?,
) -> Double {
  match buffer {
    Some(output) if index >= 0 && index < output.length() => output.get(index)
    _ => 0.0
  }
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  scheduler_probe_checked_sample(
    index,
    match scheduler_probe_runtime.val {
      Some(runtime) => Some(runtime.left)
      None => None
    },
  )
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  scheduler_probe_checked_sample(
    index,
    match scheduler_probe_runtime.val {
      Some(runtime) => Some(runtime.right)
      None => None
    },
  )
}

///|
pub fn get_pattern_error_length() -> Int {
  scheduler_probe_last_error.val.length()
}

///|
pub fn get_pattern_error_char(index : Int) -> Int {
  let message = scheduler_probe_last_error.val
  if index < 0 || index >= message.length() {
    0
  } else {
    message[index].to_int()
  }
}

///|
pub fn get_browser_error_length() -> Int {
  0
}

///|
pub fn get_browser_error_char(_index : Int) -> Int {
  0
}

///|
pub fn set_scheduler_bpm(_bpm : Double) -> Unit {
  ()
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  scheduler_probe_gain.val = if gain.is_nan() || gain.is_inf() {
    SCHEDULER_PROBE_DEFAULT_GAIN
  } else if gain < 0.0 {
    0.0
  } else if gain > 1.0 {
    1.0
  } else {
    gain
  }
}
