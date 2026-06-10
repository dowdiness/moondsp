///|
/// A pattern is a query function from time arcs to events.
///
/// WHY function, not data: Strudel's core insight. Patterns are infinite
/// repeating streams — representing them as data would require materializing
/// infinity. As functions, they are lazy: only the queried arc is computed.
/// Combinators compose functions naturally (no interpreter needed).
///
/// WHY concrete struct, not trait: Phase 4 uses concrete composition.
/// A PatternSym trait layer can wrap this in Phase 6 for incr memoization.
pub struct Pat[A] {
  query : (TimeSpan) -> Array[Event[A]]
}

///|
pub fn[A] Pat::silence() -> Pat[A] {
  { query: fn(_arc) { [] } }
}

///|
pub fn[A] Pat::pure(value : A) -> Pat[A] {
  {
    query: fn(arc) {
      arc
      .whole_cycles()
      .filter_map(span => {
        // the whole event spans one full cycle: [floor(begin), floor(begin)+1)
        let cycle_n = span.begin.floor()
        let whole_begin = Rational::new(cycle_n, 1L)
        let whole_end = Rational::new(cycle_n + 1L, 1L)
        let whole = TimeSpan::new(whole_begin, whole_end)
        // part is the intersection of whole with the original query arc
        whole.intersect(arc).map(part => { whole: Some(whole), part, value })
      })
    },
  }
}

///|
pub fn[A] Pat::query(self : Pat[A], arc : TimeSpan) -> Array[Event[A]] {
  (self.query)(arc)
}

///|
/// WHY two-step time scaling: query the inner pattern in compressed time
/// (arc * factor), then scale returned events back (timestamps / factor).
/// The inner pattern "sees" time passing faster, but events are reported
/// in the caller's real-time frame. Both whole and part are scaled.
pub fn[A] Pat::fast(self : Pat[A], factor : Rational) -> Pat[A] {
  if factor.num <= 0L {
    return Pat::silence()
  }
  let inner = self
  {
    query: fn(arc) {
      // Scale the query arc forward in time by factor (compress)
      let scaled_begin = arc.begin * factor
      let scaled_end = arc.end_ * factor
      let scaled_arc = TimeSpan::new(scaled_begin, scaled_end)
      let inv = Rational::new(1L, 1L) / factor
      // Scale the returned events back by 1/factor
      inner
      .query(scaled_arc)
      .map(ev => {
        let new_part = TimeSpan::new(ev.part.begin * inv, ev.part.end_ * inv)
        let new_whole = ev.whole.map(w => {
          TimeSpan::new(w.begin * inv, w.end_ * inv)
        })
        { whole: new_whole, part: new_part, value: ev.value }
      })
    },
  }
}

///|
pub fn[A] Pat::slow(self : Pat[A], factor : Rational) -> Pat[A] {
  if factor.num <= 0L {
    return Pat::silence()
  }
  let inv = Rational::new(1L, 1L) / factor
  self.fast(inv)
}

///|
pub fn[A] Pat::rev(self : Pat[A]) -> Pat[A] {
  let inner = self
  {
    query: fn(arc) {
      let one = Rational::from_int(1)
      arc
      .whole_cycles()
      .iter()
      .flat_map(cycle_arc => {
        // Determine the full cycle boundaries from cycle_arc.begin
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        let cycle_end = cycle_start + one
        // Mirror the query sub-arc within the cycle:
        // [begin, end) -> [cycle_end - end, cycle_end - begin)
        let mirror_arc = TimeSpan::new(
          cycle_end - cycle_arc.end_,
          cycle_end - cycle_arc.begin,
        )
        inner
        .query(mirror_arc)
        .iter()
        .map(ev => {
          // Mirror part back
          let new_part = TimeSpan::new(
            cycle_end - ev.part.end_,
            cycle_end - ev.part.begin,
          )
          let new_whole = ev.whole.map(w => {
            TimeSpan::new(cycle_end - w.end_, cycle_end - w.begin)
          })
          { whole: new_whole, part: new_part, value: ev.value }
        })
      })
      .collect()
    },
  }
}
