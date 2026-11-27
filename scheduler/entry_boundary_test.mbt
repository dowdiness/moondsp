///|
test "a prepared entry switch is audible at its rounded sample inside the block" {
  let (sched, _, left, right) = transport_fixture()
  // One source cycle lasts 128.5 samples. The edit arrives at sample 128.
  let period = @pattern.Rational(257L, 192000L)
  let note = @pattern.Pat::pure(played(@pattern.ControlMap::empty())).slow(
    period,
  )
  let old = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("entry"),
    pat=note.filter_map(_ => None).material(),
  ).lower()
  let next = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("entry"),
    pat=note.material(),
  ).lower()
  sched.queue_playback_snapshot(
    @scheduler.PlaybackSnapshot::pattern(old.playback()),
  )
  sched.render_block(left, right)
  sched.queue_playback_snapshot(
    @scheduler.PlaybackSnapshot::pattern(next.playback()),
  )
  sched.render_block(left, right)
  assert_eq(left.get(0), 0.0)
  assert_true(left.get(1) > 0.0)
  assert_eq(sched.active_note_count(), 1)
}
