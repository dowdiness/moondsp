///|
test "tempo edits preserve the anchor and retime only remaining distance" {
  let clock = @transport.Clock::at_start(
      @transport.Tempo::from_bpm(120.0).unwrap(),
      48000.0,
    )
    .unwrap()
    .advance(480000)
    .unwrap()
  assert_true(
    clock.position(clock.sample()).unwrap() == @pattern.Rational::from_int(20),
  )
  let slower = clock.with_tempo(@transport.Tempo::from_bpm(60.0).unwrap())
  assert_true(
    slower.position(slower.sample()).unwrap() ==
    clock.position(clock.sample()).unwrap(),
  )
  assert_eq(slower.sample_at(@pattern.Rational::from_int(24)).unwrap(), 672000L)
  assert_true(
    slower.advance(96000).unwrap().position(576000L).unwrap() ==
    @pattern.Rational::from_int(22),
  )
}

///|
test "conversion rounds onsets upward and retains millibpm precision" {
  let clock = @transport.Clock::at_start(
    @transport.Tempo::from_bpm(120.1234).unwrap(),
    48000.0,
  ).unwrap()
  assert_eq(clock.tempo().bpm(), 120.123)
  assert_true(
    clock.position(128L).unwrap() ==
    @pattern.Rational::new(128L * 120123L, 2880000000L),
  )
  let clock = clock.with_tempo(@transport.Tempo::from_bpm(120.0).unwrap())
  for
    entry in [(1L, 3L, 8000L), (1L, 7L, 3429L), (-1L, 7L, -3428L), (0L, 1L, 0L)] {
    let (n, d, expected) = entry
    assert_eq(clock.sample_at(@pattern.Rational::new(n, d)).unwrap(), expected)
  }
}

///|
test "many tempo edits keep exact position without denominator growth" {
  let mut clock = @transport.Clock::at_start(
    @transport.Tempo::from_bpm(120.0).unwrap(),
    48000.0,
  ).unwrap()
  for _ in 0..<10000 {
    clock = clock
      .with_tempo(@transport.Tempo::from_bpm(120.123).unwrap())
      .advance(128)
      .unwrap()
    clock = clock
      .with_tempo(@transport.Tempo::from_bpm(89.987).unwrap())
      .advance(128)
      .unwrap()
  }
  let expected = @pattern.Rational::new(
    10000L * 128L * (120123L + 89987L),
    2880000000L,
  )
  assert_true(clock.position(clock.sample()).unwrap() == expected)
  assert_eq(clock.sample_at(expected).unwrap(), 2560000L)
}

///|
test "invalid input and integer overflow return errors" {
  for bpm in [0.0, -1.0, 1000.001, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(@transport.Tempo::from_bpm(bpm) is Err(_))
  }
  let tempo = @transport.Tempo::from_bpm(1000.0).unwrap()
  for sr in [0.0, 48000.5, 384001.0, 0.0 / 0.0] {
    assert_true(@transport.Clock::at_start(tempo, sr) is Err(_))
  }
  let clock = @transport.Clock::at_start(tempo, 48000.0).unwrap()
  assert_true(clock.position(9223372036854775807L) is Err(_))
  assert_true(
    clock.sample_at(@pattern.Rational::new(9223372036854775807L, 1L)) is Err(_),
  )
  assert_true(clock.advance(-1) is Err(_))
}

///|
test "fractional tempo remains queryable after eight hours" {
  let clock = @transport.Clock::at_start(
      @transport.Tempo::from_bpm(120.123).unwrap(),
      48000.0,
    )
    .unwrap()
    .advance(1382400000)
    .unwrap()
  let arc = @pattern.TimeSpan::new(
    clock.position(clock.sample()).unwrap(),
    clock.position(clock.sample() + 128L).unwrap(),
  )
  assert_true(arc.duration() == @pattern.Rational::new(120123L, 22500000L))
  let events = @pattern.sequence([@pattern.note(60.0), @pattern.note(64.0)])
    .slow(@pattern.Rational::from_int(3))
    .query(arc)
  assert_eq(events.length(), 1)
  assert_eq(events[0].value.get("note"), Some(64.0))
  assert_true(events[0].part == arc)
}
