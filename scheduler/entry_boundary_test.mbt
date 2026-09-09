///|
test "a prepared entry switch is audible at its rounded sample inside the block" {
  let (sched, pool, left, right) = transport_fixture()
  // One source cycle lasts 128.5 samples. The edit arrives at sample 128.
  let period = @pattern.Rational::new(257L, 48000L)
  let note = @pattern.Pat::pure(@pattern.ControlMap::empty()).slow(period)
  let old = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("entry"),
    pat=note.filter_map(_ => None).material("silent"),
  ).lower()
  let next = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("entry"),
    pat=note.material("audible"),
  ).lower()
  sched.queue_pattern_snapshot(old)
  sched.process_playback_snapshot_block(pool, left, right)
  sched.queue_pattern_snapshot(next)
  sched.process_playback_snapshot_block(pool, left, right)
  assert_eq(left.get(0), 0.0)
  assert_true(left.get(1) > 0.0)
  assert_eq(sched.active_note_count(), 1)
}
