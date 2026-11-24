///|
/// How a time transform maps outer time onto its children's time
/// (ADR-0024). Outer time is cut into pieces, and on each piece child time is
/// `a·t + b` with `a ≠ 0`. The coefficients and the piece boundaries are
/// written here and nowhere else. Event queries (`TimeMap::query`) and bus
/// signals (`BusSignal::Mapped`) both read them; they are scalars so that a
/// signal read stays allocation-free.
priv enum TimeMap {
  /// One piece: child time = `scale·t + offset` (`fast`, `slow`, placement).
  Affine(Rational, Rational)
  /// One piece per cycle c: child time = `2c + 1 − t` (`rev`).
  MirrorCycles
  /// One piece per slot k of each cycle, for child k. `bounds` holds the
  /// n + 1 cumulative slot weights; slot k shows its child `[0, 1)`.
  Slots(Array[Int64])
}

///|
/// `fast(factor)`; `None` when the factor silences the pattern.
fn TimeMap::scaled(factor : Rational) -> TimeMap? {
  if factor.num > 0L {
    Some(Affine(factor, Rational::from_int(0)))
  } else {
    None
  }
}

///|
/// `n` equal slots.
fn TimeMap::sequence(n : Int32) -> TimeMap {
  Slots(Array::makei(n + 1, i => i.to_int64()))
}

///|
/// One slot per weight, as wide as its share of the total.
fn TimeMap::weighted(weights : Array[Int32]) -> TimeMap {
  let bounds = [0L]
  for weight in weights {
    bounds.push(bounds[bounds.length() - 1] + weight.to_int64())
  }
  Slots(bounds)
}

///|
/// The map of a known transform; `None` when it silences the pattern.
fn TimeTransform::time_map(self : TimeTransform) -> TimeMap? {
  match self {
    Fast(factor) => TimeMap::scaled(factor)
    Slow(factor) =>
      if factor.num > 0L {
        TimeMap::scaled(Rational::from_int(1) / factor)
      } else {
        None
      }
    Reverse => Some(MirrorCycles)
  }
}

///|
/// From the outer clock to the local clock: `(t − origin) · rate`.
fn Placement::time_map(self : Placement) -> TimeMap {
  Affine(self.rate, self.offset())
}

///|
/// `b` of the placement's map: `−origin · rate`.
fn Placement::offset(self : Placement) -> Rational {
  Rational::from_int(0) - self.origin * self.rate
}

///|
/// Where slot `k` of cycle `cycle` begins, over the denominator
/// `bounds[n]`: `cycle + bounds[k] / bounds[n]`. Slot `n` is where the cycle
/// ends.
fn slot_bound(bounds : Array[Int64], cycle : Int64, k : Int32) -> Int64 {
  cycle * bounds[bounds.length() - 1] + bounds[k]
}

///|
/// The slot holding exact time `num / den` (`den > 0`) of cycle `cycle`.
/// With `left`, the limit from below: a slot boundary belongs to the slot
/// before it. Allocates nothing.
fn TimeMap::slot_at(
  self : TimeMap,
  num : Int64,
  den : Int64,
  left : Bool,
  cycle : Int64,
) -> Int32 {
  guard self is Slots(bounds) else { return 0 }
  let scaled = num * bounds[bounds.length() - 1]
  // The last slot whose bound comes before the time; slot 0 always does.
  let mut low = 0
  let mut high = bounds.length() - 2
  while low < high {
    let mid = (low + high + 1) / 2
    let bound = slot_bound(bounds, cycle, mid) * den
    if (if left { bound < scaled } else { bound <= scaled }) {
      low = mid
    } else {
      high = mid - 1
    }
  }
  low
}

///|
/// The cycle whose piece holds exact time `num / den`, as `offset_num` and
/// `slot_at` take it. A map with one piece needs none.
fn TimeMap::cycle_at(
  self : TimeMap,
  num : Int64,
  den : Int64,
  left : Bool,
) -> Int64 {
  match self {
    Affine(_, _) => 0L
    MirrorCycles | Slots(_) => time_floor(num, den, left)
  }
}

///|
/// The floor of `num / den`. With `left`, the limit from below: an exact
/// integer belongs to the previous unit, because a sample at `t` stands for
/// `[t, t + ε)` and mirroring turns that into `(t' - ε, t']`.
fn time_floor(num : Int64, den : Int64, left : Bool) -> Int64 {
  let q = num / den
  let r = num % den
  let q = if r < 0L { q - 1L } else { q }
  if left && r == 0L {
    q - 1L
  } else {
    q
  }
}

///|
/// Numerator of `a`, the same on every slot.
fn TimeMap::scale_num(self : TimeMap) -> Int64 {
  match self {
    Affine(scale, _) => scale.num
    MirrorCycles => -1L
    Slots(bounds) => bounds[bounds.length() - 1]
  }
}

///|
/// Denominator of `a` on slot `slot`.
fn TimeMap::scale_den(self : TimeMap, slot : Int32) -> Int64 {
  match self {
    Affine(scale, _) => scale.den
    MirrorCycles => 1L
    Slots(bounds) => bounds[slot + 1] - bounds[slot]
  }
}

///|
/// Numerator of `b` on slot `slot` of cycle `cycle`.
fn TimeMap::offset_num(self : TimeMap, cycle : Int64, slot : Int32) -> Int64 {
  match self {
    Affine(_, offset) => offset.num
    MirrorCycles => 2L * cycle + 1L
    Slots(bounds) => -slot_bound(bounds, cycle, slot)
  }
}

///|
/// Denominator of `b` on slot `slot`.
fn TimeMap::offset_den(self : TimeMap, slot : Int32) -> Int64 {
  match self {
    Affine(_, offset) => offset.den
    MirrorCycles | Slots(_) => self.scale_den(slot)
  }
}

///|
/// `a` and `b` on slot `slot` of cycle `cycle`, as rationals. An affine map
/// already holds them reduced.
fn TimeMap::coefficients(
  self : TimeMap,
  cycle : Int64,
  slot : Int32,
) -> (Rational, Rational) {
  match self {
    Affine(scale, offset) => (scale, offset)
    MirrorCycles | Slots(_) =>
      (
        Rational(self.scale_num(), self.scale_den(slot)),
        Rational(self.offset_num(cycle, slot), self.offset_den(slot)),
      )
  }
}

///|
/// The length after which the mapped pattern repeats, given its child's.
fn TimeMap::period(self : TimeMap, child : Rational) -> Rational {
  match self {
    Affine(scale, _) => child / scale
    MirrorCycles => child
    Slots(_) => Rational::from_int(1)
  }
}

///|
/// Visit the pieces of `arc`: each piece's slot, outer span, and cycle.
fn TimeMap::each_piece(
  self : TimeMap,
  arc : TimeSpan,
  f : (Int32, TimeSpan, Int64) -> Unit,
) -> Unit {
  match self {
    Affine(_, _) => f(0, arc, 0L)
    MirrorCycles =>
      for piece in arc.whole_cycles() {
        f(0, piece, piece.begin.floor())
      }
    Slots(bounds) => {
      let total = bounds[bounds.length() - 1]
      for cycle_arc in arc.whole_cycles() {
        let begin = cycle_arc.begin
        let cycle = begin.floor()
        // Start at the slot holding the arc's beginning; a block query
        // covers only a few slots.
        let first = self.slot_at(begin.num, begin.den, false, cycle)
        for slot in first..<(bounds.length() - 1) {
          let slot_arc = TimeSpan(
            Rational(slot_bound(bounds, cycle, slot), total),
            Rational(slot_bound(bounds, cycle, slot + 1), total),
          )
          guard slot_arc.begin < cycle_arc.end_ else { break }
          if slot_arc.intersect(arc) is Some(piece) {
            f(slot, piece, cycle)
          }
        }
      }
    }
  }
}

///|
/// `span` under the map `t -> a·t + b`; a negative `a` swaps its ends.
/// `rev` maps by `b − t`, which skips the multiplication.
fn map_span(span : TimeSpan, a : Rational, b : Rational) -> TimeSpan {
  if a.den == 1L && a.num == -1L {
    return TimeSpan(b - span.end_, b - span.begin)
  }
  let begin = a * span.begin + b
  let end_ = a * span.end_ + b
  if a.num < 0L {
    TimeSpan(end_, begin)
  } else {
    TimeSpan(begin, end_)
  }
}

///|
/// The inverse of `t -> a·t + b`, as its coefficients.
fn inverse_affine(a : Rational, b : Rational) -> (Rational, Rational) {
  // A mirror is its own inverse.
  if a.den == 1L && a.num == -1L {
    return (a, b)
  }
  // `a` is reduced, so its reciprocal and a negation need no gcd.
  let inverse : Rational = if a.num < 0L {
    { num: -a.den, den: -a.num, }
  } else {
    { num: a.den, den: a.num, }
  }
  let back = b * inverse
  (inverse, { num: -back.num, den: back.den, })
}

///|
/// Query `children` through the map: each piece queries its slot's child
/// over the mapped span, and its events are mapped back.
fn[A] TimeMap::query(
  self : TimeMap,
  children : Array[Pat[A]],
  arc : TimeSpan,
) -> Array[Event[A]] {
  let result : Array[Event[A]] = []
  self.each_piece(arc, (slot, piece, cycle) => {
    let (a, b) = self.coefficients(cycle, slot)
    let (back_a, back_b) = inverse_affine(a, b)
    for ev in children[slot].query(map_span(piece, a, b)) {
      result.push({
        whole: ev.whole.map(whole => map_span(whole, back_a, back_b)),
        part: map_span(ev.part, back_a, back_b),
        value: ev.value,
      })
    }
  })
  result
}
