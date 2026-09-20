///|
test "Unrepresentable render frame silences dry and send without accepting queued edits" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let sched = PatternScheduler::new(bpm=1000.0, ctx~).unwrap()
  let pool = @moondsp.BoundVoicePool::new(
    @moondsp.AnalyzedGraph::analyze([
      @moondsp.DspNode::constant(1.0),
      @moondsp.DspNode::output(0),
    ]),
    ctx,
    @moondsp.ControlBindingBuilder::new(),
    max_voices=1,
  ).unwrap()
  let snapshot = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("unaccepted"),
    pat=@pattern.note(60.0),
  ).lower()
  sched.queue_pattern_snapshot(snapshot)
  // Move directly to the last representable sample at 1000 BPM without
  // rendering billions of blocks. The next 128-sample frame overflows ticks.
  let mut remaining = 9223372036854L
  while remaining > 0L {
    let count = if remaining > 2147483647L {
      2147483647
    } else {
      remaining.to_int()
    }
    sched.clock = sched.clock.advance(count).unwrap()
    remaining -= count.to_int64()
  }
  let before = sched.sample_counter()
  let left = @moondsp.AudioBuffer::filled(128, init=1.0)
  let right = @moondsp.AudioBuffer::filled(128, init=-1.0)
  let send_left = @moondsp.AudioBuffer::filled(128, init=2.0)
  let send_right = @moondsp.AudioBuffer::filled(128, init=-2.0)
  sched.render_block_with_send(pool, left, right, send_left, send_right)
  for buffer in [left, right, send_left, send_right] {
    for i in 0..<buffer.length() {
      assert_eq(buffer.get(i), 0.0)
    }
  }
  assert_true(sched.last_transport_error() is Some(TimeOutOfRange))
  assert_eq(sched.sample_counter(), before)
  assert_true(sched.accepted_snapshot() is None)
  assert_true(
    sched.queued_snapshot().unwrap().revision() == snapshot.revision(),
  )
}
