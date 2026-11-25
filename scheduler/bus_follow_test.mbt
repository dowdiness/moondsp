///|
/// 48 kHz, 128-sample blocks, 120 BPM: one cycle lasts two seconds.
const BUS_RATE : Double = 48000.0

///|
const BUS_SECONDS_PER_CYCLE : Double = 2.0

///|
const BUS_BLOCK : Int32 = 128

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
) -> @pattern.UntrackedPatternSnapshot[@score.ScoreEvent] raise {
  @pattern.PatternDoc::merge_control(
    id=bus_id("merge"),
    left=@pattern.PatternDoc::atom(
      id=bus_id("note"),
      value=played(@pattern.ControlMap::single(Note, 60.0)),
    ),
    right=@pattern.PatternDoc::continuous(
      id=bus_id("lpf"),
      key=Lpf,
      f=(t, _) => cutoff(t),
      signature="cutoff",
    ),
  )
  .slow(id=bus_id("slow"), factor=@pattern.Rational::from_int(2))
  .lower_untracked()
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
      key=@moondsp.Control::Lpf,
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
  snapshot : @pattern.UntrackedPatternSnapshot[@score.ScoreEvent],
) -> Array[Double] raise {
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let scheduler = @scheduler.PatternScheduler(
    bpm=120.0,
    ctx~,
    pools=[bus_pool(ctx)],
    route=_ => 0,
  )
  scheduler.queue_pattern_snapshot(snapshot)
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let mut previous = 0.0
  [
    for _ in 0..<((2.0 * BUS_SECONDS_PER_CYCLE * BUS_RATE).to_int() / BUS_BLOCK) => {
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
/// cycle position `cycle`, scaled by 1000.
fn bus_brightness_at(blocks : Array[Double], cycle : Double) -> Double {
  let seconds = cycle * BUS_SECONDS_PER_CYCLE
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
      #|swept     10.85 14.52 19.88 23.99 27.37
      #|reference 11.13 14.73 20.03 24.12 27.47
      #|constant  5.53 5.52 5.52 5.52 5.53
    ),
  )
}

///|
/// RMS of the first block of `doc` played with gain bound to the voice frame.
fn bus_first_block_rms(
  doc : @pattern.PatternDoc[@score.ScoreEvent],
) -> Double raise {
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let pool = @moondsp.BoundVoicePool(
    @moondsp.AnalyzedGraph::analyze([
      @moondsp.DspNode::oscillator(@moondsp.Waveform::Saw, 110.0),
      @moondsp.DspNode::output(0),
    ]),
    ctx,
    @moondsp.ControlBindingBuilder().bind_voice(
      key=@moondsp.Control::Gain,
      param=Gain,
    ),
    max_voices=4,
  )
  let scheduler = @scheduler.PatternScheduler(bpm=120.0, ctx~, pools=[pool], route=_ => {
    0
  })
  scheduler.queue_pattern_snapshot(doc.lower_untracked())
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  scheduler.render_block(left, right)
  let mut energy = 0.0
  for i in 0..<BUS_BLOCK {
    energy += left.get(i) * left.get(i)
  }
  (energy / BUS_BLOCK.to_double()).sqrt()
}

///|
test "a voice starts from its bus value, which rev defines" {
  // Reversed, the second slot's note sounds first. Its bus reads the step
  // just before the slot's end (0.9); the slot's own query samples its
  // start (0.1).
  let doc = (gain : @pattern.PatternDoc[@pattern.ControlMap]) => {
    @pattern.PatternDoc::sequence(id=bus_id("seq"), docs=[
      @pattern.PatternDoc::atom(
        id=bus_id("other"),
        value=played(@pattern.ControlMap::single(Gain, 0.0)),
      ),
      @pattern.PatternDoc::merge_control(
        id=bus_id("merge"),
        left=@pattern.PatternDoc::atom(
          id=bus_id("note"),
          value=played(@pattern.ControlMap::single(Note, 60.0)),
        ),
        right=gain,
      ),
    ]).rev(id=bus_id("rev"))
  }
  let steps = bus_first_block_rms(
    doc(
      @pattern.PatternDoc::sequence(id=bus_id("steps"), docs=[
        @pattern.PatternDoc::pure(
          id=bus_id("low"),
          value=@pattern.ControlMap::single(Gain, 0.1),
        ),
        @pattern.PatternDoc::pure(
          id=bus_id("high"),
          value=@pattern.ControlMap::single(Gain, 0.9),
        ),
      ]),
    ),
  )
  let fixed = bus_first_block_rms(
    doc(
      @pattern.PatternDoc::pure(
        id=bus_id("fixed"),
        value=@pattern.ControlMap::single(Gain, 0.9),
      ),
    ),
  )
  assert_true(fixed > 0.0)
  inspect((steps / fixed * 100.0).round() / 100.0, content="1")
}

///|
test "a signal buffer records the value held voices follow, once per block, on its material clock" {
  let source = @identity.SourceAtomId::SourceAtomId(
    @identity.SourceEpoch::SourceEpoch(3L),
    7L,
  )
  let snapshot = @pattern.PatternDoc::merge_control(
      id=bus_id("merge"),
      // Two chord tones follow one signal.
      left=@pattern.PatternDoc::stack(id=bus_id("chord"), docs=[
        @pattern.PatternDoc::atom(
          id=bus_id("root"),
          value=played(@pattern.ControlMap::single(Note, 60.0)),
        ),
        @pattern.PatternDoc::atom(
          id=bus_id("third"),
          value=played(@pattern.ControlMap::single(Note, 64.0)),
        ),
      ]),
      right=@pattern.PatternDoc::continuous(
        id=bus_id("lpf"),
        key=Lpf,
        f=(t, _) => 200.0 + 3800.0 * t,
        signature="sweep",
        source=Some(source),
      ),
    )
    .slow(id=bus_id("slow"), factor=@pattern.Rational::from_int(2))
    .lower_untracked()
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let scheduler = @scheduler.PatternScheduler(
    bpm=240.0,
    ctx~,
    pools=[bus_pool(ctx)],
    route=_ => 0,
  )
  let signals = @scheduler.SignalBuffer()
  signals.enable(true)
  scheduler.attach_signal_buffer(signals)
  scheduler.queue_pattern_snapshot(snapshot)
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  // Block 375 starts at sample 48000: one cycle, halfway through the stretched sweep.
  for _ in 0..<376 {
    scheduler.render_block(left, right)
  }
  let last = signals.count() - 1
  @debug.assert_eq([0, 1, 2, 3, 4].map(field => signals.field(last, field)), [
    48000.0, 3.0, 7.0, 1.0, 2100.0,
  ])
  // One row per block for both tones, also once the ring overwrites: the
  // chord started in block 0, so blocks 1 to 375 report.
  @debug.assert_eq((signals.count(), signals.dropped()), (256, 119.0))
  for index in 1..<signals.count() {
    assert_eq(signals.field(index, 0) - signals.field(index - 1, 0), 128.0)
  }
}

///|
test "a signal buffer keeps recording through a voice's release and stops once it is idle" {
  let snapshot = @pattern.PatternDoc::merge_control(
    id=bus_id("merge"),
    // The note sounds for the first half of the cycle.
    left=@pattern.PatternDoc::sequence(id=bus_id("seq"), docs=[
      @pattern.PatternDoc::atom(
        id=bus_id("note"),
        value=played(@pattern.ControlMap::single(Note, 60.0)),
      ),
      @pattern.PatternDoc::silence(id=bus_id("rest")),
    ]),
    right=@pattern.PatternDoc::continuous(
      id=bus_id("lpf"),
      key=Lpf,
      f=(t, _) => 200.0 + 3800.0 * t,
      signature="sweep",
      source=Some(
        @identity.SourceAtomId::SourceAtomId(
          @identity.SourceEpoch::SourceEpoch(3L),
          7L,
        ),
      ),
    ),
  ).lower_untracked()
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let scheduler = @scheduler.PatternScheduler(
    bpm=240.0,
    ctx~,
    pools=[bus_pool(ctx)],
    route=_ => 0,
  )
  let signals = @scheduler.SignalBuffer()
  signals.enable(true)
  scheduler.attach_signal_buffer(signals)
  scheduler.queue_pattern_snapshot(snapshot)
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  // The cycle is 48000 samples: the gate closes at sample 24000, the 50 ms
  // release ends 2400 samples later, and the next note starts at 48000.
  for _ in 0..<300 {
    scheduler.render_block(left, right)
  }
  let last = signals.field(signals.count() - 1, 0)
  assert_true(last > 24000.0 && last < 24000.0 + 2400.0 + 2.0 * 128.0)
  let count = signals.count()
  for _ in 0..<50 {
    scheduler.render_block(left, right)
  }
  assert_eq(signals.count(), count)
}

///|
test "a signal buffer keeps signals of different epochs apart even when their serials match" {
  let voice = (name : String, epoch : Int64, note : Double) => {
    @pattern.PatternDoc::merge_control(
      id=bus_id("merge-\{name}"),
      left=@pattern.PatternDoc::atom(
        id=bus_id("note-\{name}"),
        value=played(@pattern.ControlMap::single(Note, note)),
      ),
      right=@pattern.PatternDoc::continuous(
        id=bus_id("lpf-\{name}"),
        key=Lpf,
        f=(t, _) => 200.0 + 3800.0 * t,
        signature="sweep",
        source=Some(
          @identity.SourceAtomId::SourceAtomId(
            @identity.SourceEpoch::SourceEpoch(epoch),
            7L,
          ),
        ),
      ),
    )
  }
  let snapshot = @pattern.PatternDoc::stack(id=bus_id("both"), docs=[
    voice("old", 3L, 60.0),
    voice("new", 4L, 64.0),
  ]).lower_untracked()
  let ctx = @moondsp.DspContext(sample_rate=BUS_RATE, block_size=BUS_BLOCK)
  let scheduler = @scheduler.PatternScheduler(
    bpm=240.0,
    ctx~,
    pools=[bus_pool(ctx)],
    route=_ => 0,
  )
  let signals = @scheduler.SignalBuffer()
  signals.enable(true)
  scheduler.attach_signal_buffer(signals)
  scheduler.queue_pattern_snapshot(snapshot)
  let left = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  let right = @moondsp.AudioBuffer::filled(BUS_BLOCK)
  for _ in 0..<11 {
    scheduler.render_block(left, right)
  }
  // Blocks 1 to 10 each give one row per epoch.
  assert_eq(signals.count(), 20)
  let epochs = Array::makei(signals.count(), index => signals.field(index, 1))
  @debug.assert_eq(epochs.filter(epoch => epoch == 3.0).length(), 10)
  @debug.assert_eq(epochs.filter(epoch => epoch == 4.0).length(), 10)
}
