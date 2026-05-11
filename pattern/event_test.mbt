///|
test "Event::shift shifts whole and part spans" {
  let event = Pat::pure(7).query(span(0, 1, 1, 2))[0]
  let shifted = event.shift(r(2, 1))
  inspect(
    shifted,
    content=(
      #|{
      #|  whole: Some({ begin: { num: 2, den: 1 }, end_: { num: 3, den: 1 } }),
      #|  part: { begin: { num: 2, den: 1 }, end_: { num: 5, den: 2 } },
      #|  value: 7,
      #|}
    ),
  )
}
