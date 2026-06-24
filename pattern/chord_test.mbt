///|
test "chord parse C major" {
  let notes = parse_chord("C")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 67])
    None => fail("expected Some for C major")
  }
}

///|
test "chord parse D minor" {
  let notes = parse_chord("Dm")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [62, 65, 69])
    None => fail("expected Some for Dm")
  }
}

///|
test "chord parse G dominant 7" {
  let notes = parse_chord("G7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [67, 71, 74, 77])
    None => fail("expected Some for G7")
  }
}

///|
test "chord parse C major 7" {
  let notes = parse_chord("Cmaj7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 67, 71])
    None => fail("expected Some for Cmaj7")
  }
}

///|
test "chord parse Cmaj7 with M7 alias" {
  let notes = parse_chord("CM7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 67, 71])
    None => fail("expected Some for CM7")
  }
}

///|
test "chord parse F# minor 7" {
  let notes = parse_chord("F#m7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [66, 69, 73, 76])
    None => fail("expected Some for F#m7")
  }
}

///|
test "chord parse Bb major" {
  let notes = parse_chord("Bb")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [70, 74, 77])
    None => fail("expected Some for Bb")
  }
}

///|
test "chord parse E sus4" {
  let notes = parse_chord("Esus4")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [64, 69, 71])
    None => fail("expected Some for Esus4")
  }
}

///|
test "chord parse A minor" {
  let notes = parse_chord("Am")
  match notes {
    Some(arr) =>
      // A4 = 69, C5 = 72, E5 = 76
      @debug.assert_eq(arr, [69, 72, 76])
    None => fail("expected Some for Am")
  }
}

///|
test "chord parse C diminished" {
  let notes = parse_chord("Cdim")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 63, 66])
    None => fail("expected Some for Cdim")
  }
}

///|
test "chord parse C augmented" {
  let notes = parse_chord("Caug")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 68])
    None => fail("expected Some for Caug")
  }
}

///|
test "chord parse C+ augmented" {
  let notes = parse_chord("C+")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 68])
    None => fail("expected Some for C+")
  }
}

///|
test "chord parse D diminished 7" {
  let notes = parse_chord("Ddim7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [62, 65, 68, 71])
    None => fail("expected Some for Ddim7")
  }
}

///|
test "chord parse D half-dim 7 (m7b5)" {
  let notes = parse_chord("Dm7b5")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [62, 65, 68, 72])
    None => fail("expected Some for Dm7b5")
  }
}

///|
test "chord parse C half-dim 7 with ø7 alias" {
  let notes = parse_chord("Cø7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 63, 66, 70])
    None => fail("expected Some for Cø7")
  }
}

///|
test "chord returns None for unsupported extension instead of octave carry" {
  match parse_chord("Cm13") {
    None => ()
    Some(_) => fail("expected None for unsupported Cm13")
  }
}

///|
test "chord returns None for mixed accidentals" {
  match parse_chord("C#b") {
    None => ()
    Some(_) => fail("expected None for C#b")
  }
  match parse_chord("Cb#") {
    None => ()
    Some(_) => fail("expected None for Cb#")
  }
  match parse_chord("C#b4") {
    None => ()
    Some(_) => fail("expected None for C#b4")
  }
}

///|
test "chord parse with octave override" {
  let notes = parse_chord("C5")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [72, 76, 79])
    None => fail("expected Some for C5")
  }
}

///|
test "chord parse Dm with octave override" {
  let notes = parse_chord("Dm3")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [50, 53, 57])
    None => fail("expected Some for Dm3")
  }
}

///|
test "chord parse A augmented 7" {
  let notes = parse_chord("Aaug7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [69, 73, 77, 79])
    None => fail("expected Some for Aaug7")
  }
}

///|
test "chord parse A+7 augmented 7" {
  let notes = parse_chord("A+7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [69, 73, 77, 79])
    None => fail("expected Some for A+7")
  }
}

///|
test "chord parse C sus2" {
  let notes = parse_chord("Csus2")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 62, 67])
    None => fail("expected Some for Csus2")
  }
}

///|
test "chord parse G 7sus4" {
  let notes = parse_chord("G7sus4")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [67, 72, 74, 77])
    None => fail("expected Some for G7sus4")
  }
}

///|
test "chord parse C add9" {
  let notes = parse_chord("Cadd9")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 67, 74])
    None => fail("expected Some for Cadd9")
  }
}

///|
test "chord parse C 6th" {
  let notes = parse_chord("C6")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 67, 69])
    None => fail("expected Some for C6")
  }
}

///|
test "chord parse A minor 6" {
  let notes = parse_chord("Am6")
  match notes {
    Some(arr) =>
      // A4 = 69, C5 = 72, E5 = 76, F#5 = 78
      @debug.assert_eq(arr, [69, 72, 76, 78])
    None => fail("expected Some for Am6")
  }
}

///|
test "chord parse Eb major" {
  let notes = parse_chord("Eb")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [63, 67, 70])
    None => fail("expected Some for Eb")
  }
}

///|
test "chord parse Gb major 7" {
  let notes = parse_chord("Gbmaj7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [66, 70, 73, 77])
    None => fail("expected Some for Gbmaj7")
  }
}

///|
test "chord parse Gb major 7 with M7" {
  let notes = parse_chord("GbM7")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [66, 70, 73, 77])
    None => fail("expected Some for GbM7")
  }
}

///|
test "chord parse C major 9 with M9 alias" {
  let notes = parse_chord("CM9")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [60, 64, 67, 71, 74])
    None => fail("expected Some for CM9")
  }
}

///|
test "chord returns None for empty string" {
  match parse_chord("") {
    None => () // expected
    Some(_) => fail("expected None for empty string")
  }
}

///|
test "chord returns None for invalid root" {
  match parse_chord("X") {
    None => () // expected
    Some(_) => fail("expected None for invalid root")
  }
}

///|
test "chord returns None for unknown quality" {
  match parse_chord("Cfoo") {
    None => () // expected
    Some(_) => fail("expected None for unknown quality")
  }
}

///|
test "chord pattern C major produces 3 note events" {
  let pat = chord("C")
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  @debug.assert_eq(events.length(), 3)
}

///|
test "chord pattern C major has correct note values" {
  let pat = chord("C")
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  let notes = events.map(ev => ev.value.0.get("note"))
  // Stack order: the order from chord intervals [0, 4, 7]
  assert_true(notes.contains(Some(60.0)))
  assert_true(notes.contains(Some(64.0)))
  assert_true(notes.contains(Some(67.0)))
}

///|
test "chord pattern Dm produces 3 note events" {
  let pat = chord("Dm")
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  @debug.assert_eq(events.length(), 3)
  let notes = events.map(ev => ev.value.0.get("note"))
  assert_true(notes.contains(Some(62.0)))
  assert_true(notes.contains(Some(65.0)))
  assert_true(notes.contains(Some(69.0)))
}

///|
test "chord pattern G7 produces 4 note events" {
  let pat = chord("G7")
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  @debug.assert_eq(events.length(), 4)
}

///|
test "chord pattern silence for unknown chord" {
  let pat = chord("X")
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(arc)
  @debug.assert_eq(events.length(), 0)
}

///|
test "chord parse E natural (no accidental confusion from f)" {
  // "ef" inside a chord name should be parsed as:
  // root=E, then 'f' after the root: check it's not parsed as E-flat
  // Actually "Ef" with f after E would be E followed by 'f' — but 'f' is the flat marker
  // Wait — "Ef" by itself: root=E, accidental=f → E flat? 
  // But "E" followed by "f" in name context means E then f...
  // Let me think: "Ef" as a chord name — E is root, f might be accidental.
  // After parsing root E at pos=0, pos=1 is 'f'. In our parser, 'f' is a flat marker.
  // So "Ef" → E flat → offset 9 + (-1) = 8 → E♭4 = [63, 67, 70] (same as Eb).
  // Actually that's correct — "Ef" is the alternate flat spelling for E♭.
  let notes = parse_chord("Ef")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [63, 67, 70])
    None => fail("expected Some for Ef (E-flat)")
  }
}

///|
test "chord parse C with octave 2" {
  let notes = parse_chord("C2")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [36, 40, 43])
    None => fail("expected Some for C2")
  }
}

///|
test "chord parse with flat using b syntax" {
  let notes = parse_chord("Bb3")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [58, 62, 65])
    None => fail("expected Some for Bb3")
  }
}

///|
test "chord parse Cb preserves lower octave" {
  let notes = parse_chord("Cb4")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [59, 63, 66])
    None => fail("expected Some for Cb4")
  }
}

///|
test "chord parse B# preserves upper octave" {
  let notes = parse_chord("B#4")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [72, 76, 79])
    None => fail("expected Some for B#4")
  }
}

///|
test "chord parse F# with octave 5" {
  let notes = parse_chord("F#5")
  match notes {
    Some(arr) => @debug.assert_eq(arr, [78, 82, 85])
    None => fail("expected Some for F#5")
  }
}

///|
test "note_name_to_midi C4" {
  match note_name_to_midi("C4") {
    Some(midi) => @debug.assert_eq(midi, 60.0)
    None => fail("expected Some for C4")
  }
}

///|
test "note_name_to_midi A4" {
  match note_name_to_midi("A4") {
    Some(midi) => @debug.assert_eq(midi, 69.0)
    None => fail("expected Some for A4")
  }
}

///|
test "note_name_to_midi F#3" {
  match note_name_to_midi("F#3") {
    Some(midi) => @debug.assert_eq(midi, 54.0)
    None => fail("expected Some for F#3")
  }
}

///|
test "note_name_to_midi Bb5" {
  match note_name_to_midi("Bb5") {
    Some(midi) => @debug.assert_eq(midi, 82.0)
    None => fail("expected Some for Bb5")
  }
}

///|
test "note_name_to_midi C without octave defaults to 4" {
  match note_name_to_midi("C") {
    Some(midi) => @debug.assert_eq(midi, 60.0)
    None => fail("expected Some for C")
  }
}

///|
test "note_name_to_midi Eb6" {
  match note_name_to_midi("Eb6") {
    Some(midi) => @debug.assert_eq(midi, 87.0)
    None => fail("expected Some for Eb6")
  }
}

///|
test "note_name_to_midi returns None for empty string" {
  match note_name_to_midi("") {
    None => ()
    Some(_) => fail("expected None for empty")
  }
}

///|
test "note_name_to_midi returns None for invalid root" {
  match note_name_to_midi("X") {
    None => ()
    Some(_) => fail("expected None for invalid root")
  }
}

///|
test "note_name_to_midi returns None for trailing garbage" {
  match note_name_to_midi("Cfoo") {
    None => ()
    Some(_) => fail("expected None for trailing garbage")
  }
}

///|
test "note_name_to_midi returns None for mixed accidentals" {
  match note_name_to_midi("C#b") {
    None => ()
    Some(_) => fail("expected None for C#b")
  }
  match note_name_to_midi("Cb#") {
    None => ()
    Some(_) => fail("expected None for Cb#")
  }
  match note_name_to_midi("C#b4") {
    None => ()
    Some(_) => fail("expected None for C#b4")
  }
}

///|
test "note_name_to_midi C# (no octave) defaults to 4" {
  match note_name_to_midi("C#") {
    Some(midi) => @debug.assert_eq(midi, 61.0)
    None => fail("expected Some for C#")
  }
}
