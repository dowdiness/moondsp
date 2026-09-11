///|
test "editing event controls leaves source content unchanged" {
  let source = @pattern.note(60.0)
  let arc = span(0, 1, 1, 1)
  let value = source.query(arc)[0].value
  let with_cutoff = value.set("cutoff", 800.0)
  let replaced = with_cutoff.merge(@pattern.ControlMap::single("note", 72.0))
  let exported = replaced.entries()
  exported["note"] = 12.0
  assert_eq(with_cutoff.entries(), { "note": 60.0, "cutoff": 800.0 })
  assert_eq(replaced.entries(), { "note": 72.0, "cutoff": 800.0 })
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
