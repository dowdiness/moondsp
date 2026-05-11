///|
using @song {
  type Section,
  type SectionBody,
  type SectionBuildError,
  type TimeScope,
}

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
test "Section constructor rejects non-positive lengths" {
  let pat = @pattern.note(60.0)
  let result = try? Section(
    name="bad",
    length_cycles=@pattern.Rational::from_int(0),
    scope=TimeScope::identity(),
    body=SectionBody::single(pat),
  )
  match result {
    Err(SectionBuildError::NonPositiveLength) => ()
    _ => assert_true(false)
  }
}

///|
test "TimeScope constructor creates identity scope" {
  assert_true(TimeScope().is_identity())
}

///|
test "SectionBody::layers stacks ordered named layers" {
  let result = try? Section(
    name="chorus",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionBody::layers([
      @song.SectionLayer(name="bass", body=@pattern.note(36.0)),
      @song.SectionLayer(name="lead", body=@pattern.note(64.0)),
    ]),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
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
test "Section constructor accepts pattern body wrapper" {
  let pat = @pattern.note(60.0)
  let result = try? Section(
    name="main",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionBody::single(pat),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
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
