///|
const BENCH_SAMPLE_RATE : Double = 48000.0

///|
const BENCH_BLOCK_SIZE : Int = 128

///|
fn bench_ctx() -> @moondsp.DspContext {
  @moondsp.DspContext::new(
    sample_rate=BENCH_SAMPLE_RATE,
    block_size=BENCH_BLOCK_SIZE,
  )
}

///|
fn bench_arc() -> @pattern.TimeSpan {
  @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
}

///|
fn bench_template() -> Array[@moondsp.DspNode] {
  [
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
    @moondsp.DspNode::adsr(
      attack_ms=0.01,
      decay_ms=0.1,
      sustain=0.7,
      release_ms=0.3,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ]
}

///|
fn bench_binding_builder() -> @moondsp.ControlBindingBuilder {
  @moondsp.ControlBindingBuilder::new().bind(
    key="note",
    node_index=0,
    slot=@moondsp.GraphParamSlot::Value0,
  )
}

///|
fn bench_pool(
  template : Array[@moondsp.DspNode],
  ctx : @moondsp.DspContext,
) -> @moondsp.BoundVoicePool {
  @moondsp.BoundVoicePool::new(
    @moondsp.CompiledTemplate::analyze(template),
    ctx,
    bench_binding_builder(),
    max_voices=16,
  ).unwrap()
}

///|
fn bench_scheduler(ctx : @moondsp.DspContext) -> PatternScheduler {
  PatternScheduler::new(bpm=120.0, ctx~)
}

///|
fn bench_jux_pattern() -> @pattern.Pat[@pattern.ControlMap] {
  @pattern.sequence([
    @pattern.note(60.0),
    @pattern.note(64.0),
    @pattern.note(67.0),
    @pattern.note(72.0),
  ]).jux(fn(p) { p.rev() })
}

///|
fn bench_seed_jux_voices(
  scheduler : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  let arc = bench_arc()
  let events = bench_jux_pattern().query(arc)
  scheduler.process_events(events, arc, pool)
}

///|
test "bench/jux/scheduler_dispatch" (b : @bench.T) {
  let ctx = bench_ctx()
  let template = bench_template()
  let scheduler = bench_scheduler(ctx)
  let pool = bench_pool(template, ctx)
  let arc = bench_arc()
  let expire_arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(1),
    @pattern.Rational::from_int(2),
  )
  let events = bench_jux_pattern().query(arc)
  b.bench(name="process_events_8_jux_events", fn() {
    scheduler.process_events(events.copy(), arc, pool)
    scheduler.expire_notes(pool, expire_arc)
    b.keep(pool.active_voice_count())
  })
}

///|
test "bench/jux/stereo_routing" (b : @bench.T) {
  let ctx = bench_ctx()
  let template = bench_template()
  let scheduler = bench_scheduler(ctx)
  let pool = bench_pool(template, ctx)
  bench_seed_jux_voices(scheduler, pool)
  let left = @moondsp.AudioBuffer::filled(BENCH_BLOCK_SIZE)
  let right = @moondsp.AudioBuffer::filled(BENCH_BLOCK_SIZE)
  b.bench(name="voicepool_process_8_panned_jux_voices", fn() {
    left.fill(0.0)
    right.fill(0.0)
    pool.process(ctx, left, right)
    b.keep(left)
    b.keep(right)
  })
}

///|
test "bench/jux/process_block" (b : @bench.T) {
  let ctx = bench_ctx()
  let template = bench_template()
  let scheduler = bench_scheduler(ctx)
  let pool = bench_pool(template, ctx)
  let pattern = bench_jux_pattern()
  let left = @moondsp.AudioBuffer::filled(BENCH_BLOCK_SIZE)
  let right = @moondsp.AudioBuffer::filled(BENCH_BLOCK_SIZE)
  b.bench(name="process_block_jux_rev", fn() {
    scheduler.process_block(pattern, pool, left, right)
    b.keep(left)
    b.keep(right)
  })
}
