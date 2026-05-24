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
