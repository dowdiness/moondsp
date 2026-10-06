///|
fn onset_test_origin() -> @pattern.EventOrigin {
  let epoch = @identity.SourceEpoch::SourceEpoch(11L) catch {
    _ => abort("valid test epoch")
  }
  let atom = @identity.SourceAtomId::SourceAtomId(epoch, 19L) catch {
    _ => abort("valid test atom")
  }
  let node = @identity.PatternNodeId::from_string("onset:atom") catch {
    _ => abort("valid test node")
  }
  let doc = @pattern.PatternDoc::control_atom(
    id=node,
    source_atom=atom,
    key="note",
    value=60.0,
  )
  let snapshot = doc.lower_with_origins() catch {
    _ => abort("valid exact test snapshot")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  snapshot.query(arc)[0].origin()
}

///|
test "onset ring records fixed rows and overwrites oldest with bounded diagnostics" {
  let ring = OnsetBuffer::new()
  let origin = onset_test_origin()
  ring.enabled = true
  for sample in 0..<=ONSET_RING_CAPACITY {
    ring.record(sample.to_int64(), Some(origin))
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
  let ring = OnsetBuffer::new()
  ring.record(0L, Some(onset_test_origin()))
  assert_eq(ring.count, 0)
  ring.enabled = true
  ring.record(0L, Some(onset_test_origin()))
  ring.clear()
  assert_eq(ring.count, 0)
  assert_eq(ring.dropped_count, 0)
  assert_eq(ring.field(0, 0), 0.0)
}
