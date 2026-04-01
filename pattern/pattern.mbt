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
      let events : Array[Event[A]] = []
      let cycles = arc.whole_cycles()
      for span in cycles {
        // the whole event spans one full cycle: [floor(begin), floor(begin)+1)
        let cycle_n = span.begin.floor()
        let whole_begin = Rational::new(cycle_n, 1L)
        let whole_end = Rational::new(cycle_n + 1L, 1L)
        let whole = TimeSpan::new(whole_begin, whole_end)
        // part is the intersection of whole with the original query arc
        match whole.intersect(arc) {
          Some(part) => events.push({ whole: Some(whole), part, value })
          None => ()
        }
      }
      events
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
      let events = inner.query(scaled_arc)
      // Scale the returned events back by 1/factor
      let result : Array[Event[A]] = []
      for ev in events {
        let new_part_begin = ev.part.begin * inv
        let new_part_end = ev.part.end_ * inv
        let new_part = TimeSpan::new(new_part_begin, new_part_end)
        let new_whole = match ev.whole {
          Some(w) => {
            let wb = w.begin * inv
            let we = w.end_ * inv
            Some(TimeSpan::new(wb, we))
          }
          None => None
        }
        result.push({ whole: new_whole, part: new_part, value: ev.value })
      }
      result
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
      let cycles = arc.whole_cycles()
      let result : Array[Event[A]] = []
      for cycle_arc in cycles {
        // Determine the full cycle boundaries from cycle_arc.begin
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        let cycle_end = cycle_start + one
        // Mirror the query sub-arc within the cycle:
        // [begin, end) -> [cycle_end - end, cycle_end - begin)
        let mirror_begin = cycle_end - cycle_arc.end_
        let mirror_end = cycle_end - cycle_arc.begin
        let mirror_arc = TimeSpan::new(mirror_begin, mirror_end)
        let events = inner.query(mirror_arc)
        for ev in events {
          // Mirror part back
          let new_part_begin = cycle_end - ev.part.end_
          let new_part_end = cycle_end - ev.part.begin
          let new_part = TimeSpan::new(new_part_begin, new_part_end)
          let new_whole = match ev.whole {
            Some(w) => {
              let wb = cycle_end - w.end_
              let we = cycle_end - w.begin
              Some(TimeSpan::new(wb, we))
            }
            None => None
          }
          result.push({ whole: new_whole, part: new_part, value: ev.value })
        }
      }
      result
    },
  }
}
