///|
/// ADR-0024: every time transform maps outer time to child time piecewise
/// as `a·t + b`. `tm_reference` writes those maps from the ADR's table,
/// independently of the code under test, and the tests below check random
/// chains of transforms against it, for event queries and for bus signals
/// alike.
#derive(Eq, Debug)
priv enum TimeOp {
  /// Child time = t × num / den (`fast`, or `slow` when num < den).
  Scale(Int64, Int64)
  /// `rev`: t -> 2c + 1 - t in cycle c.
  Mirror
  /// Slot `i` of a sequence whose slots have these weights (a plain
  /// sequence when they are equal); the other slots are silent.
  Slot(Int32, Array[Int32])
  /// `euclid(3, 8)`: the child in slots 0, 3, and 6 of eight.
  Tresillo
}

///|
/// Where a placement puts the outer clock: local time `(t − 1/3) · 5/7`.
/// Its offset, −5/21, has a denominator that is neither 1 nor the rate's.
let tm_origin : @pattern.Rational = @pattern.Rational(1L, 3L)

///|
let tm_rate : @pattern.Rational = @pattern.Rational(5L, 7L)

///|
fn tm_placement() -> @pattern.Placement {
  @pattern.Placement(origin=tm_origin, rate=tm_rate)
}

///|
fn tm_r(num : Int64, den : Int64) -> @pattern.Rational {
  @pattern.Rational(num, den)
}

///|
/// floor(t); at an integer approached from below, the previous integer.
fn tm_floor(t : @pattern.Rational, left : Bool) -> Int64 {
  let f = t.floor()
  if left && t == tm_r(f, 1L) {
    f - 1L
  } else {
    f
  }
}

///|
/// The child time of outer time `t` through `ops` (innermost first) and,
/// with `placed`, the placement outside them. Also whether it is a limit
/// from below, and the map `child = a·t + b` on the piece holding `t`.
/// `None` where a slot is silent. A slot in cycle c shows its child's cycle
/// c (ADR-0024 Decision 2).
fn tm_reference(
  ops : Array[TimeOp],
  outer : @pattern.Rational,
  placed~ : Bool = false,
) -> (@pattern.Rational, Bool, @pattern.Rational, @pattern.Rational)? {
  let mut t = outer
  let mut left = false
  let mut a = tm_r(1L, 1L)
  let mut b = tm_r(0L, 1L)
  // Apply `t -> scale·t + offset` to the time and to the composed map.
  fn step(scale : @pattern.Rational, offset : @pattern.Rational) {
    t = scale * t + offset
    a = scale * a
    b = scale * b + offset
  }
  if placed {
    step(tm_rate, tm_r(0L, 1L) - tm_origin * tm_rate)
  }
  for k = ops.length() - 1; k >= 0; k = k - 1 {
    let slot = fn(weights : Array[Int32], hit : (Int32) -> Bool) -> Bool {
      let c = tm_floor(t, left)
      let mut total = 0L
      for weight in weights {
        total += weight.to_int64()
      }
      let pos = (t - tm_r(c, 1L)) * tm_r(total, 1L)
      let mut begin = 0L
      for i, weight in weights {
        let end_ = begin + weight.to_int64()
        let inside = if left {
          tm_r(begin, 1L) < pos && pos <= tm_r(end_, 1L)
        } else {
          tm_r(begin, 1L) <= pos && pos < tm_r(end_, 1L)
        }
        if inside {
          guard hit(i) else { return false }
          // Slot i of cycle c spans [c + begin/total, c + end/total) and
          // shows the child's [c, c + 1).
          let w = weight.to_int64()
          step(tm_r(total, w), tm_r(c, 1L) - tm_r(c * total + begin, w))
          return true
        }
        begin = end_
      }
      false
    }
    match ops[k] {
      Scale(num, den) => step(tm_r(num, den), tm_r(0L, 1L))
      Mirror => {
        let c = tm_floor(t, left)
        step(tm_r(-1L, 1L), tm_r(2L * c + 1L, 1L))
        left = !left
      }
      Slot(i, weights) => if !slot(weights, j => j == i) { return None }
      Tresillo =>
        if !slot(Array::make(8, 1), j => j == 0 || j == 3 || j == 6) {
          return None
        }
    }
  }
  Some((t, left, a, b))
}

///|
priv struct TmRandom {
  mut state : Int64
}

///|
fn TmRandom::below(self : TmRandom, bound : Int32) -> Int32 {
  self.state = self.state * 6364136223846793005L + 1442695040888963407L
  ((self.state >> 33) & 0x7fffffffL).to_int() % bound
}

///|
fn TmRandom::ops(self : TmRandom) -> Array[TimeOp] {
  Array::makei(self.below(4) + 1, _ => {
    match self.below(7) {
      0 => Scale(2L, 1L)
      1 => Scale(1L, 2L)
      2 => Scale(3L, 2L)
      3 => Scale(1L, 3L)
      4 => Mirror
      5 => Tresillo
      _ => {
        let weights = match self.below(3) {
          0 => Array::make(self.below(3) + 2, 1)
          1 => [1, 2]
          _ => [3, 1, 2]
        }
        Slot(self.below(weights.length()), weights)
      }
    }
  })
}

///|
/// Outer sample times in [-2, 4): sevenths miss slot boundaries, twelfths
/// land on them, and both include integers.
fn TmRandom::times(self : TmRandom) -> Array[@pattern.Rational] {
  Array::makei(24, _ => {
    let den = if self.below(2) == 0 { 7L } else { 12L }
    let num = self.below(6 * den.to_int()).to_int64() - 2L * den
    tm_r(num, den)
  })
}

///|
let tm_cycles : Int32 = 64

///|
/// Cycle c of the leaf holds c mod 64, so an event names the child cycle it
/// came from.
fn tm_leaf() -> @pattern.Pat[Int32] {
  @pattern.sequence(Array::makei(tm_cycles, c => @pattern.Pat::pure(c))).slow(
    @pattern.Rational::from_int(tm_cycles),
  )
}

///|
fn tm_apply(pat : @pattern.Pat[Int32], op : TimeOp) -> @pattern.Pat[Int32] {
  match op {
    Scale(num, den) => pat.fast(tm_r(num, den))
    Mirror => pat.rev()
    Slot(i, weights) => {
      let pats = Array::makei(weights.length(), j => {
        if j == i {
          pat
        } else {
          @pattern.Pat::silence()
        }
      })
      if weights.iter().all(w => w == 1) {
        @pattern.sequence(pats)
      } else {
        @pattern.sequence_weighted(pats, weights)
      }
    }
    Tresillo => pat.euclid(3, 8)
  }
}

///|
/// The events over `[begin, 4)`, queried as two arcs split at `split`, so
/// both queries start mid-cycle; with `placed`, through the placement.
fn[A] tm_query(
  query : (@pattern.TimeSpan) -> Array[@pattern.Event[A]],
  begin : @pattern.Rational,
  split : @pattern.Rational,
  placed : Bool,
) -> Array[@pattern.Event[A]] {
  let end_ = tm_r(4L, 1L)
  [@pattern.TimeSpan(begin, split), @pattern.TimeSpan(split, end_)]
  .iter()
  .flat_map(arc => {
    if placed {
      query(tm_placement().local_span(arc))
      .map(event => event.placed(tm_placement()))
      .iter()
    } else {
      query(arc).iter()
    }
  })
  .collect()
}

///|
/// A random query start in [-2, 0) and split point in [0, 2), both off
/// cycle boundaries.
fn TmRandom::bounds(self : TmRandom) -> (@pattern.Rational, @pattern.Rational) {
  let begin = tm_r(self.below(14).to_int64() - 14L, 7L) + tm_r(1L, 11L)
  let split = tm_r(self.below(14).to_int64(), 7L) + tm_r(2L, 13L)
  (begin, split)
}

///|
/// The leaf event sounding at `t`: its value and its whole, the outer span
/// whose child time lies in the leaf cycle on the piece holding `t`.
fn tm_expected_event(
  ops : Array[TimeOp],
  t : @pattern.Rational,
  placed : Bool,
) -> Array[(Int32, @pattern.TimeSpan)] {
  match tm_reference(ops, t, placed~) {
    None => []
    Some((child, left, a, b)) => {
      let c = tm_floor(child, left)
      let m = tm_cycles.to_int64()
      // Invert `child = a·u + b` at the leaf cycle's ends.
      let begin = (tm_r(c, 1L) - b) / a
      let end_ = (tm_r(c + 1L, 1L) - b) / a
      let whole = if begin < end_ {
        @pattern.TimeSpan(begin, end_)
      } else {
        @pattern.TimeSpan(end_, begin)
      }
      [(((c % m + m) % m).to_int(), whole)]
    }
  }
}

///|
test "time transforms place events where the reference map does" {
  let random = { state: 1L, }
  for round in 0..<400 {
    let ops = random.ops()
    let placed = round % 2 == 1
    let pat = ops.fold(init=tm_leaf(), tm_apply)
    let (begin, split) = random.bounds()
    let events = tm_query(arc => pat.query(arc), begin, split, placed)
    for t in random.times() {
      guard t >= begin else { continue }
      let actual = events
        .filter(e => e.part.begin <= t && t < e.part.end_)
        .map(e => (e.value, e.whole.unwrap()))
      @debug.assert_eq(
        (ops, placed, t, actual),
        (ops, placed, t, tm_expected_event(ops, t, placed)),
      )
    }
  }
}

///|
/// A signal that reads its own time.
fn tm_time(t : Double) -> Double {
  t
}

///|
fn tm_id(counter : Array[Int32]) -> @identity.PatternNodeId {
  counter[0] += 1
  @identity.PatternNodeId::from_string("time-map:\{counter[0]}") catch {
    _ => abort("bad id")
  }
}

///|
fn tm_apply_doc(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  op : TimeOp,
  counter : Array[Int32],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise {
  match op {
    Scale(num, den) => doc.fast(id=tm_id(counter), factor=tm_r(num, den))
    Mirror => doc.rev(id=tm_id(counter))
    Slot(i, weights) => {
      let docs = Array::makei(weights.length(), j => {
        if j == i {
          doc
        } else {
          @pattern.PatternDoc::silence(id=tm_id(counter))
        }
      })
      if weights.iter().all(w => w == 1) {
        @pattern.PatternDoc::sequence(id=tm_id(counter), docs~)
      } else {
        @pattern.PatternDoc::sequence_weighted(
          id=tm_id(counter),
          docs~,
          weights~,
        )
      }
    }
    Tresillo => doc.euclid(id=tm_id(counter), k=3, n=8)
  }
}

///|
/// A held note's gain read through its bus, with the transforms around the
/// whole merge (lowering wraps the buses) or inside the provider (the
/// provider compiles to a signal), and on half the rounds placed. Each
/// event's onset value and its bus agree with the reference.
test "time transforms move bus signals where the reference map does" {
  let random = { state: 2L, }
  for round in 0..<400 {
    let ops = random.ops()
    let placed = round / 2 % 2 == 1
    let counter = [0]
    let ramp = @pattern.PatternDoc::continuous(
      id=tm_id(counter),
      key=Gain,
      f=tm_time,
      signature="time",
    )
    let note = @pattern.PatternDoc::pure(
      id=tm_id(counter),
      value=@pattern.ControlMap::single(Note, 60.0),
    )
    let wrap_provider = round % 2 == 0
    let mut doc = if wrap_provider {
      ramp
    } else {
      @pattern.PatternDoc::merge_control(
        id=tm_id(counter),
        left=note,
        right=ramp,
      )
    }
    for op in ops {
      doc = tm_apply_doc(doc, op, counter)
    }
    if wrap_provider {
      doc = @pattern.PatternDoc::merge_control(
        id=tm_id(counter),
        left=note,
        right=doc,
      )
    }
    let snapshot = doc.lower()
    let (begin, split) = random.bounds()
    let events = tm_query(
      arc => snapshot.query_sourced_events(arc).map(e => e.event()),
      begin,
      split,
      placed,
    )
    let onset = snapshot
      .query_sourced_events(
        if placed {
          tm_placement().local_span(@pattern.TimeSpan(begin, tm_r(4L, 1L)))
        } else {
          @pattern.TimeSpan(begin, tm_r(4L, 1L))
        },
      )
      .get(0)
      .map(e => {
        if placed {
          e.controls().placed(tm_placement())
        } else {
          e.controls()
        }
      })
    fn expected(t : @pattern.Rational) -> Double? {
      tm_reference(ops, t, placed~).map(child => child.0.to_double())
    }
    let times = random.times()
    // A chain can leave the note silent everywhere; then so is the reference.
    guard onset is Some(controls) else {
      @debug.assert_eq(
        (ops, times.filter(t => t >= begin && expected(t) is Some(_))),
        (ops, []),
      )
      continue
    }
    for event in events {
      @debug.assert_eq(
        (ops, placed, event.part, event.value.get(Gain)),
        (ops, placed, event.part, expected(event.part.begin)),
      )
    }
    guard controls.reader(Gain) is Some(read) else {
      fail("no gain bus for \{@debug.to_string(ops)}")
    }
    for t in times {
      @debug.assert_eq(
        (ops, wrap_provider, placed, t, read(t.num, t.den).get()),
        (ops, wrap_provider, placed, t, expected(t)),
      )
    }
  }
}
