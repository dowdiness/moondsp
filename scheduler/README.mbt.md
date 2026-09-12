# Scheduler

The scheduler bridges identity-bearing pattern/song snapshots to a bound voice
pool. Edit orchestration helpers let UI or authoring code stage a replacement
snapshot, choose how already-sounding voices should be reconciled, and
optionally apply live graph-control changes to matching active voices before the
replacement commits at the next block boundary.

```mbt check
///|
test "edit orchestration stages a replacement and reconciles active voices" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @moondsp.BoundVoicePool::new(
    @moondsp.CompiledTemplate::analyze([
      @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
      @moondsp.DspNode::adsr(
        attack_ms=0.01,
        decay_ms=0.1,
        sustain=0.7,
        release_ms=0.3,
      ),
      @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
      @moondsp.DspNode::output(2),
    ]),
    ctx,
    @moondsp.ControlBindingBuilder::new().bind(
      key="note",
      node_index=0,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
    max_voices=4,
  ).unwrap()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~)
  let edited = try! @identity.PatternNodeId::from_string("docs:lead")
  let replacement_root = try! @identity.PatternNodeId::from_string(
    "docs:replacement",
  )
  let active_doc = @pattern.PatternDoc::from_pattern(
    id=edited,
    pat=@pattern.note(60.0),
  )
  let active_snapshot = try! active_doc.lower()

  let replacement_doc = @pattern.PatternDoc::from_pattern(
    id=replacement_root,
    pat=@pattern.note(67.0),
  )
  let replacement = try! replacement_doc.lower()
  let left = @moondsp.AudioBuffer::filled(128)
  let right = @moondsp.AudioBuffer::filled(128)
  sched.queue_pattern_snapshot(active_snapshot)
  sched.process_snapshot_block(pool, left, right)
  let outcome = sched
    .queue_pattern_snapshot_effect_result(
      replacement,
      @scheduler.PatternVoiceScope::node(edited),
      @scheduler.ActiveVoiceEffect::Release,
      pool,
    )
    .unwrap()

  assert_eq(outcome.retuned_voice_count, 0)
  assert_eq(outcome.detached_note_count, 1)
  assert_true(sched.has_pending_pattern_snapshot())
  assert_eq(sched.active_note_count(), 0)
}
```
