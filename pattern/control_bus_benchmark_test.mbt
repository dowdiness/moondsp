///|
/// Cost of one bus evaluation per block against the block query the
/// scheduler already makes, over 750 blocks (2 s at 48 kHz / 128).
test "bench/control_bus/per_block" (b : @bench.T) {
  let id = (name : String) => {
    @identity.PatternNodeId::from_string("bus-bench:" + name) catch {
      _ => abort("id")
    }
  }
  let sweep = @pattern.PatternDoc::continuous(
    id=id("sweep"),
    key="lpf",
    f=t => 200.0 + 3800.0 * t,
  )
  let chord = @pattern.PatternDoc::from_pattern(
    id=id("chord"),
    pat=@pattern.chord("Dm9"),
  )
  let doc = @pattern.PatternDoc::merge_control(
    id=id("merge"),
    left=chord,
    right=sweep,
  ).slow(id=id("slow"), factor=@pattern.Rational::from_int(2)) catch {
    _ => abort("doc")
  }
  let snapshot = doc.lower() catch { _ => abort("lower") }
  let arcs = Array::makei(750, n => {
    @pattern.TimeSpan(
      @pattern.Rational(Int64::from_int(n * 128), 48000L),
      @pattern.Rational(Int64::from_int((n + 1) * 128), 48000L),
    )
  })
  b.bench(name="block query with bus bindings", () => {
    for arc in arcs {
      b.keep(snapshot.query_sourced_events(arc))
    }
  })
  let read = snapshot.query_sourced_events(arcs[0])[0]
    .buses()
    .reader("lpf")
    .unwrap()
  b.bench(name="one compiled bus signal per block", () => {
    let mut sum = 0.0
    for arc in arcs {
      sum += read(arc.begin.num, arc.begin.den)
    }
    b.keep(sum)
  })
}
