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
