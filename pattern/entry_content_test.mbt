///|
test "editing event controls leaves source content unchanged" {
  let source = @pattern.note(60.0)
  let arc = span(0, 1, 1, 1)
  let value = source.query(arc)[0].value
  let with_lpf = value.set("lpf", 800.0)
  let replaced = with_lpf.merge(@pattern.ControlMap::single("note", 72.0))
  let exported = replaced.entries()
  exported["note"] = 12.0
  assert_eq(with_lpf.entries(), { "note": 60.0, "lpf": 800.0 })
  assert_eq(replaced.entries(), { "note": 72.0, "lpf": 800.0 })
  assert_eq(source.query(arc)[0].value.entries(), { "note": 60.0 })
  assert_true(source.same_content(@pattern.note(60.0)))
}

///|
test "content comparison distinguishes values but ignores grouped names" {
  let a = @pattern.stack([@pattern.note(60.0).named_entry("a")]).material()
  let b = @pattern.stack([@pattern.note(60.0).named_entry("b")]).material()
  let changed = @pattern.stack([@pattern.note(61.0).named_entry("a")]).material()
  assert_true(a.same_content(b))
  assert_false(a.same_content(changed))
}

///|
test "sequence owns its inputs so content and events stay consistent" {
  let inputs = [@pattern.note(60.0)]
  let sequence = @pattern.sequence(inputs)
  inputs[0] = @pattern.note(72.0)
  assert_eq(sequence.query(span(0, 1, 1, 1))[0].value.get("note"), Some(60.0))
  assert_true(sequence.same_content(@pattern.sequence([@pattern.note(60.0)])))
}

///|
test "control selection tracks both predicate and selected events" {
  let source = @pattern.stack([@pattern.note(60.0), @pattern.sound(36.0)])
  let notes = source.select_control("note")
  let missing = source.select_control("sound", value=38.0)
  assert_eq(notes.query(span(0, 1, 1, 1)).map(e => e.value.entries()), [
    { "note": 60.0 },
  ])
  assert_eq(missing.query(span(0, 1, 1, 1)).length(), 0)
  assert_true(notes.same_content(source.select_control("note")))
  assert_false(missing.same_content(source.select_control("sound", value=36.0)))
}

///|
test "known time operations track their operation and parameters" {
  let source = @pattern.note(60.0)
  let reverse = @pattern.TimeTransform::Reverse
  let fast = @pattern.TimeTransform::Fast(@pattern.Rational::from_int(2))
  assert_true(reverse.every(2, source).same_content(reverse.every(2, source)))
  assert_false(reverse.every(2, source).same_content(reverse.every(3, source)))
  assert_true(reverse.jux(source).same_content(reverse.jux(source)))
  assert_false(reverse.jux(source).same_content(fast.jux(source)))
}

///|
test "grouping and known transforms cannot identify arbitrary code" {
  let unknown = @pattern.Pat::from_query(@pattern.note(60.0).query)
  assert_false(unknown.same_content(unknown))
  let grouped = unknown.material().slow(@pattern.Rational::from_int(3))
  assert_false(grouped.same_content(grouped))
  let filtered = @pattern.note(60.0).filter_map(v => Some(v)).material()
  assert_false(filtered.same_content(filtered))
  let combined = @pattern.stack([@pattern.note(60.0), unknown]).material()
  assert_false(combined.same_content(combined))
}

///|
test "overlay content ignores subgroup names and material boundaries" {
  let a = @pattern.note(60.0)
  let b = @pattern.note(64.0)
  let c = @pattern.note(67.0)
  let plain = (a + b + c).material()
  let arc = span(0, 1, 2, 1)
  for subgroup in [(a + b).named_entry("phrase"), (a + b).material()] {
    let annotated = (subgroup + c).material()
    assert_eq(
      annotated.query(arc).map(e => (e.whole, e.part, e.value.entries())),
      plain.query(arc).map(e => (e.whole, e.part, e.value.entries())),
    )
    assert_true(annotated.same_content(plain))
    assert_true(annotated.rev().same_content(plain.rev()))
  }
}

///|
test "silent playback placeholders do not change overlay content" {
  let a = @pattern.note(60.0)
  let silent = @pattern.Pat::silence().named_entry("rest")
  let annotated = a + silent
  assert_eq(annotated.entries().length(), 2)
  assert_true(annotated.material().same_content(a.material()))
  assert_true(
    (silent + silent)
    .material()
    .same_content(@pattern.Pat::silence().material()),
  )
}

///|
test "content normalization preserves opaque queries order and unknown callbacks" {
  let a = @pattern.note(60.0)
  let b = @pattern.note(64.0)
  let c = @pattern.note(67.0)
  let wrapped = (a + b).rev().named_entry("reversed")
  assert_false(
    (wrapped + c).material().same_content((a.rev() + b.rev() + c).material()),
  )
  assert_false((a + b).material().same_content((b + a).material()))
  assert_false((a + a).material().same_content(a.material()))
  let unknown = (a + b).filter_map(v => Some(v)).named_entry("unknown")
  let combined = (unknown + c).material()
  assert_false(combined.same_content(combined))
}
