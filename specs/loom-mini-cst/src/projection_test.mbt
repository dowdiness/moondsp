///|
fn projection_boundary_pid(value : String) -> @identity.PatternNodeId {
  let result = try? @identity.PatternNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("expected valid pattern node id")
  }
}

///|
fn projection_boundary_doc(
  result : Result[@pattern.PatternDoc[@pattern.ControlMap], String],
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  match result {
    Ok(doc) => doc
    Err(msg) => abort("expected PatternDoc, got " + msg)
  }
}

///|
fn projection_boundary_snapshot(
  result : Result[
    @pattern.PatternSnapshot[@pattern.ControlMap],
    @pattern.PatternDocError,
  ],
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(_) => abort("expected lowered PatternDoc snapshot")
  }
}

///|
fn projection_boundary_mini_snapshot(
  result : Result[@pattern.PatternSnapshot[@pattern.ControlMap], String],
) -> @pattern.PatternSnapshot[@pattern.ControlMap] {
  match result {
    Ok(snapshot) => snapshot
    Err(msg) => abort("expected mini snapshot, got " + msg)
  }
}

///|
fn projection_boundary_one_cycle() -> @pattern.TimeSpan {
  @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
}

///|
fn projection_boundary_leaf_ids(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> Array[String] {
  let events = snapshot.query_sourced_events(projection_boundary_one_cycle())
  let ids : Array[String] = []
  for event in events {
    match event.pattern_node() {
      Some(id) => ids.push(id.value())
      None => ids.push("<none>")
    }
  }
  ids
}

///|
fn projection_boundary_leaf_ids_from_doc(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> Array[String] {
  projection_boundary_leaf_ids(projection_boundary_snapshot(try? doc.lower()))
}

///|
fn projection_boundary_assert_ids_equal(
  left : Array[String],
  right : Array[String],
) -> Unit {
  if left.length() != right.length() {
    abort(
      "expected equal id array lengths, got \{left.length()} and \{right.length()}",
    )
  }
  for index in 0..<left.length() {
    if left[index] != right[index] {
      abort(
        "expected id[\{index}] to match, got '\{left[index]}' and '\{right[index]}'",
      )
    }
  }
}

///|
fn projection_boundary_assert_matches_mini_doc(input : String) -> Unit {
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  if loom_doc.root().value() != mini_doc.root().value() {
    abort("expected loom and mini root IDs to match")
  }
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
fn projection_boundary_ids_after_edit(
  input : String,
  edited : String,
  edit : @core.Edit,
  old_start~ : Int,
  old_end~ : Int,
  new_end~ : Int,
) -> (Array[String], Array[String]) {
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(edit, edited)
  pipeline.set_input_with_source_edit(edited, old_start~, old_end~, new_end~)
  let loom_ids = projection_boundary_leaf_ids_from_doc(
    projection_boundary_doc(projection.parse_doc()),
  )
  let mini_ids = projection_boundary_leaf_ids(
    projection_boundary_mini_snapshot(pipeline.parse_snapshot()),
  )
  projection.dispose()
  pipeline.dispose()
  (loom_ids, mini_ids)
}

///|
test "loom atom projection matches mini PatternDoc for duplicate sound atoms" {
  let input = "s(\"bd sd bd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  inspect(
    loom_doc.contains_node(projection_boundary_pid("mini:sound:bd:0")),
    content="true",
  )
  inspect(
    loom_doc.contains_node(projection_boundary_pid("mini:sound:sd:0")),
    content="true",
  )
  inspect(
    loom_doc.contains_node(projection_boundary_pid("mini:sound:bd:1")),
    content="true",
  )
  let expected =
    #|["mini:sound:bd:0", "mini:sound:sd:0", "mini:sound:bd:1"]
  debug_inspect(
    projection_boundary_leaf_ids_from_doc(loom_doc),
    content=expected,
  )
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for plain stack" {
  let input = "stack(s(\"bd\"), note(\"60\"))"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:sound:bd:0", "mini:note:60:0"]
  debug_inspect(loom_ids, content=expected)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for dollar stack" {
  projection_boundary_assert_matches_mini_doc(
    "$: s(\"bd\")\n$: note(\"60\")",
  )
}

///|
test "loom atom projection matches mini PatternDoc for dollar stack callback methods" {
  projection_boundary_assert_matches_mini_doc(
    "$: s(\"bd sd\").jux(rev)\n$: note(\"60 64\").every(2, fast(2))",
  )
}

///|
test "loom atom projection rejects same-line dollar stack marker like mini" {
  let input = "$: s(\"bd\") $: note(\"60\")"
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Ok(_) => abort("expected loom projection to reject same-line $: marker")
    Err(_) => ()
  }
  match @mini.parse_doc(input) {
    Ok(_) => abort("expected mini parser to reject same-line $: marker")
    Err(_) => ()
  }
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc after dollar stack line insertion" {
  let input = "$: s(\"bd\")"
  let edited = "$: s(\"bd\")\n$: note(\"60\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::insert(10, 14),
    old_start=10,
    old_end=10,
    new_end=24,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:sound:bd:0", "mini:note:60:0"]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection matches mini PatternDoc for fast method" {
  let input = "s(\"bd sd\").fast(2)"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for slow method" {
  let input = "s(\"bd sd\").slow(2)"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for rev method" {
  let input = "s(\"bd sd hh\").rev()"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for jux rev method" {
  projection_boundary_assert_matches_mini_doc("s(\"bd sd\").jux(rev)")
}

///|
test "loom atom projection matches mini PatternDoc for jux fast callback method" {
  projection_boundary_assert_matches_mini_doc("s(\"bd sd\").jux(fast(2))")
}

///|
test "loom atom projection matches mini PatternDoc for jux slow callback method" {
  projection_boundary_assert_matches_mini_doc("s(\"bd sd\").jux(slow(2))")
}

///|
test "loom atom projection matches mini PatternDoc for every rev method" {
  projection_boundary_assert_matches_mini_doc("s(\"bd sd\").every(2, rev)")
}

///|
test "loom atom projection matches mini PatternDoc for every fast callback method" {
  projection_boundary_assert_matches_mini_doc(
    "s(\"bd sd\").every(2, fast(2))",
  )
}

///|
test "loom atom projection matches mini PatternDoc for every slow callback method" {
  projection_boundary_assert_matches_mini_doc(
    "s(\"bd sd\").every(2, slow(2))",
  )
}

///|
test "loom atom projection matches mini PatternDoc for chained root methods" {
  let input = "s(\"bd sd\").fast(2).rev().slow(3)"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for star postfix" {
  let input = "s(\"bd*2 sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for slow postfix" {
  let input = "s(\"bd/2 sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for degrade postfix" {
  let input = "s(\"bd? sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for euclid postfix" {
  let input = "s(\"bd(3,8) sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for euclid rotation postfix" {
  let input = "s(\"bd(3,8,1) sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for negative euclid rotation postfix" {
  let input = "s(\"bd(3,8,-1) sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for star then slow postfixes" {
  let input = "s(\"bd*2/3 sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for slow then star postfixes" {
  let input = "s(\"bd/2*3 sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
}

///|
test "loom atom projection matches mini PatternDoc for sub-notation star postfix" {
  projection_boundary_assert_matches_mini_doc("s(\"[bd sd]*2 hh\")")
}

///|
test "loom atom projection matches mini PatternDoc for sub-notation euclid postfix" {
  projection_boundary_assert_matches_mini_doc("s(\"[bd sd](5,8) hh\")")
}

///|
test "loom atom projection matches mini PatternDoc for sub-notation degrade postfix" {
  projection_boundary_assert_matches_mini_doc("s(\"[bd sd]? hh\")")
}

///|
test "loom atom projection rejects rev method with callback argument" {
  let projection = LoomMiniAtomProjection::new("s(\"bd\").rev(foo)")
  match projection.parse_doc() {
    Err(msg) =>
      inspect(
        msg,
        content="loom atom projection expected .rev() with no arguments",
      )
    Ok(_) => abort("expected rev callback projection to fail")
  }
  projection.dispose()
}

///|
test "loom atom projection rejects fast method with callback argument" {
  let projection = LoomMiniAtomProjection::new("s(\"bd\").fast(slow(2))")
  match projection.parse_doc() {
    Err(msg) =>
      inspect(
        msg,
        content="loom atom projection expected numeric method argument",
      )
    Ok(_) => abort("expected fast callback projection to fail")
  }
  projection.dispose()
}

///|
test "loom atom projection rejects nested stack instead of dropping it" {
  let projection = LoomMiniAtomProjection::new(
    "stack(stack(s(\"bd\"), note(\"60\")), s(\"sd\"))",
  )
  match projection.parse_doc() {
    Err(msg) =>
      inspect(
        msg,
        content="loom atom projection only supports plain stack arguments",
      )
    Ok(_) => abort("expected nested stack projection to fail")
  }
  projection.dispose()
}

///|
test "loom atom projection preserves duplicate sound provenance across insertion" {
  let input = "s(\"bd sd bd\")"
  let edited = "s(\"bd sd bd bd\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::insert(9, 3),
    old_start=9,
    old_end=9,
    new_end=12,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:bd:2",
    #|  "mini:sound:bd:1",
    #|]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection preserves duplicate sound provenance across deletion" {
  let input = "s(\"bd sd bd\")"
  let edited = "s(\"bd bd\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::delete(5, 8),
    old_start=5,
    old_end=8,
    new_end=5,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:sound:bd:0", "mini:sound:bd:1"]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection matches mini PatternDoc for duplicate note atoms" {
  let input = "note(\"60 62 60\")"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  inspect(
    loom_doc.contains_node(projection_boundary_pid("mini:note:60:0")),
    content="true",
  )
  inspect(
    loom_doc.contains_node(projection_boundary_pid("mini:note:62:0")),
    content="true",
  )
  inspect(
    loom_doc.contains_node(projection_boundary_pid("mini:note:60:1")),
    content="true",
  )
  let expected =
    #|["mini:note:60:0", "mini:note:62:0", "mini:note:60:1"]
  debug_inspect(
    projection_boundary_leaf_ids_from_doc(loom_doc),
    content=expected,
  )
  projection.dispose()
}

///|
test "loom atom projection preserves duplicate note provenance across insertion" {
  let input = "note(\"60 62 60\")"
  let edited = "note(\"60 62 60 60\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::insert(12, 3),
    old_start=12,
    old_end=12,
    new_end=15,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|[
    #|  "mini:note:60:0",
    #|  "mini:note:62:0",
    #|  "mini:note:60:2",
    #|  "mini:note:60:1",
    #|]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection preserves duplicate note provenance across deletion" {
  let input = "note(\"60 62 60\")"
  let edited = "note(\"60 60\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::delete(8, 11),
    old_start=8,
    old_end=11,
    new_end=8,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:note:60:0", "mini:note:60:1"]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection preserves unaffected sound provenance across replacement" {
  let input = "s(\"bd sd hh\")"
  let edited = "s(\"bd cp hh\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::replace(6, 8, 8),
    old_start=6,
    old_end=8,
    new_end=8,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:sound:bd:0", "mini:sound:cp:0", "mini:sound:hh:0"]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection preserves unaffected note provenance across replacement" {
  let input = "note(\"60 62 60\")"
  let edited = "note(\"60 64 60\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::replace(9, 11, 11),
    old_start=9,
    old_end=11,
    new_end=11,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:note:60:0", "mini:note:64:0", "mini:note:60:1"]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection preserves atom provenance across whitespace insertion" {
  let input = "s(\"bd sd\")"
  let edited = "s(\"bd   sd\")"
  let (loom_ids, mini_ids) = projection_boundary_ids_after_edit(
    input,
    edited,
    @core.Edit::insert(6, 2),
    old_start=6,
    old_end=6,
    new_end=8,
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|["mini:sound:bd:0", "mini:sound:sd:0"]
  debug_inspect(loom_ids, content=expected)
}

///|
test "loom atom projection matches mini PatternDoc after slow postfix insertion" {
  let input = "s(\"bd sd\")"
  let edited = "s(\"bd/2 sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::insert(5, 2), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=5,
    old_end=5,
    new_end=7,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection matches mini PatternDoc after degrade postfix insertion" {
  let input = "s(\"bd sd\")"
  let edited = "s(\"bd? sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::insert(5, 1), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=5,
    old_end=5,
    new_end=6,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection matches mini PatternDoc after euclid postfix insertion" {
  let input = "s(\"bd sd\")"
  let edited = "s(\"bd(3,8) sd\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::insert(5, 5), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=5,
    old_end=5,
    new_end=10,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection matches mini PatternDoc after sub-notation postfix insertion" {
  let input = "s(\"[bd sd] hh\")"
  let edited = "s(\"[bd sd]*2 hh\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::insert(10, 2), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=10,
    old_end=10,
    new_end=12,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection matches mini PatternDoc after sub-notation postfix removal" {
  let input = "s(\"[bd sd]*2 hh\")"
  let edited = "s(\"[bd sd] hh\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::delete(10, 12), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=10,
    old_end=12,
    new_end=10,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection preserves atom provenance across method replacement" {
  let input = "s(\"bd sd\").fast(2)"
  let edited = "s(\"bd sd\").slow(2)"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::replace(11, 15, 15), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=11,
    old_end=15,
    new_end=15,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection preserves atom provenance across jux callback replacement" {
  let input = "s(\"bd sd\").jux(rev)"
  let edited = "s(\"bd sd\").jux(fast(2))"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::replace(15, 18, 22), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=15,
    old_end=18,
    new_end=22,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection preserves atom provenance across every callback replacement" {
  let input = "s(\"bd sd\").every(2, rev)"
  let edited = "s(\"bd sd\").every(2, fast(2))"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::replace(20, 23, 27), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=20,
    old_end=23,
    new_end=27,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection preserves atom provenance across dollar stack jux callback replacement" {
  let input = "$: s(\"bd sd\").jux(rev)\n$: note(\"60 64\")"
  let edited = "$: s(\"bd sd\").jux(fast(2))\n$: note(\"60 64\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::replace(18, 21, 25), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=18,
    old_end=21,
    new_end=25,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection preserves atom provenance across dollar stack every callback replacement" {
  let input = "$: s(\"bd sd\")\n$: note(\"60 64\").every(2, rev)"
  let edited = "$: s(\"bd sd\")\n$: note(\"60 64\").every(2, fast(2))"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::replace(40, 43, 47), edited)
  pipeline.set_input_with_source_edit(
    edited,
    old_start=40,
    old_end=43,
    new_end=47,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids_from_doc(mini_doc)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection.dispose()
  pipeline.dispose()
}

///|
test "loom atom projection reports diagnostics and recovers with previous provenance" {
  let input = "s(\"bd sd bd\")"
  let malformed = "s(\"bd sd bd bd\""
  let recovered = "s(\"bd sd bd bd\")"
  let projection = LoomMiniAtomProjection::new(input)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(input)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(@core.Edit::insert(9, 3), malformed)
  pipeline.set_input_with_source_edit(
    malformed,
    old_start=9,
    old_end=9,
    new_end=12,
  )
  match projection.parse_doc() {
    Err(msg) => inspect(msg, content="loom mini syntax has diagnostics")
    Ok(_) => abort("expected malformed loom projection to fail")
  }
  match pipeline.parse_doc() {
    Err(_) => ()
    Ok(_) => abort("expected malformed mini authoring parse to fail")
  }
  projection.apply_edit(@core.Edit::insert(15, 1), recovered)
  pipeline.set_input_with_source_edit(
    recovered,
    old_start=9,
    old_end=9,
    new_end=12,
  )
  let loom_ids = projection_boundary_leaf_ids_from_doc(
    projection_boundary_doc(projection.parse_doc()),
  )
  let mini_ids = projection_boundary_leaf_ids(
    projection_boundary_mini_snapshot(pipeline.parse_snapshot()),
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:bd:2",
    #|  "mini:sound:bd:1",
    #|]
  debug_inspect(loom_ids, content=expected)
  projection.dispose()
  pipeline.dispose()
}
