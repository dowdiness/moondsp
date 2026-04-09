///|
test "sequence: empty array produces silence (0 events)" {
  let p : Pat[Int] = sequence([])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "sequence: single pattern produces 1 event compressed to full cycle" {
  let p = sequence([Pat::pure(99)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  inspect(events[0].value, content="99")
  // whole should span [0, 1) — the single slot is the entire cycle
  inspect(
    events[0].part,
    content="{begin: {num: 0, den: 1}, end_: {num: 1, den: 1}}",
  )
}

///|
test "sequence: 3 patterns produce 3 events with correct values and thirds" {
  let p = sequence([Pat::pure(10), Pat::pure(20), Pat::pure(30)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  inspect(events[0].value, content="10")
  inspect(events[1].value, content="20")
  inspect(events[2].value, content="30")
  // part spans: [0, 1/3), [1/3, 2/3), [2/3, 1)
  inspect(
    events[0].part,
    content="{begin: {num: 0, den: 1}, end_: {num: 1, den: 3}}",
  )
  inspect(
    events[1].part,
    content="{begin: {num: 1, den: 3}, end_: {num: 2, den: 3}}",
  )
  inspect(
    events[2].part,
    content="{begin: {num: 2, den: 3}, end_: {num: 1, den: 1}}",
  )
}

///|
test "sequence: multi-cycle query [0, 2) doubles event count" {
  let p = sequence([Pat::pure(1), Pat::pure(2)])
  let events = p.query(span(0, 1, 2, 1))
  // 2 events per cycle * 2 cycles = 4
  inspect(events.length(), content="4")
  // Cycle 0: values 1, 2
  inspect(events[0].value, content="1")
  inspect(events[1].value, content="2")
  // Cycle 1: values 1, 2 again
  inspect(events[2].value, content="1")
  inspect(events[3].value, content="2")
}

///|
test "stack: empty array produces silence (0 events)" {
  let p : Pat[Int] = stack([])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "stack: 2 patterns produce 2 events per cycle (parallel)" {
  let p = stack([Pat::pure(1), Pat::pure(2)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="1")
  inspect(events[1].value, content="2")
}

///|
test "stack: 3 patterns produce 3 events per cycle" {
  let p = stack([Pat::pure(10), Pat::pure(20), Pat::pure(30)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  inspect(events[0].value, content="10")
  inspect(events[1].value, content="20")
  inspect(events[2].value, content="30")
}

///|
test "every: n=1 always applies f (doubles events every cycle)" {
  let pat = Pat::pure(42)
  let p = every(1, fn(x) { x.fast(r(2, 1)) }, pat)
  // Cycle 0: f applied → 2 events
  let events0 = p.query(span(0, 1, 1, 1))
  inspect(events0.length(), content="2")
  // Cycle 1: f applied → 2 events
  let events1 = p.query(span(1, 1, 2, 1))
  inspect(events1.length(), content="2")
}

///|
test "every: n=3 applies f on cycle 0 but not on cycles 1 and 2" {
  let pat = Pat::pure(42)
  let p = every(3, fn(x) { x.fast(r(2, 1)) }, pat)
  // Cycle 0: f applied → 2 events
  let events0 = p.query(span(0, 1, 1, 1))
  inspect(events0.length(), content="2")
  // Cycle 1: no f → 1 event
  let events1 = p.query(span(1, 1, 2, 1))
  inspect(events1.length(), content="1")
  // Cycle 2: no f → 1 event
  let events2 = p.query(span(2, 1, 3, 1))
  inspect(events2.length(), content="1")
}

///|
test "every: n<=0 returns pattern unchanged" {
  let pat = Pat::pure(42)
  let p0 = every(0, fn(x) { x.fast(r(2, 1)) }, pat)
  let p_neg = every(-1, fn(x) { x.fast(r(2, 1)) }, pat)
  // Both should behave like the original pat → 1 event per cycle
  let events0 = p0.query(span(0, 1, 1, 1))
  inspect(events0.length(), content="1")
  let events_neg = p_neg.query(span(0, 1, 1, 1))
  inspect(events_neg.length(), content="1")
}
