///|
pub struct Rational {
  num : Int64
  den : Int64
} derive(Eq, Show)

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
  // cross-multiply: self.num/self.den vs other.num/other.den
  // => self.num * other.den vs other.num * self.den (den always positive)
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
