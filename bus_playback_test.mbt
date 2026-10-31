///|
/// PROTOTYPE: thinnest playback path for automatic control buses.
///
/// Drives a real `BoundVoicePool` block by block: onsets start voices with the
/// event's values, and each sounding voice reads its bus once per block and
/// receives the value through `apply_voice_param_bool` only when it changed.
/// 1 cycle = 1 second, 48 kHz, 128-sample blocks.
const BUS_RATE : Double = 48000.0

///|
const BUS_BLOCK : Int32 = 128

///|
fn bus_play_id(name : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string("bus-play:" + name) catch {
    _ => abort("bad id")
  }
}

///|
/// `lpf` rises linearly from 200 Hz to 4000 Hz over each cycle.
fn bus_play_doc() -> @pattern.PatternDoc[@pattern.ControlMap] raise {
  let sweep = @pattern.PatternDoc::continuous(
    id=bus_play_id("sweep"),
    key="lpf",
    f=t => 200.0 + 3800.0 * t,
  )
  // One note held for 2 cycles; the outer slow(2) must stretch the sweep too.
  @pattern.PatternDoc::merge_control(
    id=bus_play_id("merge"),
    left=@pattern.PatternDoc::from_pattern(
      id=bus_play_id("note"),
      pat=@pattern.note(60.0),
    ),
    right=sweep,
  ).slow(id=bus_play_id("slow"), factor=@pattern.Rational::from_int(2))
}

///|
fn bus_play_pool(ctx : @moondsp.DspContext) -> @moondsp.BoundVoicePool {
  let template = [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Saw, 110.0),
    @moondsp.DspNode::biquad(
      input=0,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=8000.0,
      q=0.707,
    ),
    @moondsp.DspNode::adsr(
      attack_ms=5.0,
      decay_ms=10.0,
      sustain=1.0,
      release_ms=50.0,
    ),
    @moondsp.DspNode::envelope_gain(input=1, envelope=2, amount=1.0),
    @moondsp.DspNode::output(3),
  ]
  @moondsp.BoundVoicePool(
    @moondsp.AnalyzedGraph::analyze(template),
    ctx,
    @moondsp.ControlBindingBuilder().bind(
      key="lpf",
      node_index=1,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
    max_voices=4,
  ) catch {
    _ => abort("pool")
  }
}

///|
priv struct BusPlayback {
  block_rms : Array[Double]
  /// RMS of the first difference: rises with the lowpass cutoff.
  block_brightness : Array[Double]
  note_ons : Int32
  param_sends : Int32
  bus_evaluations : Int32
  /// Largest sample-to-sample jump at block boundaries / inside blocks.
  boundary_step : Double
  interior_step : Double
}

///|
fn bus_play(follow~ : Bool, fixed? : Double) -> BusPlayback raise {
  let snapshot = bus_play_doc().lower_with_buses()
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let pool = bus_play_pool(ctx)
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  // (handle, bus, last sent value)
  let sounding : Array[(@moondsp.VoiceHandle, Int, Ref[Double])] = []
  // Preallocated: every bus is evaluated once per block into this array.
  let bus_values = Array::make(snapshot.bus_count(), 0.0)
  let block_rms = []
  let block_brightness = []
  let mut note_ons = 0
  let mut param_sends = 0
  let mut bus_evaluations = 0
  let mut boundary_step = 0.0
  let mut interior_step = 0.0
  let mut previous = 0.0
  let blocks = 2 * BUS_RATE.to_int() / BUS_BLOCK
  for n in 0..<blocks {
    let arc = @pattern.TimeSpan(
      @pattern.Rational(Int64::from_int(n * BUS_BLOCK), 48000L),
      @pattern.Rational(Int64::from_int((n + 1) * BUS_BLOCK), 48000L),
    )
    for event in snapshot.query(arc) {
      guard event.whole is Some(whole) && arc.contains(whole.begin) else {
        continue
      }
      let controls = Map([])
      event.value.controls().each((key, value) => controls[key] = value)
      if fixed is Some(cutoff) {
        controls["lpf"] = cutoff
      }
      guard pool.note_on_controls(controls) is Some(handle) else {
        fail("note_on")
      }
      note_ons += 1
      if event.value.bus_for("lpf") is Some(bus) {
        sounding.push((handle, bus, Ref(controls["lpf"])))
      }
    }
    if follow {
      snapshot.evaluate_all(arc.begin, bus_values)
      bus_evaluations += bus_values.length()
      for voice in sounding {
        let value = bus_values[voice.1]
        if !value.is_nan() && value != voice.2.val {
          voice.2.val = value
          param_sends += 1
          guard pool.apply_voice_param_bool(
            voice.0,
            1,
            @moondsp.GraphParamSlot::Value0,
            value,
          ) else {
            fail("apply_voice_param_bool rejected \{value}")
          }
        }
      }
    }
    left.fill(0.0)
    right.fill(0.0)
    pool.process(ctx, left, right)
    let mut energy = 0.0
    let mut slope = 0.0
    for i in 0..<BUS_BLOCK {
      let sample = left.get(i)
      energy += sample * sample
      let step = (sample - previous).abs()
      slope += step * step
      if i == 0 {
        if step > boundary_step {
          boundary_step = step
        }
      } else if step > interior_step {
        interior_step = step
      }
      previous = sample
    }
    block_rms.push((energy / BUS_BLOCK.to_double()).sqrt())
    block_brightness.push((slope / BUS_BLOCK.to_double()).sqrt())
  }
  {
    block_rms,
    block_brightness,
    note_ons,
    param_sends,
    bus_evaluations,
    boundary_step,
    interior_step,
  }
}

///|
/// Brightness over the 0.06 s (22 blocks, about 6.6 saw periods) ending at
/// `seconds`, scaled by 1000.
fn bus_rms_at(play : BusPlayback, seconds : Double) -> Double {
  let end_ = (seconds * BUS_RATE / BUS_BLOCK.to_double()).to_int()
  let mut energy = 0.0
  for index in (end_ - 22)..<end_ {
    energy += play.block_brightness[index] * play.block_brightness[index]
  }
  ((energy / 22.0).sqrt() * 100000.0).round() / 100.0
}

///|
test "held voice follows a stretched lpf sweep through its bus" {
  let bus = bus_play(follow=true)
  let times = [0.25, 0.5, 1.0, 1.5, 1.99]
  // The swept voice must sound like a voice fixed at the sweep's current
  // cutoff: 200 + 1900 * t after slow(2).
  let swept = times.map(t => bus_rms_at(bus, t))
  let reference = times.map(t => {
    bus_rms_at(bus_play(follow=false, fixed=200.0 + 1900.0 * t), t)
  })
  let unfollowed = times.map(t => bus_rms_at(bus_play(follow=false), t))
  let report = [
    "swept     brightness " + swept.map(v => v.to_string()).join(" "),
    "reference brightness " + reference.map(v => v.to_string()).join(" "),
    "no bus    brightness " + unfollowed.map(v => v.to_string()).join(" "),
    "note_ons=\{bus.note_ons} param_sends=\{bus.param_sends} bus_evaluations=\{bus.bus_evaluations}",
    "max step: boundary=\{(bus.boundary_step * 1000.0).round() / 1000.0} interior=\{(bus.interior_step * 1000.0).round() / 1000.0}",
  ]
  let held = bus.block_rms[10:bus.block_rms.length()]
  @debug.assert_eq(bus.note_ons, 1)
  @debug.assert_eq(held.iter().all(rms => rms > 0.01), true)
  inspect(
    report.join("\n"),
    content=(
      #|swept     brightness 11.33 14.3 19.72 23.87 27.27
      #|reference brightness 11.95 14.73 20.03 24.12 27.47
      #|no bus    brightness 5.81 5.53 5.52 5.53 5.53
      #|note_ons=1 param_sends=749 bus_evaluations=750
      #|max step: boundary=0.192 interior=0.325
    ),
  )
}
