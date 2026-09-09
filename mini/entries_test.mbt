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
  assert_eq(a[0].entry_signature(), b[1].entry_signature())
  assert_eq(a[1].entry_key(), b[0].entry_key())
  assert_true(a[1].entry_signature() != b[0].entry_signature())
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
  assert_true(a.entry_signature() != b.entry_signature())
}
