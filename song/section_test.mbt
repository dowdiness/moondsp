///|
using @song {
  type Section,
  type SectionBody,
  type SectionBuildError,
  type SectionPatch,
  type SectionPatchError,
  type TimeScope,
  type TimeScopeBuildError,
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
test "TimeScope fast and slow constructors expose exact rates" {
  let fast_result = try? TimeScope::fast(factor=@pattern.Rational::from_int(2))
  let fast = match fast_result {
    Ok(scope) => scope
    Err(_) => abort("fast scope creation failed")
  }
  assert_true(!fast.is_identity())
  assert_true(fast.rate() == @pattern.Rational::from_int(2))
  let slow_result = try? TimeScope::slow(factor=@pattern.Rational::from_int(2))
  let slow = match slow_result {
    Ok(scope) => scope
    Err(_) => abort("slow scope creation failed")
  }
  assert_true(!slow.is_identity())
  assert_true(slow.rate() == @pattern.Rational::new(1L, 2L))
}

///|
test "TimeScope rejects non-positive rates" {
  let result = try? TimeScope::fast(factor=@pattern.Rational::from_int(0))
  match result {
    Err(TimeScopeBuildError::NonPositiveRate) => ()
    _ => assert_true(false)
  }
}

///|
test "Section::query applies non-identity TimeScope" {
  let scope_result = try? TimeScope::fast(factor=@pattern.Rational::from_int(2))
  let scope = match scope_result {
    Ok(scope) => scope
    Err(_) => abort("scope creation failed")
  }
  let result = try? Section(
    name="fast",
    length_cycles=@pattern.Rational::from_int(1),
    scope~,
    body=SectionBody::single(@pattern.note(60.0)),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let scoped_events = section.query(arc)
  let raw_events = section.body().query(arc)
  assert_eq(raw_events.length(), 1)
  assert_eq(scoped_events.length(), 2)
  assert_true(scoped_events[0].part.begin == @pattern.Rational::from_int(0))
  assert_true(scoped_events[1].part.begin == @pattern.Rational::new(1L, 2L))
  assert_true(
    scoped_events[1].whole.unwrap().begin == @pattern.Rational::new(1L, 2L),
  )
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

///|
test "Section::apply_patch add layer appends named layer" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let result = try? base.apply_patch(
    SectionPatch::add_layer("counter", @pattern.note(55.0)),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("patch failed")
  }
  assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("counter") is Some(_))
}

///|
test "Section::apply_patch set layer replaces existing layer" {
  let single = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let base = single.layer(name="counter", body=@pattern.note(55.0))
  let result = try? base.apply_patch(
    SectionPatch::set_layer("counter", @pattern.note(67.0)),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("patch failed")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(48.0))
  assert_true(events[1].value.get("note") == Some(67.0))
}

///|
test "Section::apply_patch add layer rejects duplicate layer" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let result = try? base.apply_patch(
    SectionPatch::add_layer("main", @pattern.note(55.0)),
  )
  match result {
    Err(SectionPatchError::DuplicateLayer("main")) => ()
    _ => assert_true(false)
  }
}

///|
test "Section::apply_patch set layer rejects missing layer" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let result = try? base.apply_patch(
    SectionPatch::set_layer("counter", @pattern.note(55.0)),
  )
  match result {
    Err(SectionPatchError::MissingLayer("counter")) => ()
    _ => assert_true(false)
  }
}
