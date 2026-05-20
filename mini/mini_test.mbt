///|
test "drum_midi returns correct GM numbers" {
  debug_inspect(@mini.drum_midi("bd"), content="Some(36)")
  debug_inspect(@mini.drum_midi("sd"), content="Some(38)")
  debug_inspect(@mini.drum_midi("cp"), content="Some(39)")
  debug_inspect(@mini.drum_midi("hh"), content="Some(42)")
  debug_inspect(@mini.drum_midi("oh"), content="Some(46)")
}

///|
test "parse s(\"cp oh\") cross-pool drum sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"cp oh\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 39 })
    ),
  )
  inspect(
    events[1].value,
    content=(
      #|ControlMap({ "sound": 46 })
    ),
  )
}

///|
test "drum_midi returns None for unknown names" {
  debug_inspect(@mini.drum_midi("snare"), content="None")
  debug_inspect(@mini.drum_midi(""), content="None")
  debug_inspect(@mini.drum_midi("123"), content="None")
}

///|
/// Query a pattern over one cycle [0, 1) and return events.
fn query_one_cycle(
  pat : @pattern.Pat[@pattern.ControlMap],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  pat.query(arc)
}

///|
/// Unwrap an Ok result or fail the test.
fn unwrap_ok(
  result : Result[@pattern.Pat[@pattern.ControlMap], String],
) -> @pattern.Pat[@pattern.ControlMap] {
  match result {
    Ok(pat) => pat
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
fn unwrap_doc(
  result : Result[@pattern.PatternDoc[@pattern.ControlMap], String],
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  match result {
    Ok(doc) => doc
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
fn unwrap_mini_snapshot(
  result : Result[@pattern.PatternSnapshot[@pattern.ControlMap], String],
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(msg) => abort("expected Ok, got Err(\{msg})")
  }
}

///|
fn unwrap_lowered_snapshot(
  result : Result[
    @pattern.PatternSnapshot[@pattern.ControlMap],
    @pattern.PatternDocError,
  ],
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(_) => abort("expected lowered pattern snapshot")
  }
}

///|
fn pid(value : String) -> @identity.PatternNodeId {
  let result = try? @identity.PatternNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid pattern node id")
  }
}

///|
test "parse single drum sound" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 36 })
    ),
  )
}

///|
test "parse cutoff method merges sound control" {
  let pat = unwrap_ok(@mini.parse("s(\"bd\").cutoff(200)"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 36, "cutoff": 200 })
    ),
  )
}

///|
test "parse_snapshot lowers mini output through PatternDoc" {
  let snapshot = unwrap_mini_snapshot(@mini.parse_snapshot("s(\"bd sd\")"))
  inspect(
    snapshot.root().value(),
    content="mini:seq:mini:sound:bd:0:mini:sound:sd:0",
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="2")
}

///|
test "parse_snapshot lowers cutoff method through PatternDoc" {
  let snapshot = unwrap_mini_snapshot(
    @mini.parse_snapshot("s(\"bd\").cutoff(200)"),
  )
  inspect(
    snapshot.root().value(),
    content="mini:merge_control:mini:sound:bd:0:cutoff:200",
  )
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="1")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 36, "cutoff": 200 })
    ),
  )
}

///|
test "parse_doc_reusing preserves ids across whitespace edits" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd sd\")"))
  let edited = unwrap_doc(@mini.parse_doc_reusing("s(\"  bd   sd  \")", doc))
  @debug.assert_eq(doc.root().value(), edited.root().value())
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(edited.contains_node(pid("mini:sound:sd:0")))
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(unwrap_lowered_snapshot(try? doc.lower_with_cache(cache)))
  cache.reset_stats()
  ignore(unwrap_lowered_snapshot(try? edited.lower_with_cache(cache)))
  inspect(cache.hit_count(), content="1")
  inspect(cache.miss_count(), content="0")
}

///|
test "parse_doc_reusing cutoff edit preserves sound atom id" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd\").cutoff(200)"))
  let edited = unwrap_doc(@mini.parse_doc_reusing("s(\"bd\").cutoff(300)", doc))
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(
    edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:cutoff:300")),
  )
  assert_true(
    !edited.contains_node(pid("mini:merge_control:mini:sound:bd:0:cutoff:200")),
  )
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(unwrap_lowered_snapshot(try? doc.lower_with_cache(cache)))
  cache.reset_stats()
  let snapshot = unwrap_lowered_snapshot(try? edited.lower_with_cache(cache))
  assert_true(cache.hit_count() >= 1)
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  inspect(events.length(), content="1")
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[0].value.get("cutoff") == Some(300.0))
}

///|
test "parse_doc_reusing token replacement preserves unaffected token ids" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd sd hh\")"))
  let edited = unwrap_doc(@mini.parse_doc_reusing("s(\"bd cp hh\")", doc))
  assert_true(edited.contains_node(pid("mini:sound:bd:0")))
  assert_true(!edited.contains_node(pid("mini:sound:sd:0")))
  assert_true(edited.contains_node(pid("mini:sound:cp:0")))
  assert_true(edited.contains_node(pid("mini:sound:hh:0")))
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  ignore(unwrap_lowered_snapshot(try? doc.lower_with_cache(cache)))
  cache.reset_stats()
  let snapshot = unwrap_lowered_snapshot(try? edited.lower_with_cache(cache))
  assert_true(cache.hit_count() >= 2)
  assert_true(cache.miss_count() >= 1)
  let events = snapshot.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  let mut saw_cp = false
  for event in events {
    match event.value.get("sound") {
      Some(value) => if value == 39.0 { saw_cp = true }
      None => ()
    }
  }
  assert_true(saw_cp)
}

///|
test "parse_doc_reusing insertion and removal keep surviving token ids" {
  let doc = unwrap_doc(@mini.parse_doc("s(\"bd sd\")"))
  let inserted = unwrap_doc(@mini.parse_doc_reusing("s(\"hh bd sd\")", doc))
  assert_true(inserted.contains_node(pid("mini:sound:hh:0")))
  assert_true(inserted.contains_node(pid("mini:sound:bd:0")))
  assert_true(inserted.contains_node(pid("mini:sound:sd:0")))
  let removed = unwrap_doc(@mini.parse_doc_reusing("s(\"bd\")", inserted))
  assert_true(removed.contains_node(pid("mini:sound:bd:0")))
  assert_true(!removed.contains_node(pid("mini:sound:hh:0")))
  assert_true(!removed.contains_node(pid("mini:sound:sd:0")))
}

///|
test "parse drum sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh sd\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="4")
}

///|
test "parse note sequence" {
  let pat = unwrap_ok(@mini.parse("note(\"60 64 67\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "note": 60 })
    ),
  )
  inspect(
    events[1].value,
    content=(
      #|ControlMap({ "note": 64 })
    ),
  )
  inspect(
    events[2].value,
    content=(
      #|ControlMap({ "note": 67 })
    ),
  )
}

///|
test "parse with fast method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").fast(2)"))
  let events = query_one_cycle(pat)
  // fast(2) doubles the pattern, so 2 elements * 2 = 4 events
  inspect(events.length(), content="4")
}

///|
test "parse with sub-group brackets" {
  let pat = unwrap_ok(@mini.parse("s(\"bd [sd hh]\")"))
  let events = query_one_cycle(pat)
  // bd takes first half, [sd hh] takes second half (2 events in sub-group)
  inspect(events.length(), content="3")
}

///|
test "parse with stack (comma)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd, hh hh hh\")"))
  let events = query_one_cycle(pat)
  // stack of [bd sd] (2 events) and [hh hh hh] (3 events) = 5 events
  inspect(events.length(), content="5")
}

///|
test "parse empty input returns error" {
  match @mini.parse("") {
    Err(msg) => inspect(msg, content="empty input")
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse unknown primary returns error" {
  match @mini.parse("foo(\"bar\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse fast(0) returns error" {
  match @mini.parse("s(\"bd\").fast(0)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse fast(-1) returns error" {
  match @mini.parse("s(\"bd\").fast(-1)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse unknown drum name returns error" {
  match @mini.parse("s(\"snare\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err, got Ok")
  }
}

///|
test "parse with slow method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").slow(2)"))
  // slow(2) halves the speed, querying [0,1) sees only 1 event (first half of pattern)
  let events = query_one_cycle(pat)
  inspect(events.length(), content="1")
}

///|
test "parse euclid bd(3,8) tresillo" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8)\")"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 36 })
    ),
  )
}

///|
test "parse euclid with rotation bd(3,8,2)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8,2)\")"))
  let events = query_one_cycle(pat)
  // Rotation does not change pulse count
  inspect(events.length(), content="3")
}

///|
test "parse euclid on group [bd sd](5,8)" {
  let pat = unwrap_ok(@mini.parse("s(\"[bd sd](5,8)\")"))
  let events = query_one_cycle(pat)
  // 5 pulse slots, each containing the [bd sd] sub-group (2 events per slot)
  inspect(events.length(), content="10")
}

///|
test "parse euclid alongside other elements" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8) sd\")"))
  let events = query_one_cycle(pat)
  // bd(3,8) takes first half (3 pulses), sd takes second half (1 event) = 4
  inspect(events.length(), content="4")
}

///|
test "parse euclid k=0 produces silence for that element" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(0,8) sd\")"))
  let events = query_one_cycle(pat)
  // bd(0,8) is silent, only sd plays in second half
  inspect(events.length(), content="1")
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 38 })
    ),
  )
}

///|
test "parse euclid missing comma returns error" {
  match @mini.parse("s(\"bd(3 8)\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for malformed euclid")
  }
}

///|
test "parse euclid unclosed paren returns error" {
  match @mini.parse("s(\"bd(3,8\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for unclosed euclid")
  }
}

///|
test "parse step replicate bd*4 in single-element layer" {
  let pat = unwrap_ok(@mini.parse("s(\"bd*4\")"))
  let events = query_one_cycle(pat)
  // Single slot, replicated 4× via fast(4) → 4 events
  inspect(events.length(), content="4")
}

///|
test "parse step replicate within sequence" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd*3\")"))
  let events = query_one_cycle(pat)
  // bd takes first half (1 event), sd*3 takes second half (3 events) = 4
  inspect(events.length(), content="4")
}

///|
test "parse step slow bd/2 in single-element layer" {
  let pat = unwrap_ok(@mini.parse("s(\"bd/2\")"))
  let events = query_one_cycle(pat)
  // slow(2) on a single-cycle pure event: querying [0,1) sees one event
  inspect(events.length(), content="1")
}

///|
test "parse step ops compose with euclid: bd*2(3,8)" {
  let pat = unwrap_ok(@mini.parse("s(\"bd*2(3,8)\")"))
  let events = query_one_cycle(pat)
  // bd*2 fires 2 events per slot, distributed via euclid (3,8) over 8 slots
  // 3 active slots × 2 events each = 6
  inspect(events.length(), content="6")
}

///|
test "parse step replicate on group [bd sd]*2" {
  let pat = unwrap_ok(@mini.parse("s(\"[bd sd]*2\")"))
  let events = query_one_cycle(pat)
  // Group plays 2× via fast(2) → 2 × 2 = 4 events
  inspect(events.length(), content="4")
}

///|
test "parse step replicate with zero returns error" {
  match @mini.parse("s(\"bd*0\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for bd*0")
  }
}

///|
test "parse step slow with zero returns error" {
  match @mini.parse("s(\"bd/0\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for bd/0")
  }
}

///|
test "parse step replicate missing number returns error" {
  match @mini.parse("s(\"bd*\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for bd*")
  }
}

///|
test "parse degrade step bd? drops some events deterministically" {
  // 16-step pattern with `?` — expect strict subset, repeatable.
  let pat = unwrap_ok(
    @mini.parse(
      "s(\"bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd\").fast(1)",
    ),
  )
  let kept_full = query_one_cycle(pat).length()
  inspect(kept_full, content="16")
  let pat_q = unwrap_ok(
    @mini.parse(
      "s(\"bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd? bd?\")",
    ),
  )
  let kept_q = query_one_cycle(pat_q).length()
  // Strictly less than full, strictly more than zero
  inspect(kept_q < 16 && kept_q > 0, content="true")
  // Determinism: querying again yields same count
  inspect(query_one_cycle(pat_q).length() == kept_q, content="true")
}

///|
test "parse degradeBy method chain" {
  let pat = unwrap_ok(
    @mini.parse(
      "s(\"bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd bd\").degradeBy(0.5)",
    ),
  )
  let kept = query_one_cycle(pat).length()
  inspect(kept < 16 && kept > 0, content="true")
}

///|
test "parse degradeBy(0.0) keeps everything" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh sd\").degradeBy(0.0)"))
  inspect(query_one_cycle(pat).length(), content="4")
}

///|
test "parse every(2, fast(2)) doubles events on cycle 0" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").every(2, fast(2))"))
  let events = query_one_cycle(pat)
  // Cycle 0: every fires → fast(2) on the 2-element pattern → 4 events
  inspect(events.length(), content="4")
}

///|
test "parse every(2, rev) — cycle 0 timing reversed" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh\").every(2, rev)"))
  let events = query_one_cycle(pat)
  // rev mirrors timing, not array order. bd's slot under rev moves from
  // [0, 1/3) to [2/3, 1) on cycle 0.
  inspect(events.length(), content="3")
  inspect(
    events[0].part,
    content=(
      #|{ begin: { num: 2, den: 3 }, end_: { num: 1, den: 1 } }
    ),
  )
}

///|
test "parse every with unknown callback returns error" {
  match @mini.parse("s(\"bd sd\").every(2, weird)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for unknown every() callback")
  }
}

///|
test "parse every with non-positive n returns error" {
  match @mini.parse("s(\"bd sd\").every(0, rev)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for every(0, ...)")
  }
}

///|
test "parse every with non-integer n returns error (no silent truncation)" {
  match @mini.parse("s(\"bd sd\").every(2.5, rev)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for every(2.5, ...)")
  }
}

///|
test "parse every with non-integer callback arg returns error" {
  match @mini.parse("s(\"bd sd\").every(2, fast(1.5))") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for every(2, fast(1.5))")
  }
}

///|
test "parse chained postfix bd*3*4 stacks replications" {
  let pat = unwrap_ok(@mini.parse("s(\"bd*3*4\")"))
  let events = query_one_cycle(pat)
  // *3 then *4 → fast(3).fast(4) = 12 events in one slot
  inspect(events.length(), content="12")
}

///|
test "parse euclid with negative rotation" {
  let pat = unwrap_ok(@mini.parse("s(\"bd(3,8,-1)\")"))
  let events = query_one_cycle(pat)
  // Negative rotation should still produce 3 pulses (modulo wrap)
  inspect(events.length(), content="3")
}

///|
test "parse with rev method" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd hh\").rev()"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="3")
  // Reversed: hh, sd, bd
  inspect(
    events[0].value,
    content=(
      #|ControlMap({ "sound": 36 })
    ),
  )
  inspect(
    events[1].value,
    content=(
      #|ControlMap({ "sound": 38 })
    ),
  )
  inspect(
    events[2].value,
    content=(
      #|ControlMap({ "sound": 42 })
    ),
  )
}

///|
test "parse jux(rev) produces 4 events from 2-element pattern" {
  let pat = unwrap_ok(@mini.parse("s(\"bd sd\").jux(rev)"))
  let events = query_one_cycle(pat)
  // 2 events left + 2 events right = 4
  inspect(events.length(), content="4")
}

///|
test "parse jux(weird) errors with jux() in the message" {
  match @mini.parse("s(\"bd\").jux(weird)") {
    Err(msg) => {
      // Lock in error-message threading: must say jux(), not every()
      let has_jux = msg.contains("jux()")
      let has_every = msg.contains("every()")
      assert_true(has_jux)
      assert_true(!has_every)
    }
    Ok(_) => fail("expected Err for jux(weird)")
  }
}

///|
test "parse note(60 64).jux(rev) parses (non-s primary)" {
  let pat = unwrap_ok(@mini.parse("note(\"60 64\").jux(rev)"))
  let events = query_one_cycle(pat)
  // 2 events left + 2 events right = 4
  inspect(events.length(), content="4")
}

///|
test "parse stack(s, note) combines drum + melodic primaries" {
  let pat = unwrap_ok(@mini.parse("stack(s(\"bd\"), note(\"60\"))"))
  let events = query_one_cycle(pat)
  // 1 sound event + 1 note event = 2
  inspect(events.length(), content="2")
}

///|
test "parse stack with method chain on result" {
  let pat = unwrap_ok(
    @mini.parse("stack(s(\"bd sd\"), note(\"60 64\")).fast(2)"),
  )
  let events = query_one_cycle(pat)
  // (2 + 2) stacked = 4 events, fast(2) doubles = 8
  inspect(events.length(), content="8")
}

///|
test "parse stack with per-arg method chain" {
  let pat = unwrap_ok(@mini.parse("stack(s(\"bd\").fast(2), note(\"60\"))"))
  let events = query_one_cycle(pat)
  // bd.fast(2) = 2 events, note(60) = 1 event = 3
  inspect(events.length(), content="3")
}

///|
test "parse stack with single argument is a no-op" {
  let pat = unwrap_ok(@mini.parse("stack(s(\"bd sd\"))"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
}

///|
test "parse stack tolerates whitespace around args" {
  let pat = unwrap_ok(@mini.parse("stack( s(\"bd\") , note(\"60\") )"))
  let events = query_one_cycle(pat)
  inspect(events.length(), content="2")
}

///|
test "parse stack() with no args returns error" {
  match @mini.parse("stack()") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for stack() with no args")
  }
}

///|
test "parse stack with missing close paren returns error" {
  match @mini.parse("stack(s(\"bd\"), note(\"60\")") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for unclosed stack(")
  }
}

///|
test "parse nested stack(stack(...), ...) recurses through parse_expr" {
  let pat = unwrap_ok(
    @mini.parse("stack(stack(s(\"bd\"), note(\"60\")), s(\"sd\"))"),
  )
  let events = query_one_cycle(pat)
  // Inner stack: 1 sound (bd) + 1 note = 2 events.
  // Outer stack adds s("sd") = 1 sound. Total 3 events.
  inspect(events.length(), content="3")
}

///|
test "parse stack with trailing comma returns error" {
  // Trailing comma forces another parse_expr() call which sees ')' and
  // fails to find a primary. Locks current behavior — if the diagnostic
  // is ever improved (e.g. "expected expression after ','"), update this
  // test to assert the new message.
  match @mini.parse("stack(s(\"bd\"),)") {
    Err(_) => () // expected
    Ok(_) => fail("expected Err for stack with trailing comma")
  }
}
