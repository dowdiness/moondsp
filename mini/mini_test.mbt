///|
test "drum_midi returns correct GM numbers" {
  debug_inspect(@mini.drum_midi("bd"), content="Some(36)")
  debug_inspect(@mini.drum_midi("sd"), content="Some(38)")
  debug_inspect(@mini.drum_midi("cp"), content="Some(39)")
  debug_inspect(@mini.drum_midi("hh"), content="Some(42)")
  debug_inspect(@mini.drum_midi("oh"), content="Some(46)")
}

///|
test "parse s(\"cp oh\") cross-pool drum sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"cp oh\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
  assert_eq(events[0].value.entries(), { "sound": 39 })
  assert_eq(events[1].value.entries(), { "sound": 46 })
}

///|
test "rest atoms reserve their notation slots without emitting events" {
  let sound_events = query_one_cycle(unwrap_ok(@mini.parse("s(\"bd ~ sd ~\")")))
  assert_eq(sound_events.length(), 2)
  assert_eq(
    sound_events[0].whole.unwrap().begin,
    @pattern.Rational::new(0L, 1L),
  )
  assert_eq(
    sound_events[1].whole.unwrap().begin,
    @pattern.Rational::new(1L, 2L),
  )
  let note_events = query_one_cycle(
    unwrap_ok(@mini.parse("note(\"C4 ~ E4 ~\")")),
  )
  assert_eq(note_events.length(), 2)
  assert_eq(note_events[1].whole.unwrap().begin, @pattern.Rational::new(1L, 2L))
  let chord_events = query_one_cycle(unwrap_ok(@mini.parse("chord(\"C ~ G\")")))
  assert_eq(chord_events.length(), 6)
  assert_eq(
    chord_events[3].whole.unwrap().begin,
    @pattern.Rational::new(2L, 3L),
  )
  let doc = unwrap_doc(@mini.parse_doc("note(\"C4 ~ E4 ~\")"))
  assert_true(doc.contains_node(pid("mini:rest:_x126_:0")))
  assert_true(doc.contains_node(pid("mini:rest:_x126_:1")))
}

///|
test "parse_snapshot preserves rest timing and source identity" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot("note(\"C4 ~ E4 ~\")"),
  )
  assert_true(snapshot.pat().entry_period() == @pattern.Rational::from_int(1))
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  assert_eq(events.length(), 2)
  assert_eq(events[1].whole.unwrap().begin, @pattern.Rational::new(1L, 2L))
}

///|
test "gate uses an exact fraction and leaves note onsets unchanged" {
  let source = "note(\"C4 D4 E4 G4\").gate(0.4)"
  let runtime_events = query_one_cycle(unwrap_ok(@mini.parse(source)))
  let snapshot_events = unwrap_mini_snapshot(@mini.parse_snapshot(source)).query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  for events in [runtime_events, snapshot_events] {
    assert_eq(events.length(), 4)
    assert_eq(events[0].whole.unwrap().end_, @pattern.Rational::new(1L, 10L))
    assert_eq(events[1].whole.unwrap().begin, @pattern.Rational::new(1L, 4L))
    assert_eq(events[1].whole.unwrap().end_, @pattern.Rational::new(7L, 20L))
  }
}

///|
test "gate rejects fractions outside zero through one" {
  for
    source in [
      "note(\"C4\").gate(-0.01)", "note(\"C4\").gate(1.01)", "note(\"C4\").gate(1.000000000000000001)",
      "note(\"C4\").gate(18446744073709551616)",
    ] {
    match @mini.parse(source) {
      Ok(_) => abort("expected invalid gate fraction to fail")
      Err(message) =>
        assert_true(
          message.contains("gate() expects a fraction between 0 and 1"),
        )
    }
  }
}

///|
test "drum_midi returns None for unknown names" {
  debug_inspect(@mini.drum_midi("snare"), content="None")
  debug_inspect(@mini.drum_midi(""), content="None")
  debug_inspect(@mini.drum_midi("123"), content="None")
}

///|
/// Query a pattern over one cycle [0, 1) and return events.
fn query_one_cycle(
  pat : @pattern.Pat[@pattern.ControlMap],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  pat.query(arc)
}

///|
/// Unwrap an Ok result or fail the test.
fn unwrap_ok(
  result : Result[@pattern.Pat[@pattern.ControlMap], String],
) -> @pattern.Pat[@pattern.ControlMap] {
  match result {
    Ok(pat) => pat
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
fn unwrap_doc(
  result : Result[@pattern.PatternDoc[@pattern.ControlMap], String],
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  match result {
    Ok(doc) => doc
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
fn unwrap_mini_snapshot(
  result : Result[@pattern.PatternSnapshot[@pattern.ControlMap], String],
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
fn pid(value : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string(value) catch {
    _ => abort("expected valid pattern node id")
  }
}

///|
fn assert_builder_result_error(
  result : Result[@pattern.PatternDoc[@pattern.ControlMap], String],
  expected : String,
) -> Unit {
  match result {
    Err(msg) =>
      if msg != expected {
        abort("expected error '\{expected}', got '\{msg}'")
      }
    Ok(_) => abort("expected MiniDocBuilder operation to fail")
  }
}

///|
test "parse single drum sound" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  assert_eq(events[0].value.entries(), { "sound": 36 })
}

///|
test "parse lpf and hpf methods merges cutoff and optional resonance controls" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\").lpf(200, 2).hpf(40, 0.5)"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  assert_eq(events[0].value.entries(), {
    "sound": 36,
    "lpf": 200,
    "lpf_resonance": 2,
    "hpf": 40,
    "hpf_resonance": 0.5,
  })
}

///|
test "filter resonance accepts any finite positive value" {
  let high_q = query_one_cycle(
    unwrap_ok(@mini.parse("note(\"C4\").lpf(800, 64).hpf(80, 128)")),
  )
  assert_eq(high_q[0].value.get("lpf_resonance"), Some(64.0))
  assert_eq(high_q[0].value.get("hpf_resonance"), Some(128.0))
  for source in ["note(\"C4\").lpf(800, 0)", "note(\"C4\").hpf(80, -1)"] {
    match @mini.parse(source) {
      Ok(_) => abort("expected invalid filter resonance to fail")
      Err(message) =>
        assert_true(message.contains("expects finite resonance above 0"))
    }
  }
}

///|
test "parse gain and pan methods merge sound controls" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\").gain(0.5).pan(-0.25)"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("gain") == Some(0.5))
  assert_true(events[0].value.get("pan") == Some(-0.25))
}

///|
test "parse room method adds a shared reverb send" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\").room(0.625)"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  guard events[0].value.get("room") is Some(send) else {
    abort("expected room send")
  }
  assert_true((send - 0.625).abs() < 0.000001)
}

///|
test "room send must stay between zero and one" {
  for source in ["s(\"bd\").room(-0.01)", "s(\"bd\").room(1.01)"] {
    match @mini.parse(source) {
      Ok(_) => abort("expected invalid room send to fail")
      Err(message) =>
        assert_true(message.contains("room() expects a send between 0 and 1"))
    }
  }
}

///|
test "parse_snapshot lowers mini output through PatternDoc" {
  let snapshot = unwrap_mini_snapshot(@mini.parse_snapshot("s(\"bd sd\")"))
  inspect(
    snapshot.root().value(),
    content="mini:seq:mini:sound:bd:0:mini:sound:sd:0",
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="2")
}

///|
test "parse_snapshot lowers filter resonance through PatternDoc" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot("s(\"bd\").lpf(200, 2).hpf(40, 0.5)"),
  )
  inspect(
    snapshot.root().value(),
    content="mini:merge_control:mini:merge_control:mini:merge_control:mini:merge_control:mini:sound:bd:0:lpf:200:lpf_resonance:2:hpf:40:hpf_resonance:0.5",
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="1")
  assert_eq(events[0].value.entries(), {
    "sound": 36,
    "lpf": 200,
    "lpf_resonance": 2,
    "hpf": 40,
    "hpf_resonance": 0.5,
  })
}

///|
test "parse_snapshot lowers gain and pan methods through PatternDoc" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot("s(\"bd\").gain(0.5).pan(-0.25)"),
  )
  inspect(
    snapshot.root().value(),
    content="mini:merge_control:mini:merge_control:mini:sound:bd:0:gain:0.5:pan:-0.25",
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("gain") == Some(0.5))
  assert_true(events[0].value.get("pan") == Some(-0.25))
}

///|
test "parse_snapshot supports repeated lpf values in PatternDoc" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot("stack(s(\"bd\").lpf(200), s(\"sd\").lpf(200))"),
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="2")
  assert_true(events[0].value.get("lpf") == Some(200.0))
  assert_true(events[1].value.get("lpf") == Some(200.0))
}

///|
test "parse_snapshot supports repeated hpf chain in PatternDoc" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot("s(\"bd\").hpf(200).hpf(200)"),
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("hpf") == Some(200.0))
}

///|
test "parse_snapshot supports repeated gain and pan values in PatternDoc" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot(
      "stack(s(\"bd\").gain(0.5).pan(-0.25), s(\"sd\").gain(0.5).pan(-0.25))",
    ),
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="2")
  for event in events {
    assert_true(event.value.get("gain") == Some(0.5))
    assert_true(event.value.get("pan") == Some(-0.25))
  }
}

///|
test "parse pan method is overridden by jux outer pan" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\").pan(0.5).jux(rev)"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
  let (pan_neg1, pan_pos1) = for event in events; neg = 0, pos = 0 {
    match event.value.get("pan") {
      Some(-1.0) => continue neg + 1, pos
      Some(1.0) => continue neg, pos + 1
      _ => continue neg, pos
    }
  } nobreak {
    (neg, pos)
  }
  inspect(pan_neg1, content="1")
  inspect(pan_pos1, content="1")
}

///|
test "MiniDocBuilder::note_atom rejects invalid note text" {
  let builder = @mini.MiniDocBuilder::with_previous(None)
  assert_builder_result_error(
    builder.note_atom(pid("mini:note:bad:0"), ""),
    "invalid note: '' is not a number or note name",
  )
  assert_builder_result_error(
    builder.note_atom(pid("mini:note:bad:1"), "-"),
    "invalid note: '-' is not a number or note name",
  )
  assert_builder_result_error(
    builder.note_atom(pid("mini:note:bad:2"), "60abc"),
    "invalid note: '60abc' is not a number or note name",
  )
}

///|
test "parse_doc_reusing preserves ids across whitespace edits" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd sd\")"))
  let edited = unwrap_doc(
    @mini.parse_doc("s(\"  bd   sd  \")", previous=Some(doc)),
  )
  @debug.assert_eq(doc.root().value(), edited.root().value())
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(edited.contains_node(pid("mini:sound:sd:0")))
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(doc.lower_with_cache(cache))
  cache.reset_stats()
  ignore(edited.lower_with_cache(cache))
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="0")
}

///|
test "parse_doc_reusing lpf edit preserves sound atom id" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd\").lpf(200)"))
  let edited = unwrap_doc(
    @mini.parse_doc("s(\"bd\").lpf(300)", previous=Some(doc)),
  )
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(
    edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:lpf:300")),
  )
  assert_true(
    !edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:lpf:200")),
  )
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(doc.lower_with_cache(cache))
  cache.reset_stats()
  let snapshot = edited.lower_with_cache(cache)
  assert_true(cache.hit_count() >= 1)
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("lpf") == Some(300.0))
}

///|
test "parse_doc_reusing gain edit preserves sound atom id" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd\").gain(1)"))
  let edited = unwrap_doc(
    @mini.parse_doc("s(\"bd\").gain(2)", previous=Some(doc)),
  )
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(
    edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:gain:2")),
  )
  assert_true(
    !edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:gain:1")),
  )
  let events = edited
    .lower()
    .query(
      @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(1),
      ),
    )
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("gain") == Some(2.0))
}

///|
test "parse_doc_reusing pan edit preserves sound atom id" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd\").pan(-1)"))
  let edited = unwrap_doc(
    @mini.parse_doc("s(\"bd\").pan(0)", previous=Some(doc)),
  )
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(
    edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:pan:0")),
  )
  assert_true(
    !edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:pan:-1")),
  )
  let events = edited
    .lower()
    .query(
      @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(1),
      ),
    )
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("pan") == Some(0.0))
}

///|
test "parse_doc_reusing token replacement preserves unaffected token ids" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd sd hh\")"))
  let edited = unwrap_doc(
    @mini.parse_doc("s(\"bd cp hh\")", previous=Some(doc)),
  )
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(!edited.contains_node(pid("mini:sound:sd:0")))
  assert_true(edited.contains_node(pid("mini:sound:cp:0")))
  assert_true(edited.contains_node(pid("mini:sound:hh:0")))
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(doc.lower_with_cache(cache))
  cache.reset_stats()
  let snapshot = edited.lower_with_cache(cache)
  assert_true(cache.hit_count() >= 2)
  assert_true(cache.miss_count() >= 1)
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  let saw_cp = for event in events {
    match event.value.get("sound") {
      Some(39.0) => break true
      _ => ()
    }
  } nobreak {
    false
  }
  assert_true(saw_cp)
}

///|
test "parse_doc_reusing insertion and removal keep surviving token ids" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd sd\")"))
  let inserted = unwrap_doc(
    @mini.parse_doc("s(\"hh bd sd\")", previous=Some(doc)),
  )
  assert_true(inserted.contains_node(pid("mini:sound:hh:0")))
  assert_true(inserted.contains_node(pid("mini:sound:bd:0")))
  assert_true(inserted.contains_node(pid("mini:sound:sd:0")))
  let removed = unwrap_doc(
    @mini.parse_doc("s(\"bd\")", previous=Some(inserted)),
  )
  assert_true(removed.contains_node(pid("mini:sound:bd:0")))
  assert_true(!removed.contains_node(pid("mini:sound:hh:0")))
  assert_true(!removed.contains_node(pid("mini:sound:sd:0")))
}

///|
fn draft_snapshot(
  draft : @mini.Draft,
) -> @pattern.PatternSnapshotWithOrigins[@pattern.ControlMap] raise {
  let input = match draft.prepare_playback() {
    Ok(input) => input
    Err(error) => fail(error.message())
  }
  match input.compile() {
    Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) => snapshot
    Ok(_) => fail("expected exact pattern")
    Err(message) => fail(message)
  }
}

///|
fn draft_arc() -> @pattern.TimeSpan {
  @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
}

///|
fn apply_draft_edits(
  draft : @mini.Draft,
  edits : Array[@mini.TextEdit],
) -> Unit raise {
  guard draft.edit(
      @mini.EditTransaction::EditTransaction(
        base=draft.state().version(),
        edits~,
      ),
    )
    is Ok(_) else {
    fail("transaction rejected")
  }
}

///|
fn edit_draft(
  draft : @mini.Draft,
  from : Int,
  to : Int,
  inserted : String,
) -> Unit raise {
  apply_draft_edits(draft, [@mini.TextEdit::TextEdit(from~, to~, inserted~)])
}

///|
test "Draft same-text replacement is causal and frozen input is immutable" {
  let draft = @mini.Draft::new("note(\"60 60\")")
  let version = draft.state().version()
  guard draft.prepare_playback() is Ok(input) else {
    fail("expected prepared input")
  }
  let old = draft_snapshot(draft).query(draft_arc())
  edit_draft(draft, 6, 8, "60")
  let fresh = draft_snapshot(draft).query(draft_arc())
  assert_true(draft.state().version() != version)
  assert_true(old[0].origin().atom() != fresh[0].origin().atom())
  assert_eq(old[1].origin(), fresh[1].origin())
  assert_true(draft.locate_origin(old[0].origin()) is Unavailable(AtomRetired))
  assert_eq(input.version(), Some(version))
  guard input.compile() is Ok(@mini.PreparedPlayback::Pattern(retained, _)) else {
    fail("frozen compilation failed")
  }
  assert_eq(retained.query(draft_arc())[0].origin(), old[0].origin())
}

///|
test "Draft separate inverse edits do not resurrect an atom" {
  let draft = @mini.Draft::new("note(\"60 62\")")
  let old = draft_snapshot(draft).query(draft_arc())
  edit_draft(draft, 7, 7, "1")
  edit_draft(draft, 7, 8, "")
  let fresh = draft_snapshot(draft).query(draft_arc())
  assert_eq(draft.state().text(), "note(\"60 62\")")
  assert_true(old[0].origin().atom() != fresh[0].origin().atom())
  assert_eq(old[1].origin(), fresh[1].origin())
}

///|
test "Draft multi-range transaction preserves the untouched middle atom" {
  let draft = @mini.Draft::new("note(\"60 62 64\")")
  let old = draft_snapshot(draft).query(draft_arc())
  let edits = [
    @mini.TextEdit::TextEdit(from=6, to=8, inserted="67"),
    @mini.TextEdit::TextEdit(from=12, to=14, inserted="69"),
  ]
  let tx = @mini.EditTransaction::EditTransaction(
    base=draft.state().version(),
    edits~,
  )
  edits[0] = @mini.TextEdit::TextEdit(from=0, to=100, inserted="")
  assert_true(draft.edit(tx) is Ok(_))
  let fresh = draft_snapshot(draft).query(draft_arc())
  assert_eq(draft.state().text(), "note(\"67 62 69\")")
  assert_eq(old[1].origin(), fresh[1].origin())
  assert_true(old[0].origin() != fresh[0].origin())
  assert_true(old[2].origin() != fresh[2].origin())
}

///|
test "Draft duplicate insertion uses lexical extents for every atom reader" {
  for
    sample in [
      ("s(\"bd sd bd\")", 9, "bd ", 1),
      ("note(\"60 62 60\")", 12, "60 ", 1),
      ("note(\"C#4 E4 C#4\")", 13, "C#4 ", 1),
      ("note(\"C-1 E4 C-1\")", 13, "C-1 ", 1),
      ("chord(\"F#m7 F#m7\")", 12, "F#m7 ", 4),
      ("chord(\"C+7 C+7\")", 11, "C+7 ", 4),
      ("chord(\"Cø7 Cø7\")", 11, "Cø7 ", 4),
    ] {
    let (text, position, inserted, tones) = sample
    let draft = @mini.Draft::new(text)
    let old = draft_snapshot(draft).query(draft_arc())
    edit_draft(draft, position, position, inserted)
    let fresh = draft_snapshot(draft).query(draft_arc())
    assert_eq(fresh.length(), old.length() + tones)
    assert_eq(fresh[0].origin(), old[0].origin())
    assert_eq(
      fresh[fresh.length() - 1].origin(),
      old[old.length() - 1].origin(),
    )
    let added = fresh[fresh.length() - tones * 2].origin()
    for event in old {
      assert_true(event.origin().atom() != added.atom())
    }
  }
}

///|
test "Draft endpoint whitespace preserves while lexical merge and split retire" {
  let draft = @mini.Draft::new("note(\"C4 E4\")")
  let old = draft_snapshot(draft).query(draft_arc())
  edit_draft(draft, 8, 8, " ")
  assert_eq(
    draft_snapshot(draft).query(draft_arc())[0].origin(),
    old[0].origin(),
  )
  edit_draft(draft, 7, 7, " ")
  assert_true(draft.locate_origin(old[0].origin()) is Unavailable(AtomRetired))
  edit_draft(draft, 7, 8, "")
  assert_true(
    draft_snapshot(draft).query(draft_arc())[0].origin() != old[0].origin(),
  )
  assert_true(draft.locate_origin(old[1].origin()) is Located(_, _))
  let merged = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(draft, 8, 8, "x")
  assert_true(draft.locate_origin(merged) is Unavailable(AtomRetired))
}

///|
test "Draft changing literal role retires an untouched spelling" {
  let draft = @mini.Draft::new("note(\"E4\")")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(draft, 0, 4, "s")
  assert_true(draft.locate_origin(old) is Unavailable(AtomRetired))
  edit_draft(draft, 0, 1, "note")
  assert_true(draft_snapshot(draft).query(draft_arc())[0].origin() != old)
}

///|
test "Draft missing outer delimiter retains live atoms but not deleted generations" {
  let draft = @mini.Draft::new("note(\"c3 e3\")")
  let old = draft_snapshot(draft).query(draft_arc())
  edit_draft(draft, 12, 13, "")
  guard draft.prepare_playback() is Err(diagnostic) else {
    fail("expected invalid draft")
  }
  assert_eq(diagnostic.version(), draft.state().version())
  assert_true(draft.locate_origin(old[0].origin()) is Located(_, _))
  edit_draft(draft, 6, 9, "")
  edit_draft(draft, 6, 6, "c3 ")
  edit_draft(draft, 12, 12, ")")
  let fresh = draft_snapshot(draft).query(draft_arc())
  assert_true(old[0].origin() != fresh[0].origin())
  assert_eq(old[1].origin(), fresh[1].origin())
  assert_true(diagnostic.version() != draft.state().version())
}

///|
test "Draft semicolon recovery preserves references across another invalid body" {
  let prefix = "let tone = note(\"60\"); "
  let middle = "let broken = stack(s(\"bd\")); "
  let draft = @mini.Draft::new(prefix + middle + "tone")
  let origin = draft_snapshot(draft).query(draft_arc())[0].origin()
  let close = prefix.length() + middle.length() - 3
  edit_draft(draft, close, close + 1, "")
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.locate_origin(origin) is Located(_, _))
  edit_draft(draft, close, close, ")")
  assert_eq(draft_snapshot(draft).query(draft_arc())[0].origin(), origin)
}

///|
test "Draft opaque suffix keeps an independent prefix without guessing reference edges" {
  let prefix = "let tone = note(\"60\"); stack(tone,"
  let draft = @mini.Draft::new(prefix + "tone)")
  let old = draft_snapshot(draft).query(draft_arc())
  edit_draft(draft, prefix.length(), prefix.length(), "/*")
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.locate_origin(old[0].origin()) is Located(_, _))
  assert_true(
    draft.locate_origin(old[1].origin()) is Unavailable(BrokenReference),
  )
  edit_draft(draft, prefix.length(), prefix.length() + 2, "")
  let fresh = draft_snapshot(draft).query(draft_arc())
  assert_eq(old[0].origin(), fresh[0].origin())
  assert_true(old[1].origin() != fresh[1].origin())
}

///|
test "Draft duplicate target and undo end a binding even when endpoints survive" {
  let prefix = "let tone = note(\"60\"); "
  let duplicate = "let tone = note(\"62\"); "
  let draft = @mini.Draft::new(prefix + "tone")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(draft, prefix.length(), prefix.length(), duplicate)
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
  edit_draft(draft, prefix.length(), prefix.length() + duplicate.length(), "")
  let fresh = draft_snapshot(draft).query(draft_arc())[0].origin()
  assert_eq(old.atom(), fresh.atom())
  assert_eq(old.bindings()[0].reference(), fresh.bindings()[0].reference())
  assert_eq(old.bindings()[0].definition(), fresh.bindings()[0].definition())
  assert_true(old.bindings()[0].id() != fresh.bindings()[0].id())
  assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
}

///|
test "Draft missing terminators cannot hide declarations and revive bindings" {
  for prefix in ["let tone = note(\"60\")", "let tone = note(\"60\"); bpm(120)"] {
    let draft = @mini.Draft::new(prefix + "; tone")
    let old = draft_snapshot(draft).query(draft_arc())[0].origin()
    let hidden = " let tone = note(\"62\");"
    edit_draft(draft, prefix.length(), prefix.length() + 1, hidden)
    assert_true(draft.prepare_playback() is Err(_))
    assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
    edit_draft(draft, prefix.length(), prefix.length() + hidden.length(), ";")
    let fresh = draft_snapshot(draft).query(draft_arc())[0].origin()
    assert_eq(old.atom(), fresh.atom())
    assert_eq(old.bindings()[0].reference(), fresh.bindings()[0].reference())
    assert_eq(old.bindings()[0].definition(), fresh.bindings()[0].definition())
    assert_true(old.bindings()[0].id() != fresh.bindings()[0].id())
    assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
  }
}

///|
test "Draft declaration certainty respects lexical boundaries" {
  let prefix = "let tone = note(\"60\"); "
  for
    body in [
      "s(\"let tone = x;\")", "s(\"bd\") /* let tone = x; */", "s(\"bd\") // let tone = x;\n",
      "palette", "tone. /* member name, not a declaration */ let()",
    ] {
    let draft = @mini.Draft::new(prefix + "tone")
    let old = draft_snapshot(draft).query(draft_arc())[0].origin()
    edit_draft(
      draft,
      prefix.length(),
      prefix.length(),
      "let other = " + body + "; ",
    )
    assert_true(draft.locate_origin(old) is Located(_, _))
  }
}

///|
test "Draft decimal dots cannot conceal ambiguous declarations" {
  let prefix = "let tone = note(\"60\"); "
  let draft = @mini.Draft::new(prefix + "tone")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(
    draft,
    prefix.length(),
    prefix.length(),
    "let other = note(\"62\").fast(1. let tone = note(\"64\"); ",
  )
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
}

///|
test "Draft undefined target and restoration never revive an old binding" {
  let draft = @mini.Draft::new("let tone = note(\"60\"); tone")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(draft, 4, 8, "other")
  assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
  edit_draft(draft, 4, 9, "tone")
  let fresh = draft_snapshot(draft).query(draft_arc())[0].origin()
  assert_eq(old.atom(), fresh.atom())
  assert_true(
    old.bindings()[0].definition() != fresh.bindings()[0].definition(),
  )
  assert_true(old.bindings()[0].id() != fresh.bindings()[0].id())
}

///|
test "Draft nested uses share primary atoms but locate every outer-to-inner reference" {
  let prefix = "let tone = note(\"60\"); let group = tone; "
  let draft = @mini.Draft::new(prefix + "stack(group,group)")
  let events = draft_snapshot(draft).query(draft_arc())
  assert_eq(events[0].origin().atom(), events[1].origin().atom())
  assert_true(
    events[0].origin().bindings()[0].id() !=
    events[1].origin().bindings()[0].id(),
  )
  guard draft.locate_origin(events[0].origin()) is Located(atom, [outer, inner]) else {
    fail("expected complete two-edge location")
  }
  assert_eq(draft.state().text()[atom.start():atom.end()].to_owned(), "60")
  assert_eq(outer.start(), prefix.length() + 6)
  assert_eq(draft.state().text()[inner.start():inner.end()].to_owned(), "tone")
  edit_draft(draft, inner.start(), inner.end(), "tone")
  assert_true(
    draft.locate_origin(events[0].origin()) is Unavailable(BrokenReference),
  )
  assert_true(
    draft.locate_origin(events[1].origin()) is Unavailable(BrokenReference),
  )
}

///|
test "Draft control changes preserve live source paths including zero gain" {
  let prefix = "let tone = note(\"60\").gain("
  let draft = @mini.Draft::new(prefix + "1); tone")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(draft, prefix.length(), prefix.length() + 1, "0")
  let event = draft_snapshot(draft).query(draft_arc())[0]
  assert_eq(event.origin(), old)
  assert_eq(event.event().value.get("gain"), Some(0.0))
}

///|
test "Draft exact lowering preserves music material and graph scopes" {
  for
    text in [
      "note(\"60 [62 64] ~\").every(2, rev()).jux(fast(2)).gain(0)", "chord(\"C+7 F#m7 Cø7\").rev().slow(2).gate(0.5)",
      "s(\"bd(3,8) sd*2 hh/2?\").degradeBy(0.3).lpf(800).pan(0.2)", "/* 𝄞 */ let tone = note(\"C-1 F#3\"); bpm(120); let group = tone; stack(group,group.rev())",
      "let tone = note(\"60\");\n$: tone\n$: chord(\"C\")", "silence() + s(\"~ bd\")",
    ] {
    let draft = @mini.Draft::new(text)
    let exact = draft_snapshot(draft)
    guard @mini.parse_play_source(text) is Ok(source) else {
      fail("general parse failed")
    }
    guard source.body() is Pattern(doc) else { fail("expected pattern") }
    let general = doc.lower()
    let span = song_span(0L, 1L, 4L, 1L)
    let actual = exact.query(span)
    let expected = general.query_sourced_events(span)
    assert_named_events(
      actual.map(e => e.event()),
      expected.map(e => e.event()),
    )
    let actual_entries = exact.pat().entries()
    let expected_entries = general.pat().entries()
    assert_eq(actual_entries.length(), expected_entries.length())
    for index in 0..<actual.length() {
      assert_eq(
        actual[index].pattern_node_path(),
        expected[index].pattern_node_path(),
      )
      assert_true(draft.locate_origin(actual[index].origin()) is Located(_, _))
    }
    for index in 0..<actual_entries.length() {
      assert_eq(exact.entry_key(index), general.entry_key(index))
      assert_eq(
        actual_entries[index].entry_period(),
        expected_entries[index].entry_period(),
      )
      assert_eq(
        actual_entries[index].same_content(expected_entries[index]),
        expected_entries[index].same_content(expected_entries[index]),
      )
    }
  }
}

///|
test "Draft invalid transactions are atomic including UTF-16 boundaries" {
  let draft = @mini.Draft::new("// 𝄞\nnote(\"60\")")
  let before = draft.state()
  let origin = draft_snapshot(draft).query(draft_arc())[0].origin()
  let edits = [
    @mini.TextEdit::TextEdit(from=0, to=0, inserted=" "),
    @mini.TextEdit::TextEdit(from=4, to=4, inserted="x"),
  ]
  assert_true(
    draft.edit(
      @mini.EditTransaction::EditTransaction(base=before.version(), edits~),
    )
    is Err(InvalidEdit(_)),
  )
  assert_eq(draft.state().text(), before.text())
  assert_eq(draft.state().version(), before.version())
  assert_true(draft.locate_origin(origin) is Located(_, _))
  apply_draft_edits(draft, [])
  assert_eq(draft.state().version(), before.version())
  edit_draft(draft, 0, 0, " ")
  assert_true(
    draft.edit(
      @mini.EditTransaction::EditTransaction(base=before.version(), edits=[]),
    )
    is Err(WrongBase),
  )
  assert_true(
    draft.edit(
      @mini.EditTransaction::EditTransaction(base=draft.state().version(), edits=[
        @mini.TextEdit::TextEdit(from=5, to=7, inserted=""),
        @mini.TextEdit::TextEdit(from=6, to=8, inserted=""),
      ]),
    )
    is Err(InvalidEdit(_)),
  )
}

///|
test "Draft tracking limit and reset each establish fresh source epochs" {
  let draft = @mini.Draft::new("note(\"60\")")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  let padding = " ".repeat(8192)
  edit_draft(draft, 0, 0, padding)
  assert_true(draft.state().tracking() is TrackingUnavailable)
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.locate_origin(old) is Unavailable(SourceReset))
  edit_draft(draft, 0, padding.length(), "")
  let recovered = draft_snapshot(draft).query(draft_arc())[0].origin()
  assert_true(old.atom().epoch() != recovered.atom().epoch())
  assert_true(draft.reset("note(\"60\")") is Ok(_))
  assert_true(draft.locate_origin(recovered) is Unavailable(SourceReset))
}

///|
test "Draft disposal does not invalidate a separately frozen playback input" {
  let draft = @mini.Draft::new("note(\"60\")")
  guard draft.prepare_playback() is Ok(input) else { fail("expected input") }
  let origin = draft_snapshot(draft).query(draft_arc())[0].origin()
  draft.dispose()
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.reset("note(\"62\")") is Err(Disposed))
  assert_true(
    draft.edit(
      @mini.EditTransaction::EditTransaction(base=draft.state().version(), edits=[]),
    )
    is Err(Disposed),
  )
  assert_true(draft.locate_origin(origin) is Unavailable(SourceReset))
  guard input.compile() is Ok(@mini.PreparedPlayback::Pattern(snapshot, _)) else {
    fail("frozen input was invalidated")
  }
  assert_eq(snapshot.query(draft_arc())[0].origin(), origin)
}

///|
test "Draft confirmed song mode and explicit text input remain valid runtime sources" {
  let draft = @mini.Draft::new("note(\"60\")")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  let text = "bpm(72); song(section(\"intro\",1,s(\"bd\")),part(\"intro1\",\"intro\")).repeat()"
  edit_draft(draft, 0, draft.state().text().length(), text)
  assert_true(draft.state().tracking() is Song)
  guard draft.prepare_playback() is Ok(input) else {
    fail("valid song preparation failed")
  }
  guard input.compile() is Ok(@mini.PreparedPlayback::Runtime(source)) else {
    fail("song must use runtime capability")
  }
  assert_eq(source.bpm(), 72.0)
  guard source.body() is Arrangement(song, repeating) else {
    fail("expected arrangement")
  }
  assert_true(repeating)
  assert_eq(song.query(draft_arc())[0].value.get("sound"), Some(36.0))
  assert_true(draft.locate_origin(old) is Unavailable(SourceReset))
  edit_draft(draft, 0, text.length(), "/*")
  assert_true(draft.state().tracking() is Song)
  assert_true(draft.prepare_playback() is Err(_))
  edit_draft(draft, 0, 2, "note(\"60\")")
  assert_true(
    draft_snapshot(draft).query(draft_arc())[0].origin().atom().epoch() !=
    old.atom().epoch(),
  )
  let untracked = @mini.PlaybackInput::text("note(\"62\")")
  assert_true(untracked.version() is None)
  guard untracked.compile() is Ok(@mini.PreparedPlayback::Runtime(raw)) else {
    fail("text input must be explicitly untracked")
  }
  guard raw.body() is Pattern(doc) else { fail("expected runtime pattern") }
  assert_eq(doc.lower().query(draft_arc())[0].value.get("note"), Some(62.0))
}

///|
test "Draft opaque preceding scope retires a binding without retiring its endpoints" {
  let prefix = "let tone = note(\"60\"); "
  let draft = @mini.Draft::new(prefix + "tone")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  edit_draft(draft, prefix.length(), prefix.length(), "unknown(;")
  assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
  edit_draft(draft, prefix.length(), prefix.length() + 9, "")
  let fresh = draft_snapshot(draft).query(draft_arc())[0].origin()
  assert_eq(old.atom(), fresh.atom())
  assert_eq(old.bindings()[0].reference(), fresh.bindings()[0].reference())
  assert_eq(old.bindings()[0].definition(), fresh.bindings()[0].definition())
  assert_true(old.bindings()[0].id() != fresh.bindings()[0].id())
}

///|
test "Draft local depth failure preserves independent reference proofs" {
  let prefix = "let tone = note(\"60\"); let other = "
  let body = "s(\"bd\")"
  let draft = @mini.Draft::new(prefix + body + "; tone")
  let old = draft_snapshot(draft).query(draft_arc())[0].origin()
  apply_draft_edits(draft, [
    @mini.TextEdit::TextEdit(
      from=prefix.length(),
      to=prefix.length(),
      inserted="(".repeat(40),
    ),
    @mini.TextEdit::TextEdit(
      from=prefix.length() + body.length(),
      to=prefix.length() + body.length(),
      inserted=")".repeat(40),
    ),
  ])
  assert_true(draft.prepare_playback() is Err(_))
  assert_true(draft.locate_origin(old) is Located(_, _))
  let boundary = draft.state().text().length() - "; tone".length()
  edit_draft(draft, boundary, boundary, " let tone = note(\"62\")")
  assert_true(draft.locate_origin(old) is Unavailable(BrokenReference))
}

///|
test "Draft chord tones share one atom and retain separate voice scopes" {
  let draft = @mini.Draft::new("chord(\"C\")")
  guard draft_snapshot(draft).query(draft_arc()) is [root, third, fifth] else {
    fail("expected major chord")
  }
  assert_eq(root.origin(), third.origin())
  assert_eq(root.origin(), fifth.origin())
  assert_true(root.pattern_node_path() != third.pattern_node_path())
  assert_true(third.pattern_node_path() != fifth.pattern_node_path())
  guard draft.locate_origin(root.origin()) is Located(atom, []) else {
    fail("expected chord source atom")
  }
  assert_eq(draft.state().text()[atom.start():atom.end()].to_owned(), "C")
}

///|
test "parse_doc stack chord and numeric note has disjoint node ids" {
  let doc = unwrap_doc(@mini.parse_doc("stack(chord(\"C\"), note(\"60\"))"))
  assert_true(doc.contains_node(pid("mini:chord-tone:mini:chord:C:0:0:60")))
  assert_true(doc.contains_node(pid("mini:chord-tone:mini:chord:C:0:1:64")))
  assert_true(doc.contains_node(pid("mini:chord-tone:mini:chord:C:0:2:67")))
  assert_true(doc.contains_node(pid("mini:note:60:0")))
}

///|
test "parse drum sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh sd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="4")
}

///|
test "parse note sequence" {
  let pat = unwrap_ok(@mini.parse("note(\"60 64 67\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  assert_eq(events[0].value.entries(), { "note": 60 })
  assert_eq(events[1].value.entries(), { "note": 64 })
  assert_eq(events[2].value.entries(), { "note": 67 })
}

///|
test "parse with fast method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").fast(2)"))
  let events = query_one_cycle(pat)
  // fast(2) doubles the pattern, so 2 elements * 2 = 4 events
  inspect(events.length(), content="4")
}

///|
test "parse with sub-group brackets" {
  let pat = unwrap_ok(@mini.parse("s(\"bd [sd hh]\")"))
  let events = query_one_cycle(pat)
  // bd takes first half, [sd hh] takes second half (2 events in sub-group)
  inspect(events.length(), content="3")
}

///|
test "parse with stack (comma)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd, hh hh hh\")"))
  let events = query_one_cycle(pat)
  // stack of [bd sd] (2 events) and [hh hh hh] (3 events) = 5 events
  inspect(events.length(), content="5")
}

///|
test "parse empty input returns error" {
  match @mini.parse("") {
    Err(msg) => inspect(msg, content="empty input")
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse unknown primary returns error" {
  match @mini.parse("foo(\"bar\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse fast(0) returns error" {
  match @mini.parse("s(\"bd\").fast(0)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse fast(-1) returns error" {
  match @mini.parse("s(\"bd\").fast(-1)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse unknown drum name returns error" {
  match @mini.parse("s(\"snare\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse with slow method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").slow(2)"))
  // slow(2) halves the speed, querying [0,1) sees only 1 event (first half of pattern)
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
}

///|
test "parse euclid bd(3,8) tresillo" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8)\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  assert_eq(events[0].value.entries(), { "sound": 36 })
}

///|
test "parse euclid with rotation bd(3,8,2)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8,2)\")"))
  let events = query_one_cycle(pat)
  // Rotation does not change pulse count
  inspect(events.length(), content="3")
}

///|
test "parse euclid on group [bd sd](5,8)" {
  let pat = unwrap_ok(@mini.parse("s(\"[bd sd](5,8)\")"))
  let events = query_one_cycle(pat)
  // 5 pulse slots, each containing the [bd sd] sub-group (2 events per slot)
  inspect(events.length(), content="10")
}

///|
test "parse euclid alongside other elements" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8) sd\")"))
  let events = query_one_cycle(pat)
  // bd(3,8) takes first half (3 pulses), sd takes second half (1 event) = 4
  inspect(events.length(), content="4")
}

///|
test "parse euclid k=0 produces silence for that element" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(0,8) sd\")"))
  let events = query_one_cycle(pat)
  // bd(0,8) is silent, only sd plays in second half
  inspect(events.length(), content="1")
  assert_eq(events[0].value.entries(), { "sound": 38 })
}

///|
test "parse euclid missing comma returns error" {
  match @mini.parse("s(\"bd(3 8)\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for malformed euclid")
  }
}

///|
test "parse euclid unclosed paren returns error" {
  match @mini.parse("s(\"bd(3,8\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for unclosed euclid")
  }
}

///|
test "parse step replicate bd*4 in single-element layer" {
  let pat = unwrap_ok(@mini.parse("s(\"bd*4\")"))
  let events = query_one_cycle(pat)
  // Single slot, replicated 4× via fast(4) → 4 events
  inspect(events.length(), content="4")
}

///|
test "parse step replicate within sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd*3\")"))
  let events = query_one_cycle(pat)
  // bd takes first half (1 event), sd*3 takes second half (3 events) = 4
  inspect(events.length(), content="4")
}

///|
test "parse step slow bd/2 in single-element layer" {
  let pat = unwrap_ok(@mini.parse("s(\"bd/2\")"))
  let events = query_one_cycle(pat)
  // slow(2) on a single-cycle pure event: querying [0,1) sees one event
  inspect(events.length(), content="1")
}

///|
test "parse step ops compose with euclid: bd*2(3,8)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd*2(3,8)\")"))
  let events = query_one_cycle(pat)
  // bd*2 fires 2 events per slot, distributed via euclid (3,8) over 8 slots
  // 3 active slots × 2 events each = 6
  inspect(events.length(), content="6")
}

///|
test "parse step replicate on group [bd sd]*2" {
  let pat = unwrap_ok(@mini.parse("s(\"[bd sd]*2\")"))
  let events = query_one_cycle(pat)
  // Group plays 2× via fast(2) → 2 × 2 = 4 events
  inspect(events.length(), content="4")
}

///|
test "parse step replicate with zero returns error" {
  match @mini.parse("s(\"bd*0\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for bd*0")
  }
}

///|
test "parse step slow with zero returns error" {
  match @mini.parse("s(\"bd/0\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for bd/0")
  }
}

///|
test "parse step replicate missing number returns error" {
  match @mini.parse("s(\"bd*\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for bd*")
  }
}

///|
test "parse degrade step bd? drops some events deterministically" {
  // 16-step pattern with `?` — expect strict subset, repeatable.
  let pat = unwrap_ok(
    @mini.parse(
      "s(\"bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd\").fast(1)",
    ),
  )
  let kept_full = query_one_cycle(pat).length()
  inspect(kept_full, content="16")
  let pat_q = unwrap_ok(
    @mini.parse(
      "s(\"bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd?\")",
    ),
  )
  let kept_q = query_one_cycle(pat_q).length()
  // Strictly less than full, strictly more than zero
  inspect(kept_q < 16 && kept_q > 0, content="true")
  // Determinism: querying again yields same count
  inspect(query_one_cycle(pat_q).length() == kept_q, content="true")
}

///|
test "parse degradeBy method chain" {
  let pat = unwrap_ok(
    @mini.parse(
      "s(\"bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd\").degradeBy(0.5)",
    ),
  )
  let kept = query_one_cycle(pat).length()
  inspect(kept < 16 && kept > 0, content="true")
}

///|
test "parse degradeBy(0.0) keeps everything" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh sd\").degradeBy(0.0)"))
  inspect(query_one_cycle(pat).length(), content="4")
}

///|
test "parse every(2, fast(2)) doubles events on cycle 0" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").every(2, fast(2))"))
  let events = query_one_cycle(pat)
  // Cycle 0: every fires → fast(2) on the 2-element pattern → 4 events
  inspect(events.length(), content="4")
}

///|
test "parse every(2, rev) — cycle 0 timing reversed" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh\").every(2, rev)"))
  let events = query_one_cycle(pat)
  // rev mirrors timing, not array order. bd's slot under rev moves from
  // [0, 1/3) to [2/3, 1) on cycle 0.
  inspect(events.length(), content="3")
  inspect(
    events[0].part,
    content=(
      #|{ begin: { num: 2, den: 3 }, end_: { num: 1, den: 1 } }
    ),
  )
}

///|
test "parse every with unknown callback returns error" {
  match @mini.parse("s(\"bd sd\").every(2, weird)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for unknown every() callback")
  }
}

///|
test "parse every with non-positive n returns error" {
  match @mini.parse("s(\"bd sd\").every(0, rev)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for every(0, ...)")
  }
}

///|
test "parse every with non-integer n returns error (no silent truncation)" {
  match @mini.parse("s(\"bd sd\").every(2.5, rev)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for every(2.5, ...)")
  }
}

///|
test "parse every with non-integer callback arg returns error" {
  match @mini.parse("s(\"bd sd\").every(2, fast(1.5))") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for every(2, fast(1.5))")
  }
}

///|
test "parse chained postfix bd*3*4 stacks replications" {
  let pat = unwrap_ok(@mini.parse("s(\"bd*3*4\")"))
  let events = query_one_cycle(pat)
  // *3 then *4 → fast(3).fast(4) = 12 events in one slot
  inspect(events.length(), content="12")
}

///|
test "parse euclid with negative rotation" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8,-1)\")"))
  let events = query_one_cycle(pat)
  // Negative rotation should still produce 3 pulses (modulo wrap)
  inspect(events.length(), content="3")
}

///|
test "parse with rev method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh\").rev()"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  // Reversed: hh, sd, bd
  assert_eq(events[0].value.entries(), { "sound": 36 })
  assert_eq(events[1].value.entries(), { "sound": 38 })
  assert_eq(events[2].value.entries(), { "sound": 42 })
}

///|
test "parse jux(rev) produces 4 events from 2-element pattern" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").jux(rev)"))
  let events = query_one_cycle(pat)
  // 2 events left + 2 events right = 4
  inspect(events.length(), content="4")
}

///|
test "parse jux(weird) errors with jux() in the message" {
  match @mini.parse("s(\"bd\").jux(weird)") {
    Err(msg) => {
      // Lock in error-message threading: must say jux(), not every()
      let has_jux = msg.contains("jux()")
      let has_every = msg.contains("every()")
      assert_true(has_jux)
      assert_true(!has_every)
    }
    Ok(_) => fail("expected Err for jux(weird)")
  }
}

///|
test "parse note(60 64).jux(rev) parses (non-s primary)" {
  let pat = unwrap_ok(@mini.parse("note(\"60 64\").jux(rev)"))
  let events = query_one_cycle(pat)
  // 2 events left + 2 events right = 4
  inspect(events.length(), content="4")
}

///|
test "parse stack(s, note) combines drum + melodic primaries" {
  let pat = unwrap_ok(@mini.parse("stack(s(\"bd\"), note(\"60\"))"))
  let events = query_one_cycle(pat)
  // 1 sound event + 1 note event = 2
  inspect(events.length(), content="2")
}

///|
test "parse stack with method chain on result" {
  let pat = unwrap_ok(
    @mini.parse("stack(s(\"bd sd\"), note(\"60 64\")).fast(2)"),
  )
  let events = query_one_cycle(pat)
  // (2 + 2) stacked = 4 events, fast(2) doubles = 8
  inspect(events.length(), content="8")
}

///|
test "parse stack with per-arg method chain" {
  let pat = unwrap_ok(@mini.parse("stack(s(\"bd\").fast(2), note(\"60\"))"))
  let events = query_one_cycle(pat)
  // bd.fast(2) = 2 events, note(60) = 1 event = 3
  inspect(events.length(), content="3")
}

///|
test "parse stack with single argument is a no-op" {
  let pat = unwrap_ok(@mini.parse("stack(s(\"bd sd\"))"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
}

///|
test "parse stack tolerates whitespace around args" {
  let pat = unwrap_ok(@mini.parse("stack( s(\"bd\") , note(\"60\") )"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
}

///|
test "parse Strudel-style dollar stack lines" {
  let input =
    #|$: s("bd")
    #|$: note("60")
  let pat = unwrap_ok(@mini.parse(input))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
}

///|
test "parse Strudel-style dollar stack lines with per-line methods" {
  let input =
    #|$: s("bd").fast(2)
    #|$: s("hh")
  let pat = unwrap_ok(@mini.parse(input))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
}

///|
test "parse Strudel-style dollar single line is a no-op stack" {
  let pat = unwrap_ok(@mini.parse("$: s(\"bd sd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
}

///|
test "parse_doc lowers Strudel-style dollar stack lines" {
  let input =
    #|$: s("bd")
    #|$: note("60")
  let snapshot = unwrap_mini_snapshot(@mini.parse_snapshot(input))
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(
    snapshot.root().value(),
    content="mini:stack:mini:sound:bd:0:mini:note:60:0",
  )
  inspect(events.length(), content="2")
}

///|
test "Draft accepts dollar stack lines with independent exact origins" {
  let draft = @mini.Draft::new("$: s(\"bd\")\n$: s(\"hh\")")
  let events = draft_snapshot(draft).query(draft_arc())
  assert_named_events(
    events.map(e => e.event()),
    query_one_cycle(unwrap_ok(@mini.parse("stack(s(\"bd\"),s(\"hh\"))"))),
  )
  assert_true(events[0].origin().atom() != events[1].origin().atom())
}

///|
test "parse Strudel-style dollar stack rejects non-dollar content after stack starts" {
  let input =
    #|$: s("bd")
    #|s("hh")
  match @mini.parse(input) {
    Err(_) => ()
    Ok(_) => fail("expected Err for non-dollar line in dollar stack")
  }
}

///|
test "parse stack() with no args returns error" {
  match @mini.parse("stack()") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for stack() with no args")
  }
}

///|
test "parse stack with missing close paren returns error" {
  match @mini.parse("stack(s(\"bd\"), note(\"60\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for unclosed stack(")
  }
}

///|
test "parse nested stack(stack(...), ...) recurses through parse_expr" {
  let pat = unwrap_ok(
    @mini.parse("stack(stack(s(\"bd\"), note(\"60\")), s(\"sd\"))"),
  )
  let events = query_one_cycle(pat)
  // Inner stack: 1 sound (bd) + 1 note = 2 events.
  // Outer stack adds s("sd") = 1 sound. Total 3 events.
  inspect(events.length(), content="3")
}

///|
test "parse stack with trailing comma returns error" {
  // Trailing comma forces another parse_expr() call which sees ')' and
  // fails to find a primary. Locks current behavior — if the diagnostic
  // is ever improved (e.g. "expected expression after ','"), update this
  // test to assert the new message.
  match @mini.parse("stack(s(\"bd\"),)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for stack with trailing comma")
  }
}

///|
test "chord(C) parses C major as 3 stacked notes" {
  let pat = unwrap_ok(@mini.parse("chord(\"C\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  let notes = events.map(ev => ev.value.get("note"))
  assert_true(notes.contains(Some(60.0)))
  assert_true(notes.contains(Some(64.0)))
  assert_true(notes.contains(Some(67.0)))
}

///|
test "chord(Dm G7) sequences two chords" {
  let pat = unwrap_ok(@mini.parse("chord(\"Dm G7\")"))
  let events = query_one_cycle(pat)
  // Dm = 3 notes, G7 = 4 notes = 7 total (sequenced)
  inspect(events.length(), content="7")
}

///|
test "chord with unknown name returns error" {
  match @mini.parse("chord(\"X\")") {
    Err(_) => ()
    Ok(_) => fail("expected Err for unknown chord")
  }
}

///|
test "note notation rejects adjacent note names without separator" {
  match @mini.parse("note(\"C4E4\")") {
    Err(_) => ()
    Ok(_) => fail("expected Err for adjacent note names without separator")
  }
}

///|
test "note notation rejects numeric note followed by letters without separator" {
  match @mini.parse("note(\"60abc\")") {
    Err(_) => ()
    Ok(_) =>
      fail("expected Err for adjacent number and letters without separator")
  }
}

///|
test "parse_doc rejects adjacent note names without separator" {
  match @mini.parse_doc("note(\"C4E4\")") {
    Err(_) => ()
    Ok(_) => fail("expected Err for adjacent note names without separator")
  }
}

///|
test "note(C4 E4 G4) parses note names into MIDI numbers" {
  let pat = unwrap_ok(@mini.parse("note(\"C4 E4 G4\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  assert_eq(events[0].value.entries(), { "note": 60 })
  assert_eq(events[1].value.entries(), { "note": 64 })
  assert_eq(events[2].value.entries(), { "note": 67 })
}

///|
test "note(C D E F G) defaults octave to 4" {
  let pat = unwrap_ok(@mini.parse("note(\"C D E F G\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="5")
  @debug.assert_eq(events[0].value.get("note"), Some(60.0))
  @debug.assert_eq(events[1].value.get("note"), Some(62.0))
  @debug.assert_eq(events[2].value.get("note"), Some(64.0))
  @debug.assert_eq(events[3].value.get("note"), Some(65.0))
  @debug.assert_eq(events[4].value.get("note"), Some(67.0))
}

///|
test "note(C-1) parses negative octave note name" {
  let pat = unwrap_ok(@mini.parse("note(\"C-1\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  @debug.assert_eq(events[0].value.get("note"), Some(0.0))
}

///|
test "parse_doc note(C-1) preserves full negative octave token" {
  let doc = unwrap_doc(@mini.parse_doc("note(\"C-1\")"))
  assert_true(doc.contains_node(pid("mini:note:C-1:0")))
}

///|
test "note(name).jux(rev) works with note names" {
  let pat = unwrap_ok(@mini.parse("note(\"C4 E4\").jux(rev)"))
  let events = query_one_cycle(pat)
  // 2 events left + 2 events right = 4
  inspect(events.length(), content="4")
}

///|
test "stack(chord, s) combines chord and drum primaries" {
  let pat = unwrap_ok(@mini.parse("stack(chord(\"C\"), s(\"bd\"))"))
  let events = query_one_cycle(pat)
  // 3 chord notes + 1 drum = 4
  inspect(events.length(), content="4")
}

///|
test "chord method chain .gain(0.5).pan(-0.5)" {
  let pat = unwrap_ok(@mini.parse("chord(\"C\").gain(0.5).pan(-0.5)"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  for event in events {
    assert_true(event.value.get("gain") == Some(0.5))
    assert_true(event.value.get("pan") == Some(-0.5))
  }
}

///|
test "note(F#3) parses single note with sharp" {
  let pat = unwrap_ok(@mini.parse("note(\"F#3\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  @debug.assert_eq(events[0].value.get("note"), Some(54.0))
}

///|
test "note(C#4 Bb3 D#5) parses various accidentals" {
  let pat = unwrap_ok(@mini.parse("note(\"C#4 Bb3 D#5\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  let notes = events.map(ev => ev.value.get("note"))
  assert_true(notes.contains(Some(61.0))) // C#4
  assert_true(notes.contains(Some(58.0))) // Bb3
  assert_true(notes.contains(Some(75.0))) // D#5
}

///|
test "note notation rejects mixed accidentals" {
  match @mini.parse("note(\"C#b Cb# C#b4\")") {
    Err(_) => ()
    Ok(_) => fail("expected Err for mixed accidentals")
  }
}

///|
test "parse_doc rejects mixed accidentals" {
  match @mini.parse_doc("note(\"C#b\")") {
    Err(_) => ()
    Ok(_) => fail("expected Err for mixed accidentals")
  }
}

///|
test "note(C#4) parses note with sharp and octave" {
  let pat = unwrap_ok(@mini.parse("note(\"C#4\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  @debug.assert_eq(events[0].value.get("note"), Some(61.0))
}

///|
test "chord(C#) parses C-sharp major" {
  let pat = unwrap_ok(@mini.parse("chord(\"C#\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  let notes = events.map(ev => ev.value.get("note"))
  assert_true(notes.contains(Some(61.0))) // C#4
  assert_true(notes.contains(Some(65.0))) // F4
  assert_true(notes.contains(Some(68.0))) // G#4
}

///|
test "chord(F#m7) parses F-sharp minor 7" {
  let pat = unwrap_ok(@mini.parse("chord(\"F#m7\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="4")
  let notes = events.map(ev => ev.value.get("note"))
  assert_true(notes.contains(Some(66.0))) // F#4
  assert_true(notes.contains(Some(69.0))) // A4
  assert_true(notes.contains(Some(73.0))) // C#5
  assert_true(notes.contains(Some(76.0))) // E5
}

///|
test "chord(Bb) parses B-flat major" {
  let pat = unwrap_ok(@mini.parse("chord(\"Bb\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  let notes = events.map(ev => ev.value.get("note"))
  assert_true(notes.contains(Some(70.0))) // Bb4
  assert_true(notes.contains(Some(74.0))) // D5
  assert_true(notes.contains(Some(77.0))) // F5
}

///|
test "chord(C) produces same events each cycle" {
  let pat = unwrap_ok(@mini.parse("chord(\"C\")"))
  let arc1 = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let arc2 = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(1),
    @pattern.Rational::from_int(2),
  )
  let events1 = pat.query(arc1)
  let events2 = pat.query(arc2)
  inspect(events1.length(), content="3")
  inspect(events2.length(), content="3")
  // Verify events in both cycles have the same note values
  for ev in events1 {
    let note = ev.value.get("note")
    assert_true(note == Some(60.0) || note == Some(64.0) || note == Some(67.0))
  }
  for ev in events2 {
    let note = ev.value.get("note")
    assert_true(note == Some(60.0) || note == Some(64.0) || note == Some(67.0))
  }
}

///|
test "chord(C) and note(60 64 67) produce identical events" {
  let pat1 = unwrap_ok(@mini.parse("chord(\"C\")"))
  let pat2 = unwrap_ok(@mini.parse("note(\"60 64 67\")"))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events1 = pat1.query(arc)
  let events2 = pat2.query(arc)
  inspect(events1.length(), content="3")
  inspect(events2.length(), content="3")
  // Same notes (order may differ since chord uses stack and note uses sequence)
  let notes1 = events1.map(ev => ev.value.get("note"))
  let notes2 = events2.map(ev => ev.value.get("note"))
  for n in [Some(60.0), Some(64.0), Some(67.0)] {
    assert_true(notes1.contains(n))
    assert_true(notes2.contains(n))
  }
}
