///|
fn pid(value : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string(value) catch {
    _ => abort("expected valid pattern node id")
  }
}

///|
fn doc_span(
  b_num : Int32,
  b_den : Int32,
  e_num : Int32,
  e_den : Int32,
) -> @pattern.TimeSpan {
  @pattern.TimeSpan(
    @pattern.Rational(b_num.to_int64(), b_den.to_int64()),
    @pattern.Rational(e_num.to_int64(), e_den.to_int64()),
  )
}

///|
fn unwrap_doc(
  build : () -> @pattern.PatternDoc[@pattern.ControlMap] raise @pattern.PatternDocError,
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  build() catch {
    _ => abort("expected pattern doc")
  }
}

///|
fn unwrap_snapshot(
  build : () -> @pattern.PatternSnapshot[@pattern.ControlMap] raise @pattern.PatternDocError,
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  build() catch {
    _ => abort("expected pattern snapshot")
  }
}

///|
fn assert_pattern_event_path(
  event : @pattern.PatternSnapshotEvent[@pattern.ControlMap],
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
  build : () -> @identity.Revision raise @pattern.PatternDocError,
) -> @identity.Revision {
  build() catch {
    _ => abort("expected pattern node revision")
  }
}

///|
fn edited_leaf_doc(
  edit_count : Int32,
  value : Int32,
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  let count = edit_count.abs() % 8 + 1
  let mut doc = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(value))
  for i in 0..<count {
    doc = unwrap_doc(() => {
      doc.replace_with_pure(id=pid("leaf"), value=n(value + i))
    })
  }
  doc
}

///|
fn revisioned_leaf_doc(
  id_value : String,
  revision : Int32,
  value : Int32,
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  let mut doc = @pattern.PatternDoc::pure(id=pid(id_value), value=n(value))
  for i in 0..<revision {
    doc = unwrap_doc(() => {
      doc.replace_with_pure(id=pid(id_value), value=n(value + i + 1))
    })
  }
  doc
}

///|
test "PatternDoc::pure lowers to runtime Pat" {
  let doc = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(7))
  let snapshot = unwrap_snapshot(() => doc.lower())
  inspect(snapshot.revision().value(), content="0")
  inspect(snapshot.root().value(), content="leaf")
  let events = snapshot.query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  @debug.assert_eq(events[0].value, n(7))
}

///|
test "PatternDoc::fast adds stable root and bumps revision" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(7)).fast(
      id=pid("fast"),
      factor=@pattern.Rational::from_int(2),
    )
  })
  inspect(doc.root().value(), content="fast")
  inspect(doc.revision().value(), content="1")
  inspect(doc.node_count(), content="2")
  assert_true(doc.contains_node(pid("leaf")))
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
}

///|
test "PatternSnapshot::query_sourced_events tags fast ancestor and leaf path" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(7)).fast(
      id=pid("fast"),
      factor=@pattern.Rational::from_int(2),
    )
  })
  let snapshot = unwrap_snapshot(() => doc.lower())
  let events = snapshot.query_sourced_events(doc_span(0, 1, 1, 1))
  let raw_events = snapshot.query(doc_span(0, 1, 1, 1))
  @debug.assert_eq(events.length(), raw_events.length())
  @debug.assert_eq(events.length(), 2)
  assert_pattern_event_path(events[0], ["fast", "leaf"])
  assert_pattern_event_path(events[1], ["fast", "leaf"])
  assert_true(events[0].pattern_node_path().leaf() == pid("leaf"))
  assert_true(events[0].event().value == raw_events[0].value)
  assert_true(events[1].event().part.begin == raw_events[1].part.begin)
}

///|
test "PatternSnapshot::query_sourced_events tags sequence and stack children" {
  let left = @pattern.PatternDoc::pure(id=pid("left"), value=n(1))
  let right = @pattern.PatternDoc::pure(id=pid("right"), value=n(2))
  let seq = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[left, right])
  })
  let seq_events = unwrap_snapshot(() => seq.lower()).query_sourced_events(
    doc_span(0, 1, 1, 1),
  )
  @debug.assert_eq(seq_events.length(), 2)
  assert_pattern_event_path(seq_events[0], ["seq", "left"])
  assert_pattern_event_path(seq_events[1], ["seq", "right"])
  assert_true(seq_events[0].event().value == n(1))
  assert_true(seq_events[1].event().value == n(2))
  let stack = unwrap_doc(() => {
    @pattern.PatternDoc::stack(id=pid("stack"), docs=[
      @pattern.PatternDoc::pure(id=pid("stack-left"), value=n(3)),
      @pattern.PatternDoc::pure(id=pid("stack-right"), value=n(4)),
    ])
  })
  let stack_events = unwrap_snapshot(() => stack.lower()).query_sourced_events(
    doc_span(0, 1, 1, 1),
  )
  @debug.assert_eq(stack_events.length(), 2)
  assert_pattern_event_path(stack_events[0], ["stack", "stack-left"])
  assert_pattern_event_path(stack_events[1], ["stack", "stack-right"])
}

///|
test "PatternSnapshot::query_sourced_events covers every callback subtrees" {
  let child = unwrap_doc(() => {
    @pattern.PatternDoc::stack(id=pid("every-stack"), docs=[
      @pattern.PatternDoc::pure(id=pid("every-left"), value=n(1)),
      @pattern.PatternDoc::pure(id=pid("every-right"), value=n(2)),
    ])
  })
  let doc = unwrap_doc(() => {
    child.every(
      id=pid("every"),
      n=1,
      transform=@pattern.TimeTransform::Fast(@pattern.Rational::from_int(2)),
    )
  })
  let events = unwrap_snapshot(() => doc.lower()).query_sourced_events(
    doc_span(0, 1, 1, 100),
  )
  assert_true(events.length() > 0)
  assert_pattern_event_path(events[0], [
    "every", "every-stack", "every-left", "every-right",
  ])
}

///|
test "PatternSnapshot::query_sourced_events covers jux callback subtrees" {
  let child = unwrap_doc(() => {
    @pattern.PatternDoc::stack(id=pid("jux-stack"), docs=[
      @pattern.PatternDoc::from_pattern(
        id=pid("jux-left"),
        pat=@pattern.control(Note, 60.0),
      ),
      @pattern.PatternDoc::from_pattern(
        id=pid("jux-right"),
        pat=@pattern.control(Note, 67.0),
      ),
    ])
  })
  let doc = unwrap_doc(() => {
    child.jux(
      id=pid("jux"),
      transform=@pattern.TimeTransform::Fast(@pattern.Rational::from_int(2)),
    )
  })
  let events = unwrap_snapshot(() => doc.lower()).query_sourced_events(
    doc_span(0, 1, 1, 100),
  )
  assert_true(events.length() > 0)
  assert_pattern_event_path(events[0], [
    "jux", "jux-stack", "jux-left", "jux-right",
  ])
}

///|
test "PatternSnapshot::query_sourced_events covers merge_control inputs" {
  let left = @pattern.PatternDoc::from_pattern(
    id=pid("merge-left"),
    pat=@pattern.control(Note, 60.0),
  )
  let right = @pattern.PatternDoc::control_atom(
    id=pid("merge-right"),
    key=Lpf,
    value=800.0,
  )
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::merge_control(id=pid("merge"), left~, right~)
  })
  let events = unwrap_snapshot(() => doc.lower()).query_sourced_events(
    doc_span(0, 1, 1, 100),
  )
  @debug.assert_eq(events.length(), 1)
  assert_pattern_event_path(events[0], ["merge", "merge-left", "merge-right"])
  assert_true(events[0].event().value.get(Note) == Some(60.0))
  assert_true(events[0].event().value.get(Lpf) == Some(800.0))
}

///|
test "PatternDoc edit preserves ids and changes lowered future events" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1)).fast(
      id=pid("fast"),
      factor=@pattern.Rational::from_int(2),
    )
  })
  let edited = unwrap_doc(() => {
    doc.replace_with_pure(id=pid("leaf"), value=n(2))
  })
  inspect(edited.root().value(), content="fast")
  inspect(edited.revision().value(), content="2")
  assert_true(edited.contains_node(pid("leaf")))
  let events = unwrap_snapshot(() => edited.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  @debug.assert_eq(events[0].value, n(2))
  @debug.assert_eq(events[1].value, n(2))
}

///|
test "PatternDoc snapshot remains stable after document edit" {
  let doc = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  let snapshot = unwrap_snapshot(() => doc.lower())
  let edited = unwrap_doc(() => {
    doc.replace_with_pure(id=pid("leaf"), value=n(2))
  })
  let old_events = snapshot.query(doc_span(0, 1, 1, 1))
  let new_events = unwrap_snapshot(() => edited.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  @debug.assert_eq(old_events[0].value, n(1))
  @debug.assert_eq(new_events[0].value, n(2))
}

///|
test "PatternDoc node revisions invalidate ancestors but not siblings" {
  let left = @pattern.PatternDoc::pure(id=pid("left"), value=n(1))
  let right = @pattern.PatternDoc::pure(id=pid("right"), value=n(2))
  let base = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[left, right])
  })
  let edited = unwrap_doc(() => {
    base.replace_with_pure(id=pid("left"), value=n(3))
  })
  let base_left = unwrap_revision(() => base.node_revision(pid("left")))
  let edited_left = unwrap_revision(() => edited.node_revision(pid("left")))
  let base_right = unwrap_revision(() => base.node_revision(pid("right")))
  let edited_right = unwrap_revision(() => edited.node_revision(pid("right")))
  let base_root = unwrap_revision(() => base.node_revision(pid("seq")))
  let edited_root = unwrap_revision(() => edited.node_revision(pid("seq")))
  assert_true(base_left != edited_left)
  assert_true(base_right == edited_right)
  assert_true(base_root != edited_root)
}

///|
test "PatternLoweringCache reuses unchanged child after pattern edit" {
  let left = @pattern.PatternDoc::pure(id=pid("left"), value=n(1))
  let right = @pattern.PatternDoc::pure(id=pid("right"), value=n(2))
  let base = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[left, right])
  })
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(unwrap_snapshot(() => base.lower_with_cache(cache)))
  inspect(cache.hit_count(), content="0")
  inspect(cache.miss_count(), content="3")
  inspect(cache.entry_count(), content="3")
  let edited_left = unwrap_doc(() => {
    left.replace_with_pure(id=pid("left"), value=n(3))
  })
  let edited = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[edited_left, right])
  })
  cache.reset_stats()
  let snapshot = unwrap_snapshot(() => edited.lower_with_cache(cache))
  let events = snapshot.query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  @debug.assert_eq(events[0].value, n(3))
  @debug.assert_eq(events[1].value, n(2))
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="2")
  inspect(cache.entry_count(), content="5")
  cache.reset_stats()
  ignore(unwrap_snapshot(() => edited.lower_with_cache(cache)))
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="0")
}

///|
test "PatternLoweringCache does not reuse fresh doc with same id and revision" {
  let first = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  let second = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(2))
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  let first_snapshot = unwrap_snapshot(() => first.lower_with_cache(cache))
  @debug.assert_eq(first_snapshot.query(doc_span(0, 1, 1, 1))[0].value, n(1))
  cache.reset_stats()
  let second_snapshot = unwrap_snapshot(() => second.lower_with_cache(cache))
  @debug.assert_eq(second_snapshot.query(doc_span(0, 1, 1, 1))[0].value, n(2))
  inspect(cache.hit_count(), content="0")
  inspect(cache.miss_count(), content="1")
  inspect(cache.entry_count(), content="2")
}

///|
test "PatternLoweringCache does not reuse divergent replacements" {
  let left = @pattern.PatternDoc::pure(id=pid("left"), value=n(1))
  let right = @pattern.PatternDoc::pure(id=pid("right"), value=n(2))
  let base = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[left, right])
  })
  let first = unwrap_doc(() => {
    base.replace_with_pure(id=pid("left"), value=n(3))
  })
  let second = unwrap_doc(() => {
    base.replace_with_pure(id=pid("left"), value=n(4))
  })
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  let first_snapshot = unwrap_snapshot(() => first.lower_with_cache(cache))
  let first_events = first_snapshot.query(doc_span(0, 1, 1, 1))
  @debug.assert_eq(first_events[0].value, n(3))
  @debug.assert_eq(first_events[1].value, n(2))
  cache.reset_stats()
  let second_snapshot = unwrap_snapshot(() => second.lower_with_cache(cache))
  let second_events = second_snapshot.query(doc_span(0, 1, 1, 1))
  @debug.assert_eq(second_events[0].value, n(4))
  @debug.assert_eq(second_events[1].value, n(2))
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="2")
  inspect(cache.entry_count(), content="5")
}

///|
test "PatternDoc::replace_with_pattern swaps runtime body under stable id" {
  let doc = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  let edited = unwrap_doc(() => {
    doc.replace_with_pattern(
      id=pid("leaf"),
      pat=@pattern.sequence([@pattern.Pat::pure(n(2)), @pattern.Pat::pure(n(3))]),
    )
  })
  inspect(edited.root().value(), content="leaf")
  inspect(edited.revision().value(), content="1")
  let events = unwrap_snapshot(() => edited.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  @debug.assert_eq(events[0].value, n(2))
  @debug.assert_eq(events[1].value, n(3))
}

///|
test "PatternDoc::sequence combines child documents" {
  let a = @pattern.PatternDoc::pure(id=pid("a"), value=n(1))
  let b = @pattern.PatternDoc::pure(id=pid("b"), value=n(2))
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[a, b])
  })
  inspect(doc.node_count(), content="3")
  inspect(doc.root().value(), content="seq")
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  @debug.assert_eq(events[0].value, n(1))
  @debug.assert_eq(events[1].value, n(2))
}

///|
test "PatternDoc::stack combines child documents in parallel" {
  let a = @pattern.PatternDoc::pure(id=pid("a"), value=n(1))
  let b = @pattern.PatternDoc::pure(id=pid("b"), value=n(2))
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::stack(id=pid("stack"), docs=[a, b])
  })
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  @debug.assert_eq(events[0].value, n(1))
  @debug.assert_eq(events[1].value, n(2))
}

///|
test "PatternDoc aggregate revisions preserve child edits" {
  let base_child = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  let edited_child = unwrap_doc(() => {
    base_child.replace_with_pure(id=pid("leaf"), value=n(2))
  })
  let base = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[base_child])
  })
  let edited = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[edited_child])
  })
  inspect(base.revision().value(), content="1")
  inspect(edited.revision().value(), content="2")
  @debug.assert_eq(
    unwrap_snapshot(() => edited.lower()).query(doc_span(0, 1, 1, 1))[0].value,
    n(2),
  )
}

///|
test "prop: aggregate sequence revision advances with child revisions" {
  @qc.quick_check_fn(
    fn(raw : Int32) {
      let base_child = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
      let edited_child = edited_leaf_doc(raw, 2)
      let base = unwrap_doc(() => {
        @pattern.PatternDoc::sequence(id=pid("seq"), docs=[base_child])
      })
      let edited = unwrap_doc(() => {
        @pattern.PatternDoc::sequence(id=pid("seq"), docs=[edited_child])
      })
      edited.revision().value() > base.revision().value() &&
      edited.revision().value() == edited_child.revision().value() + 1L
    },
    max_success=50,
  )
}

///|
test "prop: aggregate stack revision advances with child revisions" {
  @qc.quick_check_fn(
    fn(raw : Int32) {
      let base_child = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
      let edited_child = edited_leaf_doc(raw, 2)
      let base = unwrap_doc(() => {
        @pattern.PatternDoc::stack(id=pid("stack"), docs=[base_child])
      })
      let edited = unwrap_doc(() => {
        @pattern.PatternDoc::stack(id=pid("stack"), docs=[edited_child])
      })
      edited.revision().value() > base.revision().value() &&
      edited.revision().value() == edited_child.revision().value() + 1L
    },
    max_success=50,
  )
}

///|
test "PatternDoc aggregate revisions distinguish shifted child revisions" {
  let left_one = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("left"), value=n(1)).replace_with_pure(
      id=pid("left"),
      value=n(2),
    )
  })
  let right_one = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("right"), value=n(10)).replace_with_pure(
      id=pid("right"),
      value=n(11),
    )
  })
  let left_two = unwrap_doc(() => {
    left_one.replace_with_pure(id=pid("left"), value=n(3))
  })
  let right_zero = @pattern.PatternDoc::pure(id=pid("right"), value=n(10))
  let first = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[left_one, right_one])
  })
  let second = unwrap_doc(() => {
    @pattern.PatternDoc::sequence(id=pid("seq"), docs=[left_two, right_zero])
  })
  assert_true(first.revision() != second.revision())
  let first_events = unwrap_snapshot(() => first.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  let second_events = unwrap_snapshot(() => second.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  assert_true(first_events[0].value != second_events[0].value)
}

///|
test "prop: aggregate sequence revisions distinguish child revision vectors" {
  @qc.quick_check_fn(
    fn(raw : (Int32, Int32, Int32, Int32)) {
      let (raw_left_a, raw_right_a, raw_left_b, raw_right_b) = raw
      let left_a = raw_left_a.abs() % 8
      let right_a = raw_right_a.abs() % 8
      let left_b = raw_left_b.abs() % 8
      let right_b = raw_right_b.abs() % 8
      let first = unwrap_doc(() => {
        @pattern.PatternDoc::sequence(id=pid("seq"), docs=[
          revisioned_leaf_doc("left", left_a, 10),
          revisioned_leaf_doc("right", right_a, 20),
        ])
      })
      let second = unwrap_doc(() => {
        @pattern.PatternDoc::sequence(id=pid("seq"), docs=[
          revisioned_leaf_doc("left", left_b, 10),
          revisioned_leaf_doc("right", right_b, 20),
        ])
      })
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
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1)).fast(
      id=pid("fast"),
      factor=@pattern.Rational::from_int(2),
    )
  })
  let rerooted = unwrap_doc(() => doc.with_root(root=pid("leaf")))
  inspect(rerooted.root().value(), content="leaf")
  inspect(rerooted.revision().value(), content="2")
  let events = unwrap_snapshot(() => rerooted.lower()).query(
    doc_span(0, 1, 1, 1),
  )
  inspect(events.length(), content="1")
}

///|
test "PatternDoc::slow and rev lower through runtime combinators" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1)).slow(
      id=pid("slow"),
      factor=@pattern.Rational::from_int(2),
    )
  })
  let revved = unwrap_doc(() => doc.rev(id=pid("rev")))
  inspect(revved.root().value(), content="rev")
  inspect(revved.revision().value(), content="2")
  let events = unwrap_snapshot(() => revved.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
}

///|
test "PatternDoc::filter_map lowers through runtime combinator" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(2)).filter_map(
      id=pid("filter"),
      f=fn(value) {
        if value.get(Note) is Some(note) && note > 1.0 {
          Some(value.set(Note, note * 10.0))
        } else {
          None
        }
      },
    )
  })
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  @debug.assert_eq(events[0].value, n(20))
}

///|
test "PatternDoc::euclid lowers through runtime combinator" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1)).euclid(
      id=pid("euclid"),
      k=3,
      n=8,
    )
  })
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  inspect(events[0].part.begin, content="{ num: 0, den: 1 }")
  inspect(events[1].part.begin, content="{ num: 3, den: 8 }")
  inspect(events[2].part.begin, content="{ num: 3, den: 4 }")
}

///|
test "PatternDoc::degrade_by lowers through runtime combinator" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1)).degrade_by(
      id=pid("drop"),
      p=1.0,
      seed=7,
    )
  })
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "PatternDoc::every lowers through runtime combinator" {
  let doc = unwrap_doc(() => {
    @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1)).every(
      id=pid("every"),
      n=2,
      transform=@pattern.TimeTransform::Fast(@pattern.Rational::from_int(2)),
    )
  })
  inspect(doc.revision().value(), content="1")
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 2, 1))
  inspect(events.length(), content="3")
}

///|
test "PatternDoc::jux lowers through control-map runtime combinator" {
  let doc = @pattern.PatternDoc::from_pattern(
    id=pid("sound"),
    pat=@pattern.sequence([
      @pattern.control(Note, 36.0),
      @pattern.control(Note, 38.0),
    ]),
  )
  let juxed = unwrap_doc(() => {
    doc.jux(id=pid("jux"), transform=@pattern.TimeTransform::Reverse)
  })
  inspect(juxed.revision().value(), content="1")
  let events = unwrap_snapshot(() => juxed.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="4")
  let (pan_neg1, pan_pos1) = for event in events; neg = 0, pos = 0 {
    match event.value.get(Pan) {
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
  let note_doc = @pattern.PatternDoc::from_pattern(
    id=pid("note"),
    pat=@pattern.control(Note, 60.0),
  )
  let gain_doc = @pattern.PatternDoc::control_atom(
    id=pid("gain"),
    key=Gain,
    value=0.5,
  )
  let merged = unwrap_doc(() => {
    @pattern.PatternDoc::merge_control(
      id=pid("merge"),
      left=note_doc,
      right=gain_doc,
    )
  })
  inspect(merged.revision().value(), content="1")
  let events = unwrap_snapshot(() => merged.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  assert_true(events[0].value.get(Note) == Some(60.0))
  assert_true(events[0].value.get(Gain) == Some(0.5))
}

///|
test "PatternDoc::merge_control revision changes when lower-revision input changes" {
  let note_doc = @pattern.PatternDoc::from_pattern(
    id=pid("note"),
    pat=@pattern.control(Note, 60.0),
  )
  let note_doc = unwrap_doc(() => {
    note_doc.replace_with_pattern(
      id=pid("note"),
      pat=@pattern.control(Note, 61.0),
    )
  })
  let note_doc = unwrap_doc(() => {
    note_doc.replace_with_pattern(
      id=pid("note"),
      pat=@pattern.control(Note, 62.0),
    )
  })
  let note_doc = unwrap_doc(() => {
    note_doc.replace_with_pattern(
      id=pid("note"),
      pat=@pattern.control(Note, 63.0),
    )
  })
  let gain_doc = @pattern.PatternDoc::pure(
    id=pid("gain"),
    value=@pattern.ControlMap::single(Gain, 0.5),
  )
  let edited_gain_doc = unwrap_doc(() => {
    gain_doc.replace_with_pure(
      id=pid("gain"),
      value=@pattern.ControlMap::single(Gain, 0.75),
    )
  })
  let base = unwrap_doc(() => {
    @pattern.PatternDoc::merge_control(
      id=pid("merge"),
      left=note_doc,
      right=gain_doc,
    )
  })
  let edited = unwrap_doc(() => {
    @pattern.PatternDoc::merge_control(
      id=pid("merge"),
      left=note_doc,
      right=edited_gain_doc,
    )
  })
  assert_true(base.revision() != edited.revision())
  let events = unwrap_snapshot(() => edited.lower()).query(doc_span(0, 1, 1, 1))
  assert_true(events[0].value.get(Gain) == Some(0.75))
}

///|
test "PatternDoc rejects duplicate node ids" {
  let doc = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  try doc.fast(id=pid("leaf"), factor=@pattern.Rational::from_int(2)) catch {
    @pattern.PatternDocError::DuplicateNodeId("leaf") => ()
    _ => abort("expected duplicate node id")
  } noraise {
    _ => abort("expected duplicate node id")
  }
}

///|
test "PatternDoc rejects duplicate ids across combined docs" {
  let a = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  let b = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(2))
  try @pattern.PatternDoc::sequence(id=pid("seq"), docs=[a, b]) catch {
    @pattern.PatternDocError::DuplicateNodeId("leaf") => ()
    _ => abort("expected duplicate node id")
  } noraise {
    _ => abort("expected duplicate node id")
  }
}

///|
test "PatternDoc rejects missing edit target" {
  let doc = @pattern.PatternDoc::pure(id=pid("leaf"), value=n(1))
  try doc.replace_with_silence(id=pid("missing")) catch {
    @pattern.PatternDocError::MissingNode("missing") => ()
    _ => abort("expected missing node")
  } noraise {
    _ => abort("expected missing node")
  }
}

///|
test "PatternDoc rejects empty sequence documents" {
  let docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  try @pattern.PatternDoc::sequence(id=pid("seq"), docs~) catch {
    @pattern.PatternDocError::EmptyPatternDocs => ()
    _ => abort("expected empty pattern docs")
  } noraise {
    _ => abort("expected empty pattern docs")
  }
}

///|
test "PatternDoc::from_pattern wraps existing runtime patterns" {
  let doc = @pattern.PatternDoc::from_pattern(
    id=pid("runtime"),
    pat=@pattern.sequence([@pattern.Pat::pure(n(1)), @pattern.Pat::pure(n(2))]),
  )
  let events = unwrap_snapshot(() => doc.lower()).query(doc_span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  @debug.assert_eq(events[0].value, n(1))
  @debug.assert_eq(events[1].value, n(2))
}

///|
/// A payload that stands for the number `value`, for structural tests.
fn n(value : Int32) -> @pattern.ControlMap {
  @pattern.ControlMap::single(Note, value.to_double())
}
