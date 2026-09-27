///|
test "references retain distinct use-site paths into the same definition" {
  let definition = @pattern.PatternDoc::pure(id=pid("note"), value=60).slow(
    id=pid("phrase"),
    factor=@pattern.Rational::from_int(3),
  )
  let left = @pattern.PatternDoc::reference(id=pid("left"), definition~)
  let right = @pattern.PatternDoc::reference(id=pid("right"), definition~)
  let doc = @pattern.PatternDoc::stack(id=pid("mix"), docs=[left, right])
  let snapshot = doc.lower()
  let events = snapshot.query_sourced_events(doc_span(0, 1, 3, 1))
  @debug.assert_eq(events.length(), 2)
  assert_pattern_event_path(events[0], ["mix", "left", "phrase", "note"])
  assert_pattern_event_path(events[1], ["mix", "right", "phrase", "note"])
  guard left.referenced_definition(pid("left")) is Some(target) else {
    fail("missing reference target")
  }
  assert_true(target.contains_node(pid("note")))
}

///|
test "references to divergent definition revisions never share stale values" {
  let original = @pattern.PatternDoc::pure(id=pid("note"), value=60).slow(
    id=pid("phrase"),
    factor=@pattern.Rational::from_int(3),
  )
  let edited = original.replace_with_pure(id=pid("note"), value=72)
  let doc = @pattern.PatternDoc::stack(id=pid("mix"), docs=[
    @pattern.PatternDoc::reference(id=pid("original"), definition=original),
    @pattern.PatternDoc::reference(id=pid("edited"), definition=edited),
  ])
  let snapshot = doc.lower()
  @debug.assert_eq(
    snapshot.query(doc_span(0, 1, 3, 1)).map(event => event.value),
    [60, 72],
  )
  @debug.assert_eq(
    snapshot
    .query_sourced_events(doc_span(0, 1, 3, 1))
    .map(event => event.event().value),
    [60, 72],
  )
}

///|
test "rebuilding references to an edited definition invalidates a persistent cache" {
  let original = @pattern.PatternDoc::pure(id=pid("note"), value=60)
  let cache : @pattern.PatternLoweringCache[Int] = @pattern.PatternLoweringCache::new()
  let before = @pattern.PatternDoc::reference(
    id=pid("use"),
    definition=original,
  ).lower_with_cache(cache)
  let edited = original.replace_with_pure(id=pid("note"), value=72)
  let after = @pattern.PatternDoc::reference(id=pid("use"), definition=edited).lower_with_cache(
    cache,
  )
  @debug.assert_eq(
    before.query(doc_span(0, 1, 1, 1)).map(event => event.value),
    [60],
  )
  @debug.assert_eq(
    after.query(doc_span(0, 1, 1, 1)).map(event => event.value),
    [72],
  )
  assert_pattern_event_path(
    after.query_sourced_events(doc_span(0, 1, 1, 1))[0],
    ["use", "note"],
  )
}
