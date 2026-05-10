///|
fn bench_one_cycle() -> TimeSpan {
  TimeSpan::new(Rational::from_int(0), Rational::from_int(1))
}

///|
fn bench_jux_base_pattern() -> Pat[ControlMap] {
  sequence([note(60.0), note(64.0), note(67.0), note(72.0)])
}

///|
fn bench_jux_rev_pattern() -> Pat[ControlMap] {
  bench_jux_base_pattern().jux(fn(p) { p.rev() })
}

///|
fn bench_jux_fast_pattern() -> Pat[ControlMap] {
  bench_jux_base_pattern().jux(fn(p) { p.fast(Rational::from_int(2)) })
}

///|
test "bench/jux/query" (b : @bench.T) {
  let arc = bench_one_cycle()
  let rev = bench_jux_rev_pattern()
  let fast = bench_jux_fast_pattern()
  b.bench(name="rev_4step", fn() {
    let events = rev.query(arc)
    b.keep(events)
  })
  b.bench(name="fast_4step", fn() {
    let events = fast.query(arc)
    b.keep(events)
  })
}
