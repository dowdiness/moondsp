///|
/// Exact fraction for musical time. Int64 numerator and denominator.
///
/// WHY Int64: MoonBit Int is 32-bit. Cross-multiplication for comparison
/// and nested fast/slow transforms overflow 32-bit quickly in live sessions.
///
/// Invariants (enforced by Rational::new):
/// - den is always positive (sign lives in num)
/// - num/den is always in lowest terms (GCD-reduced)
/// These are required for correct cross-multiply comparison.
pub struct Rational {
  num : Int64
  den : Int64
} derive(Eq, Debug)

///|
pub impl Show for Rational with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn gcd(a : Int64, b : Int64) -> Int64 {
  let mut x = a.abs()
  let mut y = b.abs()
  while y != 0L {
    let t = y
    y = x % y
    x = t
  }
  x
}

///|
pub fn Rational::new(num : Int64, den : Int64) -> Rational {
  if den == 0L {
    abort("Rational: denominator cannot be zero")
  }
  let g = gcd(num, den)
  let n = num / g
  let d = den / g
  // normalize sign: den always positive
  if d < 0L {
    { num: -n, den: -d }
  } else {
    { num: n, den: d }
  }
}

///|
pub fn Rational::from_int(n : Int) -> Rational {
  { num: Int64::from_int(n), den: 1L }
}

///|
pub fn Rational::to_double(self : Rational) -> Double {
  self.num.to_double() / self.den.to_double()
}

///|
pub impl Add for Rational with add(self : Rational, other : Rational) -> Rational {
  Rational::new(
    self.num * other.den + other.num * self.den,
    self.den * other.den,
  )
}

///|
pub impl Sub for Rational with sub(self : Rational, other : Rational) -> Rational {
  Rational::new(
    self.num * other.den - other.num * self.den,
    self.den * other.den,
  )
}

///|
pub impl Mul for Rational with mul(self : Rational, other : Rational) -> Rational {
  Rational::new(self.num * other.num, self.den * other.den)
}

///|
pub impl Div for Rational with div(self : Rational, other : Rational) -> Rational {
  Rational::new(self.num * other.den, self.den * other.num)
}

///|
pub impl Compare for Rational with compare(self : Rational, other : Rational) -> Int {
  // WHY cross-multiply: avoids float conversion. Safe because den > 0.
  // NOTE: can overflow Int64 for very large numerators/denominators.
  // Musical patterns use small values (cycle counts, subdivisions) so this
  // is not a practical concern, but adversarial inputs could trigger it.
  let lhs = self.num * other.den
  let rhs = other.num * self.den
  if lhs < rhs {
    -1
  } else if lhs > rhs {
    1
  } else {
    0
  }
}

///|
pub fn Rational::floor(self : Rational) -> Int64 {
  if self.num >= 0L {
    self.num / self.den
  } else {
    // For negative: floor rounds toward -infinity
    // e.g. floor(-7/4) = floor(-1.75) = -2
    // = (num - den + 1) / den
    (self.num - self.den + 1L) / self.den
  }
}
