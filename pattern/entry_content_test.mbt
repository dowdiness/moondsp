///|
test "event control edits do not mutate identified source content" {
  let source = @pattern.note(60.0)
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let value = source.query(arc)[0].value
  let exported = value.entries()
  exported["note"] = 12.0
  let changed = value.set("note", 72.0)
  let merged = value.merge(@pattern.ControlMap::single("note", 84.0))
  assert_eq(changed.get("note"), Some(72.0))
  assert_eq(merged.get("note"), Some(84.0))
  assert_eq(source.query(arc)[0].value.get("note"), Some(60.0))
  assert_true(source.same_content(@pattern.note(60.0)))
}

///|
test "content comparison follows source values, selections and time operations" {
  let a = @pattern.stack([@pattern.note(60.0), @pattern.sound(36.0)])
  let b = @pattern.stack([@pattern.note(60.0), @pattern.sound(36.0)])
  assert_true(a.same_content(b))
  assert_true(
    @pattern.stack([@pattern.note(60.0).named_entry("a")])
    .material()
    .same_content(
      @pattern.stack([@pattern.note(60.0).named_entry("b")]).material(),
    ),
  )
  let inputs = [@pattern.note(60.0)]
  let sequence = @pattern.sequence(inputs)
  inputs[0] = @pattern.note(72.0)
  assert_true(sequence.same_content(@pattern.sequence([@pattern.note(60.0)])))
  assert_false(
    a.same_content(@pattern.stack([@pattern.note(61.0), @pattern.sound(36.0)])),
  )
  assert_true(a.select_control("note").same_content(b.select_control("note")))
  assert_false(
    a
    .select_control("sound", value=36.0)
    .same_content(b.select_control("sound", value=38.0)),
  )
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  assert_eq(sequence.query(arc).map(e => e.value.get("note").unwrap()), [60.0])
  assert_eq(
    a.select_control("note").query(arc).map(e => e.value.get("note").unwrap()),
    [60.0],
  )
  assert_eq(a.select_control("sound", value=38.0).query(arc).length(), 0)
  let reverse = @pattern.TimeTransform::Reverse
  assert_true(reverse.every(2, a).same_content(reverse.every(2, b)))
  assert_false(reverse.every(2, a).same_content(reverse.every(3, b)))
  assert_true(reverse.jux(a).same_content(reverse.jux(b)))
  assert_false(
    reverse
    .jux(a)
    .same_content(
      @pattern.TimeTransform::Fast(@pattern.Rational::from_int(2)).jux(b),
    ),
  )
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
