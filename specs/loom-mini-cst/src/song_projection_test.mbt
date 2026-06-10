// Phase 2 Piece 2 — song-level differential parity harness.
//
// Compares the loom song projection (`loom_mini_parse_song`) against the oracle
// (`@mini.parse_song_with_bpm`). Both build a real `@song.Song[ControlMap]`, so
// part layout, fill gaps, and occurrence ids are equal BY CONSTRUCTION when the
// section/part/fill/bpm specs agree; divergence can only enter through parsing
// or section-body lowering. The harness decomposes equality by NAME and lowered
// VALUE (never object identity — `@song` exposes no stable section identity):
// bpm, ordered occurrences (name / start / end / section name+length / id), each
// section's body events, and the whole-song query events. Section-body parity
// reuses Piece 1's value-level helper (`projection_boundary_assert_value_events_equal`)
// minus the leaf-id axis, which `Pat::query` does not surface on the oracle side.

///|
fn song_parity_unwrap_loom(
  result : Result[LoomMiniParsedSong, String],
) -> LoomMiniParsedSong {
  match result {
    Ok(parsed) => parsed
    Err(msg) => abort("expected loom parsed song, got Err(\{msg})")
  }
}

///|
fn song_parity_unwrap_oracle(
  result : Result[@mini.ParsedSong, String],
) -> @mini.ParsedSong {
  match result {
    Ok(parsed) => parsed
    Err(msg) => abort("expected oracle parsed song, got Err(\{msg})")
  }
}

///|
/// Canonicalize plain `@pattern.Event`s (from `Section::query` / `Song::query`,
/// which carry no source ids) into Piece 1's `BoundaryEvent` shape with a fixed
/// sentinel id, so the value-level comparison runs on `{control, whole, part}`.
fn song_parity_value_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[BoundaryEvent] {
  let out : Array[BoundaryEvent] = []
  for event in events {
    out.push({
      id: "<song>",
      control: event.value.entries(),
      whole: event.whole,
      part: event.part,
    })
  }
  out
}

///|
/// Assert loom and oracle AGREE on `input`: both `Ok` (then full structural +
/// value decomposition) or both `Err` (message text not contractual). A
/// one-sided result is a real parity hole and aborts.
fn assert_song_parity(input : String) -> Unit {
  let loom_result = loom_mini_parse_song(input)
  let oracle_result = @mini.parse_song_with_bpm(input)
  match (loom_result, oracle_result) {
    (Ok(loom), Ok(oracle)) =>
      assert_song_parity_equal(input, loom, oracle)
    (Err(_), Err(_)) => ()
    (Ok(_), Err(msg)) =>
      abort("input '\{input}': loom accepted but oracle rejected (\{msg})")
    (Err(msg), Ok(_)) =>
      abort("input '\{input}': oracle accepted but loom rejected (\{msg})")
  }
}

///|
fn assert_song_parity_equal(
  input : String,
  loom : LoomMiniParsedSong,
  oracle : @mini.ParsedSong,
) -> Unit {
  if loom.bpm() != oracle.bpm() {
    abort("input '\{input}': bpm mismatch")
  }
  let loom_song = loom.song()
  let oracle_song = oracle.song()
  if loom_song.duration() != oracle_song.duration() {
    abort("input '\{input}': song duration mismatch")
  }
  let loom_occurrences = loom_song.occurrences()
  let oracle_occurrences = oracle_song.occurrences()
  if loom_occurrences.length() != oracle_occurrences.length() {
    abort("input '\{input}': occurrence count mismatch")
  }
  let window = projection_boundary_parity_window()
  for index in 0..<loom_occurrences.length() {
    let l = loom_occurrences[index]
    let o = oracle_occurrences[index]
    if l.name() != o.name() {
      abort("input '\{input}': occurrence[\{index}] name mismatch")
    }
    if l.start() != o.start() {
      abort("input '\{input}': occurrence[\{index}] start mismatch")
    }
    if l.end_() != o.end_() {
      abort("input '\{input}': occurrence[\{index}] end mismatch")
    }
    if l.id().value() != o.id().value() {
      abort("input '\{input}': occurrence[\{index}] id mismatch")
    }
    let l_section = l.section()
    let o_section = o.section()
    if l_section.name() != o_section.name() {
      abort("input '\{input}': occurrence[\{index}] section name mismatch")
    }
    if l_section.length_cycles() != o_section.length_cycles() {
      abort("input '\{input}': occurrence[\{index}] section length mismatch")
    }
    projection_boundary_assert_value_events_equal(
      song_parity_value_events(l_section.query(window)),
      song_parity_value_events(o_section.query(window)),
    )
  }
  // Whole-song parity over the song's own duration window folds part placement,
  // section bodies, and timing into one global cross-check.
  let global_window = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    loom_song.duration(),
  )
  projection_boundary_assert_value_events_equal(
    song_parity_value_events(loom_song.query(global_window)),
    song_parity_value_events(oracle_song.query(global_window)),
  )
}

///|
/// Assert both implementations reject `input` (malformed corpus). Catches a
/// loom over-acceptance that `assert_song_parity`'s both-`Err` arm would
/// silently tolerate if the oracle also (wrongly) accepted.
fn assert_song_both_reject(input : String) -> Unit {
  let loom_rejected = loom_mini_parse_song(input) is Err(_)
  let oracle_rejected = @mini.parse_song_with_bpm(input) is Err(_)
  if !loom_rejected {
    abort("input '\{input}': expected loom to reject")
  }
  if !oracle_rejected {
    abort("input '\{input}': expected oracle to reject")
  }
  // Agreement is still enforced (a one-sided accept aborts in here above).
  assert_song_parity(input)
}

///|
fn song_parity_valid_corpus() -> Array[String] {
  let multiline =
    #|song(
    #|  section(
    #|    "ode",
    #|    4,
    #|    stack(
    #|      s("bd")
    #|        .slow(4),
    #|      note("64
    #|64 65
    #|67")
    #|        .slow(4)
    #|    )
    #|  ),
    #|  part("ode1", "ode")
    #|)
  [
    // implicit parts across two sections
    "song(section(\"intro\",1,s(\"bd\")),section(\"verse\",2,note(\"60\")),part(\"intro1\",\"intro\"),part(\"verse1\",\"verse\"))",
    // bpm metadata
    "song(bpm(72),section(\"intro\",1,s(\"bd\")),part(\"intro1\",\"intro\"))",
    // multiline whitespace + notation newlines + method chains
    multiline,
    // explicit rational starts and gaps
    "song(section(\"a\",1,s(\"bd\")),section(\"b\",1,s(\"sd\")),part(\"a1\",\"a\"),part(\"b1\",\"b\",3/2))",
    // authoring order preserved for explicit overlaps
    "song(section(\"late\",2,s(\"bd\")),section(\"early\",2,s(\"sd\")),part(\"late1\",\"late\",1),part(\"early1\",\"early\",0))",
    // boundary fill directive
    "song(section(\"a\",1,s(\"bd\")),section(\"b\",1,s(\"sd\")),section(\"fill\",1,s(\"hh\")),part(\"a1\",\"a\"),part(\"b1\",\"b\",3),fill(\"fill\",\"fill\"))",
    // explicit occurrence id (with ':') and display name (with ' ')
    "song(section(\"verse\",1,s(\"bd\")),part_id(\"verse:1\",\"Verse 1\",\"verse\"))",
    // control method on a section body
    "song(section(\"a\",1,s(\"bd\").gain(0.5)),part(\"a1\",\"a\"))",
  ]
}

///|
fn song_parity_malformed_corpus() -> Array[String] {
  [
    // unknown section reference
    "song(part(\"a1\",\"missing\"))",
    // empty song()
    "song()",
    // duplicate section name
    "song(section(\"a\",1,s(\"bd\")),section(\"a\",1,s(\"sd\")),part(\"a1\",\"a\"))",
    // duplicate bpm
    "song(bpm(72),bpm(80),section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    // non-positive bpm
    "song(bpm(-1),section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    // non-positive section length
    "song(section(\"a\",0,s(\"bd\")),part(\"a1\",\"a\"))",
    // empty occurrence id
    "song(section(\"a\",1,s(\"bd\")),part_id(\"\",\"x\",\"a\"))",
    // duplicate occurrence name
    "song(section(\"a\",1,s(\"bd\")),part(\"x\",\"a\"),part(\"x\",\"a\"))",
    // trailing input after song()
    "song(section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\")) extra",
    // missing close paren
    "song(section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\")",
    // unknown item keyword
    "song(verse(\"a\",1,s(\"bd\")))",
    // whitespace before keyword paren (oracle match_keyword is contiguous)
    "song (section(\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
    "song(section (\"a\",1,s(\"bd\")),part(\"a1\",\"a\"))",
  ]
}

///|
/// Positive control (Piece 2 calibration): prove the song-level value parity is
/// sensitive, not vacuous. Perturb one section-body event's ControlMap and
/// confirm the value-level helper aborts. `panic ` ⇒ the test PASSES iff abort.
test "panic phase2 piece2 song body parity catches control divergence" {
  let parsed = song_parity_unwrap_loom(
    loom_mini_parse_song(
      "song(section(\"a\",1,s(\"bd\").gain(0.5)),part(\"a1\",\"a\"))",
    ),
  )
  let occurrence = parsed.song().occurrences()[0]
  let window = projection_boundary_parity_window()
  let base = song_parity_value_events(occurrence.section().query(window))
  guard base.length() > 0 else {
    abort("positive control needs at least one event")
  }
  let perturbed : Array[BoundaryEvent] = []
  for index in 0..<base.length() {
    let event = base[index]
    if index == 0 {
      let bumped : Map[String, Double] = {}
      event.control.each(fn(key, value) { bumped[key] = value })
      bumped["__divergence__"] = 1.0
      perturbed.push({
        id: event.id,
        control: bumped,
        whole: event.whole,
        part: event.part,
      })
    } else {
      perturbed.push(event)
    }
  }
  projection_boundary_assert_value_events_equal(base, perturbed)
}

///|
/// Piece 2 green gate (plan Step 12): the whole song corpus passes agreement +
/// structural + value-level parity, and every malformed case is rejected by
/// both implementations.
test "phase2 piece2 song value-parity corpus" {
  let valid = song_parity_valid_corpus()
  for input in valid {
    assert_song_parity(input)
  }
  let malformed = song_parity_malformed_corpus()
  for input in malformed {
    assert_song_both_reject(input)
  }
  inspect(valid.length() >= 7, content="true")
  inspect(malformed.length() >= 7, content="true")
}
