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
    content=(
      #|{ begin: { num: 0, den: 1 }, end_: { num: 1, den: 1 } }
    ),
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
    content=(
      #|{ begin: { num: 0, den: 1 }, end_: { num: 1, den: 3 } }
    ),
  )
  inspect(
    events[1].part,
    content=(
      #|{ begin: { num: 1, den: 3 }, end_: { num: 2, den: 3 } }
    ),
  )
  inspect(
    events[2].part,
    content=(
      #|{ begin: { num: 2, den: 3 }, end_: { num: 1, den: 1 } }
    ),
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

///|
test "filter_map: keeps matching events with transformed value" {
  // sequence of 3 values, filter_map keeps only even numbers doubled
  let p = sequence([Pat::pure(2), Pat::pure(3), Pat::pure(4)])
  let filtered = p.filter_map(fn(x) {
    if x % 2 == 0 {
      Some(x * 2)
    } else {
      None
    }
  })
  let events = filtered.query(span(0, 1, 1, 1))
  // Only 2 and 4 pass the filter → 2 events
  inspect(events.length(), content="2")
  inspect(events[0].value, content="4")
  inspect(events[1].value, content="8")
}

///|
test "filter_map: removes all non-matching events" {
  let p = Pat::pure(1)
  let filtered = p.filter_map(fn(_x) { None })
  let events = filtered.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "filter_map: on silence returns empty" {
  let p : Pat[Int] = Pat::silence()
  let filtered = p.filter_map(fn(x) { Some(x + 1) })
  let events = filtered.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "euclid: (3,8) tresillo — 3 pulses at steps 0, 3, 6" {
  let pat = Pat::pure(1)
  let p = pat.euclid(3, 8)
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  // Hits at slots 0, 3, 6 of 8 → parts [0,1/8), [3/8,1/2), [3/4,7/8)
  inspect(
    events[0].part,
    content=(
      #|{ begin: { num: 0, den: 1 }, end_: { num: 1, den: 8 } }
    ),
  )
  inspect(
    events[1].part,
    content=(
      #|{ begin: { num: 3, den: 8 }, end_: { num: 1, den: 2 } }
    ),
  )
  inspect(
    events[2].part,
    content=(
      #|{ begin: { num: 3, den: 4 }, end_: { num: 7, den: 8 } }
    ),
  )
}

///|
test "euclid: (5,8) cinquillo — 5 pulses at steps 0, 2, 3, 5, 6" {
  let p = Pat::pure(1).euclid(5, 8)
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="5")
  // Verify slot positions: 0, 2, 3, 5, 6 (each slot is 1/8)
  inspect(
    events[0].part,
    content=(
      #|{ begin: { num: 0, den: 1 }, end_: { num: 1, den: 8 } }
    ),
  )
  inspect(
    events[1].part,
    content=(
      #|{ begin: { num: 1, den: 4 }, end_: { num: 3, den: 8 } }
    ),
  )
  inspect(
    events[2].part,
    content=(
      #|{ begin: { num: 3, den: 8 }, end_: { num: 1, den: 2 } }
    ),
  )
  inspect(
    events[3].part,
    content=(
      #|{ begin: { num: 5, den: 8 }, end_: { num: 3, den: 4 } }
    ),
  )
  inspect(
    events[4].part,
    content=(
      #|{ begin: { num: 3, den: 4 }, end_: { num: 7, den: 8 } }
    ),
  )
}

///|
test "euclid: rotation=1 shifts (3,8) pulses left by one slot" {
  let p = Pat::pure(1).euclid(3, 8, rotation=1)
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  // Original tresillo: hits at 0,3,6
  // Left-rotate by 1 → hits at -1,2,5 → wrapped: 7,2,5 → sorted by time: 2,5,7
  inspect(
    events[0].part,
    content=(
      #|{ begin: { num: 1, den: 4 }, end_: { num: 3, den: 8 } }
    ),
  )
  inspect(
    events[1].part,
    content=(
      #|{ begin: { num: 5, den: 8 }, end_: { num: 3, den: 4 } }
    ),
  )
  inspect(
    events[2].part,
    content=(
      #|{ begin: { num: 7, den: 8 }, end_: { num: 1, den: 1 } }
    ),
  )
}

///|
test "euclid: k>=n produces n pulses (every slot)" {
  let p = Pat::pure(1).euclid(8, 8)
  inspect(p.query(span(0, 1, 1, 1)).length(), content="8")
  let p2 = Pat::pure(1).euclid(10, 8)
  inspect(p2.query(span(0, 1, 1, 1)).length(), content="8")
}

///|
test "euclid: k=0 or k<0 produces silence" {
  let p0 = Pat::pure(1).euclid(0, 8)
  inspect(p0.query(span(0, 1, 1, 1)).length(), content="0")
  let pn = Pat::pure(1).euclid(-3, 8)
  inspect(pn.query(span(0, 1, 1, 1)).length(), content="0")
}

///|
test "euclid: n<=0 produces silence" {
  let p = Pat::pure(1).euclid(3, 0)
  inspect(p.query(span(0, 1, 1, 1)).length(), content="0")
}

///|
test "euclid: rotation wraps modulo n (rotation=8 same as 0)" {
  let pa = Pat::pure(1).euclid(3, 8)
  let pb = Pat::pure(1).euclid(3, 8, rotation=8)
  let ea = pa.query(span(0, 1, 1, 1))
  let eb = pb.query(span(0, 1, 1, 1))
  inspect(ea.length() == eb.length(), content="true")
  for i in 0..<ea.length() {
    inspect(ea[i].part == eb[i].part, content="true")
  }
}

///|
test "degrade_by(0.0) keeps every event" {
  let p = sequence([Pat::pure(1), Pat::pure(2), Pat::pure(3), Pat::pure(4)])
  let d = p.degrade_by(0.0)
  inspect(d.query(span(0, 1, 1, 1)).length(), content="4")
}

///|
test "degrade_by(1.0) drops every event (silence)" {
  let p = sequence([Pat::pure(1), Pat::pure(2), Pat::pure(3), Pat::pure(4)])
  let d = p.degrade_by(1.0)
  inspect(d.query(span(0, 1, 1, 1)).length(), content="0")
}

///|
test "degrade_by is deterministic — same query yields same result" {
  let p = sequence([
    Pat::pure(1),
    Pat::pure(2),
    Pat::pure(3),
    Pat::pure(4),
    Pat::pure(5),
    Pat::pure(6),
    Pat::pure(7),
    Pat::pure(8),
  ])
  let d = p.degrade_by(0.5)
  let a = d.query(span(0, 1, 1, 1))
  let b = d.query(span(0, 1, 1, 1))
  inspect(a.length() == b.length(), content="true")
  for i in 0..<a.length() {
    inspect(a[i].value == b[i].value, content="true")
  }
}

///|
test "degrade_by(0.5) drops some but not all events from 32-event pattern" {
  let pats : Array[Pat[Int]] = []
  for i in 0..<32 {
    pats.push(Pat::pure(i))
  }
  let p = sequence(pats)
  let d = p.degrade_by(0.5)
  let kept = d.query(span(0, 1, 1, 1)).length()
  inspect(kept > 0 && kept < 32, content="true")
}

///|
test "every(2, rev) on sequence — cycle 0 timing reversed, cycle 1 not" {
  // Pat::rev mirrors event *timing*, not array order. So we check the
  // part.begin of the first array element: under rev cycle 0, the first
  // element's slot moves from [0, 1/3) to [2/3, 1).
  let p = sequence([Pat::pure(36), Pat::pure(38), Pat::pure(42)])
  let p2 = every(2, fn(x) { x.rev() }, p)
  let cyc0 = p2.query(span(0, 1, 1, 1))
  inspect(cyc0.length(), content="3")
  inspect(
    cyc0[0].part,
    content=(
      #|{ begin: { num: 2, den: 3 }, end_: { num: 1, den: 1 } }
    ),
  )
  // Cycle 1: every does not fire — value 36 returns to slot [1, 4/3).
  let cyc1 = p2.query(span(1, 1, 2, 1))
  inspect(
    cyc1[0].part,
    content=(
      #|{ begin: { num: 1, den: 1 }, end_: { num: 4, den: 3 } }
    ),
  )
}

///|
test "degrade_by clamps p outside [0,1]" {
  let p = sequence([Pat::pure(1), Pat::pure(2)])
  inspect(p.degrade_by(-0.5).query(span(0, 1, 1, 1)).length(), content="2")
  inspect(p.degrade_by(2.0).query(span(0, 1, 1, 1)).length(), content="0")
}

///|
test "filter_map: preserves event timing (whole and part spans unchanged)" {
  let p = Pat::pure(42)
  let filtered = p.filter_map(fn(x) { Some(x + 1) })
  let events = filtered.query(span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  inspect(events[0].value, content="43")
  // whole should be [0, 1)
  inspect(
    events[0].whole,
    content=(
      #|Some({ begin: { num: 0, den: 1 }, end_: { num: 1, den: 1 } })
    ),
  )
  // part should be [0, 1)
  inspect(
    events[0].part,
    content=(
      #|{ begin: { num: 0, den: 1 }, end_: { num: 1, den: 1 } }
    ),
  )
}
