///|
fn bus_id(name : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string("bus-test:" + name) catch {
    _ => abort("bad id")
  }
}

///|
fn bus_r(num : Int64, den : Int64) -> @pattern.Rational {
  @pattern.Rational(num, den)
}

///|
/// Continuous control whose value is the absolute time it is sampled at.
fn bus_ramp(name : String) -> @pattern.PatternDoc[@pattern.ControlMap] {
  @pattern.PatternDoc::continuous(id=bus_id(name), key="gain", f=t => t)
}

///|
/// Discrete gain steps, one per slot.
fn bus_steps(
  name : String,
  values : Array[Double],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise {
  @pattern.PatternDoc::sequence(
    id=bus_id(name),
    docs=values.mapi((i, v) => {
      @pattern.PatternDoc::pure(
        id=bus_id(name + "-" + i.to_string()),
        value=@pattern.ControlMap::single("gain", v),
      )
    }),
  )
}

///|
fn bus_with(
  source : String,
  name : String,
  right : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise {
  @pattern.PatternDoc::merge_control(
    id=bus_id(name),
    left=bus_doc(source),
    right~,
  )
}

///|
fn bus_doc(source : String) -> @pattern.PatternDoc[@pattern.ControlMap] {
  match @mini.parse_doc(source) {
    Ok(doc) => doc
    Err(message) => abort(message)
  }
}

///|
fn bus_with_ramp(
  source : String,
  name : String,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise {
  bus_with(source, name, bus_ramp(name + "-ramp"))
}

///|
/// The first onset of `source` queried over `[0, end)`: its `key`, and its bus
/// read at each of `times`.
fn bus_first_onset(
  source : String,
  key : String,
  end : @pattern.Rational,
  times : Array[@pattern.Rational],
) -> (Double?, Array[Double]) {
  let snapshot = match @mini.parse_snapshot(source) {
    Ok(snapshot) => snapshot
    Err(message) => abort(message)
  }
  let onset = snapshot.query_sourced_events(
      @pattern.TimeSpan(bus_r(0L, 1L), end),
    )[0]
  let read = match onset.buses().reader(key) {
    Some(read) => read
    None => abort("no bus for \{key}")
  }
  (onset.event().value.get(key), times.map(t => read(t.num, t.den)))
}

///|
test "a key set twice falls back to the inner value where the outer one rests" {
  let times = [bus_r(1L, 4L), bus_r(3L, 4L)]
  // The outer "1 ~" rests over [1/2, 1), where saw reads t.
  @debug.assert_eq(
    bus_first_onset(
      "note(\"60\").gain(saw).gain(\"1 ~\")",
      "gain",
      bus_r(1L, 8L),
      times,
    ),
    (Some(1.0), [1.0, 0.75]),
  )
  // Resting at the onset must not bind the voice to the inner bus alone.
  @debug.assert_eq(
    bus_first_onset(
      "note(\"60\").gain(saw).gain(\"~ 1\")",
      "gain",
      bus_r(1L, 8L),
      times,
    ),
    (Some(0.0), [0.25, 1.0]),
  )
}

///|
test "onset values under rev do not depend on the query length" {
  // Reversed, the onset at 0 reads the step just before the note's end.
  let source = "note(\"60\").gain(\"0.1 0.2\").rev()"
  for end in [bus_r(1L, 8L), bus_r(1L, 3L), bus_r(1L, 1L)] {
    @debug.assert_eq(
      bus_first_onset(source, "gain", end, [bus_r(0L, 1L)]),
      (Some(0.2), [0.2]),
    )
  }
}

///|
test "a provider that is itself a merge sets the key wherever its left has an event" {
  // The inner left side sets only lpf; the gain steps still apply.
  let snapshot = bus_with(
    "note(\"60 64\")",
    "a",
    @pattern.PatternDoc::merge_control(
      id=bus_id("inner"),
      left=@pattern.PatternDoc::pure(
        id=bus_id("lpf"),
        value=@pattern.ControlMap::single("lpf", 800.0),
      ),
      right=bus_steps("st", [0.3, 0.6, 0.9]),
    ),
  ).lower()
  let events = snapshot.query_sourced_events(
    @pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 1L)),
  )
  @debug.assert_eq(
    events.map(event => {
      (event.event().value.get("gain"), event.event().value.get("lpf"))
    }),
    [(Some(0.3), Some(800.0)), (Some(0.6), Some(800.0))],
  )
  let read = events[1].buses().reader("gain").unwrap()
  @debug.assert_eq(read(3L, 4L), 0.9)
}

///|
test "held voice follows a stretched sweep through its bus" {
  let doc = bus_with_ramp("note(\"60\")", "held").slow(
    id=bus_id("slow"),
    factor=bus_r(2L, 1L),
  )
  let snapshot = doc.lower()
  let step = bus_r(1L, 4L)
  let onset = snapshot.query_sourced_events(
      @pattern.TimeSpan(bus_r(0L, 1L), step),
    )[0]
  guard onset.buses().reader("gain") is Some(read) else { fail("no gain bus") }
  let values = []
  let mut t = bus_r(0L, 1L)
  // The voice holds for [0, 2); after slow(2) the ramp reads t / 2.
  while t < bus_r(2L, 1L) {
    values.push(read(t.num, t.den))
    t = t + step
  }
  @debug.assert_eq(values, [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875])
}

///|
/// The query form of a continuous control is not defined under `rev` (the
/// value depends on the block length) or inside `sequence` (each slot reads
/// its child at the slot start). The signal follows the exact time instead.
test "continuous bus signal is exact under rev and inside sequence" {
  let reversed = bus_with_ramp("note(\"60 64\")", "a")
    .rev(id=bus_id("rev"))
    .lower()
  let in_slot = @pattern.PatternDoc::sequence(id=bus_id("seq"), docs=[
    bus_with_ramp("note(\"60 64\")", "a"),
    bus_doc("note(\"67\")"),
  ]).lower()
  let gain_reader = (snapshot : @pattern.PatternSnapshot[@pattern.ControlMap]) => {
    snapshot.query_sourced_events(
      @pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 8L)),
    )[0]
    .buses()
    .reader("gain")
    .unwrap()
  }
  let times = [bus_r(1L, 8L), bus_r(3L, 8L), bus_r(17L, 16L)]
  // rev mirrors within the cycle: t -> 2c + 1 - t, and the ramp reads it.
  let read = gain_reader(reversed)
  @debug.assert_eq(times.map(t => read(t.num, t.den)), [0.875, 0.625, 0.9375])
  // Slot 0 of 2 maps [c, c + 1/2) onto the child's [0, 1).
  let read = gain_reader(in_slot)
  @debug.assert_eq(times.map(t => read(t.num, t.den)), [0.25, 0.75, 0.125])
}

///|
test "filter_map that rewrites a bound value unbinds it" {
  let snapshot = bus_with("note(\"60\")", "m", bus_steps("st", [0.5]))
    .filter_map(id=bus_id("f"), f=c => Some(c.set("gain", 1.0)))
    .lower()
  let onset = snapshot.query_sourced_events(
      @pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 8L)),
    )[0]
  @debug.assert_eq(onset.event().value.get("gain"), Some(1.0))
  @debug.assert_eq(onset.buses().reader("gain") is None, true)
  // An unchanged value keeps following its bus.
  let kept = bus_with("note(\"60\")", "k", bus_steps("st", [0.5]))
    .filter_map(id=bus_id("f"), f=c => Some(c))
    .lower()
  let onset = kept.query_sourced_events(
      @pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 8L)),
    )[0]
  @debug.assert_eq(onset.buses().reader("gain") is Some(_), true)
}

///|
/// A cached subtree keeps local bus indices; its parent renumbers them. The
/// second child must keep reading its own bus beside a sibling's bus and
/// once that sibling is removed, while its compiled subtree comes from the
/// cache.
test "cached subtree buses follow their new position after an edit" {
  let doc = @pattern.PatternDoc::stack(id=bus_id("stack"), docs=[
    bus_with("note(\"60\")", "a", bus_steps("sa", [0.2, 0.4])),
    bus_with("note(\"64\")", "b", bus_steps("sb", [0.6, 0.8])),
  ])
  fn gain_buses(
    snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
  ) -> Array[(Double?, Double)] {
    let arc = @pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 1L))
    snapshot
    .query_sourced_events(arc)
    .map(event => {
      let value = match event.buses().reader("gain") {
        Some(read) => read(3L, 4L)
        None => -1.0
      }
      (event.event().value.get("note"), value)
    })
  }
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  let original = doc.lower_with_cache(cache)
  @debug.assert_eq(gain_buses(original), [(Some(60.0), 0.4), (Some(64.0), 0.8)])
  let edited = doc.replace_with_silence(id=bus_id("a"))
  cache.reset_stats()
  let cached = edited.lower_with_cache(cache)
  assert_true(cache.hit_count() > 0)
  let fresh = edited.lower()
  @debug.assert_eq(gain_buses(cached), [(Some(64.0), 0.8)])
  @debug.assert_eq(gain_buses(cached), gain_buses(fresh))
}

///|
/// The onset value and the bus reading, at `at`, of `key` on the first onset.
fn mini_control_at(
  source : String,
  key : String,
  at : @pattern.Rational,
) -> (Double?, Double) raise {
  let snapshot = match @mini.parse_snapshot(source) {
    Ok(snapshot) => snapshot
    Err(message) => fail(message)
  }
  let onset = snapshot.query_sourced_events(
      @pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 64L)),
    )[0]
  guard onset.buses().reader(key) is Some(read) else { fail("no \{key} bus") }
  (onset.event().value.get(key), read(at.num, at.den))
}

///|
test "Mini control arguments accept quoted steps and signals" {
  // A held note follows the second step while it sounds.
  @debug.assert_eq(
    mini_control_at("note(\"60\").gain(\"0.2 0.8\")", "gain", bus_r(3L, 4L)),
    (Some(0.2), 0.8),
  )
  // slow(4) stretches the saw: 200 + 800 × t / 4.
  @debug.assert_eq(
    mini_control_at(
      "note(\"60\").slow(8).lpf(saw.range(200, 1000).slow(4))",
      "lpf",
      bus_r(2L, 1L),
    ),
    (Some(200.0), 600.0),
  )
  // A later range maps the earlier one: 1 + 2 × (0 + 10 × 0.5).
  @debug.assert_eq(
    mini_control_at(
      "note(\"60\").pan(saw.range(0, 10).range(1, 3))",
      "pan",
      bus_r(1L, 2L),
    ),
    (Some(1.0), 11.0),
  )
  // The resonance argument takes the same forms.
  @debug.assert_eq(
    mini_control_at(
      "note(\"60\").lpf(800, \"1 4\")",
      "lpf_resonance",
      bus_r(1L, 2L),
    ),
    (Some(1.0), 4.0),
  )
  let shape = (name : String, t : @pattern.Rational) => {
    mini_control_at("note(\"60\").gain(\{name})", "gain", t).1
  }
  @debug.assert_eq(
    [
      shape("sine", bus_r(1L, 4L)),
      shape("cosine", bus_r(0L, 1L)),
      shape("isaw", bus_r(1L, 4L)),
      shape("tri", bus_r(1L, 4L)),
      shape("tri", bus_r(3L, 4L)),
      shape("square", bus_r(1L, 4L)),
      shape("square", bus_r(3L, 4L)),
    ],
    [1.0, 1.0, 0.75, 0.5, 0.5, 0.0, 1.0],
  )
}

///|
test "Mini control arguments are range-checked and syntax-checked" {
  let error = (source : String) => {
    match @mini.parse_snapshot(source) {
      Ok(_) => "ok"
      Err(message) => message
    }
  }
  inspect(
    [
      error("note(\"60\").room(\"0.5 2\")"),
      error("note(\"60\").attack(saw.range(0, 100000))"),
      error("note(\"60\").lpf(800, saw.range(0, 2))"),
      error("note(\"60\").gain(sin)"),
      error("note(\"60\").gain(saw.wobble(2))"),
      error("note(\"60\").gain(\"0.3 C4\")"),
      error("note(\"60\").gain(\"0.1 0.2?\")"),
      error("stack(note(\"60\").pan(sine), note(\"64\").pan(sine))"),
    ].join("\n"),
    content=(
      #|position 11: room() expects a send between 0 and 1
      #|position 11: attack() expects seconds between 0 and 86400
      #|position 11: lpf() expects finite resonance above 0
      #|position 16: expected a number, a quoted pattern, or a signal (sine, cosine, saw, isaw, tri, square), got 'sin'
      #|position 20: unknown signal method 'wobble'; use range, fast, or slow
      #|position 4: expected number
      #|position 7: random drop ? is not supported in gain patterns
      #|ok
    ),
  )
}

///|
test "step argument spelling does not change identity or degrade drops" {
  fn shape(steps : String) -> (String, Array[@pattern.Rational]) raise {
    let doc = @mini.parse_doc(
      "s(\"bd sd hh cp\").gain(\"" + steps + "\").degradeBy(0.5)",
    ).unwrap()
    let kept = doc
      .lower()
      .query(@pattern.TimeSpan(bus_r(0L, 1L), bus_r(8L, 1L)))
      .map(event => event.part.begin)
    (doc.root().value(), kept)
  }

  let (root, kept) = shape("0.3 0.8")
  @debug.assert_eq(shape("0.3   0.8"), (root, kept))
  @debug.assert_eq(shape("[0.3 0.8]").1, kept)
}
