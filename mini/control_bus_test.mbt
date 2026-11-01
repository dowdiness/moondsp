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
/// Play `doc` in blocks of `step` cycles. In every block, each sounding voice
/// reads its gain bus at the block start. The pattern's own gain for that
/// voice at that time must equal both the queried bus and the compiled signal.
fn bus_follow(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  step : @pattern.Rational,
) -> String raise {
  let snapshot = doc.lower()
  let mut checked = 0
  let mut mismatched = 0
  let mut unbound = 0
  let mut t = bus_r(0L, 1L)
  while t < bus_r(4L, 1L) {
    let arc = @pattern.TimeSpan(t, t + step)
    for sourced in snapshot.query_sourced_events(arc) {
      let event = sourced.event()
      guard event.whole is Some(_) && event.part.begin == arc.begin else {
        continue
      }
      let expected = event.value.get("gain")
      match sourced.buses().reader("gain") {
        None => unbound += 1
        Some(read) => {
          checked += 1
          let signal = read(arc.begin.num, arc.begin.den)
          let signal = if signal.is_nan() { None } else { Some(signal) }
          if signal != expected {
            mismatched += 1
          }
        }
      }
    }
    t = t + step
  }
  "checked=\{checked} mismatched=\{mismatched} unbound=\{unbound}"
}

///|
test "control bus follows the pattern under every combinator" {
  let reverse = @pattern.TimeTransform::Reverse
  let cases : Array[(String, @pattern.PatternDoc[@pattern.ControlMap])] = [
    (
      "slow 3",
      bus_with_ramp("note(\"60 64\")", "a").slow(
        id=bus_id("op"),
        factor=bus_r(3L, 1L),
      ),
    ),
    (
      "fast 2",
      bus_with_ramp("note(\"60 64\")", "a").fast(
        id=bus_id("op"),
        factor=bus_r(2L, 1L),
      ),
    ),
    ("rev", bus_with_ramp("note(\"60 64\")", "a").rev(id=bus_id("op"))),
    (
      "euclid",
      bus_with_ramp("note(\"60 64\")", "a").euclid(id=bus_id("op"), k=3, n=8),
    ),
    (
      "every",
      bus_with_ramp("note(\"60 64\")", "a").every(
        id=bus_id("op"),
        n=2,
        transform=reverse,
      ),
    ),
    (
      "degrade",
      bus_with_ramp("note(\"60*4\")", "a").degrade_by(id=bus_id("op"), p=0.5),
    ),
    (
      "jux",
      bus_with_ramp("note(\"60 64\")", "a").jux(
        id=bus_id("op"),
        transform=reverse,
      ),
    ),
    (
      "sequence",
      @pattern.PatternDoc::sequence(id=bus_id("op"), docs=[
        bus_with_ramp("note(\"60 64\")", "a"),
        bus_doc("note(\"67\")"),
      ]),
    ),
    (
      "stack",
      @pattern.PatternDoc::stack(id=bus_id("op"), docs=[
        bus_with_ramp("note(\"60 64\")", "a"),
        bus_doc("note(\"67\")"),
      ]),
    ),
    (
      "nested",
      @pattern.PatternDoc::sequence(id=bus_id("seq"), docs=[
        bus_with_ramp("note(\"60 64\")", "a").slow(
          id=bus_id("slow"),
          factor=bus_r(2L, 1L),
        ),
        bus_doc("note(\"67\")"),
      ]).fast(id=bus_id("fast"), factor=bus_r(3L, 1L)),
    ),
    (
      "chord jux",
      bus_with_ramp("chord(\"Dm9 Bbmaj7\")", "a")
      .slow(id=bus_id("slow"), factor=bus_r(2L, 1L))
      .jux(id=bus_id("jux"), transform=reverse),
    ),
    // Discrete steps held across a long note: the value changes mid-note.
    (
      "steps under slow 3",
      bus_with("note(\"60\")", "a", bus_steps("st", [0.3, 0.6])).slow(
        id=bus_id("op"),
        factor=bus_r(3L, 1L),
      ),
    ),
    (
      "steps rev every 2 under jux",
      bus_with(
        "note(\"60 64 67\")",
        "a",
        bus_steps("st", [0.1, 0.2, 0.3]).every(
          id=bus_id("ev"),
          n=2,
          transform=reverse,
        ),
      ).jux(id=bus_id("op"), transform=reverse),
    ),
    (
      "euclid steps, weighted",
      bus_with(
        "note(\"60*8\")",
        "a",
        @pattern.PatternDoc::sequence_weighted(
          id=bus_id("w"),
          docs=[
            bus_steps("x", [0.2]).euclid(id=bus_id("eu"), k=3, n=8),
            bus_steps("y", [0.9, 0.7]),
          ],
          weights=[3, 1],
        ),
      ),
    ),
    (
      "stack of steps and ramp",
      bus_with(
        "note(\"60 64\")",
        "a",
        @pattern.PatternDoc::stack(id=bus_id("stk"), docs=[
          bus_ramp("r"),
          bus_steps("st", [0.4]).euclid(id=bus_id("eu"), k=1, n=4),
        ]),
      ).fast(id=bus_id("op"), factor=bus_r(3L, 2L)),
    ),
    // The provider is itself a merge whose left side never sets gain.
    (
      "nested merge provider",
      bus_with(
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
      ),
    ),
    (
      "mini gain on chord jux",
      bus_doc("chord(\"Dm9 Bbmaj7\").gain(0.5).slow(2).jux(rev)"),
    ),
  ]
  let lines = []
  for case in cases {
    for step in [bus_r(1L, 64L), bus_r(1L, 7L), bus_r(3L, 5L)] {
      lines.push(
        "\{case.0} step=\{step.num}/\{step.den}: \{bus_follow(case.1, step)}",
      )
    }
  }
  inspect(
    lines.join("\n"),
    content=(
      #|slow 3 step=1/64: checked=256 mismatched=0 unbound=0
      #|slow 3 step=1/7: checked=28 mismatched=0 unbound=0
      #|slow 3 step=3/5: checked=7 mismatched=0 unbound=0
      #|fast 2 step=1/64: checked=256 mismatched=0 unbound=0
      #|fast 2 step=1/7: checked=28 mismatched=0 unbound=0
      #|fast 2 step=3/5: checked=7 mismatched=0 unbound=0
      #|rev step=1/64: checked=256 mismatched=256 unbound=0
      #|rev step=1/7: checked=28 mismatched=28 unbound=0
      #|rev step=3/5: checked=7 mismatched=7 unbound=0
      #|euclid step=1/64: checked=96 mismatched=84 unbound=0
      #|euclid step=1/7: checked=12 mismatched=8 unbound=0
      #|euclid step=3/5: checked=4 mismatched=2 unbound=0
      #|every step=1/64: checked=256 mismatched=128 unbound=0
      #|every step=1/7: checked=28 mismatched=14 unbound=0
      #|every step=3/5: checked=7 mismatched=3 unbound=0
      #|degrade step=1/64: checked=176 mismatched=0 unbound=0
      #|degrade step=1/7: checked=19 mismatched=0 unbound=0
      #|degrade step=3/5: checked=4 mismatched=0 unbound=0
      #|jux step=1/64: checked=512 mismatched=256 unbound=0
      #|jux step=1/7: checked=56 mismatched=28 unbound=0
      #|jux step=3/5: checked=14 mismatched=7 unbound=0
      #|sequence step=1/64: checked=128 mismatched=124 unbound=128
      #|sequence step=1/7: checked=16 mismatched=12 unbound=12
      #|sequence step=3/5: checked=4 mismatched=2 unbound=3
      #|stack step=1/64: checked=256 mismatched=0 unbound=256
      #|stack step=1/7: checked=28 mismatched=0 unbound=28
      #|stack step=3/5: checked=7 mismatched=0 unbound=7
      #|nested step=1/64: checked=128 mismatched=124 unbound=128
      #|nested step=1/7: checked=16 mismatched=12 unbound=12
      #|nested step=3/5: checked=4 mismatched=2 unbound=3
      #|chord jux step=1/64: checked=2432 mismatched=1280 unbound=0
      #|chord jux step=1/7: checked=266 mismatched=140 unbound=0
      #|chord jux step=3/5: checked=66 mismatched=35 unbound=0
      #|steps under slow 3 step=1/64: checked=256 mismatched=0 unbound=0
      #|steps under slow 3 step=1/7: checked=28 mismatched=0 unbound=0
      #|steps under slow 3 step=3/5: checked=7 mismatched=0 unbound=0
      #|steps rev every 2 under jux step=1/64: checked=512 mismatched=0 unbound=0
      #|steps rev every 2 under jux step=1/7: checked=56 mismatched=0 unbound=0
      #|steps rev every 2 under jux step=3/5: checked=14 mismatched=0 unbound=0
      #|euclid steps, weighted step=1/64: checked=136 mismatched=0 unbound=120
      #|euclid steps, weighted step=1/7: checked=16 mismatched=0 unbound=12
      #|euclid steps, weighted step=3/5: checked=5 mismatched=0 unbound=2
      #|stack of steps and ramp step=1/64: checked=256 mismatched=0 unbound=0
      #|stack of steps and ramp step=1/7: checked=28 mismatched=0 unbound=0
      #|stack of steps and ramp step=3/5: checked=7 mismatched=0 unbound=0
      #|nested merge provider step=1/64: checked=256 mismatched=0 unbound=0
      #|nested merge provider step=1/7: checked=28 mismatched=0 unbound=0
      #|nested merge provider step=3/5: checked=7 mismatched=0 unbound=0
      #|mini gain on chord jux step=1/64: checked=2432 mismatched=0 unbound=0
      #|mini gain on chord jux step=1/7: checked=266 mismatched=0 unbound=0
      #|mini gain on chord jux step=3/5: checked=66 mismatched=0 unbound=0
    ),
  )
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
  // The runtime pattern path gives the same onset values.
  guard @mini.parse("note(\"60 64\").gain(\"0.2 0.8\")") is Ok(pat) else {
    fail("parse")
  }
  @debug.assert_eq(
    pat
    .query(@pattern.TimeSpan(bus_r(0L, 1L), bus_r(1L, 1L)))
    .map(event => event.value.get("gain")),
    [Some(0.2), Some(0.8)],
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
