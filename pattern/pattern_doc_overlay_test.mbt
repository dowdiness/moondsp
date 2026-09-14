///|
test "overlay regrouping preserves playback keys while retaining source ancestry" {
  let a = PatternDoc::pure(id=pid("a"), value=1)
  let b = PatternDoc::pure(id=pid("b"), value=2)
  let c = PatternDoc::pure(id=pid("c"), value=3)
  let group = PatternDoc::stack(id=pid("group"), docs=[a, b])
  let nested = PatternDoc::stack(id=pid("nested"), docs=[group, c]).lower()
  let flat = PatternDoc::stack(id=pid("flat"), docs=[a, b, c]).lower()
  let arc = doc_span(0, 1, 2, 1)
  @debug.assert_eq(
    nested.query(arc).map(e => (e.whole, e.part, e.value)),
    flat.query(arc).map(e => (e.whole, e.part, e.value)),
  )
  for index in 0..<3 {
    @debug.assert_eq(nested.entry_key(index), flat.entry_key(index))
    @debug.assert_eq(
      nested
      .query_sourced_events_for_entry(index, arc)
      .map(e => {
        let raw = e.event()
        (raw.whole, raw.part, raw.value)
      }),
      flat
      .query_sourced_events_for_entry(index, arc)
      .map(e => {
        let raw = e.event()
        (raw.whole, raw.part, raw.value)
      }),
    )
  }
  assert_true(
    nested
    .query_sourced_events_for_entry(0, arc)
    .iter()
    .all(e => e.pattern_nodes().contains(pid("group"))),
  )
  assert_true(
    flat
    .query_sourced_events_for_entry(0, arc)
    .iter()
    .all(e => !e.pattern_nodes().contains(pid("group"))),
  )
}

///|
test "reference identity belongs to the use site rather than its definition" {
  let definition = PatternDoc::pure(id=pid("definition"), value=7)
  let first = PatternDoc::reference(id=pid("first-use"), definition~)
  let second = PatternDoc::reference(id=pid("second-use"), definition~)
  let snapshot = PatternDoc::stack(id=pid("both"), docs=[first, second]).lower()
  guard snapshot.entry_key(0) is Some(first_key) else {
    fail("first occurrence missing")
  }
  guard snapshot.entry_key(1) is Some(second_key) else {
    fail("second occurrence missing")
  }
  assert_true(first_key != second_key)
  let arc = doc_span(0, 1, 1, 1)
  @debug.assert_eq(
    snapshot
    .query_sourced_events_for_entry(0, arc)
    .map(e => {
      let raw = e.event()
      (raw.whole, raw.part, raw.value)
    }),
    snapshot
    .query_sourced_events_for_entry(1, arc)
    .map(e => {
      let raw = e.event()
      (raw.whole, raw.part, raw.value)
    }),
  )
  assert_true(
    snapshot.query_sourced_events_for_entry(0, arc)[0]
    .pattern_nodes()
    .contains(pid("first-use")),
  )
  assert_true(
    snapshot.query_sourced_events_for_entry(1, arc)[0]
    .pattern_nodes()
    .contains(pid("second-use")),
  )
  let edited = PatternDoc::reference(
    id=pid("first-use"),
    definition=PatternDoc::pure(id=pid("changed-definition"), value=8),
  ).lower()
  @debug.assert_eq(edited.entry_key(0), Some(first_key))
  @debug.assert_eq(edited.query(arc).map(event => event.value), [8])
}

///|
test "silence in an overlay does not shift sourced playback entries" {
  let silent : PatternDoc[Int] = PatternDoc::silence(id=pid("silent"))
  let audible = PatternDoc::pure(id=pid("audible"), value=8)
  let snapshot = PatternDoc::stack(id=pid("mixed"), docs=[silent, audible]).lower()
  let arc = doc_span(0, 1, 1, 1)
  @debug.assert_eq(snapshot.pat().entries().length(), 1)
  @debug.assert_eq(
    snapshot
    .query_sourced_events_for_entry(0, arc)
    .map(e => {
      let raw = e.event()
      (raw.whole, raw.part, raw.value)
    }),
    snapshot.query(arc).map(e => (e.whole, e.part, e.value)),
  )
  @debug.assert_eq(snapshot.entry_key(1), None)
  assert_true(snapshot.query_sourced_events_for_entry(1, arc).is_empty())
}
