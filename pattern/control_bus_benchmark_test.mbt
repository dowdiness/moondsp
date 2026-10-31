///|
/// PROTOTYPE cost check: one bus evaluation per block against the block query
/// the scheduler already makes, over 750 blocks (2 s at 48 kHz / 128).
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
  let snapshot = doc.lower_with_buses() catch { _ => abort("buses") }
  let plain = doc.lower() catch { _ => abort("lower") }
  let arcs = Array::makei(750, n => {
    @pattern.TimeSpan(
      @pattern.Rational(Int64::from_int(n * 128), 48000L),
      @pattern.Rational(Int64::from_int((n + 1) * 128), 48000L),
    )
  })
  b.bench(name="existing block query (lower)", () => {
    for arc in arcs {
      b.keep(plain.query(arc))
    }
  })
  b.bench(name="block query with bus bindings", () => {
    for arc in arcs {
      b.keep(snapshot.query(arc))
    }
  })
  b.bench(name="one bus query per block (reference form)", () => {
    for arc in arcs {
      b.keep(snapshot.query_bus_value(0, arc))
    }
  })
  let values = Array::make(snapshot.bus_count(), 0.0)
  b.bench(name="one compiled bus signal per block", () => {
    for arc in arcs {
      snapshot.evaluate_all(arc.begin, values)
    }
    b.keep(values)
  })
}
