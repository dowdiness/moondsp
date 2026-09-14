///|
test "overlay associativity preserves ordered events content and entry addresses" {
  let a = @pattern.note(48.0)
  let b = @pattern.note(60.0)
  let c = @pattern.note(72.0)
  let flat = @pattern.stack([a, b, c])
  let arc = span(0, 1, 2, 1)
  assert_eq(flat.query(arc).map(e => e.value.get("note")), [
    Some(48.0),
    Some(48.0),
    Some(60.0),
    Some(60.0),
    Some(72.0),
    Some(72.0),
  ])
  for
    grouped in [
      a + b + c,
      a + (b + c),
      @pattern.stack([@pattern.stack([a, b]), c]),
    ] {
    @debug.assert_eq(
      grouped.query(arc).map(e => (e.whole, e.part, e.value.entries())),
      flat.query(arc).map(e => (e.whole, e.part, e.value.entries())),
    )
    assert_true(grouped.material().same_content(flat.material()))
    assert_eq(
      grouped.entries().map(p => p.entry_key()),
      flat.entries().map(p => p.entry_key()),
    )
  }
}

///|
test "overlay removes anonymous silence but owns inputs and preserves duplicates" {
  let a = @pattern.note(60.0).slow(@pattern.Rational::from_int(3))
  let silent = @pattern.Pat::silence()
  assert_true(@pattern.stack([silent, a, silent]).same_content(a))
  assert_true(@pattern.stack([a]).same_content(a))
  let empty : @pattern.Pat[@pattern.ControlMap] = @pattern.stack([])
  assert_true(empty.same_content(silent))
  let inputs = [a, silent, a]
  let combined = @pattern.stack(inputs)
  inputs[0] = @pattern.note(72.0)
  assert_eq(combined.query(span(0, 1, 1, 1)).map(e => e.value.get("note")), [
    Some(60.0),
    Some(60.0),
  ])
  assert_true(combined.same_content(a + a))
}

///|
test "normalization does not rebuild reverse queries from entry projections" {
  let a = @pattern.note(60.0)
  let b = @pattern.note(72.0)
  let c = @pattern.note(84.0)
  let reversed = (a + b).rev()
  let arc = span(0, 1, 2, 1)
  let actual = @pattern.stack([reversed, c]).query(arc)
  @debug.assert_eq(
    actual.map(e => (e.whole, e.part, e.value.entries())),
    (reversed.query(arc) + c.query(arc)).map(e => {
      (e.whole, e.part, e.value.entries())
    }),
  )
  assert_eq(actual.map(e => e.value.get("note")), [
    Some(60.0),
    Some(72.0),
    Some(60.0),
    Some(72.0),
    Some(84.0),
    Some(84.0),
  ])
}

///|
test "names anchor independent clocks while material explicitly groups them" {
  let three = @pattern.Rational::from_int(3)
  let four = @pattern.Rational::from_int(4)
  let named = (@pattern.note(60.0).slow(three) + @pattern.note(72.0).slow(four)).named_entry(
    "phrase",
  )
  assert_eq(named.entries().map(p => p.entry_period()), [three, four])
  assert_eq(named.material().entries().length(), 1)
  let two = @pattern.Rational::from_int(2)
  let grouped = named.material().slow(two).entries()[0]
  assert_eq(
    (grouped + @pattern.note(84.0).slow(three))
    .entries()
    .map(p => p.entry_period()),
    [two, three],
  )
  let rest : @pattern.Pat[Int] = @pattern.Pat::silence()
    .slow(three)
    .named_entry("rest")
  assert_eq(rest.entries().map(p => p.entry_period()), [three])
  assert_true(rest.query(span(0, 1, 4, 1)).is_empty())
}
