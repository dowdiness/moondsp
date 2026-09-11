///|
/// Exact fraction for musical time. Int64 numerator and denominator.
///
/// WHY Int64: MoonBit Int is 32-bit. Cross-multiplication for comparison
/// and nested fast/slow transforms overflow 32-bit quickly in live sessions.
///
/// Invariants (enforced by Rational::new):
/// - den is always positive (sign lives in num)
/// - num/den is always in lowest terms (GCD-reduced)
/// Arithmetic cancels common factors before multiplying. Results must still
/// fit Int64; comparisons avoid cross-products entirely.
pub struct Rational {
  num : Int64
  den : Int64
} derive(Eq, Debug)

///|
pub impl Show for Rational with fn output(self, logger) {
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
#alias(new)
pub fn Rational::Rational(num : Int64, den : Int64) -> Rational {
  if den == 0L {
    abort("Rational: denominator cannot be zero")
  }
  let g = gcd(num, den)
  let n = num / g
  let d = den / g
  // normalize sign: den always positive
  if d < 0L {
    { num: -n, den: -d, }
  } else {
    { num: n, den: d, }
  }
}

///|
pub fn Rational::from_int(n : Int) -> Rational {
  { num: Int64::from_int(n), den: 1L, }
}

///|
pub fn Rational::to_double(self : Rational) -> Double {
  self.num.to_double() / self.den.to_double()
}

///|
pub impl Add for Rational with fn add(self : Rational, other : Rational) -> Rational {
  let common = gcd(self.den, other.den)
  let num = self.num * (other.den / common) + other.num * (self.den / common)
  let cancel = gcd(num, common)
  Rational::new(num / cancel, self.den / common * (other.den / cancel))
}

///|
pub impl Sub for Rational with fn sub(self : Rational, other : Rational) -> Rational {
  let common = gcd(self.den, other.den)
  let num = self.num * (other.den / common) - other.num * (self.den / common)
  let cancel = gcd(num, common)
  Rational::new(num / cancel, self.den / common * (other.den / cancel))
}

///|
pub impl Mul for Rational with fn mul(self : Rational, other : Rational) -> Rational {
  let left = gcd(self.num, other.den)
  let right = gcd(other.num, self.den)
  Rational::new(
    self.num / left * (other.num / right),
    self.den / right * (other.den / left),
  )
}

///|
pub impl Div for Rational with fn div(self : Rational, other : Rational) -> Rational {
  if other.num == 0L {
    abort("Rational: division by zero")
  }
  let left = gcd(self.num, other.num)
  let right = gcd(self.den, other.den)
  Rational::new(
    self.num / left * (other.den / right),
    self.den / right * (other.num / left),
  )
}

///|
// Compare integer parts, then reciprocal remainders with reversed ordering.
// Euclidean division terminates without an overflowing cross-product.
pub impl Compare for Rational with fn compare(self : Rational, other : Rational) -> Int {
  if self.den == other.den {
    return if self.num < other.num {
      -1
    } else if self.num > other.num {
      1
    } else {
      0
    }
  }
  for an = self.num, ad = self.den, bn = other.num, bd = other.den, direction = 1 {
    let ar = an % ad
    let br = bn % bd
    let aq = an / ad - (if ar < 0L { 1L } else { 0L })
    let bq = bn / bd - (if br < 0L { 1L } else { 0L })
    if aq < bq {
      break -direction
    }
    if aq > bq {
      break direction
    }
    let ar = if ar < 0L { ar + ad } else { ar }
    let br = if br < 0L { br + bd } else { br }
    if ar == 0L || br == 0L {
      break if ar == br { 0 } else if ar == 0L { -direction } else { direction }
    }
    continue ad, ar, bd, br, -direction
  }
}

///|
pub fn Rational::floor(self : Rational) -> Int64 {
  let quotient = self.num / self.den
  if self.num % self.den < 0L {
    quotient - 1L
  } else {
    quotient
  }
}
