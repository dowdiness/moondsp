///|
fn atom_id(
  serial : Int64,
) -> @identity.SourceAtomId raise @identity.StableIdError {
  @identity.SourceAtomId::SourceAtomId(
    @identity.SourceEpoch::SourceEpoch(1L),
    serial,
  )
}

///|
fn origin_note(
  name : String,
  serial : Int64,
  pitch : Double,
) -> PatternDoc[ControlMap] raise @identity.StableIdError {
  PatternDoc::control_atom(
    id=pid(name),
    source_atom=atom_id(serial),
    key="note",
    value=pitch,
  )
}

///|
fn resolved_use(
  name : String,
  definition : PatternDoc[ControlMap],
  reference_serial : Int64,
  binding_serial : Int64,
) -> PatternDoc[ControlMap] raise @identity.StableIdError {
  let epoch = @identity.SourceEpoch::SourceEpoch(1L)
  PatternDoc::reference_with_binding(
    id=pid(name),
    resolved_reference=ResolvedReference::ResolvedReference(
      definition~,
      definition_id=@identity.DefinitionId::DefinitionId(epoch, 100L),
      reference=@identity.ReferenceId::ReferenceId(epoch, reference_serial),
      binding=@identity.ReferenceBindingId::ReferenceBindingId(
        epoch, binding_serial,
      ),
    ),
  )
}

///|
fn musical_rows(
  events : Array[Event[ControlMap]],
) -> Array[(TimeSpan?, TimeSpan, Map[String, Double])] {
  events.map(event => (event.whole, event.part, event.value.entries()))
}

///|
test "exact compiler shares musical kernels without changing material metadata" {
  let a = origin_note("a", 1L, 60.0)
  let b = origin_note("b", 2L, 64.0)
  let base = PatternDoc::sequence(id=pid("sequence"), docs=[a, b])
  let raw = sequence([note(60.0), note(64.0)])
  let factor = Rational::from_int(2)
  let docs = [
    base,
    base.fast(id=pid("fast"), factor~),
    base.slow(id=pid("slow"), factor~),
    base.rev(id=pid("rev")),
    base.gate(id=pid("gate"), factor=Rational::new(1L, 3L)),
    base.euclid(id=pid("euclid"), k=3, n=8, rotation=2),
    base.degrade_by(id=pid("degrade"), p=0.4, seed=71),
    base.every(id=pid("every"), n=2, transform=TimeTransform::Fast(factor)),
    base.jux(id=pid("jux"), transform=TimeTransform::Reverse),
    PatternDoc::stack(id=pid("stack"), docs=[
      a.slow(id=pid("a-slow"), factor~),
      b.fast(id=pid("b-fast"), factor~),
    ]),
  ]
  let runtime = [
    raw,
    raw.fast(factor),
    raw.slow(factor),
    raw.rev(),
    raw.gate(Rational::new(1L, 3L)),
    raw.euclid(3, 8, rotation=2),
    raw.degrade_by(0.4, seed=71),
    every(2, p => p.fast(factor), raw),
    raw.jux(p => p.rev()),
    stack([note(60.0).slow(factor), note(64.0).fast(factor)]),
  ]
  let arc = doc_span(-5, 4, 9, 4)
  for index in 0..<docs.length() {
    let exact = docs[index].lower_with_origins()
    let general = docs[index].lower()
    let projected = exact.as_snapshot()
    let events = exact.query(arc)
    @debug.assert_eq(
      musical_rows(events.map(event => event.event())),
      musical_rows(runtime[index].query(arc)),
    )
    @debug.assert_eq(
      musical_rows(projected.query(arc)),
      musical_rows(general.query(arc)),
    )
    @debug.assert_eq(
      events.map(event => event.pattern_node_path()),
      general.query_sourced_events(arc).map(event => event.pattern_node_path()),
    )
    for event in events {
      let expected = if event.event().value.get("note") == Some(60.0) {
        atom_id(1L)
      } else {
        atom_id(2L)
      }
      @debug.assert_eq(event.origin().atom(), expected)
      @debug.assert_eq(event.origin().bindings(), [])
    }
    let entries = exact.pat().entries()
    let raw_entries = runtime[index].entries()
    @debug.assert_eq(entries.length(), raw_entries.length())
    for slot in 0..<entries.length() {
      @debug.assert_eq(entries[slot].entry_key(), raw_entries[slot].entry_key())
      @debug.assert_eq(
        entries[slot].entry_period(),
        raw_entries[slot].entry_period(),
      )
      @debug.assert_eq(
        entries[slot].same_content(raw_entries[slot]),
        raw_entries[slot].same_content(raw_entries[slot]),
      )
      @debug.assert_eq(exact.entry_key(slot), general.entry_key(slot))
      @debug.assert_eq(
        musical_rows(
          exact.query_for_entry(slot, arc).map(event => event.event()),
        ),
        musical_rows(
          general
          .query_sourced_events_for_entry(slot, arc)
          .map(event => event.event()),
        ),
      )
    }
  }
}

///|
test "control providers keep left origin and overlap precedence including zero gain" {
  let left = origin_note("note", 1L, 60.0)
  let provider = PatternDoc::reference(
    id=pid("provider"),
    definition=PatternDoc::from_pattern(
      id=pid("controls"),
      pat=stack([control("gain", 0.8), control("gain", 0.0)]),
    ),
  )
  let doc = PatternDoc::merge_control(id=pid("merge"), left~, right=provider)
  let snapshot = doc.lower_with_origins()
  let events = snapshot.query(doc_span(1, 4, 3, 4))
  guard events is [event] else { fail("expected one primary note") }
  @debug.assert_eq(event.event().value.get("gain"), Some(0.0))
  @debug.assert_eq(event.event().whole, Some(doc_span(0, 1, 1, 1)))
  @debug.assert_eq(event.event().part, doc_span(1, 4, 3, 4))
  @debug.assert_eq(event.origin().atom(), atom_id(1L))
  @debug.assert_eq(event.origin().bindings(), [])
  @debug.assert_eq(event.pattern_node_path().nodes().map(id => id.value()), [
    "merge", "note", "provider", "controls",
  ])
}

///|
test "filtering changes values but retains source and exact control routing" {
  let doc = PatternDoc::stack(id=pid("chord"), docs=[
    origin_note("tone-c", 1L, 60.0),
    origin_note("tone-e", 1L, 64.0),
    origin_note("other", 2L, 67.0),
  ]).filter_map(id=pid("filter"), f=cm => {
    match cm.get("note") {
      Some(64.0) => None
      Some(pitch) => Some(cm.set("note", pitch + 12.0))
      None => None
    }
  })
  let snapshot = doc.lower_with_origins().select_control("note", value=72.0)
  guard snapshot.query(doc_span(0, 1, 1, 1)) is [event] else {
    fail("expected selected transposed chord tone")
  }
  @debug.assert_eq(event.origin().atom(), atom_id(1L))
  @debug.assert_eq(event.pattern_node_path().nodes().map(id => id.value()), [
    "filter", "chord", "tone-c",
  ])
  @debug.assert_eq(event.event().value.get("note"), Some(72.0))
  @debug.assert_eq(
    snapshot.query_for_entry(1, doc_span(0, 1, 1, 1)).length(),
    0,
  )
  @debug.assert_eq(
    snapshot.query_for_entry(-1, doc_span(0, 1, 1, 1)).length(),
    0,
  )
  @debug.assert_eq(
    snapshot.query_for_entry(3, doc_span(0, 1, 1, 1)).length(),
    0,
  )
  @debug.assert_eq(snapshot.entry_key(0), doc.lower().entry_key(0))
}

///|
test "nested reference bindings are immutable outer to inner and distinct per use" {
  let definition = resolved_use("inner", origin_note("atom", 1L, 60.0), 3L, 4L)
  let left = resolved_use("left", definition, 5L, 6L)
  let right = resolved_use("right", definition, 7L, 8L)
  let snapshot = PatternDoc::stack(id=pid("mix"), docs=[left, right]).lower_with_origins()
  let arc = doc_span(0, 1, 1, 1)
  guard snapshot.query(arc) is [a, b] else {
    fail("expected both reference uses")
  }
  @debug.assert_eq(a.origin().atom(), b.origin().atom())
  @debug.assert_eq(
    a.origin().bindings().map(binding => binding.id().serial()),
    [6L, 4L],
  )
  @debug.assert_eq(
    b.origin().bindings().map(binding => binding.id().serial()),
    [8L, 4L],
  )
  @debug.assert_eq(a.pattern_node_path().nodes().map(id => id.value()), [
    "mix", "left", "inner", "atom",
  ])
  @debug.assert_eq(b.pattern_node_path().nodes().map(id => id.value()), [
    "mix", "right", "inner", "atom",
  ])
  assert_true(snapshot.entry_key(0) != snapshot.entry_key(1))
  let copy = a.origin().bindings()
  copy.clear()
  @debug.assert_eq(
    snapshot.query(arc)[0]
    .origin()
    .bindings()
    .map(binding => binding.id().serial()),
    [6L, 4L],
  )
  @debug.assert_eq(snapshot.query_for_entry(1, arc)[0].origin(), b.origin())
}

///|
test "same music refreshes origins through reused cache without changing entry identity" {
  let cache : PatternLoweringCache[ControlMap] = PatternLoweringCache::new()
  let before_doc = resolved_use("use", origin_note("atom", 1L, 60.0), 3L, 4L)
  let after_doc = resolved_use("use", origin_note("atom", 2L, 60.0), 3L, 5L)
  // Populate general specialization first; exact compilation must not reuse it.
  ignore(before_doc.lower_with_cache(cache))
  let before = before_doc.lower_with_origins(cache~)
  let after = after_doc.lower_with_origins(cache~)
  let arc = doc_span(0, 1, 1, 1)
  assert_true(before.pat().same_content(after.pat()))
  @debug.assert_eq(before.entry_key(0), after.entry_key(0))
  @debug.assert_eq(before.query(arc)[0].origin().atom(), atom_id(1L))
  @debug.assert_eq(after.query(arc)[0].origin().atom(), atom_id(2L))
  @debug.assert_eq(
    before.query(arc)[0]
    .origin()
    .bindings()
    .map(binding => binding.id().serial()),
    [4L],
  )
  @debug.assert_eq(
    after.query(arc)[0]
    .origin()
    .bindings()
    .map(binding => binding.id().serial()),
    [5L],
  )
  @debug.assert_eq(
    before_doc.lower_with_origins(cache~).query(arc)[0].origin(),
    before.query(arc)[0].origin(),
  )
  let old_degraded = before_doc
    .degrade_by(id=pid("random"), p=0.5, seed=37)
    .lower_with_origins(cache~)
  let new_degraded = after_doc
    .degrade_by(id=pid("random"), p=0.5, seed=37)
    .lower_with_origins(cache~)
  @debug.assert_eq(
    musical_rows(old_degraded.pat().query(doc_span(-4, 1, 8, 1))),
    musical_rows(new_degraded.pat().query(doc_span(-4, 1, 8, 1))),
  )
}

///|
test "exact lowering rejects missing attribution before returning a snapshot" {
  let cache : PatternLoweringCache[Int] = PatternLoweringCache::new()
  let runtime = PatternDoc::pure(id=pid("runtime"), value=1)
  ignore(runtime.lower_with_cache(cache))
  let missing_atom = try {
    ignore(runtime.lower_with_origins(cache~))
    None
  } catch {
    error => Some(error)
  }
  @debug.assert_eq(
    missing_atom,
    Some(PatternDocError::MissingAtomOrigin(pid("runtime"))),
  )
  let custom = PatternDoc::from_pattern(id=pid("opaque"), pat=Pat::pure(1))
  let missing_opaque = try {
    ignore(custom.lower_with_origins(cache~))
    None
  } catch {
    error => Some(error)
  }
  @debug.assert_eq(
    missing_opaque,
    Some(PatternDocError::MissingAtomOrigin(pid("opaque"))),
  )
  let reference = PatternDoc::reference(
    id=pid("reference"),
    definition=PatternDoc::atom(
      id=pid("atom"),
      source_atom=atom_id(1L),
      value=1,
    ),
  )
  let missing_binding = try {
    ignore(reference.lower_with_origins(cache~))
    None
  } catch {
    error => Some(error)
  }
  @debug.assert_eq(
    missing_binding,
    Some(PatternDocError::MissingReferenceBinding(pid("reference"))),
  )
  let silence : PatternDoc[Int] = PatternDoc::silence(id=pid("silence"))
  @debug.assert_eq(
    silence.lower_with_origins().query(doc_span(0, 1, 1, 1)).length(),
    0,
  )
  @debug.assert_eq(
    runtime.lower().query(doc_span(0, 1, 1, 1)).map(event => event.value),
    [1],
  )
}
