///|
/// How a time transform maps outer time onto its children's time
/// (ADR-0024). Outer time is cut into pieces, and on each piece child time is
/// `a·t + b` with `a ≠ 0`. The coefficients are written here and nowhere
/// else; they are scalars so that a lookup at one instant can stay
/// allocation-free.
priv enum TimeMap {
  /// One piece: child time = `scale·t + offset` (`fast`, `slow`).
  Affine(Rational, Rational)
  /// One piece per cycle c: child time = `2c + 1 − t` (`rev`).
  MirrorCycles
  /// One piece per slot k of each cycle, for child k. `bounds` holds the
  /// n + 1 cumulative slot weights; slot k spans
  /// `[c + bounds[k] / total, c + bounds[k + 1] / total)` and shows its child
  /// `[0, 1)`.
  Slots(Array[Int64])
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
/// Denominator of `a`, and of `b` for cycle maps, on slot `slot`.
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
    Slots(bounds) => -(cycle * bounds[bounds.length() - 1] + bounds[slot])
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
        let cycle = cycle_arc.begin.floor()
        for slot in 0..<(bounds.length() - 1) {
          let slot_arc = TimeSpan(
            Rational(cycle * total + bounds[slot], total),
            Rational(cycle * total + bounds[slot + 1], total),
          )
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
fn map_span(span : TimeSpan, a : Rational, b : Rational) -> TimeSpan {
  let begin = a * span.begin + b
  let end_ = a * span.end_ + b
  if a.num < 0L {
    TimeSpan(end_, begin)
  } else {
    TimeSpan(begin, end_)
  }
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
    let a = Rational(self.scale_num(), self.scale_den(slot))
    let b = Rational(self.offset_num(cycle, slot), self.offset_den(slot))
    let inverse_a = Rational::from_int(1) / a
    let inverse_b = Rational::from_int(0) - b * inverse_a
    for ev in children[slot].query(map_span(piece, a, b)) {
      result.push({
        whole: ev.whole.map(whole => map_span(whole, inverse_a, inverse_b)),
        part: map_span(ev.part, inverse_a, inverse_b),
        value: ev.value,
      })
    }
  })
  result
}
