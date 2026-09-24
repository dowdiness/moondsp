///|
fn bench_origin_draft_doc(
  text : String,
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  let draft = try! Draft::new(text)
  match draft.parsed {
    Ok(source) =>
      match source.body() {
        Pattern(doc) => doc
        Arrangement(_, _) => abort("expected pattern source")
      }
    Err(message) => abort("benchmark parse failed: \{message}")
  }
}

///|
fn bench_origin_arc(index : Int) -> @pattern.TimeSpan {
  let starts = [0, 1, 2, 3]
  let start = @pattern.Rational::from_int(starts[index % starts.length()])
  @pattern.TimeSpan::new(start, start + @pattern.Rational::new(3L, 2L))
}

///|
fn bench_origin_rows(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[(@pattern.TimeSpan?, @pattern.TimeSpan, Map[String, Double])] {
  events.map(event => (event.whole, event.part, event.value.entries()))
}

///|
fn bench_origin_check_parity(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  arcs : Array[@pattern.TimeSpan],
  require_bindings : Bool,
) -> (
  @pattern.PatternSnapshot[@pattern.ControlMap],
  @pattern.PatternSnapshotWithOrigins[@pattern.ControlMap],
) raise {
  let ordinary = try! doc.lower()
  let exact = try! doc.lower_with_origins()
  for arc in arcs {
    assert_true(
      bench_origin_rows(ordinary.query(arc)) ==
      bench_origin_rows(exact.query(arc).map(event => event.event())),
    )
    assert_true(
      ordinary.query_sourced_events(arc).map(event => event.pattern_node_path()) ==
      exact.query(arc).map(event => event.pattern_node_path()),
    )
    if require_bindings {
      let events = exact.query(arc)
      assert_true(events.length() > 0)
      for event in events {
        assert_true(event.origin().bindings().length() > 0)
      }
    }
  }
  (ordinary, exact)
}

///|
test "bench/exact_origin/query" (b : @bench.T) {
  let arcs = [
    bench_origin_arc(0),
    bench_origin_arc(1),
    bench_origin_arc(2),
    bench_origin_arc(3),
  ]
  let direct = bench_origin_check_parity(
    bench_origin_draft_doc("note(\"60 62 64 67\")"),
    arcs,
    false,
  )
  let nested = bench_origin_check_parity(
    bench_origin_draft_doc(
      "let motif = note(\"60 62 64 67\"); let phrase = stack(motif, motif.slow(2)); stack(phrase, phrase.slow(3))",
    ),
    arcs,
    true,
  )
  let direct_index = Ref(0)
  let nested_index = Ref(0)
  b.bench(name="direct/ordinary_sourced", fn() {
    let events = direct.0.query_sourced_events(arcs[direct_index.val])
    direct_index.val = (direct_index.val + 1) % arcs.length()
    b.keep(events)
  })
  b.bench(name="direct/exact_origin", fn() {
    let events = direct.1.query(arcs[direct_index.val])
    direct_index.val = (direct_index.val + 1) % arcs.length()
    b.keep(events)
  })
  b.bench(name="nested_reused/ordinary_sourced", fn() {
    let events = nested.0.query_sourced_events(arcs[nested_index.val])
    nested_index.val = (nested_index.val + 1) % arcs.length()
    b.keep(events)
  })
  b.bench(name="nested_reused/exact_origin", fn() {
    let events = nested.1.query(arcs[nested_index.val])
    nested_index.val = (nested_index.val + 1) % arcs.length()
    b.keep(events)
  })
}

///|
test "bench/exact_origin/prepare" (b : @bench.T) {
  let cases = [
    ("direct", bench_origin_draft_doc("note(\"60 62 64 67\")")),
    (
      "nested_reused",
      bench_origin_draft_doc(
        "let motif = note(\"60 62 64 67\"); let phrase = stack(motif, motif.slow(2)); stack(phrase, phrase.slow(3))",
      ),
    ),
    (
      "shared_32_paths",
      bench_origin_draft_doc(
        "let a = note(\"60\"); let b = stack(a, a); let c = stack(b, b); let d = stack(c, c); let e = stack(d, d); stack(e, e)",
      ),
    ),
  ]
  for (name, doc) in cases {
    b.bench(name="\{name}/cold_exact", fn() {
      b.keep(try! doc.lower_with_origins())
    })
  }
}
