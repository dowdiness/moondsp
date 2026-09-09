///|
/// Known musical-time operations. Each operation owns execution and identity;
/// callers cannot attach a misleading identity to an unrelated callback.
pub(all) enum TimeTransform {
  Fast(Rational)
  Slow(Rational)
  Reverse
}

///|
pub fn[A] TimeTransform::apply(self : TimeTransform, pat : Pat[A]) -> Pat[A] {
  match self {
    Fast(n) => pat.fast(n)
    Slow(n) => pat.slow(n)
    Reverse => pat.rev()
  }
}

///|
fn TimeTransform::signature(self : TimeTransform) -> String {
  match self {
    Fast(n) => "fast:\{n.num}:\{n.den}"
    Slow(n) => "slow:\{n.num}:\{n.den}"
    Reverse => "rev"
  }
}

///|
pub fn[A] TimeTransform::every(
  self : TimeTransform,
  n : Int,
  pat : Pat[A],
) -> Pat[A] {
  every_known(n, p => self.apply(p), pat, self.signature())
}

///|
pub fn TimeTransform::jux(
  self : TimeTransform,
  pat : Pat[ControlMap],
) -> Pat[ControlMap] {
  pat.jux_known(p => self.apply(p), self.signature())
}
