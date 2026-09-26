///|
fn pitch_test_span() -> TimeSpan {
  TimeSpan::new(Rational::from_int(0), Rational::from_int(1))
}

///|
fn pitch_test_notes(events : Array[Event[ControlMap]]) -> Array[Double] {
  events.map(event => event.value.get("note").unwrap_or(-1.0))
}

///|
test "pitch transforms preserve timing and non-note controls" {
  let source = merge_control(chord("C"), control("gain", 0.5))
  let shifted = source.transpose(2)
  let events = shifted.query(pitch_test_span())
  assert_eq(pitch_test_notes(events), [62.0, 66.0, 69.0])
  assert_true(events.all(event => event.value.get("gain") is Some(0.5)))
  assert_true(events.all(event => event.whole is Some(_)))
}

///|
test "explicit scale-step transposition follows the supplied scale" {
  let shifted = chord("C").steps([0, 2, 4, 5, 7, 9, 11], 1)
  assert_eq(pitch_test_notes(shifted.query(pitch_test_span())), [
    62.0, 65.0, 69.0,
  ])
}

///|
test "scale-step composition owns its validated pitch scale" {
  let scale = [0, 2, 4, 5, 7, 9, 11]
  let shifted = note(60.0).steps(scale, 1)
  scale[1] = 3
  assert_eq(pitch_test_notes(shifted.query(pitch_test_span())), [62.0])
}

///|
test "lowest and voicing project shared chord events without changing their clock" {
  let progression = sequence([chord("C"), chord("G7")]).slow(
    Rational::from_int(4),
  )
  let roots = progression.lowest()
  assert_eq(pitch_test_notes(roots.query(pitch_test_span())), [60.0])
  let voicing = progression.voicing(60, 77, count=2)
  assert_eq(pitch_test_notes(voicing.query(pitch_test_span())), [60.0, 64.0])
  assert_eq(roots.entry_period(), progression.entry_period())
  assert_eq(voicing.entry_period(), progression.entry_period())
}

///|
test "direct cross-layer pitch projections expose the same playback material" {
  let layered = stack([note(60.0), note(64.0)])
  for projected in [layered.lowest(), layered.voicing(48, 79, count=1)] {
    assert_eq(pitch_test_notes(projected.query(pitch_test_span())), [60.0])
    let playback = []
    for entry in projected.entries() {
      playback.append(entry.query(pitch_test_span()))
    }
    assert_eq(pitch_test_notes(playback), [60.0])
  }
}

///|
test "onset mask keeps progression period and filters onset slots" {
  let progression = sequence([chord("C"), chord("G"), chord("F")])
  let filtered = progression.mask([true, false, true])
  let events = filtered.query(pitch_test_span())
  assert_eq(pitch_test_notes(events), [60.0, 64.0, 67.0, 65.0, 69.0, 72.0])
  assert_eq(filtered.entry_period(), progression.entry_period())
}

///|
test "onset mask owns the caller's slots across edits and clearing" {
  let slots = [true, false]
  let source = sequence([note(60.0), note(64.0)])
  let filtered = source.mask(slots)
  let layered = stack([
    note(60.0).named_entry("low"),
    note(64.0).named_entry("high"),
  ]).mask(slots)
  slots[0] = false
  slots[1] = true
  assert_eq(pitch_test_notes(filtered.query(pitch_test_span())), [60.0])
  assert_true(filtered.same_content(source.mask([true, false])))
  slots.clear()
  assert_eq(pitch_test_notes(filtered.query(pitch_test_span())), [60.0])
  let playback = []
  for entry in layered.entries() {
    playback.append(entry.query(pitch_test_span()))
  }
  assert_eq(pitch_test_notes(playback), [60.0, 64.0])
}

///|
test "all-rest onset mask keeps its authored entry and distinct content" {
  let source = note(60.0).slow(Rational::from_int(4)).named_entry("lead")
  let resting = source.mask([false, false])
  assert_eq(resting.query(pitch_test_span()).length(), 0)
  assert_eq(resting.entry_period(), Rational::from_int(4))
  assert_eq(resting.entries().length(), 1)
  assert_eq(resting.entries()[0].entry_key(), "name:lead")
  assert_false(resting.same_content(source))
  assert_true(resting.same_content(source.mask([false, false])))
  let empty : Array[Bool] = []
  let no_slots = source.mask(empty)
  assert_eq(no_slots.query(pitch_test_span()).length(), 0)
  assert_eq(no_slots.entry_period(), Rational::from_int(4))
  assert_eq(no_slots.entries().length(), 1)
  assert_false(no_slots.same_content(resting))
}

///|
test "pitch projections select the full onset cohort across split queries" {
  let source = stack([note(60.0).gate(Rational::new(1L, 4L)), note(72.0)])
  let late = TimeSpan::new(Rational::new(1L, 2L), Rational::from_int(1))
  for projected in [source.lowest(), source.voicing(48, 79, count=1)] {
    let whole = projected.query(pitch_test_span())
    let second_half = projected.query(late)
    assert_eq(pitch_test_notes(whole), [60.0])
    assert_eq(pitch_test_notes(second_half), [])
  }
}

///|
test "tail replacement clips the original span and preserves entry period" {
  let source = note(60.0).slow(Rational::from_int(4))
  let replaced = source.tail(note(64.0))
  let events = replaced.query(
    TimeSpan::new(Rational::from_int(0), Rational::from_int(4)),
  )
  assert_eq(pitch_test_notes(events), [60.0, 64.0])
  assert_eq(replaced.entry_period(), source.entry_period())
  assert_eq(
    events[0].whole,
    Some(TimeSpan::new(Rational::from_int(0), Rational::from_int(3))),
  )
  assert_eq(
    events[1].whole,
    Some(TimeSpan::new(Rational::from_int(3), Rational::from_int(4))),
  )
}

///|
test "tail replacement fills silence without shortening its authored span" {
  let source : Pat[ControlMap] = Pat::silence().slow(Rational::from_int(4))
  let replaced = source.tail(note(64.0))
  let events = replaced.query(
    TimeSpan::new(Rational::from_int(0), Rational::from_int(4)),
  )
  assert_eq(pitch_test_notes(events), [64.0])
  assert_eq(replaced.entry_period(), Rational::from_int(4))
  assert_true(
    events[0].part ==
    TimeSpan::new(Rational::from_int(3), Rational::from_int(4)),
  )
}

///|
test "voicing folds chord tones into the requested MIDI register" {
  let low_chord = chord("C", octave=2).voicing(48, 60)
  assert_eq(pitch_test_notes(low_chord.query(pitch_test_span())), [
    48.0, 52.0, 55.0,
  ])
}

///|
test "omitting voicing count retains every fitting chord tone" {
  let chord = chord("G7")
  assert_eq(pitch_test_notes(chord.voicing(48, 79).query(pitch_test_span())), [
    67.0, 71.0, 74.0, 77.0,
  ])
  assert_eq(
    pitch_test_notes(chord.voicing(48, 79, count=3).query(pitch_test_span())),
    [67.0, 71.0, 74.0],
  )
}

///|
test "tail rejects its one-cycle default on shorter entries" {
  let short = note(60.0).fast(Rational::from_int(2))
  try short.tail(note(64.0)) catch {
    TailError::InvalidDuration => ()
  } noraise {
    _ => abort("expected invalid duration")
  }
  let replaced = short.tail(note(64.0), cycles=Rational::new(1L, 2L))
  assert_eq(pitch_test_notes(replaced.query(pitch_test_span())), [64.0, 64.0])
}
