///|
fn bus_id(name : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string("bus-test:" + name) catch {
    _ => abort("bad id")
  }
}

///|
fn bus_r(num : Int64, den : Int64) -> @pattern.Rational {
  @pattern.Rational::new(num, den)
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
  let snapshot = doc.lower_with_buses()
  let mut checked = 0
  let mut query_mismatched = 0
  let mut signal_mismatched = 0
  let mut unbound = 0
  let mut t = bus_r(0L, 1L)
  while t < bus_r(4L, 1L) {
    let arc = @pattern.TimeSpan::new(t, t + step)
    for event in snapshot.query(arc) {
      guard event.whole is Some(_) && event.part.begin == arc.begin else {
        continue
      }
      let expected = event.value.controls().get("gain")
      match event.value.bus_for("gain") {
        None => unbound += 1
        Some(bus) => {
          checked += 1
          if snapshot.query_bus_value(bus, arc) != expected {
            query_mismatched += 1
          }
          let signal = snapshot.bus_value(bus, arc.begin)
          let signal = if signal.is_nan() { None } else { Some(signal) }
          if signal != expected {
            signal_mismatched += 1
          }
        }
      }
    }
    t = t + step
  }
  "buses=\{snapshot.bus_count()} checked=\{checked} mismatched query=\{query_mismatched} signal=\{signal_mismatched} unbound=\{unbound}"
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
    ("mini gain on chord jux", bus_doc("chord(\"Dm9 Bbmaj7\").gain(0.5).slow(2).jux(rev)")),
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
      #|slow 3 step=1/64: buses=1 checked=256 mismatched query=0 signal=0 unbound=0
      #|slow 3 step=1/7: buses=1 checked=28 mismatched query=0 signal=0 unbound=0
      #|slow 3 step=3/5: buses=1 checked=7 mismatched query=0 signal=0 unbound=0
      #|fast 2 step=1/64: buses=1 checked=256 mismatched query=0 signal=0 unbound=0
      #|fast 2 step=1/7: buses=1 checked=28 mismatched query=0 signal=0 unbound=0
      #|fast 2 step=3/5: buses=1 checked=7 mismatched query=0 signal=0 unbound=0
      #|rev step=1/64: buses=1 checked=256 mismatched query=0 signal=256 unbound=0
      #|rev step=1/7: buses=1 checked=28 mismatched query=0 signal=28 unbound=0
      #|rev step=3/5: buses=1 checked=7 mismatched query=0 signal=7 unbound=0
      #|euclid step=1/64: buses=1 checked=96 mismatched query=0 signal=84 unbound=0
      #|euclid step=1/7: buses=1 checked=12 mismatched query=0 signal=8 unbound=0
      #|euclid step=3/5: buses=1 checked=4 mismatched query=0 signal=2 unbound=0
      #|every step=1/64: buses=1 checked=256 mismatched query=0 signal=128 unbound=0
      #|every step=1/7: buses=1 checked=28 mismatched query=0 signal=14 unbound=0
      #|every step=3/5: buses=1 checked=7 mismatched query=0 signal=3 unbound=0
      #|degrade step=1/64: buses=1 checked=176 mismatched query=0 signal=0 unbound=0
      #|degrade step=1/7: buses=1 checked=19 mismatched query=0 signal=0 unbound=0
      #|degrade step=3/5: buses=1 checked=4 mismatched query=0 signal=0 unbound=0
      #|jux step=1/64: buses=2 checked=512 mismatched query=0 signal=256 unbound=0
      #|jux step=1/7: buses=2 checked=56 mismatched query=0 signal=28 unbound=0
      #|jux step=3/5: buses=2 checked=14 mismatched query=0 signal=7 unbound=0
      #|sequence step=1/64: buses=1 checked=128 mismatched query=0 signal=124 unbound=128
      #|sequence step=1/7: buses=1 checked=16 mismatched query=0 signal=12 unbound=12
      #|sequence step=3/5: buses=1 checked=4 mismatched query=0 signal=2 unbound=3
      #|stack step=1/64: buses=1 checked=256 mismatched query=0 signal=0 unbound=256
      #|stack step=1/7: buses=1 checked=28 mismatched query=0 signal=0 unbound=28
      #|stack step=3/5: buses=1 checked=7 mismatched query=0 signal=0 unbound=7
      #|nested step=1/64: buses=1 checked=128 mismatched query=0 signal=124 unbound=128
      #|nested step=1/7: buses=1 checked=16 mismatched query=0 signal=12 unbound=12
      #|nested step=3/5: buses=1 checked=4 mismatched query=0 signal=2 unbound=3
      #|chord jux step=1/64: buses=2 checked=2432 mismatched query=0 signal=1280 unbound=0
      #|chord jux step=1/7: buses=2 checked=266 mismatched query=0 signal=140 unbound=0
      #|chord jux step=3/5: buses=2 checked=66 mismatched query=0 signal=35 unbound=0
      #|steps under slow 3 step=1/64: buses=1 checked=256 mismatched query=0 signal=0 unbound=0
      #|steps under slow 3 step=1/7: buses=1 checked=28 mismatched query=0 signal=0 unbound=0
      #|steps under slow 3 step=3/5: buses=1 checked=7 mismatched query=0 signal=0 unbound=0
      #|steps rev every 2 under jux step=1/64: buses=2 checked=512 mismatched query=0 signal=0 unbound=0
      #|steps rev every 2 under jux step=1/7: buses=2 checked=56 mismatched query=0 signal=0 unbound=0
      #|steps rev every 2 under jux step=3/5: buses=2 checked=14 mismatched query=0 signal=0 unbound=0
      #|euclid steps, weighted step=1/64: buses=1 checked=136 mismatched query=0 signal=0 unbound=120
      #|euclid steps, weighted step=1/7: buses=1 checked=16 mismatched query=0 signal=0 unbound=12
      #|euclid steps, weighted step=3/5: buses=1 checked=5 mismatched query=0 signal=0 unbound=2
      #|stack of steps and ramp step=1/64: buses=1 checked=256 mismatched query=0 signal=0 unbound=0
      #|stack of steps and ramp step=1/7: buses=1 checked=28 mismatched query=0 signal=0 unbound=0
      #|stack of steps and ramp step=3/5: buses=1 checked=7 mismatched query=0 signal=0 unbound=0
      #|mini gain on chord jux step=1/64: buses=2 checked=2432 mismatched query=0 signal=0 unbound=0
      #|mini gain on chord jux step=1/7: buses=2 checked=266 mismatched query=0 signal=0 unbound=0
      #|mini gain on chord jux step=3/5: buses=2 checked=66 mismatched query=0 signal=0 unbound=0

    ),
  )
}

///|
test "held voice follows a stretched sweep through its bus" {
  let doc = bus_with_ramp("note(\"60\")", "held").slow(
    id=bus_id("slow"),
    factor=bus_r(2L, 1L),
  )
  let snapshot = doc.lower_with_buses()
  let step = bus_r(1L, 4L)
  let onset = snapshot.query(@pattern.TimeSpan::new(bus_r(0L, 1L), step))[0]
  guard onset.value.bus_for("gain") is Some(bus) else { fail("no gain bus") }
  let values = []
  let mut t = bus_r(0L, 1L)
  // The voice holds for [0, 2); after slow(2) the ramp reads t / 2.
  while t < bus_r(2L, 1L) {
    values.push(snapshot.bus_value(bus, t))
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
    .lower_with_buses()
  let in_slot = @pattern.PatternDoc::sequence(id=bus_id("seq"), docs=[
    bus_with_ramp("note(\"60 64\")", "a"),
    bus_doc("note(\"67\")"),
  ]).lower_with_buses()
  let times = [bus_r(1L, 8L), bus_r(3L, 8L), bus_r(17L, 16L)]
  // rev mirrors within the cycle: t -> 2c + 1 - t, and the ramp reads it.
  @debug.assert_eq(times.map(t => reversed.bus_value(0, t)), [
    0.875, 0.625, 0.9375,
  ])
  // Slot 0 of 2 maps [c, c + 1/2) onto the child's [0, 1).
  @debug.assert_eq(times.map(t => in_slot.bus_value(0, t)), [0.25, 0.75, 0.125])
}

///|
test "a non-positive slow factor leaves its bus without a value" {
  let snapshot = @pattern.PatternDoc::merge_control(
      id=bus_id("m"),
      left=bus_doc("note(\"60 64\")"),
      right=bus_steps("st", [0.3, 0.6]),
    )
    .slow(id=bus_id("s"), factor=bus_r(0L, 1L))
    .lower_with_buses()
  let values = Array::make(snapshot.bus_count(), 0.0)
  snapshot.evaluate_all(bus_r(1L, 3L), values)
  @debug.assert_eq(values.map(v => v.is_nan()), [true])
}

///|
test "filter_map that rewrites a bound value unbinds it" {
  let snapshot = bus_with("note(\"60\")", "m", bus_steps("st", [0.5]))
    .filter_map(id=bus_id("f"), f=c => Some(c.set("gain", 1.0)))
    .lower_with_buses()
  let onset = snapshot.query(
      @pattern.TimeSpan::new(bus_r(0L, 1L), bus_r(1L, 8L)),
    )[0]
  @debug.assert_eq(onset.value.controls().get("gain"), Some(1.0))
  @debug.assert_eq(onset.value.bus_for("gain"), None)
  // An unchanged value keeps following its bus.
  let kept = bus_with("note(\"60\")", "k", bus_steps("st", [0.5]))
    .filter_map(id=bus_id("f"), f=c => Some(c))
    .lower_with_buses()
  let onset = kept.query(@pattern.TimeSpan::new(bus_r(0L, 1L), bus_r(1L, 8L)))[0]
  @debug.assert_eq(onset.value.bus_for("gain") is Some(_), true)
}
