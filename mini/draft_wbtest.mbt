///|
fn wb_draft_origin(draft : Draft) -> @pattern.EventOrigin raise {
  guard draft.prepare_playback() is Ok(input) else {
    fail("expected valid draft")
  }
  guard input.compile() is Ok(TrackedPattern(snapshot, _)) else {
    fail("expected tracked pattern")
  }
  let span = @pattern.TimeSpan(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  guard snapshot.query(span) is [event, ..] else { fail("expected an event") }
  event.origin()
}

///|
test "identity exhaustion rejects the whole transaction and reset recovers" {
  let draft = Draft("note(\"60 62\")")
  let old_origin = wb_draft_origin(draft)
  let before = draft.state()
  draft.sources = SourceMap(
    draft.sources.epoch,
    DRAFT_IDENTITY_MAX - 1L,
    draft.sources.atoms,
    draft.sources.literals,
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
test "literal frame identities survive offsets but retire on content edits" {
  let draft = Draft("note(\"60 62\")")
  guard draft.sources.literals is [literal, ..] else {
    fail("expected literal source frame")
  }
  let original = literal.id
  guard draft.sources.atoms is [_, untouched_atom, ..] else {
    fail("expected two notation atoms")
  }
  let untouched_atom_id = untouched_atom.id
  let first = draft.state()
  assert_true(
    draft.edit(
      EditTransaction(base=first.version(), edits=[
        TextEdit(from=0, to=0, inserted=" "),
      ]),
    )
    is Ok(_),
  )
  guard draft.sources.literals is [shifted, ..] else {
    fail("expected shifted literal source frame")
  }
  assert_eq(shifted.id, original)
  let shifted_state = draft.state()
  assert_true(
    draft.edit(
      EditTransaction(base=shifted_state.version(), edits=[
        TextEdit(from=8, to=9, inserted="4"),
      ]),
    )
    is Ok(_),
  )
  guard draft.sources.literals is [changed, ..] else {
    fail("expected replacement literal source frame")
  }
  assert_true(changed.id != original)
  assert_true(
    draft.locate_frame_fields(original.epoch().serial(), original.serial())
    is None,
  )
  assert_true(
    draft.locate_origin_fields(
      untouched_atom_id.epoch().serial(),
      untouched_atom_id.serial(),
      [],
    )
    is Located(_, _),
  )
  assert_true(
    draft.locate_frame_fields(changed.id.epoch().serial(), changed.id.serial())
    is Some(_),
  )
}

///|
test "revision exhaustion cannot wrap into a prior edit base" {
  let draft = Draft("note(\"60\")")
  let version = DraftVersion(draft.at.epoch, DRAFT_IDENTITY_MAX)
  draft.at = version
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
  let draft = Draft("let first = note(\"60\"); first")
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

///|
test "a mistake in one literal keeps the identity of the rest of its expression" {
  let draft = Draft(
    "let beat = s(\"bd\");\nstack(note(\"c4 e4\"), s(\"bd sd\"), beat)",
  )
  let atoms = draft.sources.atoms.map(atom => atom.id)
  let literals = draft.sources.literals.map(literal => literal.id)
  let references = draft.sources.references.map(reference => reference.id)
  // The note literal's content is at 32..37; `e4` becomes `??` and back.
  for inserted in ["??", "e4"] {
    let state = draft.state()
    assert_true(
      draft.edit(
        EditTransaction(base=state.version(), edits=[
          TextEdit(from=35, to=37, inserted~),
        ]),
      )
      is Ok(_),
    )
  }
  let after = draft.sources
  // Only `e4` and the note literal around it were edited; every other atom,
  // literal and reference keeps its identity.
  assert_eq(after.atoms.length(), atoms.length())
  for index, atom in after.atoms {
    if index != 2 {
      assert_eq(atom.id, atoms[index])
    }
  }
  assert_eq(after.literals.length(), literals.length())
  for index, literal in after.literals {
    if index != 1 {
      assert_eq(literal.id, literals[index])
    }
  }
  assert_eq(after.references.map(reference => reference.id), references)
}

///|
test "a mistake in a control string keeps the literals after it" {
  let facts = recognize_mini_source(
    "stack(note(\"c4\").gain(\"0.5 y\"), s(\"bd sd\"))",
  )
  assert_eq(facts.literals.map(literal => literal.kind), ["note", "drum"])
  assert_eq(facts.atoms.map(atom => atom.kind), ["note", "sound", "sound"])
}
