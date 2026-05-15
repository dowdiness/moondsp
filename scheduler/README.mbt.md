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
    [
      @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
      @moondsp.DspNode::adsr(
        attack_ms=0.01,
        decay_ms=0.1,
        sustain=0.7,
        release_ms=0.3,
      ),
      @moondsp.DspNode::envelope_gain(0, 1, 1.0),
      @moondsp.DspNode::output(2),
    ],
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
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let active_playback = @scheduler.PlaybackSnapshot::pattern(active_snapshot)
  let active_events = active_playback.query_playback_events(arc)
  sched.process_playback_events(active_events, arc, pool)

  let replacement_doc = @pattern.PatternDoc::from_pattern(
    id=replacement_root,
    pat=@pattern.note(67.0),
  )
  let replacement = try! replacement_doc.lower()
  let outcome = sched
    .queue_pattern_snapshot_live_control_edit_result(
      snapshot=replacement,
      policy=@scheduler.AffectedVoicePolicy::GateOffAffected,
      edit=@scheduler.AffectedVoiceEditScope::pattern_node(edited),
      controls=[
        // Pattern notes use the "note" binding's MIDI-to-Hz mapping; direct
        // graph controls write the target slot's raw value.
        @moondsp.GraphControl::set_param(
          0,
          @moondsp.GraphParamSlot::Value0,
          330.0,
        ),
      ],
      pool~,
    )
    .unwrap()

  assert_eq(outcome.controlled_voice_count, 1)
  assert_eq(outcome.removed_active_note_count, 1)
  assert_true(sched.has_pending_pattern_snapshot())
  assert_eq(sched.active_note_count(), 0)
}
```
