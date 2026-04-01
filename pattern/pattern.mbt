///|
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
