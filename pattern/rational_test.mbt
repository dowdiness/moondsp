///|
fn r(num : Int, den : Int) -> Rational {
  Rational::new(Int64::from_int(num), Int64::from_int(den))
}

///|
test "simplification: 6/4 -> 3/2" {
  let rat = r(6, 4)
  inspect(
    rat,
    content=(
      #|{ num: 3, den: 2 }
    ),
  )
}

///|
test "simplification: 2/4 -> 1/2" {
  let rat = r(2, 4)
  inspect(
    rat,
    content=(
      #|{ num: 1, den: 2 }
    ),
  )
}

///|
test "negative denominator normalization" {
  let rat = Rational::new(3L, -4L)
  inspect(
    rat,
    content=(
      #|{ num: -3, den: 4 }
    ),
  )
}

///|
test "negative denominator normalization: -3/-4 -> 3/4" {
  let rat = Rational::new(-3L, -4L)
  inspect(
    rat,
    content=(
      #|{ num: 3, den: 4 }
    ),
  )
}

///|
test "add: 1/2 + 1/3 = 5/6" {
  let result = r(1, 2) + r(1, 3)
  inspect(
    result,
    content=(
      #|{ num: 5, den: 6 }
    ),
  )
}

///|
test "sub: 3/4 - 1/4 = 1/2" {
  let result = r(3, 4) - r(1, 4)
  inspect(
    result,
    content=(
      #|{ num: 1, den: 2 }
    ),
  )
}

///|
test "mul: 2/3 * 3/4 = 1/2" {
  let result = r(2, 3) * r(3, 4)
  inspect(
    result,
    content=(
      #|{ num: 1, den: 2 }
    ),
  )
}

///|
test "div: 3/4 / 3/2 = 1/2" {
  let result = r(3, 4) / r(3, 2)
  inspect(
    result,
    content=(
      #|{ num: 1, den: 2 }
    ),
  )
}

///|
test "compare: 1/2 < 2/3" {
  let a = r(1, 2)
  let b = r(2, 3)
  assert_true(a < b)
  assert_true(b > a)
}

///|
test "compare: 2/4 == 1/2" {
  let a = r(2, 4)
  let b = r(1, 2)
  assert_true(a == b)
  assert_true(a.compare(b) == 0)
}

///|
test "floor: positive 7/4 = 1" {
  let result = r(7, 4).floor()
  inspect(result, content="1")
}

///|
test "floor: positive exact 4/2 = 2" {
  let result = r(4, 2).floor()
  inspect(result, content="2")
}

///|
test "floor: negative -7/4 = -2" {
  let result = r(-7, 4).floor()
  inspect(result, content="-2")
}

///|
test "floor: negative -4/4 = -1" {
  let result = r(-4, 4).floor()
  inspect(result, content="-1")
}

///|
test "from_int: 5 -> 5/1" {
  let rat = Rational::from_int(5)
  inspect(
    rat,
    content=(
      #|{ num: 5, den: 1 }
    ),
  )
}

///|
test "to_double: 1/4 = 0.25" {
  let d = r(1, 4).to_double()
  inspect(d, content="0.25")
}

///|
test "panic zero denominator" {
  ignore(Rational::new(1L, 0L))
}
