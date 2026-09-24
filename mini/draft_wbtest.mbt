///|
fn wb_draft_origin(draft : Draft) -> @pattern.EventOrigin raise {
  guard draft.prepare_playback() is Ok(input) else {
    fail("expected valid draft")
  }
  guard input.compile() is Ok(Pattern(snapshot, _)) else {
    fail("expected exact pattern")
  }
  let span = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  guard snapshot.query(span) is [event, ..] else { fail("expected an event") }
  event.origin()
}

///|
test "identity exhaustion rejects the whole transaction and reset recovers" {
  let draft = Draft::new("note(\"60 62\")")
  let old_origin = wb_draft_origin(draft)
  let before = draft.state()
  draft.sources = SourceMap(
    draft.sources.epoch,
    DRAFT_IDENTITY_MAX - 1L,
    draft.sources.atoms,
    draft.sources.definitions,
    draft.sources.references,
  )
  let tx = EditTransaction(base=before.version(), edits=[
    TextEdit(from=6, to=8, inserted="64"),
    TextEdit(from=9, to=11, inserted="65"),
  ])
  assert_true(draft.edit(tx) is Err(IdentityExhausted))
  assert_eq(draft.state().text(), before.text())
  assert_eq(draft.state().version(), before.version())
  assert_true(draft.locate_origin(old_origin) is Located(_, _))
  assert_true(draft.reset("note(\"64 65\")") is Ok(_))
  assert_true(draft.locate_origin(old_origin) is Unavailable(SourceReset))
  assert_true(wb_draft_origin(draft).atom() != old_origin.atom())
}

///|
test "revision exhaustion cannot wrap into a prior edit base" {
  let draft = Draft::new("note(\"60\")")
  let version = DraftVersion(draft.current.at.epoch, DRAFT_IDENTITY_MAX)
  draft.current = DraftState(draft.current.input, version, Pattern, None)
  assert_true(draft.edit(EditTransaction(base=version, edits=[])) is Ok(_))
  assert_true(
    draft.edit(
      EditTransaction(base=version, edits=[
        TextEdit(from=6, to=8, inserted="60"),
      ]),
    )
    is Err(IdentityExhausted),
  )
  assert_eq(draft.state().version(), version)
  assert_eq(draft.state().text(), "note(\"60\")")
  assert_true(draft.reset("note(\"60\")") is Ok(_))
  assert_true(draft.state().version() != version)
}

///|
test "current source indices stay bounded across unique historical names" {
  let draft = Draft::new("let first = note(\"60\"); first")
  let origin = wb_draft_origin(draft)
  for index in 0..<300 {
    let text = "let phrase_\{index} = note(\"60\"); phrase_\{index}"
    assert_true(
      draft.edit(
        EditTransaction(base=draft.state().version(), edits=[
          TextEdit(from=0, to=draft.state().text().length(), inserted=text),
        ]),
      )
      is Ok(_),
    )
    let live_count = draft.sources.atoms.length() +
      draft.sources.definitions.length() +
      draft.sources.references.length()
    assert_true(live_count <= text.length())
  }
  assert_true(draft.locate_origin(origin) is Unavailable(AtomRetired))
  assert_true(wb_draft_origin(draft).atom() != origin.atom())
}
