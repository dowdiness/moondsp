///|
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
pub fn TimeSpan::intersect(self : TimeSpan, other : TimeSpan) -> TimeSpan? {
  let begin = if self.begin > other.begin { self.begin } else { other.begin }
  let end_ = if self.end_ < other.end_ { self.end_ } else { other.end_ }
  if begin < end_ {
    Some({ begin, end_ })
  } else {
    None
  }
}

///|
pub fn TimeSpan::whole_cycles(self : TimeSpan) -> Array[TimeSpan] {
  let result : Array[TimeSpan] = []
  let one = Rational::from_int(1)
  // first cycle: cycle containing begin
  let mut cycle_start = Rational::new(self.begin.floor(), 1L)
  while cycle_start < self.end_ {
    let cycle_end = cycle_start + one
    let arc = TimeSpan::new(cycle_start, cycle_end)
    match arc.intersect(self) {
      Some(intersection) => result.push(intersection)
      None => ()
    }
    cycle_start = cycle_start + one
  }
  result
}
