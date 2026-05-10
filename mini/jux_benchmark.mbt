///|
const BENCH_JUX_REV : String = "s(\"bd sd hh sd\").jux(rev)"

///|
const BENCH_JUX_FAST : String = "s(\"bd sd hh sd\").jux(fast(2))"

///|
const BENCH_JUX_STACK : String = "stack(s(\"bd sd\"), note(\"60 64\")).jux(rev)"

///|
test "bench/jux/parse" (b : @bench.T) {
  b.bench(name="s_rev", fn() {
    let result = parse(BENCH_JUX_REV)
    b.keep(result)
  })
  b.bench(name="s_fast", fn() {
    let result = parse(BENCH_JUX_FAST)
    b.keep(result)
  })
  b.bench(name="stack_rev", fn() {
    let result = parse(BENCH_JUX_STACK)
    b.keep(result)
  })
}
