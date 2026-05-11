///|
test "Section::from_pattern wraps a pattern with identity scope" {
  let pat = @pattern.note(60.0)
  let section = Section::from_pattern(name="main", body=pat)
  assert_eq(section.name(), "main")
  assert_true(section.length_cycles() == @pattern.Rational::from_int(1))
  assert_true(section.scope().is_identity())
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
}

///|
test "Section::new rejects non-positive lengths" {
  let pat = @pattern.note(60.0)
  let zero = Section::new(
    name="bad",
    length_cycles=@pattern.Rational::from_int(0),
    scope=TimeScope::identity(),
    body=pat,
  )
  assert_true(zero is None)
}

///|
test "SectionBody::layers stacks ordered named layers" {
  let section = match
    Section::new_body(
      name="chorus",
      length_cycles=@pattern.Rational::from_int(1),
      scope=TimeScope::identity(),
      body=SectionBody::layers([
        SectionLayer::new(name="bass", body=@pattern.note(36.0)),
        SectionLayer::new(name="lead", body=@pattern.note(64.0)),
      ]),
    ) {
    Some(section) => section
    None => abort("section creation failed")
  }
  assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("bass") is Some(_))
  assert_true(section.get_layer("lead") is Some(_))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(36.0))
  assert_true(events[1].value.get("note") == Some(64.0))
}

///|
test "Section::layer converts single body to named layers" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let section = base.layer(name="counter", body=@pattern.note(55.0))
  assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("main") is Some(_))
  assert_true(section.get_layer("counter") is Some(_))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(48.0))
  assert_true(events[1].value.get("note") == Some(55.0))
}

///|
test "Section::layer replaces existing layer by name" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let section = base.layer(name="main", body=@pattern.note(60.0))
  assert_eq(section.layer_count(), 1)
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
}
