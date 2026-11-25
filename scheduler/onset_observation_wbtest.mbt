///|
fn onset_test_event() -> @pattern.EventWithOrigin[@score.ScoreEvent] {
  let epoch = @identity.SourceEpoch::SourceEpoch(11L) catch {
    _ => abort("valid test epoch")
  }
  let atom = @identity.SourceAtomId::SourceAtomId(epoch, 19L) catch {
    _ => abort("valid test atom")
  }
  let node = @identity.PatternNodeId::from_string("onset:atom") catch {
    _ => abort("valid test node")
  }
  let doc = @pattern.PatternDoc::atom(
    id=node,
    source_atom=atom,
    value=@score.ScoreEvent(Note(@score.Instrument::default(), pitch=60.0)),
  )
  let snapshot = doc.lower_tracked() catch {
    _ => abort("valid tracked test snapshot")
  }
  let arc = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  snapshot.query(arc)[0]
}

///|
test "onset ring records fixed rows and overwrites oldest with bounded diagnostics" {
  let ring = OnsetBuffer()
  let event = onset_test_event()
  ring.enabled = true
  for sample in 0..<=ONSET_RING_CAPACITY {
    ring.record(sample.to_int64(), Some(event))
  }
  assert_eq(ring.count, ONSET_RING_CAPACITY)
  assert_eq(ring.dropped_count, 1)
  assert_eq(ring.field(0, 0), 1.0)
  assert_eq(ring.field(255, 0), 256.0)
  assert_eq(ring.field(255, 1), 11.0)
  assert_eq(ring.field(255, 2), 19.0)
  assert_eq(ring.field(255, 6), 0.0)
  assert_eq(ring.field(256, 0), 0.0)
}

///|
test "onset ring defaults disabled and clear resets bounded state" {
  let ring = OnsetBuffer()
  ring.record(0L, Some(onset_test_event()))
  assert_eq(ring.count, 0)
  ring.enabled = true
  ring.record(0L, Some(onset_test_event()))
  ring.clear()
  assert_eq(ring.count, 0)
  assert_eq(ring.dropped_count, 0)
  assert_eq(ring.field(0, 0), 0.0)
}

///|
test "onset ring skips untracked events and encodes a missing frame as serial 0 and start -1" {
  let ring = OnsetBuffer()
  ring.enabled = true
  ring.record(1L, None)
  assert_eq(ring.count, 0)
  ring.record(2L, Some(onset_test_event()))
  assert_eq(ring.field(0, 3), 0.0)
  assert_eq(ring.field(0, 4), -1.0)
  assert_eq(ring.field(0, 5), 60.0)
}
