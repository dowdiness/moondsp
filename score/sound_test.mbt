///|
test "a sample's number is its position in all" {
  for i, sample in @score.Sample::all() {
    assert_eq(sample.number(), i)
    assert_eq(@score.Sample::parse(sample.name()), Some(sample))
  }
}
