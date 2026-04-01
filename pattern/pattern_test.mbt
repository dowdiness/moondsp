///|
test "silence produces 0 events" {
  let p : Pat[Int] = Pat::silence()
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "silence over multi-cycle produces 0 events" {
  let p : Pat[Int] = Pat::silence()
  let events = p.query(span(0, 1, 4, 1))
  inspect(events.length(), content="0")
}

///|
test "pure produces 1 event per cycle for single cycle query" {
  let p = Pat::pure(42)
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  inspect(events[0].value, content="42")
}

///|
test "pure: event whole spans full cycle [0,1)" {
  let p = Pat::pure(42)
  let events = p.query(span(0, 1, 1, 1))
  match events[0].whole {
    Some(whole) =>
      inspect(
        whole,
        content=(
          #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 1}}
        ),
      )
    None => abort("expected whole")
  }
}

///|
test "pure: event part equals query arc when arc is within cycle" {
  let p = Pat::pure(42)
  let events = p.query(span(0, 1, 1, 1))
  inspect(
    events[0].part,
    content=(
      #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 1}}
    ),
  )
}

///|
test "pure multi-cycle [0,3) produces 3 events" {
  let p = Pat::pure(42)
  let events = p.query(span(0, 1, 3, 1))
  inspect(events.length(), content="3")
}

///|
test "pure slices part to query arc: query [1/4, 3/4)" {
  let p = Pat::pure(42)
  let events = p.query(span(1, 4, 3, 4))
  inspect(events.length(), content="1")
  // part should be clipped to [1/4, 3/4)
  inspect(
    events[0].part,
    content=(
      #|{begin: {num: 1, den: 4}, end_: {num: 3, den: 4}}
    ),
  )
  // whole is still full cycle [0, 1)
  match events[0].whole {
    Some(whole) =>
      inspect(
        whole,
        content=(
          #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 1}}
        ),
      )
    None => abort("expected whole")
  }
}

///|
test "pure slices part across cycle boundary: query [3/4, 5/4)" {
  let p = Pat::pure(42)
  let events = p.query(span(3, 4, 5, 4))
  inspect(events.length(), content="2")
  // first event: part = [3/4, 1), whole = [0, 1)
  inspect(
    events[0].part,
    content=(
      #|{begin: {num: 3, den: 4}, end_: {num: 1, den: 1}}
    ),
  )
  // second event: part = [1, 5/4), whole = [1, 2)
  inspect(
    events[1].part,
    content=(
      #|{begin: {num: 1, den: 1}, end_: {num: 5, den: 4}}
    ),
  )
}

///|
test "fast(2) produces 2 events per cycle with correct part spans" {
  let p = Pat::pure(42).fast(r(2, 1))
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  // first event part: [0, 1/2)
  inspect(
    events[0].part,
    content=(
      #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 2}}
    ),
  )
  // second event part: [1/2, 1)
  inspect(
    events[1].part,
    content=(
      #|{begin: {num: 1, den: 2}, end_: {num: 1, den: 1}}
    ),
  )
}

///|
test "fast(2) transforms whole correctly (half-cycle each)" {
  let p = Pat::pure(42).fast(r(2, 1))
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  match events[0].whole {
    Some(w) =>
      inspect(
        w,
        content=(
          #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 2}}
        ),
      )
    None => abort("expected whole for event 0")
  }
  match events[1].whole {
    Some(w) =>
      inspect(
        w,
        content=(
          #|{begin: {num: 1, den: 2}, end_: {num: 1, den: 1}}
        ),
      )
    None => abort("expected whole for event 1")
  }
}

///|
test "slow(2) halves events: 1 event per cycle, whole spans 2 cycles" {
  let p = Pat::pure(42).slow(r(2, 1))
  // Query cycle 0: the event's whole should span [0, 2)
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="1")
  match events[0].whole {
    Some(w) =>
      inspect(
        w,
        content=(
          #|{begin: {num: 0, den: 1}, end_: {num: 2, den: 1}}
        ),
      )
    None => abort("expected whole")
  }
}

///|
test "rev of fast(2) mirrors the two events" {
  let p = Pat::pure(42).fast(r(2, 1)).rev()
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  // After rev, the first event should be [1/2, 1) and second [0, 1/2)
  inspect(
    events[0].part,
    content=(
      #|{begin: {num: 1, den: 2}, end_: {num: 1, den: 1}}
    ),
  )
  inspect(
    events[1].part,
    content=(
      #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 2}}
    ),
  )
}

///|
test "fast(0) returns silence (no events)" {
  let p = Pat::pure(42).fast(r(0, 1))
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}

///|
test "sequence([pure(1), pure(2), pure(3)]) produces 3 events at thirds" {
  let p = sequence([Pat::pure(1), Pat::pure(2), Pat::pure(3)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="3")
  // Event 0: value=1, part=[0, 1/3)
  inspect(events[0].value, content="1")
  inspect(
    events[0].part,
    content=(
      #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 3}}
    ),
  )
  // Event 1: value=2, part=[1/3, 2/3)
  inspect(events[1].value, content="2")
  inspect(
    events[1].part,
    content=(
      #|{begin: {num: 1, den: 3}, end_: {num: 2, den: 3}}
    ),
  )
  // Event 2: value=3, part=[2/3, 1)
  inspect(events[2].value, content="3")
  inspect(
    events[2].part,
    content=(
      #|{begin: {num: 2, den: 3}, end_: {num: 1, den: 1}}
    ),
  )
}

///|
test "sequence with silence creates rest (2 events from 3 slots)" {
  let p = sequence([Pat::pure(1), Pat::silence(), Pat::pure(3)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="2")
  inspect(events[0].value, content="1")
  inspect(events[1].value, content="3")
}

///|
test "stack merges events from all patterns" {
  let p = stack([Pat::pure(1), Pat::pure(2)])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="2")
}

///|
test "every(2, fast(2), pat): cycle 0 gets 2 events, cycle 1 gets 1" {
  let pat = Pat::pure(42)
  let p = every(2, fn(x) { x.fast(r(2, 1)) }, pat)
  // Cycle 0: every fires, so fast(2) applied → 2 events
  let events0 = p.query(span(0, 1, 1, 1))
  inspect(events0.length(), content="2")
  // Cycle 1: every does not fire, so plain pat → 1 event
  let events1 = p.query(span(1, 1, 2, 1))
  inspect(events1.length(), content="1")
}

///|
test "empty sequence produces 0 events" {
  let p : Pat[Int] = sequence([])
  let events = p.query(span(0, 1, 1, 1))
  inspect(events.length(), content="0")
}
