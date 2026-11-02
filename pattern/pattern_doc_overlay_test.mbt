///|
test "overlay regrouping preserves playback keys while retaining source ancestry" {
  let a = @pattern.PatternDoc::pure(id=pid("a"), value=1)
  let b = @pattern.PatternDoc::pure(id=pid("b"), value=2)
  let c = @pattern.PatternDoc::pure(id=pid("c"), value=3)
  let group = @pattern.PatternDoc::stack(id=pid("group"), docs=[a, b])
  let nested = @pattern.PatternDoc::stack(id=pid("nested"), docs=[group, c]).lower()
  let flat = @pattern.PatternDoc::stack(id=pid("flat"), docs=[a, b, c]).lower()
  let arc = doc_span(0, 1, 2, 1)
  @debug.assert_eq(
    nested.query(arc).map(e => (e.whole, e.part, e.value)),
    flat.query(arc).map(e => (e.whole, e.part, e.value)),
  )
  for index in 0..<3 {
    @debug.assert_eq(
      nested.pat().entries()[index].entry_key(),
      flat.pat().entries()[index].entry_key(),
    )
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
  let definition = @pattern.PatternDoc::pure(id=pid("definition"), value=7)
  let first = @pattern.PatternDoc::reference(id=pid("first-use"), definition~)
  let second = @pattern.PatternDoc::reference(id=pid("second-use"), definition~)
  let snapshot = @pattern.PatternDoc::stack(id=pid("both"), docs=[first, second]).lower()
  let first_key = snapshot.pat().entries()[0].entry_key()
  let second_key = snapshot.pat().entries()[1].entry_key()
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
  let edited = @pattern.PatternDoc::reference(
    id=pid("first-use"),
    definition=@pattern.PatternDoc::pure(id=pid("changed-definition"), value=8),
  ).lower()
  @debug.assert_eq(edited.pat().entries()[0].entry_key(), first_key)
  @debug.assert_eq(edited.query(arc).map(event => event.value), [8])
}

///|
test "silence in an overlay does not shift sourced playback entries" {
  let silent : @pattern.PatternDoc[Int] = @pattern.PatternDoc::silence(
    id=pid("silent"),
  )
  let audible = @pattern.PatternDoc::pure(id=pid("audible"), value=8)
  let snapshot = @pattern.PatternDoc::stack(id=pid("mixed"), docs=[
    silent, audible,
  ]).lower()
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
  assert_true(snapshot.query_sourced_events_for_entry(1, arc).is_empty())
}
