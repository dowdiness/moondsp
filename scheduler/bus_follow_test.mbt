///|
/// 60 BPM: 1 cycle = 1 second, 48 kHz, 128-sample blocks.
const BUS_RATE : Double = 48000.0

///|
const BUS_BLOCK : Int = 128

///|
fn bus_id(name : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string("bus-follow:" + name) catch {
    _ => abort("bad id")
  }
}

///|
/// One note held for 2 cycles under `slow(2)`, with `lpf` read from `cutoff`
/// over the first cycle before the stretch.
fn bus_doc(
  cutoff : (Double) -> Double,
) -> @pattern.PatternSnapshot[@pattern.ControlMap] raise {
  @pattern.PatternDoc::merge_control(
    id=bus_id("merge"),
    left=@pattern.PatternDoc::control_atom(
      id=bus_id("note"),
      key="note",
      value=60.0,
    ),
    right=@pattern.PatternDoc::continuous(id=bus_id("lpf"), key="lpf", f=cutoff),
  )
  .slow(id=bus_id("slow"), factor=@pattern.Rational::from_int(2))
  .lower()
}

///|
fn bus_pool(ctx : @moondsp.DspContext) -> @moondsp.BoundVoicePool raise {
  @moondsp.BoundVoicePool(
    @moondsp.AnalyzedGraph::analyze([
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
    ]),
    ctx,
    @moondsp.ControlBindingBuilder().bind(
      key="lpf",
      node_index=1,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
    max_voices=4,
  )
}

///|
/// Per-block brightness (RMS of the first difference, which rises with the
/// lowpass cutoff) of two cycles played through the scheduler.
fn bus_brightness(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> Array[Double] raise {
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let scheduler = @scheduler.PatternScheduler(bpm=60.0, ctx~, instruments=[
    (@scheduler.InstrumentSelector::AllEvents, bus_pool(ctx)),
  ])
  scheduler.queue_pattern_snapshot(snapshot)
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let mut previous = 0.0
  [
    for _ in 0..<(2 * BUS_RATE.to_int() / BUS_BLOCK) => {
      scheduler.render_block(left, right)
      let mut slope = 0.0
      for i in 0..<BUS_BLOCK {
        let step = left.get(i) - previous
        slope += step * step
        previous = left.get(i)
      }
      (slope / BUS_BLOCK.to_double()).sqrt()
    }
  ]
}

///|
/// Brightness over the 0.06 s (22 blocks, about 6.6 saw periods) ending at
/// `seconds`, scaled by 1000.
fn bus_brightness_at(blocks : Array[Double], seconds : Double) -> Double {
  let end_ = (seconds * BUS_RATE / BUS_BLOCK.to_double()).to_int()
  let mut energy = 0.0
  for index in (end_ - 22)..<end_ {
    energy += blocks[index] * blocks[index]
  }
  ((energy / 22.0).sqrt() * 100000.0).round() / 100.0
}

///|
test "a held voice follows a stretched lpf sweep through its bus" {
  let times = [0.25, 0.5, 1.0, 1.5, 1.99]
  let swept = bus_brightness(bus_doc(t => 200.0 + 3800.0 * t))
  // A voice fixed at the sweep's current cutoff: 200 + 1900 * t after slow(2).
  let reference = times.map(t => {
    let cutoff = 200.0 + 1900.0 * t
    bus_brightness_at(bus_brightness(bus_doc(_ => cutoff)), t)
  })
  let unfollowed = bus_brightness(bus_doc(_ => 200.0))
  let row = (values : Array[Double]) => values.map(v => v.to_string()).join(" ")
  inspect(
    [
      "swept     " + row(times.map(t => bus_brightness_at(swept, t))),
      "reference " + row(reference),
      "constant  " + row(times.map(t => bus_brightness_at(unfollowed, t))),
    ].join("\n"),
    content=(
      #|swept     11.33 14.3 19.72 23.87 27.27
      #|reference 11.95 14.73 20.03 24.12 27.47
      #|constant  5.81 5.53 5.52 5.53 5.53
    ),
  )
}
