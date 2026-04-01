///|
fn span(b_num : Int, b_den : Int, e_num : Int, e_den : Int) -> TimeSpan {
  TimeSpan::new(r(b_num, b_den), r(e_num, e_den))
}

///|
test "duration: [0, 1) = 1" {
  let ts = span(0, 1, 1, 1)
  inspect(
    ts.duration(),
    content=(
      #|{num: 1, den: 1}
    ),
  )
}

///|
test "duration: [1/4, 3/4) = 1/2" {
  let ts = span(1, 4, 3, 4)
  inspect(
    ts.duration(),
    content=(
      #|{num: 1, den: 2}
    ),
  )
}

///|
test "contains: [0, 1) contains 1/2" {
  let ts = span(0, 1, 1, 1)
  assert_true(ts.contains(r(1, 2)))
}

///|
test "contains: [0, 1) contains 0 (boundary begin)" {
  let ts = span(0, 1, 1, 1)
  assert_true(ts.contains(r(0, 1)))
}

///|
test "contains: [0, 1) does not contain 1 (half-open boundary end)" {
  let ts = span(0, 1, 1, 1)
  assert_false(ts.contains(r(1, 1)))
}

///|
test "contains: [0, 1) does not contain -1" {
  let ts = span(0, 1, 1, 1)
  assert_false(ts.contains(r(-1, 1)))
}

///|
test "intersect: overlapping [0,1) and [1/2,2) = [1/2, 1)" {
  let a = span(0, 1, 1, 1)
  let b = span(1, 2, 2, 1)
  match a.intersect(b) {
    Some(ts) =>
      inspect(
        ts,
        content=(
          #|{begin: {num: 1, den: 2}, end_: {num: 1, den: 1}}
        ),
      )
    None => abort("expected intersection")
  }
}

///|
test "intersect: disjoint [0,1) and [2,3) = None" {
  let a = span(0, 1, 1, 1)
  let b = span(2, 1, 3, 1)
  inspect(a.intersect(b), content="None")
}

///|
test "intersect: touching [0,1) and [1,2) = None (half-open)" {
  let a = span(0, 1, 1, 1)
  let b = span(1, 1, 2, 1)
  inspect(a.intersect(b), content="None")
}

///|
test "intersect: same arc = same arc" {
  let a = span(0, 1, 1, 1)
  match a.intersect(a) {
    Some(ts) =>
      inspect(
        ts,
        content=(
          #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 1}}
        ),
      )
    None => abort("expected intersection")
  }
}

///|
test "whole_cycles: single cycle [0,1) = [[0,1)]" {
  let ts = span(0, 1, 1, 1)
  let cycles = ts.whole_cycles()
  inspect(cycles.length(), content="1")
  inspect(
    cycles[0],
    content=(
      #|{begin: {num: 0, den: 1}, end_: {num: 1, den: 1}}
    ),
  )
}

///|
test "whole_cycles: multi-cycle [0,3) = 3 cycles" {
  let ts = span(0, 1, 3, 1)
  let cycles = ts.whole_cycles()
  inspect(cycles.length(), content="3")
}

///|
test "whole_cycles: partial [1/4, 7/4) spans 2 cycles" {
  let ts = span(1, 4, 7, 4)
  let cycles = ts.whole_cycles()
  inspect(cycles.length(), content="2")
  // first partial: [1/4, 1)
  inspect(
    cycles[0],
    content=(
      #|{begin: {num: 1, den: 4}, end_: {num: 1, den: 1}}
    ),
  )
  // second partial: [1, 7/4)
  inspect(
    cycles[1],
    content=(
      #|{begin: {num: 1, den: 1}, end_: {num: 7, den: 4}}
    ),
  )
}

///|
test "whole_cycles: sub-cycle [1/4, 3/4) = 1 arc" {
  let ts = span(1, 4, 3, 4)
  let cycles = ts.whole_cycles()
  inspect(cycles.length(), content="1")
  inspect(
    cycles[0],
    content=(
      #|{begin: {num: 1, den: 4}, end_: {num: 3, den: 4}}
    ),
  )
}
