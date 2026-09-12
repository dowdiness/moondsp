///|
test "named entry identities survive reordering and unchanged material stays unchanged" {
  let a = @mini.parse(
      "let a = note(\"60\").slow(3); let b = note(\"72\").slow(4); stack(a,b)",
    )
    .unwrap()
    .entries()
  let b = @mini.parse(
      "let a = note(\"60\").slow(3); let b = note(\"74\").slow(4); stack(b,a)",
    )
    .unwrap()
    .entries()
  assert_eq(a[0].entry_key(), b[1].entry_key())
  assert_true(a[0].same_content(b[1]))
  assert_eq(a[1].entry_key(), b[0].entry_key())
  assert_false(a[1].same_content(b[0]))
  assert_true(a[0].entry_period() == @pattern.Rational::from_int(3))
  assert_true(a[1].entry_period() == @pattern.Rational::from_int(4))
}

///|
test "silent, filtered and transformed materials retain their entry period" {
  let pat = @mini.parse("note(\"60\").slow(8).degradeBy(1).gain(0.2)").unwrap()
  assert_true(pat.entry_period() == @pattern.Rational::from_int(8))
  assert_true(pat.filter_map(_ => None).entry_period() == pat.entry_period())
  let a = @mini.parse("stack(note(\"60\"),note(\"72\")).jux(rev)").unwrap()
  let b = @mini.parse("stack(note(\"61\"),note(\"72\")).jux(rev)").unwrap()
  assert_eq(a.entries().length(), 1)
  assert_false(a.same_content(b))
}

///|
test "compiled transforms keep stable identities and distinguish their parameters" {
  let pairs = [
    (".gain(0.2)", ".gain(0.3)"),
    (".every(2, rev)", ".every(3, rev)"),
    (".jux(rev)", ".jux(fast(2))"),
    (".degradeBy(0.2)", ".degradeBy(0.3)"),
    (".fast(2)", ".fast(3)"),
  ]
  for pair in pairs {
    let (first, second) = pair
    let text = "stack(note(\"60\"), note(\"72\"))"
    let a = @mini.parse(text + first).unwrap()
    let same = @mini.parse(text + first).unwrap()
    let changed = @mini.parse(text + second).unwrap()
    assert_true(a.same_content(same))
    assert_false(a.same_content(changed))
  }
}

///|
test "envelope seconds change content without stretching the source period" {
  let text = "note(\"60 64\").slow(3)"
  let base = @mini.parse(text).unwrap()
  let shaped = @mini.parse(text + ".attack(2).hold(3).release(8)").unwrap()
  assert_true(base.entry_period() == shaped.entry_period())
  assert_false(base.same_content(shaped))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(3),
  )
  let original = base.query(arc)
  let events = shaped.query(arc)
  assert_eq(events.length(), original.length())
  for i in 0..<events.length() {
    assert_true(events[i].whole == original[i].whole)
    assert_eq(events[i].value.get("attack"), Some(2.0))
    assert_eq(events[i].value.get("hold"), Some(3.0))
    assert_eq(events[i].value.get("release"), Some(8.0))
  }
  for method_name in ["attack", "hold", "release"] {
    assert_true(@mini.parse(text + ".\{method_name}(0)") is Ok(_))
    assert_true(@mini.parse(text + ".\{method_name}(-1)") is Err(_))
    assert_true(@mini.parse(text + ".\{method_name}(86401)") is Err(_))
  }
}
