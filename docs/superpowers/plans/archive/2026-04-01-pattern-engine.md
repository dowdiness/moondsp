# Phase 4: Pattern Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Strudel-inspired pattern algebra in a standalone `pattern/` package with rational time, 8 combinators, and ControlMap output.

**Architecture:** New `pattern/` package with zero dependency on `lib/`. `Pat[A]` is a struct wrapping a query function `(TimeSpan) -> Array[Event[A]]`. Combinators compose these functions. Time uses `Int64`-based `Rational` for exact arithmetic. `ControlMap` = `Map[String, Double]`.

**Tech Stack:** MoonBit, `moonbitlang/quickcheck` (for property tests)

**Spec:** `docs/superpowers/specs/2026-04-01-pattern-engine-design.md`

**Verification after every task:**
```bash
moon check && moon test -p pattern
```

---

### Task 1: Package setup + Rational type

**Files:**
- Create: `pattern/moon.pkg`
- Create: `pattern/rational.mbt`
- Create: `pattern/rational_test.mbt`

- [ ] **Step 1: Create the package config**

Create `pattern/moon.pkg`:

```
import {
  "moonbitlang/quickcheck" @qc,
}
```

- [ ] **Step 2: Create Rational with arithmetic and comparison**

Create `pattern/rational.mbt`:

```moonbit
///|
/// Exact fraction for musical time. Always simplified, denominator > 0.
/// WHY Int64: MoonBit Int is 32-bit. Cross-multiplication for comparison
/// and nested fast/slow transforms overflow 32-bit quickly in live sessions.
pub struct Rational {
  num : Int64
  den : Int64
} derive(Eq, Show)

///|
fn gcd(a : Int64, b : Int64) -> Int64 {
  let mut x = a.abs()
  let mut y = b.abs()
  while y != 0L {
    let t = y
    y = x % y
    x = t
  }
  x
}

///|
pub fn Rational::new(num : Int64, den : Int64) -> Rational {
  if den == 0L {
    abort("Rational: zero denominator")
  }
  let sign : Int64 = if den < 0L { -1L } else { 1L }
  let g = gcd(num, den)
  { num: sign * num / g, den: sign * den / g }
}

///|
pub fn Rational::from_int(n : Int) -> Rational {
  { num: Int64::from_int(n), den: 1L }
}

///|
pub fn Rational::to_double(self : Rational) -> Double {
  self.num.to_double() / self.den.to_double()
}

///|
pub fn Rational::add(self : Rational, other : Rational) -> Rational {
  Rational::new(self.num * other.den + other.num * self.den, self.den * other.den)
}

///|
pub fn Rational::sub(self : Rational, other : Rational) -> Rational {
  Rational::new(self.num * other.den - other.num * self.den, self.den * other.den)
}

///|
pub fn Rational::mul(self : Rational, other : Rational) -> Rational {
  Rational::new(self.num * other.num, self.den * other.den)
}

///|
pub fn Rational::div(self : Rational, other : Rational) -> Rational {
  Rational::new(self.num * other.den, self.den * other.num)
}

///|
pub impl Compare for Rational with compare(self, other) {
  let lhs = self.num * other.den
  let rhs = other.num * self.den
  if lhs < rhs {
    -1
  } else if lhs > rhs {
    1
  } else {
    0
  }
}

///|
pub fn Rational::op_add(self : Rational, other : Rational) -> Rational {
  self.add(other)
}

///|
pub fn Rational::op_sub(self : Rational, other : Rational) -> Rational {
  self.sub(other)
}

///|
pub fn Rational::op_mul(self : Rational, other : Rational) -> Rational {
  self.mul(other)
}

///|
pub fn Rational::op_div(self : Rational, other : Rational) -> Rational {
  self.div(other)
}

///|
/// Floor division: largest integer <= self
pub fn Rational::floor(self : Rational) -> Int64 {
  if self.num >= 0L {
    self.num / self.den
  } else {
    (self.num - self.den + 1L) / self.den
  }
}
```

- [ ] **Step 3: Run `moon check`**

Expected: No errors (unused @qc warning is OK).

- [ ] **Step 4: Write Rational tests**

Create `pattern/rational_test.mbt`:

```moonbit
///|
test "rational simplifies fractions" {
  let r = Rational::new(6L, 4L)
  assert_eq(r.num, 3L)
  assert_eq(r.den, 2L)
}

///|
test "rational normalizes negative denominator" {
  let r = Rational::new(3L, -4L)
  assert_eq(r.num, -3L)
  assert_eq(r.den, 4L)
}

///|
test "rational addition" {
  let a = Rational::new(1L, 3L)
  let b = Rational::new(1L, 3L)
  let c = a + b
  assert_eq(c, Rational::new(2L, 3L))
}

///|
test "rational subtraction" {
  let a = Rational::new(1L, 2L)
  let b = Rational::new(1L, 3L)
  let c = a - b
  assert_eq(c, Rational::new(1L, 6L))
}

///|
test "rational multiplication" {
  let a = Rational::new(2L, 3L)
  let b = Rational::new(3L, 4L)
  let c = a * b
  assert_eq(c, Rational::new(1L, 2L))
}

///|
test "rational division" {
  let a = Rational::new(1L, 2L)
  let b = Rational::new(3L, 4L)
  let c = a / b
  assert_eq(c, Rational::new(2L, 3L))
}

///|
test "rational comparison" {
  let a = Rational::new(1L, 3L)
  let b = Rational::new(1L, 2L)
  assert_true(a < b)
  assert_true(b > a)
  assert_true(a == a)
}

///|
test "rational floor" {
  assert_eq(Rational::new(7L, 3L).floor(), 2L)
  assert_eq(Rational::new(-1L, 3L).floor(), -1L)
  assert_eq(Rational::new(3L, 1L).floor(), 3L)
  assert_eq(Rational::new(0L, 1L).floor(), 0L)
}

///|
test "rational from_int and to_double" {
  let r = Rational::from_int(3)
  assert_eq(r, Rational::new(3L, 1L))
  assert_true((Rational::new(1L, 3L).to_double() - 0.333333).abs() < 0.001)
}

///|
test "panic rational zero denominator" {
  ignore(Rational::new(1L, 0L))
}
```

- [ ] **Step 5: Run tests**

Run: `moon check && moon test -p pattern`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add pattern/ moon.mod.json
git commit -m "feat: add pattern/ package with Rational type (Int64-based exact arithmetic)"
```

---

### Task 2: TimeSpan (Arc)

**Files:**
- Create: `pattern/time.mbt`
- Create: `pattern/time_test.mbt`

- [ ] **Step 1: Create TimeSpan**

Create `pattern/time.mbt`:

```moonbit
///|
/// Half-open time interval [begin, end) with rational boundaries.
pub struct TimeSpan {
  begin : Rational
  end_ : Rational
} derive(Eq, Show)

///|
pub fn TimeSpan::new(begin : Rational, end_ : Rational) -> TimeSpan {
  { begin, end_ }
}

///|
pub fn TimeSpan::duration(self : TimeSpan) -> Rational {
  self.end_ - self.begin
}

///|
pub fn TimeSpan::contains(self : TimeSpan, time : Rational) -> Bool {
  self.begin <= time && time < self.end_
}

///|
/// Returns the intersection of two arcs, or None if disjoint.
pub fn TimeSpan::intersect(
  self : TimeSpan,
  other : TimeSpan,
) -> TimeSpan? {
  let b = if self.begin > other.begin { self.begin } else { other.begin }
  let e = if self.end_ < other.end_ { self.end_ } else { other.end_ }
  if b < e {
    Some(TimeSpan::new(b, e))
  } else {
    None
  }
}

///|
/// Split an arc into per-cycle sub-arcs.
/// WHY: patterns repeat every cycle (Rational 1). A multi-cycle query must
/// be broken into per-cycle arcs so each cycle's events are generated
/// independently with correct positions.
pub fn TimeSpan::whole_cycles(self : TimeSpan) -> Array[TimeSpan] {
  let result : Array[TimeSpan] = []
  let one = Rational::from_int(1)
  let mut cycle_start = Rational::new(self.begin.floor(), 1L)
  // Ensure cycle_start <= self.begin
  if cycle_start > self.begin {
    cycle_start = cycle_start - one
  }
  while cycle_start < self.end_ {
    let cycle_end = cycle_start + one
    match self.intersect(TimeSpan::new(cycle_start, cycle_end)) {
      Some(arc) => result.push(arc)
      None => ()
    }
    cycle_start = cycle_end
  }
  result
}
```

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Write TimeSpan tests**

Create `pattern/time_test.mbt`:

```moonbit
///|
fn r(num : Int, den : Int) -> Rational {
  Rational::new(Int64::from_int(num), Int64::from_int(den))
}

///|
test "timespan duration" {
  let arc = TimeSpan::new(r(1, 4), r(3, 4))
  assert_eq(arc.duration(), r(1, 2))
}

///|
test "timespan contains" {
  let arc = TimeSpan::new(r(0, 1), r(1, 1))
  assert_true(arc.contains(r(0, 1)))
  assert_true(arc.contains(r(1, 2)))
  assert_true(!arc.contains(r(1, 1))) // half-open: end is excluded
  assert_true(!arc.contains(r(-1, 1)))
}

///|
test "timespan intersect overlapping" {
  let a = TimeSpan::new(r(0, 1), r(1, 1))
  let b = TimeSpan::new(r(1, 2), r(3, 2))
  let c = a.intersect(b)
  assert_eq(c, Some(TimeSpan::new(r(1, 2), r(1, 1))))
}

///|
test "timespan intersect disjoint" {
  let a = TimeSpan::new(r(0, 1), r(1, 2))
  let b = TimeSpan::new(r(1, 2), r(1, 1))
  // [0, 0.5) and [0.5, 1) are touching but disjoint (half-open)
  let c = a.intersect(b)
  assert_true(c is None)
}

///|
test "whole_cycles splits multi-cycle arc" {
  let arc = TimeSpan::new(r(0, 1), r(5, 2))
  let cycles = arc.whole_cycles()
  assert_eq(cycles.length(), 3)
  assert_eq(cycles[0], TimeSpan::new(r(0, 1), r(1, 1)))
  assert_eq(cycles[1], TimeSpan::new(r(1, 1), r(2, 1)))
  assert_eq(cycles[2], TimeSpan::new(r(2, 1), r(5, 2)))
}

///|
test "whole_cycles single cycle" {
  let arc = TimeSpan::new(r(0, 1), r(1, 1))
  let cycles = arc.whole_cycles()
  assert_eq(cycles.length(), 1)
  assert_eq(cycles[0], TimeSpan::new(r(0, 1), r(1, 1)))
}

///|
test "whole_cycles partial cycle" {
  let arc = TimeSpan::new(r(1, 4), r(3, 4))
  let cycles = arc.whole_cycles()
  assert_eq(cycles.length(), 1)
  assert_eq(cycles[0], TimeSpan::new(r(1, 4), r(3, 4)))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p pattern`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add pattern/time.mbt pattern/time_test.mbt
git commit -m "feat: add TimeSpan with duration, contains, intersect, whole_cycles"
```

---

### Task 3: Event type + Pat struct + silence + pure

**Files:**
- Create: `pattern/event.mbt`
- Create: `pattern/pattern.mbt`
- Create: `pattern/pattern_test.mbt`

- [ ] **Step 1: Create Event and Pat types**

Create `pattern/event.mbt`:

```moonbit
///|
/// A value positioned in time.
/// `whole`: the event's ideal duration (for gate timing in Phase 5).
/// `part`: the portion intersecting the query arc.
/// `whole` is None for continuous signals (no onset trigger).
pub struct Event[A] {
  whole : TimeSpan?
  part : TimeSpan
  value : A
} derive(Show)
```

Create `pattern/pattern.mbt`:

```moonbit
///|
/// A pattern is a query function from time to events.
/// WHY function, not data: combinators compose functions naturally.
/// The tagless layer (Phase 6) can wrap this without replacing it.
pub struct Pat[A] {
  query : (TimeSpan) -> Array[Event[A]]
}

///|
/// Empty pattern — no events for any query. Essential for rests.
pub fn[A] Pat::silence() -> Pat[A] {
  { query: fn(_arc) { [] } }
}

///|
/// Constant pattern — one event per cycle spanning the full cycle.
pub fn[A] Pat::pure(value : A) -> Pat[A] {
  {
    query: fn(arc) {
      let events : Array[Event[A]] = []
      let cycles = arc.whole_cycles()
      for i = 0; i < cycles.length(); i = i + 1 {
        let cycle_arc = cycles[i]
        let cycle_num = cycle_arc.begin.floor()
        let whole = TimeSpan::new(
          Rational::new(cycle_num, 1L),
          Rational::new(cycle_num + 1L, 1L),
        )
        match whole.intersect(cycle_arc) {
          Some(part) =>
            events.push({ whole: Some(whole), part, value })
          None => ()
        }
      }
      events
    },
  }
}

///|
/// Query a pattern over a time arc.
pub fn[A] Pat::query(self : Pat[A], arc : TimeSpan) -> Array[Event[A]] {
  (self.query)(arc)
}
```

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Write tests for silence and pure**

Create `pattern/pattern_test.mbt`:

```moonbit
///|
fn r(num : Int, den : Int) -> Rational {
  Rational::new(Int64::from_int(num), Int64::from_int(den))
}

///|
fn arc(begin_num : Int, begin_den : Int, end_num : Int, end_den : Int) -> TimeSpan {
  TimeSpan::new(r(begin_num, begin_den), r(end_num, end_den))
}

///|
test "silence produces no events" {
  let pat : Pat[Int] = Pat::silence()
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 0)
}

///|
test "pure produces one event per cycle" {
  let pat = Pat::pure(42)
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 1)
  assert_eq(events[0].value, 42)
  assert_eq(events[0].whole, Some(arc(0, 1, 1, 1)))
  assert_eq(events[0].part, arc(0, 1, 1, 1))
}

///|
test "pure produces multiple events for multi-cycle query" {
  let pat = Pat::pure(42)
  let events = pat.query(arc(0, 1, 3, 1))
  assert_eq(events.length(), 3)
}

///|
test "pure slices event part to query arc" {
  let pat = Pat::pure(42)
  let events = pat.query(arc(1, 4, 3, 4))
  assert_eq(events.length(), 1)
  assert_eq(events[0].whole, Some(arc(0, 1, 1, 1)))
  assert_eq(events[0].part, arc(1, 4, 3, 4))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p pattern`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add pattern/event.mbt pattern/pattern.mbt pattern/pattern_test.mbt
git commit -m "feat: add Event, Pat, silence, and pure pattern constructors"
```

---

### Task 4: fast, slow, rev combinators

**Files:**
- Modify: `pattern/pattern.mbt`
- Modify: `pattern/pattern_test.mbt`

- [ ] **Step 1: Add fast, slow, rev to pattern.mbt**

Append to `pattern/pattern.mbt`:

```moonbit
///|
/// Speed up by factor. Both whole and part are scaled.
/// Returns silence for zero or negative factors (prevents division by zero).
pub fn[A] Pat::fast(self : Pat[A], factor : Rational) -> Pat[A] {
  if factor.num <= 0L {
    return Pat::silence()
  }
  let inv = Rational::from_int(1) / factor
  {
    query: fn(arc) {
      // Scale query arc into the inner pattern's faster time
      let inner_arc = TimeSpan::new(arc.begin * factor, arc.end_ * factor)
      let inner_events = (self.query)(inner_arc)
      // Scale events back to caller's time frame
      let events : Array[Event[A]] = []
      for i = 0; i < inner_events.length(); i = i + 1 {
        let e = inner_events[i]
        let new_part = TimeSpan::new(e.part.begin * inv, e.part.end_ * inv)
        let new_whole = match e.whole {
          Some(w) => Some(TimeSpan::new(w.begin * inv, w.end_ * inv))
          None => None
        }
        events.push({ whole: new_whole, part: new_part, value: e.value })
      }
      events
    },
  }
}

///|
/// Slow down by factor. Sugar for fast(1/factor).
/// Returns silence for zero or negative factors.
pub fn[A] Pat::slow(self : Pat[A], factor : Rational) -> Pat[A] {
  if factor.num <= 0L {
    return Pat::silence()
  }
  self.fast(Rational::from_int(1) / factor)
}

///|
/// Reverse event order within each cycle.
/// Both whole and part are mirrored around the cycle midpoint.
pub fn[A] Pat::rev(self : Pat[A]) -> Pat[A] {
  {
    query: fn(arc) {
      let cycles = arc.whole_cycles()
      let events : Array[Event[A]] = []
      let one = Rational::from_int(1)
      for c = 0; c < cycles.length(); c = c + 1 {
        let cycle_arc = cycles[c]
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        let cycle_end = cycle_start + one
        // Mirror the query within this cycle
        let mirror_begin = cycle_start + (cycle_end - cycle_arc.end_)
        let mirror_end = cycle_start + (cycle_end - cycle_arc.begin)
        let mirrored_arc = TimeSpan::new(mirror_begin, mirror_end)
        let inner_events = (self.query)(mirrored_arc)
        for i = 0; i < inner_events.length(); i = i + 1 {
          let e = inner_events[i]
          let new_part = TimeSpan::new(
            cycle_start + (cycle_end - e.part.end_),
            cycle_start + (cycle_end - e.part.begin),
          )
          let new_whole = match e.whole {
            Some(w) =>
              Some(
                TimeSpan::new(
                  cycle_start + (cycle_end - w.end_),
                  cycle_start + (cycle_end - w.begin),
                ),
              )
            None => None
          }
          events.push({ whole: new_whole, part: new_part, value: e.value })
        }
      }
      events
    },
  }
}
```

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Add tests**

Append to `pattern/pattern_test.mbt`:

```moonbit
///|
test "fast doubles events per cycle" {
  let pat = Pat::pure(42).fast(r(2, 1))
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 2)
  // First event at [0, 1/2), second at [1/2, 1)
  assert_eq(events[0].part, arc(0, 1, 1, 2))
  assert_eq(events[1].part, arc(1, 2, 1, 1))
}

///|
test "fast transforms both whole and part" {
  let pat = Pat::pure(42).fast(r(2, 1))
  let events = pat.query(arc(0, 1, 1, 1))
  // whole should be [0, 1/2) and [1/2, 1) — half-cycle each
  assert_eq(events[0].whole, Some(arc(0, 1, 1, 2)))
  assert_eq(events[1].whole, Some(arc(1, 2, 1, 1)))
}

///|
test "slow halves events per cycle" {
  let pat = Pat::pure(42).slow(r(2, 1))
  let events = pat.query(arc(0, 1, 1, 1))
  // One event spanning [0, 2), but part is sliced to [0, 1)
  assert_eq(events.length(), 1)
  assert_eq(events[0].part, arc(0, 1, 1, 1))
  assert_eq(events[0].whole, Some(arc(0, 1, 2, 1)))
}

///|
test "rev mirrors events within cycle" {
  let pat = Pat::pure(42).fast(r(2, 1)).rev()
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 2)
  // fast(2) produces [0, 1/2) and [1/2, 1)
  // rev mirrors: [1/2, 1) and [0, 1/2)
  assert_eq(events[0].part, arc(1, 2, 1, 1))
  assert_eq(events[1].part, arc(0, 1, 1, 2))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p pattern`
Expected: All tests pass. If rev order is different, adjust test expectations to match actual Strudel semantics.

- [ ] **Step 5: Commit**

```bash
git add pattern/pattern.mbt pattern/pattern_test.mbt
git commit -m "feat: add fast, slow, rev pattern combinators"
```

---

### Task 5: sequence, stack, every combinators

**Files:**
- Create: `pattern/combinators.mbt`
- Modify: `pattern/pattern_test.mbt`

- [ ] **Step 1: Create combinators.mbt**

Create `pattern/combinators.mbt`:

```moonbit
///|
/// Divide each cycle equally among the patterns.
/// sequence([a, b, c]) gives each pattern 1/3 of a cycle.
pub fn[A] sequence(pats : Array[Pat[A]]) -> Pat[A] {
  let n = pats.length()
  if n == 0 {
    return Pat::silence()
  }
  let n_rat = Rational::from_int(n)
  {
    query: fn(arc) {
      let events : Array[Event[A]] = []
      let cycles = arc.whole_cycles()
      for c = 0; c < cycles.length(); c = c + 1 {
        let cycle_arc = cycles[c]
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        for i = 0; i < n; i = i + 1 {
          let i_rat = Rational::from_int(i)
          let slot_begin = cycle_start + i_rat / n_rat
          let slot_end = cycle_start + (i_rat + Rational::from_int(1)) / n_rat
          let slot_arc = TimeSpan::new(slot_begin, slot_end)
          // Only query if this slot overlaps the cycle_arc
          match slot_arc.intersect(cycle_arc) {
            None => continue i + 1
            Some(query_arc) => {
              // Query the sub-pattern in compressed time (fast by N)
              let inner_arc = TimeSpan::new(
                (query_arc.begin - slot_begin) * n_rat,
                (query_arc.end_ - slot_begin) * n_rat,
              )
              let inner_events = pats[i].query(inner_arc)
              // Scale events back to slot position
              let inv_n = Rational::from_int(1) / n_rat
              for j = 0; j < inner_events.length(); j = j + 1 {
                let e = inner_events[j]
                let new_part = TimeSpan::new(
                  e.part.begin * inv_n + slot_begin,
                  e.part.end_ * inv_n + slot_begin,
                )
                let new_whole = match e.whole {
                  Some(w) =>
                    Some(
                      TimeSpan::new(
                        w.begin * inv_n + slot_begin,
                        w.end_ * inv_n + slot_begin,
                      ),
                    )
                  None => None
                }
                events.push(
                  { whole: new_whole, part: new_part, value: e.value },
                )
              }
            }
          }
        }
      }
      events
    },
  }
}

///|
/// Layer patterns simultaneously. All events are merged.
pub fn[A] stack(pats : Array[Pat[A]]) -> Pat[A] {
  if pats.length() == 0 {
    return Pat::silence()
  }
  {
    query: fn(arc) {
      let events : Array[Event[A]] = []
      for i = 0; i < pats.length(); i = i + 1 {
        let inner = pats[i].query(arc)
        for j = 0; j < inner.length(); j = j + 1 {
          events.push(inner[j])
        }
      }
      events
    },
  }
}

///|
/// Apply transformation f every nth cycle.
/// Returns the unmodified pattern if n <= 0.
pub fn[A] every(
  n : Int,
  f : (Pat[A]) -> Pat[A],
  pat : Pat[A],
) -> Pat[A] {
  if n <= 0 {
    return pat
  }
  let n64 = Int64::from_int(n)
  {
    query: fn(arc) {
      let cycles = arc.whole_cycles()
      let events : Array[Event[A]] = []
      for c = 0; c < cycles.length(); c = c + 1 {
        let cycle_arc = cycles[c]
        let cycle_num = cycle_arc.begin.floor()
        // WHY ((cycle_num % n64) + n64) % n64: MoonBit's % can return
        // negative values for negative dividends. This double-mod ensures
        // a non-negative remainder for correct cycle counting with negative
        // cycle numbers (e.g., querying arcs before time 0).
        let remainder = ((cycle_num % n64) + n64) % n64
        let source = if remainder == 0L {
          f(pat)
        } else {
          pat
        }
        let inner = source.query(cycle_arc)
        for i = 0; i < inner.length(); i = i + 1 {
          events.push(inner[i])
        }
      }
      events
    },
  }
}
```

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Add tests**

Append to `pattern/pattern_test.mbt`:

```moonbit
///|
test "sequence divides cycle equally" {
  let pat = sequence([Pat::pure(1), Pat::pure(2), Pat::pure(3)])
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 3)
  assert_eq(events[0].value, 1)
  assert_eq(events[1].value, 2)
  assert_eq(events[2].value, 3)
  assert_eq(events[0].part, arc(0, 1, 1, 3))
  assert_eq(events[1].part, arc(1, 3, 2, 3))
  assert_eq(events[2].part, arc(2, 3, 1, 1))
}

///|
test "sequence with silence creates rest" {
  let pat = sequence([Pat::pure(1), Pat::silence(), Pat::pure(3)])
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 2) // silence produces no events
  assert_eq(events[0].value, 1)
  assert_eq(events[1].value, 3)
}

///|
test "stack merges events from all patterns" {
  let pat = stack([Pat::pure(1), Pat::pure(2)])
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 2)
  assert_eq(events[0].value, 1)
  assert_eq(events[1].value, 2)
}

///|
test "every applies function on nth cycles" {
  let pat = every(
    2,
    fn(p) { p.fast(r(2, 1)) },
    Pat::pure(42),
  )
  // Cycle 0: every triggers, fast(2) → 2 events
  let events_c0 = pat.query(arc(0, 1, 1, 1))
  assert_eq(events_c0.length(), 2)
  // Cycle 1: no trigger → 1 event
  let events_c1 = pat.query(arc(1, 1, 2, 1))
  assert_eq(events_c1.length(), 1)
}

///|
test "empty sequence produces silence" {
  let pat : Pat[Int] = sequence([])
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 0)
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p pattern`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add pattern/combinators.mbt pattern/pattern_test.mbt
git commit -m "feat: add sequence, stack, every combinators"
```

---

### Task 6: ControlMap + note helpers + merge_control

**Files:**
- Create: `pattern/control.mbt`
- Create: `pattern/control_test.mbt`

- [ ] **Step 1: Create control.mbt**

Create `pattern/control.mbt`:

```moonbit
///|
/// Numeric control map — the contract between Pattern and DSP engines.
/// WHY Map[String, Double]: sufficient for numeric synth parameters.
/// Richer types (sample names, arrays) deferred to a future ControlValue enum.
/// WHY newtype struct not type alias: enables ControlMap(m) construction and
/// .0 field access for the inner Map. A bare `type` alias would not support this.
pub struct ControlMap(Map[String, Double]) derive(Show)

///|
fn single_control(key : String, value : Double) -> ControlMap {
  let m : Map[String, Double] = {}
  m[key] = value
  ControlMap(m)
}

///|
pub fn note(n : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("note", n))
}

///|
/// Convert note name to MIDI number.
/// Supports: c, cs/df, d, ds/ef, e, f, fs/gf, g, gs/af, a, as/bf, b
/// followed by octave number. c0 = 12, a4 = 69.
pub fn note_name(name : String) -> Pat[ControlMap] {
  let midi = parse_note_name(name)
  note(midi)
}

///|
fn parse_note_name(name : String) -> Double {
  let len = name.length()
  if len < 2 {
    return 0.0
  }
  // Parse the letter
  let letter = name[0]
  let base_semitone = match letter {
    'c' | 'C' => 0
    'd' | 'D' => 2
    'e' | 'E' => 4
    'f' | 'F' => 5
    'g' | 'G' => 7
    'a' | 'A' => 9
    'b' | 'B' => 11
    _ => 0
  }
  // Check for sharp/flat modifier
  let mut offset = 1
  let mut modifier = 0
  if offset < len {
    match name[offset] {
      's' | '#' => {
        modifier = 1
        offset = offset + 1
      }
      'f' | 'b' =>
        // Only treat as flat if it's not the octave digit
        if offset + 1 < len {
          modifier = -1
          offset = offset + 1
        }
      _ => ()
    }
  }
  // Parse octave number (remaining characters)
  let mut octave = 0
  let mut negative = false
  if offset < len && name[offset] == '-' {
    negative = true
    offset = offset + 1
  }
  while offset < len {
    let c = name[offset]
    if c >= '0' && c <= '9' {
      octave = octave * 10 + (c.to_int() - '0'.to_int())
    }
    offset = offset + 1
  }
  if negative {
    octave = -octave
  }
  let midi = (octave + 1) * 12 + base_semitone + modifier
  midi.to_double()
}

///|
pub fn s_cutoff(f : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("cutoff", f))
}

///|
pub fn s_gain(g : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("gain", g))
}

///|
pub fn s_pan(p : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("pan", p))
}

///|
/// Merge two ControlMap values (right-biased union).
fn merge_maps(a : ControlMap, b : ControlMap) -> ControlMap {
  let result : Map[String, Double] = {}
  a.0.each(fn(k, v) { result[k] = v })
  b.0.each(fn(k, v) { result[k] = v }) // b wins on conflicts
  ControlMap(result)
}

///|
/// Merge controls: for each event in pattern a, merge all overlapping b events.
/// WHY overlap-based (not strict onset-point): Phase 4 controls are all pure()
/// (full-cycle), so overlap == onset for all practical cases. Phase 5 may
/// refine to strict onset-point sampling if fast-changing b patterns are needed.
pub fn merge_control(
  a : Pat[ControlMap],
  b : Pat[ControlMap],
) -> Pat[ControlMap] {
  {
    query: fn(arc) {
      let a_events = a.query(arc)
      let b_events = b.query(arc)
      let events : Array[Event[ControlMap]] = []
      for i = 0; i < a_events.length(); i = i + 1 {
        let ae = a_events[i]
        let mut merged = ae.value
        // Sample all b events that overlap this a event's part
        for j = 0; j < b_events.length(); j = j + 1 {
          let be = b_events[j]
          match ae.part.intersect(be.part) {
            Some(_) => merged = merge_maps(merged, be.value)
            None => ()
          }
        }
        events.push({ whole: ae.whole, part: ae.part, value: merged })
      }
      events
    },
  }
}
```

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Write control tests**

Create `pattern/control_test.mbt`:

```moonbit
///|
fn r(num : Int, den : Int) -> Rational {
  Rational::new(Int64::from_int(num), Int64::from_int(den))
}

///|
fn arc(begin_num : Int, begin_den : Int, end_num : Int, end_den : Int) -> TimeSpan {
  TimeSpan::new(r(begin_num, begin_den), r(end_num, end_den))
}

///|
test "note_name c3 = 48" {
  let pat = note_name("c3")
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events[0].value.0["note"], Some(48.0))
}

///|
test "note_name e3 = 52" {
  let pat = note_name("e3")
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events[0].value.0["note"], Some(52.0))
}

///|
test "note_name g3 = 55" {
  let pat = note_name("g3")
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events[0].value.0["note"], Some(55.0))
}

///|
test "note_name fs4 = 66" {
  let pat = note_name("fs4")
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events[0].value.0["note"], Some(66.0))
}

///|
test "note_name a4 = 69" {
  let pat = note_name("a4")
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events[0].value.0["note"], Some(69.0))
}

///|
test "merge_control combines note and cutoff" {
  let merged = merge_control(note(60.0), s_cutoff(800.0))
  let events = merged.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 1)
  assert_eq(events[0].value.0["note"], Some(60.0))
  assert_eq(events[0].value.0["cutoff"], Some(800.0))
}

///|
test "merge_control right-biased on conflict" {
  let a = note(60.0)
  let b = note(72.0)
  let merged = merge_control(a, b)
  let events = merged.query(arc(0, 1, 1, 1))
  // b's "note" value wins
  assert_eq(events[0].value.0["note"], Some(72.0))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p pattern`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add pattern/control.mbt pattern/control_test.mbt
git commit -m "feat: add ControlMap, note helpers, merge_control combinator"
```

---

### Task 7: End-to-end deliverable test + final verification

**Files:**
- Modify: `pattern/control_test.mbt`

- [ ] **Step 1: Add the deliverable test**

Append to `pattern/control_test.mbt`:

```moonbit
///|
test "deliverable: sequence c3 e3 g3 fast 2 produces 6 events" {
  let pat = sequence([note_name("c3"), note_name("e3"), note_name("g3")]).fast(
    Rational::from_int(2),
  )
  let events = pat.query(arc(0, 1, 1, 1))
  assert_eq(events.length(), 6)
  // First half: c3 e3 g3 in [0, 1/2)
  assert_eq(events[0].value.0["note"], Some(48.0)) // c3
  assert_eq(events[1].value.0["note"], Some(52.0)) // e3
  assert_eq(events[2].value.0["note"], Some(55.0)) // g3
  // Second half: c3 e3 g3 in [1/2, 1)
  assert_eq(events[3].value.0["note"], Some(48.0)) // c3
  assert_eq(events[4].value.0["note"], Some(52.0)) // e3
  assert_eq(events[5].value.0["note"], Some(55.0)) // g3
  // Verify time boundaries are rational (no float)
  assert_eq(events[0].part.begin, Rational::new(0L, 1L))
  assert_eq(events[0].part.end_, Rational::new(1L, 6L))
  assert_eq(events[5].part.begin, Rational::new(5L, 6L))
  assert_eq(events[5].part.end_, Rational::new(1L, 1L))
}
```

- [ ] **Step 2: Run the deliverable test**

Run: `moon check && moon test -p pattern`
Expected: All tests pass, including the end-to-end deliverable.

- [ ] **Step 3: Run the full project test suite**

Run: `moon test`
Expected: 331 existing DSP tests + all new pattern tests pass. The pattern package is independent — no interference.

- [ ] **Step 4: Run `moon info && moon fmt`**

Expected: `.mbti` file generated for pattern package. All files formatted.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: complete Phase 4 Pattern Engine deliverable"
```
