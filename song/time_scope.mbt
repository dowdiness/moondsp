///|
pub(all) suberror TimeScopeBuildError {
  NonPositiveRate
} derive(Eq, Debug)

///|
/// Section-local timing context.
///
/// `rate` is body cycles per section-local cycle. A rate of `2` makes the
/// section body play twice as fast inside the same section-local timeline;
/// a rate of `1/2` makes it play half as fast. Future groove, meter, key, and
/// rubato can be added behind this opaque representation without changing the
/// scheduler compatibility path.
pub struct TimeScope {
  priv rate : @pattern.Rational
}

///|
pub fn TimeScope::TimeScope() -> TimeScope {
  { rate: @pattern.Rational::from_int(1) }
}

///|
pub fn TimeScope::identity() -> TimeScope {
  TimeScope()
}

///|
pub fn TimeScope::is_identity(self : TimeScope) -> Bool {
  self.rate == @pattern.Rational::from_int(1)
}

///|
pub fn TimeScope::rate(self : TimeScope) -> @pattern.Rational {
  self.rate
}

///|
pub fn TimeScope::at_rate(
  rate~ : @pattern.Rational,
) -> TimeScope raise TimeScopeBuildError {
  if rate.num <= 0L {
    raise NonPositiveRate
  } else {
    { rate, }
  }
}

///|
pub fn TimeScope::fast(
  factor~ : @pattern.Rational,
) -> TimeScope raise TimeScopeBuildError {
  TimeScope::at_rate(rate=factor)
}

///|
pub fn TimeScope::slow(
  factor~ : @pattern.Rational,
) -> TimeScope raise TimeScopeBuildError {
  if factor.num <= 0L {
    raise NonPositiveRate
  } else {
    TimeScope::at_rate(rate=@pattern.Rational::new(1L, 1L) / factor)
  }
}
