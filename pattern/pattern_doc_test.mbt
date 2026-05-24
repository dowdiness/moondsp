///|
fn pid(value : String) -> @identity.PatternNodeId {
  let result = try? @identity.PatternNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid pattern node id")
  }
}

///|
fn doc_span(b_num : Int, b_den : Int, e_num : Int, e_den : Int) -> TimeSpan {
  TimeSpan::new(
    Rational::new(b_num.to_int64(), b_den.to_int64()),
    Rational::new(e_num.to_int64(), e_den.to_int64()),
  )
}

///|
fn[A] unwrap_doc(
  result : Result[PatternDoc[A], PatternDocError],
) -> PatternDoc[A] {
  match result {
    Ok(doc) => doc
    Err(_) => abort("expected pattern doc")
  }
}

///|
fn[A] unwrap_snapshot(
  result : Result[PatternSnapshot[A], PatternDocError],
) -> PatternSnapshot[A] {
  match result {
    Ok(snapshot) => snapshot
    Err(_) => abort("expected pattern snapshot")
  }
}

///|
fn[A] assert_pattern_event_path(
  event : PatternSnapshotEvent[A],
  expected : Array[String],
) -> Unit {
  let nodes = event.pattern_nodes()
  if nodes.length() != expected.length() {
    abort("unexpected pattern source path length")
  }
  for index in 0..<expected.length() {
    if nodes[index] != pid(expected[index]) {
      abort("unexpected pattern source path")
    }
  }
}

///|
fn unwrap_revision(
  result : Result[@identity.Revision, PatternDocError],
) -> @identity.Revision {
  match result {
    Ok(revision) => revision
    Err(_) => abort("expected pattern node revision")
  }
}

///|
fn edited_leaf_doc(edit_count : Int, value : Int) -> PatternDoc[Int] {
  let count = edit_count.abs() % 8 + 1
  let mut doc = PatternDoc::pure(id=pid("leaf"), value~)
  for i in 0..<count {
    doc = unwrap_doc(
      try? doc.replace_with_pure(id=pid("leaf"), value=value + i),
    )
  }
  doc
}

///|
fn revisioned_leaf_doc(
  id_value : String,
  revision : Int,
  value : Int,
) -> PatternDoc[Int] {
  let mut doc = PatternDoc::pure(id=pid(id_value), value~)
  for i in 0..<revision {
    doc = unwrap_doc(
      try? doc.replace_with_pure(id=pid(id_value), value=value + i + 1),
    )
  }
  doc
}

///|
test "PatternDoc::pure lowers to runtime Pat" {
  let doc = PatternDoc::pure(id=pid("leaf"), value=7)
  let snapshot = unwrap_snapshot(try? doc.lower())
  inspect(snapshot.revision().value(), content="0")
  inspect(snapshot.root().value(), content="leaf")
  let events = snapshot.query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  inspect(events[0].value, content="7")
}

///|
test "PatternDoc::fast adds stable root and bumps revision" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=7).fast(
      id=pid("fast"),
      factor=Rational::from_int(2),
    ),
  )
  inspect(doc.root().value(), content="fast")
  inspect(doc.revision().value(), content="1")
  inspect(doc.node_count(), content="2")
  assert_true(doc.contains_node(pid("leaf")))
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
}

///|
test "PatternSnapshot::query_sourced_events tags fast ancestor and leaf path" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=7).fast(
      id=pid("fast"),
      factor=Rational::from_int(2),
    ),
  )
  let snapshot = unwrap_snapshot(try? doc.lower())
  let events = snapshot.query_sourced_events(doc_span(0, 1, 1, 1))
  let raw_events = snapshot.query(doc_span(0, 1, 1, 1))
  @debug.assert_eq(events.length(), raw_events.length())
  @debug.assert_eq(events.length(), 2)
  assert_pattern_event_path(events[0], ["fast", "leaf"])
  assert_pattern_event_path(events[1], ["fast", "leaf"])
  assert_true(events[0].pattern_node() == Some(pid("leaf")))
  assert_true(events[0].event().value == raw_events[0].value)
  assert_true(events[1].event().part.begin == raw_events[1].part.begin)
}

///|
test "PatternSnapshot::query_sourced_events tags sequence and stack children" {
  let left = PatternDoc::pure(id=pid("left"), value=1)
  let right = PatternDoc::pure(id=pid("right"), value=2)
  let seq = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[left, right]),
  )
  let seq_events = unwrap_snapshot(try? seq.lower()).query_sourced_events(
    doc_span(0, 1, 1, 1),
  )
  @debug.assert_eq(seq_events.length(), 2)
  assert_pattern_event_path(seq_events[0], ["seq", "left"])
  assert_pattern_event_path(seq_events[1], ["seq", "right"])
  assert_true(seq_events[0].event().value == 1)
  assert_true(seq_events[1].event().value == 2)
  let stack = unwrap_doc(
    try? PatternDoc::stack(id=pid("stack"), docs=[
      PatternDoc::pure(id=pid("stack-left"), value=3),
      PatternDoc::pure(id=pid("stack-right"), value=4),
    ]),
  )
  let stack_events = unwrap_snapshot(try? stack.lower()).query_sourced_events(
    doc_span(0, 1, 1, 1),
  )
  @debug.assert_eq(stack_events.length(), 2)
  assert_pattern_event_path(stack_events[0], ["stack", "stack-left"])
  assert_pattern_event_path(stack_events[1], ["stack", "stack-right"])
}

///|
test "PatternSnapshot::query_sourced_events covers every callback subtrees" {
  let child = unwrap_doc(
    try? PatternDoc::stack(id=pid("every-stack"), docs=[
      PatternDoc::pure(id=pid("every-left"), value=1),
      PatternDoc::pure(id=pid("every-right"), value=2),
    ]),
  )
  let doc = unwrap_doc(
    try? child.every(id=pid("every"), n=1, f=fn(p) {
      p.fast(Rational::from_int(2))
    }),
  )
  let events = unwrap_snapshot(try? doc.lower()).query_sourced_events(
    doc_span(0, 1, 1, 100),
  )
  assert_true(events.length() > 0)
  assert_pattern_event_path(events[0], [
    "every", "every-stack", "every-left", "every-right",
  ])
}

///|
test "PatternSnapshot::query_sourced_events covers jux callback subtrees" {
  let child = unwrap_doc(
    try? PatternDoc::stack(id=pid("jux-stack"), docs=[
      PatternDoc::from_pattern(id=pid("jux-left"), pat=note(60.0)),
      PatternDoc::from_pattern(id=pid("jux-right"), pat=note(67.0)),
    ]),
  )
  let doc = unwrap_doc(
    try? child.jux(id=pid("jux"), f=fn(p) { p.fast(Rational::from_int(2)) }),
  )
  let events = unwrap_snapshot(try? doc.lower()).query_sourced_events(
    doc_span(0, 1, 1, 100),
  )
  assert_true(events.length() > 0)
  assert_pattern_event_path(events[0], [
    "jux", "jux-stack", "jux-left", "jux-right",
  ])
}

///|
test "PatternSnapshot::query_sourced_events covers merge_control inputs" {
  let left = PatternDoc::from_pattern(id=pid("merge-left"), pat=note(60.0))
  let right = PatternDoc::from_pattern(
    id=pid("merge-right"),
    pat=s_cutoff(800.0),
  )
  let doc = unwrap_doc(
    try? PatternDoc::merge_control(id=pid("merge"), left~, right~),
  )
  let events = unwrap_snapshot(try? doc.lower()).query_sourced_events(
    doc_span(0, 1, 1, 100),
  )
  @debug.assert_eq(events.length(), 1)
  assert_pattern_event_path(events[0], ["merge", "merge-left", "merge-right"])
  assert_true(events[0].event().value.get("note") == Some(60.0))
  assert_true(events[0].event().value.get("cutoff") == Some(800.0))
}

///|
test "PatternDoc edit preserves ids and changes lowered future events" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=1).fast(
      id=pid("fast"),
      factor=Rational::from_int(2),
    ),
  )
  let edited = unwrap_doc(try? doc.replace_with_pure(id=pid("leaf"), value=2))
  inspect(edited.root().value(), content="fast")
  inspect(edited.revision().value(), content="2")
  assert_true(edited.contains_node(pid("leaf")))
  let events = unwrap_snapshot(try? edited.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="2")
  inspect(events[1].value, content="2")
}

///|
test "PatternDoc snapshot remains stable after document edit" {
  let doc = PatternDoc::pure(id=pid("leaf"), value=1)
  let snapshot = unwrap_snapshot(try? doc.lower())
  let edited = unwrap_doc(try? doc.replace_with_pure(id=pid("leaf"), value=2))
  let old_events = snapshot.query(doc_span(0, 1, 1, 1))
  let new_events = unwrap_snapshot(try? edited.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  inspect(old_events[0].value, content="1")
  inspect(new_events[0].value, content="2")
}

///|
test "PatternDoc node revisions invalidate ancestors but not siblings" {
  let left = PatternDoc::pure(id=pid("left"), value=1)
  let right = PatternDoc::pure(id=pid("right"), value=2)
  let base = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[left, right]),
  )
  let edited = unwrap_doc(try? base.replace_with_pure(id=pid("left"), value=3))
  let base_left = unwrap_revision(try? base.node_revision(pid("left")))
  let edited_left = unwrap_revision(try? edited.node_revision(pid("left")))
  let base_right = unwrap_revision(try? base.node_revision(pid("right")))
  let edited_right = unwrap_revision(try? edited.node_revision(pid("right")))
  let base_root = unwrap_revision(try? base.node_revision(pid("seq")))
  let edited_root = unwrap_revision(try? edited.node_revision(pid("seq")))
  assert_true(base_left != edited_left)
  assert_true(base_right == edited_right)
  assert_true(base_root != edited_root)
}

///|
test "PatternLoweringCache reuses unchanged child after pattern edit" {
  let left = PatternDoc::pure(id=pid("left"), value=1)
  let right = PatternDoc::pure(id=pid("right"), value=2)
  let base = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[left, right]),
  )
  let cache : PatternLoweringCache[Int] = PatternLoweringCache::new()
  ignore(unwrap_snapshot(try? base.lower_with_cache(cache)))
  inspect(cache.hit_count(), content="0")
  inspect(cache.miss_count(), content="3")
  inspect(cache.entry_count(), content="3")
  let edited_left = unwrap_doc(
    try? left.replace_with_pure(id=pid("left"), value=3),
  )
  let edited = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[edited_left, right]),
  )
  cache.reset_stats()
  let snapshot = unwrap_snapshot(try? edited.lower_with_cache(cache))
  let events = snapshot.query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="3")
  inspect(events[1].value, content="2")
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="2")
  inspect(cache.entry_count(), content="5")
  cache.reset_stats()
  ignore(unwrap_snapshot(try? edited.lower_with_cache(cache)))
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="0")
}

///|
test "PatternLoweringCache does not reuse fresh doc with same id and revision" {
  let first = PatternDoc::pure(id=pid("leaf"), value=1)
  let second = PatternDoc::pure(id=pid("leaf"), value=2)
  let cache : PatternLoweringCache[Int] = PatternLoweringCache::new()
  let first_snapshot = unwrap_snapshot(try? first.lower_with_cache(cache))
  inspect(first_snapshot.query(doc_span(0, 1, 1, 1))[0].value, content="1")
  cache.reset_stats()
  let second_snapshot = unwrap_snapshot(try? second.lower_with_cache(cache))
  inspect(second_snapshot.query(doc_span(0, 1, 1, 1))[0].value, content="2")
  inspect(cache.hit_count(), content="0")
  inspect(cache.miss_count(), content="1")
  inspect(cache.entry_count(), content="2")
}

///|
test "PatternLoweringCache does not reuse divergent replacements" {
  let left = PatternDoc::pure(id=pid("left"), value=1)
  let right = PatternDoc::pure(id=pid("right"), value=2)
  let base = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[left, right]),
  )
  let first = unwrap_doc(try? base.replace_with_pure(id=pid("left"), value=3))
  let second = unwrap_doc(try? base.replace_with_pure(id=pid("left"), value=4))
  let cache : PatternLoweringCache[Int] = PatternLoweringCache::new()
  let first_snapshot = unwrap_snapshot(try? first.lower_with_cache(cache))
  let first_events = first_snapshot.query(doc_span(0, 1, 1, 1))
  inspect(first_events[0].value, content="3")
  inspect(first_events[1].value, content="2")
  cache.reset_stats()
  let second_snapshot = unwrap_snapshot(try? second.lower_with_cache(cache))
  let second_events = second_snapshot.query(doc_span(0, 1, 1, 1))
  inspect(second_events[0].value, content="4")
  inspect(second_events[1].value, content="2")
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="2")
  inspect(cache.entry_count(), content="5")
}

///|
test "PatternDoc::replace_with_pattern swaps runtime body under stable id" {
  let doc = PatternDoc::pure(id=pid("leaf"), value=1)
  let edited = unwrap_doc(
    try? doc.replace_with_pattern(
      id=pid("leaf"),
      pat=sequence([Pat::pure(2), Pat::pure(3)]),
    ),
  )
  inspect(edited.root().value(), content="leaf")
  inspect(edited.revision().value(), content="1")
  let events = unwrap_snapshot(try? edited.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="2")
  inspect(events[1].value, content="3")
}

///|
test "PatternDoc::sequence combines child documents" {
  let a = PatternDoc::pure(id=pid("a"), value=1)
  let b = PatternDoc::pure(id=pid("b"), value=2)
  let doc = unwrap_doc(try? PatternDoc::sequence(id=pid("seq"), docs=[a, b]))
  inspect(doc.node_count(), content="3")
  inspect(doc.root().value(), content="seq")
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="1")
  inspect(events[1].value, content="2")
}

///|
test "PatternDoc::stack combines child documents in parallel" {
  let a = PatternDoc::pure(id=pid("a"), value=1)
  let b = PatternDoc::pure(id=pid("b"), value=2)
  let doc = unwrap_doc(try? PatternDoc::stack(id=pid("stack"), docs=[a, b]))
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="1")
  inspect(events[1].value, content="2")
}

///|
test "PatternDoc aggregate revisions preserve child edits" {
  let base_child = PatternDoc::pure(id=pid("leaf"), value=1)
  let edited_child = unwrap_doc(
    try? base_child.replace_with_pure(id=pid("leaf"), value=2),
  )
  let base = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[base_child]),
  )
  let edited = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[edited_child]),
  )
  inspect(base.revision().value(), content="1")
  inspect(edited.revision().value(), content="2")
  inspect(
    unwrap_snapshot(try? edited.lower()).query(doc_span(0, 1, 1, 1))[0].value,
    content="2",
  )
}

///|
test "prop: aggregate sequence revision advances with child revisions" {
  @qc.quick_check_fn(
    fn(raw : Int) {
      let base_child = PatternDoc::pure(id=pid("leaf"), value=1)
      let edited_child = edited_leaf_doc(raw, 2)
      let base = unwrap_doc(
        try? PatternDoc::sequence(id=pid("seq"), docs=[base_child]),
      )
      let edited = unwrap_doc(
        try? PatternDoc::sequence(id=pid("seq"), docs=[edited_child]),
      )
      edited.revision().value() > base.revision().value() &&
      edited.revision().value() == edited_child.revision().value() + 1L
    },
    max_success=50,
  )
}

///|
test "prop: aggregate stack revision advances with child revisions" {
  @qc.quick_check_fn(
    fn(raw : Int) {
      let base_child = PatternDoc::pure(id=pid("leaf"), value=1)
      let edited_child = edited_leaf_doc(raw, 2)
      let base = unwrap_doc(
        try? PatternDoc::stack(id=pid("stack"), docs=[base_child]),
      )
      let edited = unwrap_doc(
        try? PatternDoc::stack(id=pid("stack"), docs=[edited_child]),
      )
      edited.revision().value() > base.revision().value() &&
      edited.revision().value() == edited_child.revision().value() + 1L
    },
    max_success=50,
  )
}

///|
test "PatternDoc aggregate revisions distinguish shifted child revisions" {
  let left_one = unwrap_doc(
    try? PatternDoc::pure(id=pid("left"), value=1).replace_with_pure(
      id=pid("left"),
      value=2,
    ),
  )
  let right_one = unwrap_doc(
    try? PatternDoc::pure(id=pid("right"), value=10).replace_with_pure(
      id=pid("right"),
      value=11,
    ),
  )
  let left_two = unwrap_doc(
    try? left_one.replace_with_pure(id=pid("left"), value=3),
  )
  let right_zero = PatternDoc::pure(id=pid("right"), value=10)
  let first = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[left_one, right_one]),
  )
  let second = unwrap_doc(
    try? PatternDoc::sequence(id=pid("seq"), docs=[left_two, right_zero]),
  )
  assert_true(first.revision() != second.revision())
  let first_events = unwrap_snapshot(try? first.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  let second_events = unwrap_snapshot(try? second.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  assert_true(first_events[0].value != second_events[0].value)
}

///|
test "prop: aggregate sequence revisions distinguish child revision vectors" {
  @qc.quick_check_fn(
    fn(raw : (Int, Int, Int, Int)) {
      let (raw_left_a, raw_right_a, raw_left_b, raw_right_b) = raw
      let left_a = raw_left_a.abs() % 8
      let right_a = raw_right_a.abs() % 8
      let left_b = raw_left_b.abs() % 8
      let right_b = raw_right_b.abs() % 8
      let first = unwrap_doc(
        try? PatternDoc::sequence(id=pid("seq"), docs=[
          revisioned_leaf_doc("left", left_a, 10),
          revisioned_leaf_doc("right", right_a, 20),
        ]),
      )
      let second = unwrap_doc(
        try? PatternDoc::sequence(id=pid("seq"), docs=[
          revisioned_leaf_doc("left", left_b, 10),
          revisioned_leaf_doc("right", right_b, 20),
        ]),
      )
      if left_a == left_b && right_a == right_b {
        first.revision() == second.revision()
      } else {
        first.revision() != second.revision()
      }
    },
    max_success=50,
  )
}

///|
test "PatternDoc::with_root selects an existing stable node" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=1).fast(
      id=pid("fast"),
      factor=Rational::from_int(2),
    ),
  )
  let rerooted = unwrap_doc(try? doc.with_root(root=pid("leaf")))
  inspect(rerooted.root().value(), content="leaf")
  inspect(rerooted.revision().value(), content="2")
  let events = unwrap_snapshot(try? rerooted.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  inspect(events.length(), content="1")
}

///|
test "PatternDoc::slow and rev lower through runtime combinators" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=1).slow(
      id=pid("slow"),
      factor=Rational::from_int(2),
    ),
  )
  let revved = unwrap_doc(try? doc.rev(id=pid("rev")))
  inspect(revved.root().value(), content="rev")
  inspect(revved.revision().value(), content="2")
  let events = unwrap_snapshot(try? revved.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
}

///|
test "PatternDoc::filter_map lowers through runtime combinator" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=2).filter_map(
      id=pid("filter"),
      f=fn(value) { if value > 1 { Some(value * 10) } else { None } },
    ),
  )
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  inspect(events[0].value, content="20")
}

///|
test "PatternDoc::euclid lowers through runtime combinator" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=1).euclid(
      id=pid("euclid"),
      k=3,
      n=8,
    ),
  )
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  inspect(events[0].part.begin, content="{ num: 0, den: 1 }")
  inspect(events[1].part.begin, content="{ num: 3, den: 8 }")
  inspect(events[2].part.begin, content="{ num: 3, den: 4 }")
}

///|
test "PatternDoc::degrade_by lowers through runtime combinator" {
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=1).degrade_by(
      id=pid("drop"),
      p=1.0,
      seed=7,
    ),
  )
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "PatternDoc::every lowers through runtime combinator" {
  let double_speed : (Pat[Int]) -> Pat[Int] = fn(p) {
    p.fast(Rational::from_int(2))
  }
  let doc = unwrap_doc(
    try? PatternDoc::pure(id=pid("leaf"), value=1).every(
      id=pid("every"),
      n=2,
      f=double_speed,
    ),
  )
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 2, 1))
  inspect(events.length(), content="3")
}

///|
test "PatternDoc::jux lowers through control-map runtime combinator" {
  let doc = PatternDoc::from_pattern(
    id=pid("sound"),
    pat=sequence([sound(36.0), sound(38.0)]),
  )
  let juxed = unwrap_doc(try? doc.jux(id=pid("jux"), f=fn(p) { p.rev() }))
  inspect(juxed.revision().value(), content="1")
  let events = unwrap_snapshot(try? juxed.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="4")
  let (pan_neg1, pan_pos1) = for event in events; neg = 0, pos = 0 {
    match event.value.get("pan") {
      Some(-1.0) => continue neg + 1, pos
      Some(1.0) => continue neg, pos + 1
      _ => continue neg, pos
    }
  } nobreak {
    (neg, pos)
  }
  inspect(pan_neg1, content="2")
  inspect(pan_pos1, content="2")
}

///|
test "PatternDoc::merge_control lowers through control-map runtime combinator" {
  let note_doc = PatternDoc::from_pattern(id=pid("note"), pat=note(60.0))
  let gain_doc = PatternDoc::from_pattern(id=pid("gain"), pat=s_gain(0.5))
  let merged = unwrap_doc(
    try? PatternDoc::merge_control(
      id=pid("merge"),
      left=note_doc,
      right=gain_doc,
    ),
  )
  inspect(merged.revision().value(), content="1")
  let events = unwrap_snapshot(try? merged.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[0].value.get("gain") == Some(0.5))
}

///|
test "PatternDoc::merge_control revision changes when lower-revision input changes" {
  let note_doc = PatternDoc::from_pattern(id=pid("note"), pat=note(60.0))
  let note_doc = unwrap_doc(
    try? note_doc.replace_with_pattern(id=pid("note"), pat=note(61.0)),
  )
  let note_doc = unwrap_doc(
    try? note_doc.replace_with_pattern(id=pid("note"), pat=note(62.0)),
  )
  let note_doc = unwrap_doc(
    try? note_doc.replace_with_pattern(id=pid("note"), pat=note(63.0)),
  )
  let gain_doc = PatternDoc::from_pattern(id=pid("gain"), pat=s_gain(0.5))
  let edited_gain_doc = unwrap_doc(
    try? gain_doc.replace_with_pattern(id=pid("gain"), pat=s_gain(0.75)),
  )
  let base = unwrap_doc(
    try? PatternDoc::merge_control(
      id=pid("merge"),
      left=note_doc,
      right=gain_doc,
    ),
  )
  let edited = unwrap_doc(
    try? PatternDoc::merge_control(
      id=pid("merge"),
      left=note_doc,
      right=edited_gain_doc,
    ),
  )
  assert_true(base.revision() != edited.revision())
  let events = unwrap_snapshot(try? edited.lower()).query(doc_span(0, 1, 1, 1))
  assert_true(events[0].value.get("gain") == Some(0.75))
}

///|
test "PatternDoc rejects duplicate node ids" {
  let doc = PatternDoc::pure(id=pid("leaf"), value=1)
  let result = try? doc.fast(id=pid("leaf"), factor=Rational::from_int(2))
  match result {
    Err(PatternDocError::DuplicateNodeId("leaf")) => ()
    _ => abort("expected duplicate node id")
  }
}

///|
test "PatternDoc rejects duplicate ids across combined docs" {
  let a = PatternDoc::pure(id=pid("leaf"), value=1)
  let b = PatternDoc::pure(id=pid("leaf"), value=2)
  let result = try? PatternDoc::sequence(id=pid("seq"), docs=[a, b])
  match result {
    Err(PatternDocError::DuplicateNodeId("leaf")) => ()
    _ => abort("expected duplicate node id")
  }
}

///|
test "PatternDoc rejects missing edit target" {
  let doc = PatternDoc::pure(id=pid("leaf"), value=1)
  let result = try? doc.replace_with_silence(id=pid("missing"))
  match result {
    Err(PatternDocError::MissingNode("missing")) => ()
    _ => abort("expected missing node")
  }
}

///|
test "PatternDoc rejects empty sequence documents" {
  let docs : Array[PatternDoc[Int]] = []
  let result = try? PatternDoc::sequence(id=pid("seq"), docs~)
  match result {
    Err(PatternDocError::EmptyPatternDocs) => ()
    _ => abort("expected empty pattern docs")
  }
}

///|
test "PatternDoc::from_pattern wraps existing runtime patterns" {
  let doc = PatternDoc::from_pattern(
    id=pid("runtime"),
    pat=sequence([Pat::pure(1), Pat::pure(2)]),
  )
  let events = unwrap_snapshot(try? doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="1")
  inspect(events[1].value, content="2")
}
