///|
/// Half-open time interval [begin, end) with rational boundaries.
///
/// WHY half-open: adjacent cycle arcs must not overlap. [0,1) and [1,2) are
/// disjoint — the boundary point 1 belongs to the second arc only. This
/// prevents double-counting events at cycle boundaries.
///
/// WHY `end_` not `end`: avoids potential keyword collision in MoonBit.
pub struct TimeSpan {
  begin : Rational
  end_ : Rational
} derive(Eq, Debug)

///|
pub impl Show for TimeSpan with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn TimeSpan::TimeSpan(begin : Rational, end_ : Rational) -> TimeSpan {
  { begin, end_, }
}

///|
pub fn TimeSpan::duration(self : TimeSpan) -> Rational {
  self.end_ - self.begin
}

///|
pub fn TimeSpan::shift(self : TimeSpan, offset : Rational) -> TimeSpan {
  if offset.num == 0L {
    return self
  }
  TimeSpan(self.begin + offset, self.end_ + offset)
}

///|
/// Where a local clock sits on an outer clock: local time `t` is outer time
/// `t / rate + origin` (`rate > 0`). Events and the buses they follow are
/// placed with the same value, so they stay on one clock.
pub struct Placement {
  priv origin : Rational
  priv rate : Rational
}

///|
pub fn Placement::Placement(
  origin? : Rational = Rational::from_int(0),
  rate? : Rational = Rational::from_int(1),
) -> Placement {
  { origin, rate, }
}

///|
fn Placement::is_identity(self : Placement) -> Bool {
  self.origin.num == 0L && self.rate == Rational::from_int(1)
}

///|
/// This placement followed by `outer`.
fn Placement::then(self : Placement, outer : Placement) -> Placement {
  {
    origin: self.origin / outer.rate + outer.origin,
    rate: self.rate * outer.rate,
  }
}

///|
/// `span` from the local clock on the outer clock.
fn Placement::span(self : Placement, span : TimeSpan) -> TimeSpan {
  if self.rate == Rational::from_int(1) {
    return span.shift(self.origin)
  }
  TimeSpan(
    span.begin / self.rate + self.origin,
    span.end_ / self.rate + self.origin,
  )
}

///|
/// `span` from the outer clock on the local clock.
pub fn Placement::local_span(self : Placement, span : TimeSpan) -> TimeSpan {
  TimeSpan(
    (span.begin - self.origin) * self.rate,
    (span.end_ - self.origin) * self.rate,
  )
}

///|
pub fn TimeSpan::contains(self : TimeSpan, time : Rational) -> Bool {
  self.begin <= time && time < self.end_
}

///|
pub fn TimeSpan::intersect(self : TimeSpan, other : TimeSpan) -> TimeSpan? {
  let begin_from_self = self.begin >= other.begin
  let end_from_self = self.end_ <= other.end_
  let begin = if begin_from_self { self.begin } else { other.begin }
  let end_ = if end_from_self { self.end_ } else { other.end_ }
  if begin < end_ {
    if begin_from_self && end_from_self {
      Some(self)
    } else if !begin_from_self && !end_from_self {
      Some(other)
    } else {
      Some({ begin, end_, })
    }
  } else {
    None
  }
}

///|
pub fn TimeSpan::whole_cycles(self : TimeSpan) -> Array[TimeSpan] {
  let result : Array[TimeSpan] = []
  let one = Rational::from_int(1)
  // first cycle: cycle containing begin
  let mut cycle_start = Rational(self.begin.floor(), 1L)
  while cycle_start < self.end_ {
    let cycle_end = cycle_start + one
    let arc = TimeSpan(cycle_start, cycle_end)
    match arc.intersect(self) {
      Some(intersection) => result.push(intersection)
      None => ()
    }
    cycle_start = cycle_end
  }
  result
}

///|
pub extend TimeSpan with Debug::{to_repr}

///|
pub extend TimeSpan with Eq::{not_equal, equal}

///|
pub extend TimeSpan with Show::{to_string, output}
