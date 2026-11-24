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
  /// Slot `i` of an `n`-slot sequence; the other slots are silent.
  Slot(Int32, Int32)
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
/// The child time of outer time `t` through `ops` (innermost first), and
/// whether it is a limit from below; `None` where a slot is silent. A slot
/// in cycle c shows its child's cycle c (ADR-0024 Decision 2).
fn tm_reference(
  ops : Array[TimeOp],
  outer : @pattern.Rational,
) -> (@pattern.Rational, Bool)? {
  let mut t = outer
  let mut left = false
  for k = ops.length() - 1; k >= 0; k = k - 1 {
    match ops[k] {
      Scale(num, den) => t = t * tm_r(num, den)
      Mirror => {
        let c = tm_floor(t, left)
        t = tm_r(2L * c + 1L, 1L) - t
        left = !left
      }
      Slot(i, n) => {
        let c = tm_floor(t, left)
        let pos = (t - tm_r(c, 1L)) * tm_r(n.to_int64(), 1L)
        guard tm_floor(pos, left) == i.to_int64() else { return None }
        t = pos - tm_r(i.to_int64(), 1L) + tm_r(c, 1L)
      }
    }
  }
  Some((t, left))
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
    match self.below(6) {
      0 => Scale(2L, 1L)
      1 => Scale(1L, 2L)
      2 => Scale(3L, 2L)
      3 => Scale(1L, 3L)
      4 => Mirror
      _ => {
        let n = self.below(3) + 2
        Slot(self.below(n), n)
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
    Slot(i, n) =>
      @pattern.sequence(
        Array::makei(n, j => if j == i { pat } else { @pattern.Pat::silence() }),
      )
  }
}

///|
/// What sounds at `t`: the value of each event whose part contains it.
fn tm_events_at(
  events : Array[@pattern.Event[Int32]],
  t : @pattern.Rational,
) -> Array[Int32] {
  events.filter(e => e.part.begin <= t && t < e.part.end_).map(e => e.value)
}

///|
fn tm_expected_event(
  ops : Array[TimeOp],
  t : @pattern.Rational,
) -> Array[Int32] {
  match tm_reference(ops, t) {
    None => []
    Some((child, left)) => {
      let c = tm_floor(child, left)
      let m = tm_cycles.to_int64()
      [((c % m + m) % m).to_int()]
    }
  }
}

///|
test "time transforms place events where the reference map does" {
  let random = { state: 1L, }
  for _ in 0..<300 {
    let ops = random.ops()
    let pat = ops.fold(init=tm_leaf(), tm_apply)
    let events = pat.query(@pattern.TimeSpan(tm_r(-2L, 1L), tm_r(4L, 1L)))
    for t in random.times() {
      @debug.assert_eq(
        (ops, t, tm_events_at(events, t)),
        (ops, t, tm_expected_event(ops, t)),
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
    Slot(i, n) => {
      let docs = Array::makei(n, j => {
        if j == i {
          doc
        } else {
          @pattern.PatternDoc::silence(id=tm_id(counter))
        }
      })
      @pattern.PatternDoc::sequence(id=tm_id(counter), docs~)
    }
  }
}

///|
/// A held note's gain read through its bus, with the transforms around the
/// whole merge (lowering wraps the buses) or inside the provider (the
/// provider compiles to a signal).
test "time transforms move bus signals where the reference map does" {
  let random = { state: 2L, }
  for round in 0..<300 {
    let ops = random.ops()
    let counter = [0]
    let ramp = @pattern.PatternDoc::continuous(
      id=tm_id(counter),
      key=Gain,
      f=tm_time,
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
    let events = snapshot.query_sourced_events(
      @pattern.TimeSpan(tm_r(-2L, 1L), tm_r(4L, 1L)),
    )
    let times = random.times()
    let expected = times.map(t => {
      tm_reference(ops, t).map(child => child.0.to_double())
    })
    // A chain can leave the note silent everywhere; then so is the reference.
    guard events.get(0) is Some(onset) else {
      @debug.assert_eq((ops, expected.filter(v => v is Some(_))), (ops, []))
      continue
    }
    guard onset.controls().reader(Gain) is Some(read) else {
      fail("no gain bus for \{@debug.to_string(ops)}")
    }
    for index, t in times {
      @debug.assert_eq(
        (ops, wrap_provider, t, read(t.num, t.den).get()),
        (ops, wrap_provider, t, expected[index]),
      )
    }
  }
}
