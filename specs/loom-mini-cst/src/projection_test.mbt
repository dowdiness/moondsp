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
/// Fixed differential parity window. WHY [0,8): captures the full period of the
/// `slow`/`fast` factors the mini corpus uses, identical on both oracle and loom
/// sides (apples-to-apples). Widen HERE, not per input, if a corpus case needs a
/// longer period (Phase 2 plan, Orchestrator resolution 1).
fn projection_boundary_parity_window() -> @pattern.TimeSpan {
  @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(8),
  )
}

///|
/// Value-level canonical event: node id (or "<none>"), the ControlMap payload as
/// an order-independent `Map[String, Double]` (ControlMap has NO derived `Eq`,
/// so compare entries maps structurally), and both ideal/actual `TimeSpan`s
/// (which derive `Eq`).
priv struct BoundaryEvent {
  id : String
  control : Map[String, Double]
  whole : @pattern.TimeSpan?
  part : @pattern.TimeSpan
}

///|
/// Canonicalize a lowered snapshot's sourced events over the fixed parity window
/// for value-level differential parity (Phase 2 plan Step 2).
fn projection_boundary_value_events(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> Array[BoundaryEvent] {
  let events = snapshot.query_sourced_events(projection_boundary_parity_window())
  let out : Array[BoundaryEvent] = []
  for sourced in events {
    let id = match sourced.pattern_node() {
      Some(node) => node.value()
      None => "<none>"
    }
    let ev = sourced.event()
    out.push({ id, control: ev.value.entries(), whole: ev.whole, part: ev.part })
  }
  out
}

///|
fn projection_boundary_value_events_from_doc(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> Array[BoundaryEvent] {
  projection_boundary_value_events(
    projection_boundary_snapshot(try? doc.lower()),
  )
}

///|
/// Value-level event parity (strengthens the id-only
/// `projection_boundary_assert_ids_equal`): equal counts, ordered node ids,
/// ControlMap payloads (order-independent Map equality), and both TimeSpans.
fn projection_boundary_assert_value_events_equal(
  left : Array[BoundaryEvent],
  right : Array[BoundaryEvent],
) -> Unit {
  guard left.length() == right.length() else {
    abort(
      "expected equal event counts, got \{left.length()} and \{right.length()}",
    )
  }
  for index in 0..<left.length() {
    let l = left[index]
    let r = right[index]
    if l.id != r.id {
      abort("event[\{index}] id mismatch: '\{l.id}' vs '\{r.id}'")
    }
    if l.control != r.control {
      abort("event[\{index}] control mismatch: \{l.control} vs \{r.control}")
    }
    if l.whole != r.whole {
      abort("event[\{index}] whole-span mismatch")
    }
    if l.part != r.part {
      abort("event[\{index}] part-span mismatch")
    }
  }
}

///|
fn projection_boundary_assert_control_method_matches_mini(
  input : String,
  expected_root : String,
  expected_controls : Array[(String, Double)],
) -> Unit {
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  if loom_doc.root().value() != mini_doc.root().value() {
    abort("expected loom and mini root IDs to match")
  }
  if loom_doc.root().value() != expected_root {
    abort("expected loom root ID to match control-method root")
  }
  let loom_snapshot = projection_boundary_snapshot(try? loom_doc.lower())
  let mini_snapshot = projection_boundary_snapshot(try? mini_doc.lower())
  let loom_ids = projection_boundary_leaf_ids(loom_snapshot)
  let mini_ids = projection_boundary_leaf_ids(mini_snapshot)
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  let loom_events = loom_snapshot.query_sourced_events(
    projection_boundary_one_cycle(),
  )
  let mini_events = mini_snapshot.query_sourced_events(
    projection_boundary_one_cycle(),
  )
  if loom_events.length() != 1 {
    abort("expected one loom lowered event")
  }
  if mini_events.length() != 1 {
    abort("expected one mini lowered event")
  }
  if loom_events.length() != mini_events.length() {
    abort("expected loom and mini lowered event counts to match")
  }
  for index in 0..<loom_events.length() {
    let loom_value = loom_events[index].event().value
    let mini_value = mini_events[index].event().value
    let mut loom_control_count = 0
    loom_value.each(fn(key, value) {
      loom_control_count += 1
      if mini_value.get(key) != Some(value) {
        abort("expected lowered control '\{key}' to match mini")
      }
    })
    let mut mini_control_count = 0
    mini_value.each(fn(key, value) {
      mini_control_count += 1
      if loom_value.get(key) != Some(value) {
        abort("expected mini control '\{key}' to match loom")
      }
    })
    if loom_control_count != mini_control_count {
      abort("expected lowered control count to match mini")
    }
    for expected in expected_controls {
      let key = expected.0
      let value = expected.1
      if loom_value.get(key) != Some(value) {
        abort("expected lowered control '\{key}' to match expected value")
      }
    }
  }
  projection.dispose()
}

///|
fn projection_boundary_assert_control_method_cache_reused_after_edit(
  input : String,
  edited : String,
  edit : @core.Edit,
) -> Unit {
  let projection = LoomMiniAtomProjection::new(input)
  let initial_doc = projection_boundary_doc(projection.parse_doc())
  let cache : @pattern.PatternLoweringCache[@pattern.ControlMap] =
    @pattern.PatternLoweringCache::new()
  ignore(
    projection_boundary_snapshot(try? initial_doc.lower_with_cache(cache)),
  )
  cache.reset_stats()
  projection.apply_edit(edit, edited)
  let edited_doc = projection_boundary_doc(projection.parse_doc())
  if edited_doc.root().value() != initial_doc.root().value() {
    abort("expected control-method edit to preserve root ID")
  }
  ignore(
    projection_boundary_snapshot(try? edited_doc.lower_with_cache(cache)),
  )
  if cache.hit_count() != 1 {
    abort("expected one control-method lowering-cache hit")
  }
  if cache.miss_count() != 0 {
    abort("expected no control-method lowering-cache misses")
  }
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
test "loom set_source uses source-diff fallback for atom identity" {
  let projection = LoomMiniAtomProjection::new("s(\"bd sd bd\")")
  ignore(projection_boundary_doc(projection.parse_doc()))
  projection.set_source("s(\"bd sd bd bd\")")
  let ids = projection_boundary_leaf_ids_from_doc(
    projection_boundary_doc(projection.parse_doc()),
  )
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:bd:1",
    #|  "mini:sound:bd:2",
    #|]
  debug_inspect(ids, content=expected)
  projection.dispose()
}

///|
struct ProjectionProvenanceEditSpan {
  old_start : Int
  old_end : Int
  new_end : Int
}

///|
fn ProjectionProvenanceEditSpan::ProjectionProvenanceEditSpan(
  old_start~ : Int,
  old_end~ : Int,
  new_end~ : Int,
) -> ProjectionProvenanceEditSpan {
  { old_start, old_end, new_end }
}

///|
struct ProjectionProvenanceMatrixRow {
  family : String
  initial : String
  edited : String
  edit : @core.Edit
  span : ProjectionProvenanceEditSpan
  initial_diagnostics : Int
  edited_diagnostics : Int
  expected_lowered_event_ids : Array[String]
}

///|
fn ProjectionProvenanceMatrixRow::ProjectionProvenanceMatrixRow(
  family~ : String,
  initial~ : String,
  edited~ : String,
  edit~ : @core.Edit,
  span~ : ProjectionProvenanceEditSpan,
  initial_diagnostics~ : Int,
  edited_diagnostics~ : Int,
  expected_lowered_event_ids~ : Array[String],
) -> ProjectionProvenanceMatrixRow {
  {
    family,
    initial,
    edited,
    edit,
    span,
    initial_diagnostics,
    edited_diagnostics,
    expected_lowered_event_ids,
  }
}

///|
fn projection_boundary_assert_int_equal(
  label : String,
  actual : Int,
  expected : Int,
) -> Unit {
  if actual != expected {
    abort("expected \{label} to be \{expected}, got \{actual}")
  }
}

///|
fn projection_boundary_assert_provenance_matrix_row(
  row : ProjectionProvenanceMatrixRow,
) -> Array[String] {
  let (_initial_cst, initial_diagnostics) = try! parse_cst(row.initial)
  projection_boundary_assert_int_equal(
    "\{row.family} initial CST diagnostics",
    initial_diagnostics.length(),
    row.initial_diagnostics,
  )
  let (_edited_cst, edited_diagnostics) = try! parse_cst(row.edited)
  projection_boundary_assert_int_equal(
    "\{row.family} edited CST diagnostics",
    edited_diagnostics.length(),
    row.edited_diagnostics,
  )
  let projection = LoomMiniAtomProjection::new(row.initial)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(row.initial)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(row.edit, row.edited)
  pipeline.set_input_with_source_edit(
    row.edited,
    old_start=row.span.old_start,
    old_end=row.span.old_end,
    new_end=row.span.new_end,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  if loom_doc.root().value() != mini_doc.root().value() {
    abort("expected \{row.family} loom and mini root IDs to match")
  }
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids(
    projection_boundary_mini_snapshot(pipeline.parse_snapshot()),
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection_boundary_assert_ids_equal(row.expected_lowered_event_ids, loom_ids)
  projection.dispose()
  pipeline.dispose()
  loom_ids
}

///|
struct ProjectionProvenanceRecoveryMatrixRow {
  family : String
  initial : String
  malformed : String
  recovered : String
  malformed_edit : @core.Edit
  recovery_edit : @core.Edit
  span : ProjectionProvenanceEditSpan
  expected_loom_error : String
  expected_lowered_event_ids : Array[String]
}

///|
fn ProjectionProvenanceRecoveryMatrixRow::ProjectionProvenanceRecoveryMatrixRow(
  family~ : String,
  initial~ : String,
  malformed~ : String,
  recovered~ : String,
  malformed_edit~ : @core.Edit,
  recovery_edit~ : @core.Edit,
  span~ : ProjectionProvenanceEditSpan,
  expected_loom_error~ : String,
  expected_lowered_event_ids~ : Array[String],
) -> ProjectionProvenanceRecoveryMatrixRow {
  {
    family,
    initial,
    malformed,
    recovered,
    malformed_edit,
    recovery_edit,
    span,
    expected_loom_error,
    expected_lowered_event_ids,
  }
}

///|
fn projection_boundary_assert_recovery_matrix_row(
  row : ProjectionProvenanceRecoveryMatrixRow,
) -> Array[String] {
  let (_initial_cst, initial_diagnostics) = try! parse_cst(row.initial)
  projection_boundary_assert_int_equal(
    "\{row.family} initial CST diagnostics",
    initial_diagnostics.length(),
    0,
  )
  let (_malformed_cst, malformed_diagnostics) = try! parse_cst(row.malformed)
  if malformed_diagnostics.length() == 0 {
    abort("expected \{row.family} malformed CST diagnostics")
  }
  let (_recovered_cst, recovered_diagnostics) = try! parse_cst(row.recovered)
  projection_boundary_assert_int_equal(
    "\{row.family} recovered CST diagnostics",
    recovered_diagnostics.length(),
    0,
  )
  let projection = LoomMiniAtomProjection::new(row.initial)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(row.initial)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(row.malformed_edit, row.malformed)
  pipeline.set_input_with_source_edit(
    row.malformed,
    old_start=row.span.old_start,
    old_end=row.span.old_end,
    new_end=row.span.new_end,
  )
  match projection.parse_doc() {
    Err(msg) =>
      if msg != row.expected_loom_error {
        abort("expected \{row.family} loom error to match")
      }
    Ok(_) => abort("expected \{row.family} loom projection to fail")
  }
  match pipeline.parse_doc() {
    Err(_) => ()
    Ok(_) => abort("expected \{row.family} mini authoring parse to fail")
  }
  projection.apply_edit(row.recovery_edit, row.recovered)
  pipeline.set_input_with_source_edit(
    row.recovered,
    old_start=row.span.old_start,
    old_end=row.span.old_end,
    new_end=row.span.new_end,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  if loom_doc.root().value() != mini_doc.root().value() {
    abort("expected \{row.family} loom and mini recovered root IDs to match")
  }
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids(
    projection_boundary_mini_snapshot(pipeline.parse_snapshot()),
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection_boundary_assert_ids_equal(row.expected_lowered_event_ids, loom_ids)
  projection.dispose()
  pipeline.dispose()
  loom_ids
}

///|
struct ProjectionProvenanceSemanticRecoveryMatrixRow {
  family : String
  initial : String
  malformed : String
  recovered : String
  malformed_edit : @core.Edit
  recovery_edit : @core.Edit
  malformed_span : ProjectionProvenanceEditSpan
  recovered_span : ProjectionProvenanceEditSpan
  expected_loom_error : String
  expected_lowered_event_ids : Array[String]
}

///|
fn ProjectionProvenanceSemanticRecoveryMatrixRow::ProjectionProvenanceSemanticRecoveryMatrixRow(
  family~ : String,
  initial~ : String,
  malformed~ : String,
  recovered~ : String,
  malformed_edit~ : @core.Edit,
  recovery_edit~ : @core.Edit,
  malformed_span~ : ProjectionProvenanceEditSpan,
  recovered_span~ : ProjectionProvenanceEditSpan,
  expected_loom_error~ : String,
  expected_lowered_event_ids~ : Array[String],
) -> ProjectionProvenanceSemanticRecoveryMatrixRow {
  {
    family,
    initial,
    malformed,
    recovered,
    malformed_edit,
    recovery_edit,
    malformed_span,
    recovered_span,
    expected_loom_error,
    expected_lowered_event_ids,
  }
}

///|
fn projection_boundary_assert_semantic_recovery_matrix_row(
  row : ProjectionProvenanceSemanticRecoveryMatrixRow,
) -> Array[String] {
  let (_initial_cst, initial_diagnostics) = try! parse_cst(row.initial)
  projection_boundary_assert_int_equal(
    "\{row.family} initial CST diagnostics",
    initial_diagnostics.length(),
    0,
  )
  let (_malformed_cst, malformed_diagnostics) = try! parse_cst(row.malformed)
  projection_boundary_assert_int_equal(
    "\{row.family} malformed CST diagnostics",
    malformed_diagnostics.length(),
    0,
  )
  let (_recovered_cst, recovered_diagnostics) = try! parse_cst(row.recovered)
  projection_boundary_assert_int_equal(
    "\{row.family} recovered CST diagnostics",
    recovered_diagnostics.length(),
    0,
  )
  let projection = LoomMiniAtomProjection::new(row.initial)
  ignore(projection_boundary_doc(projection.parse_doc()))
  let pipeline = @mini.MiniAuthoringPipeline::new(row.initial)
  ignore(projection_boundary_mini_snapshot(pipeline.parse_snapshot()))
  projection.apply_edit(row.malformed_edit, row.malformed)
  pipeline.set_input_with_source_edit(
    row.malformed,
    old_start=row.malformed_span.old_start,
    old_end=row.malformed_span.old_end,
    new_end=row.malformed_span.new_end,
  )
  match projection.parse_doc() {
    Err(msg) =>
      if msg != row.expected_loom_error {
        abort("expected \{row.family} loom error to match")
      }
    Ok(_) => abort("expected \{row.family} loom projection to fail")
  }
  match pipeline.parse_doc() {
    Err(_) => ()
    Ok(_) => abort("expected \{row.family} mini authoring parse to fail")
  }
  projection.apply_edit(row.recovery_edit, row.recovered)
  pipeline.set_input_with_source_edit(
    row.recovered,
    old_start=row.recovered_span.old_start,
    old_end=row.recovered_span.old_end,
    new_end=row.recovered_span.new_end,
  )
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(pipeline.parse_doc())
  if loom_doc.root().value() != mini_doc.root().value() {
    abort("expected \{row.family} loom and mini recovered root IDs to match")
  }
  let loom_ids = projection_boundary_leaf_ids_from_doc(loom_doc)
  let mini_ids = projection_boundary_leaf_ids(
    projection_boundary_mini_snapshot(pipeline.parse_snapshot()),
  )
  projection_boundary_assert_ids_equal(loom_ids, mini_ids)
  projection_boundary_assert_ids_equal(row.expected_lowered_event_ids, loom_ids)
  projection.dispose()
  pipeline.dispose()
  loom_ids
}

///|
test "loom provenance matrix row covers duplicate sound insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="duplicate sound atoms",
      initial="s(\"bd sd bd\")",
      edited="s(\"bd sd bd bd\")",
      edit=@core.Edit::insert(9, 3),
      span=ProjectionProvenanceEditSpan(
        old_start=9,
        old_end=9,
        new_end=12,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:sd:0",
        "mini:sound:bd:2",
        "mini:sound:bd:1",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:bd:2",
    #|  "mini:sound:bd:1",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers duplicate note insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="duplicate note atoms",
      initial="note(\"60 62 60\")",
      edited="note(\"60 62 60 60\")",
      edit=@core.Edit::insert(12, 3),
      span=ProjectionProvenanceEditSpan(
        old_start=12,
        old_end=12,
        new_end=15,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:note:60:0",
        "mini:note:62:0",
        "mini:note:60:2",
        "mini:note:60:1",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:note:60:0",
    #|  "mini:note:62:0",
    #|  "mini:note:60:2",
    #|  "mini:note:60:1",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers duplicate sound deletion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="duplicate sound atoms",
      initial="s(\"bd sd bd\")",
      edited="s(\"bd bd\")",
      edit=@core.Edit::delete(5, 8),
      span=ProjectionProvenanceEditSpan(
        old_start=5,
        old_end=8,
        new_end=5,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:bd:1",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:sound:bd:1"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers duplicate note deletion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="duplicate note atoms",
      initial="note(\"60 62 60\")",
      edited="note(\"60 60\")",
      edit=@core.Edit::delete(8, 11),
      span=ProjectionProvenanceEditSpan(
        old_start=8,
        old_end=11,
        new_end=8,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:note:60:0",
        "mini:note:60:1",
      ],
    ),
  )
  let expected =
    #|["mini:note:60:0", "mini:note:60:1"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers sound atom replacement" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="sound atom replacement",
      initial="s(\"bd sd hh\")",
      edited="s(\"bd cp hh\")",
      edit=@core.Edit::replace(6, 8, 8),
      span=ProjectionProvenanceEditSpan(
        old_start=6,
        old_end=8,
        new_end=8,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:cp:0",
        "mini:sound:hh:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:sound:cp:0", "mini:sound:hh:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers whitespace-only edit" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="whitespace edit",
      initial="s(\"bd sd\")",
      edited="s(\"bd   sd\")",
      edit=@core.Edit::insert(6, 2),
      span=ProjectionProvenanceEditSpan(
        old_start=6,
        old_end=6,
        new_end=8,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:sound:sd:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers dollar stack line insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="dollar stack line insertion",
      initial="$: s(\"bd\")",
      edited="$: s(\"bd\")\n$: note(\"60\")",
      edit=@core.Edit::insert(10, 14),
      span=ProjectionProvenanceEditSpan(
        old_start=10,
        old_end=10,
        new_end=24,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:note:60:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:note:60:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers layer comma insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="layer comma insertion",
      initial="s(\"bd sd\")",
      edited="s(\"bd, sd\")",
      edit=@core.Edit::insert(5, 1),
      span=ProjectionProvenanceEditSpan(
        old_start=5,
        old_end=5,
        new_end=6,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:sound:sd:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers slow postfix insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="postfix insertion",
      initial="s(\"bd sd\")",
      edited="s(\"bd/2 sd\")",
      edit=@core.Edit::insert(5, 2),
      span=ProjectionProvenanceEditSpan(
        old_start=5,
        old_end=5,
        new_end=7,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:sound:sd:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers euclid postfix insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="euclid postfix insertion",
      initial="s(\"bd sd\")",
      edited="s(\"bd(3,8) sd\")",
      edit=@core.Edit::insert(5, 5),
      span=ProjectionProvenanceEditSpan(
        old_start=5,
        old_end=5,
        new_end=10,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:bd:0",
        "mini:sound:bd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:bd:0",
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers sub-notation postfix insertion" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="sub-notation postfix insertion",
      initial="s(\"[bd sd] hh\")",
      edited="s(\"[bd sd]*2 hh\")",
      edit=@core.Edit::insert(10, 2),
      span=ProjectionProvenanceEditSpan(
        old_start=10,
        old_end=10,
        new_end=12,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:sd:0",
        "mini:sound:bd:0",
        "mini:sound:sd:0",
        "mini:sound:hh:0",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:hh:0",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers root method replacement" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="root method replacement",
      initial="s(\"bd sd\").fast(2)",
      edited="s(\"bd sd\").slow(2)",
      edit=@core.Edit::replace(11, 15, 15),
      span=ProjectionProvenanceEditSpan(
        old_start=11,
        old_end=15,
        new_end=15,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=["mini:sound:bd:0"],
    ),
  )
  let expected =
    #|["mini:sound:bd:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers jux callback replacement" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="jux callback replacement",
      initial="s(\"bd sd\").jux(rev)",
      edited="s(\"bd sd\").jux(fast(2))",
      edit=@core.Edit::replace(15, 18, 22),
      span=ProjectionProvenanceEditSpan(
        old_start=15,
        old_end=18,
        new_end=22,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers every callback replacement" {
  let ids = projection_boundary_assert_provenance_matrix_row(
    ProjectionProvenanceMatrixRow(
      family="every callback replacement",
      initial="s(\"bd sd\").every(2, rev)",
      edited="s(\"bd sd\").every(2, fast(2))",
      edit=@core.Edit::replace(20, 23, 27),
      span=ProjectionProvenanceEditSpan(
        old_start=20,
        old_end=23,
        new_end=27,
      ),
      initial_diagnostics=0,
      edited_diagnostics=0,
      expected_lowered_event_ids=[
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom provenance matrix row covers parse-error recovery" {
  let ids = projection_boundary_assert_recovery_matrix_row(
    ProjectionProvenanceRecoveryMatrixRow(
      family="parse-error recovery",
      initial="s(\"bd sd bd\")",
      malformed="s(\"bd sd bd bd\"",
      recovered="s(\"bd sd bd bd\")",
      malformed_edit=@core.Edit::insert(9, 3),
      recovery_edit=@core.Edit::insert(15, 1),
      span=ProjectionProvenanceEditSpan(
        old_start=9,
        old_end=9,
        new_end=12,
      ),
      expected_loom_error="loom mini syntax has diagnostics",
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:sound:sd:0",
        "mini:sound:bd:2",
        "mini:sound:bd:1",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:bd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:bd:2",
    #|  "mini:sound:bd:1",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom recovery matrix row covers dollar stack line recovery" {
  let ids = projection_boundary_assert_recovery_matrix_row(
    ProjectionProvenanceRecoveryMatrixRow(
      family="dollar stack line recovery",
      initial="$: s(\"bd\")",
      malformed="$: s(\"bd\")\n$: note(\"60\"",
      recovered="$: s(\"bd\")\n$: note(\"60\")",
      malformed_edit=@core.Edit::insert(10, 14),
      recovery_edit=@core.Edit::insert(23, 1),
      span=ProjectionProvenanceEditSpan(
        old_start=10,
        old_end=10,
        new_end=24,
      ),
      expected_loom_error="loom mini syntax has diagnostics",
      expected_lowered_event_ids=[
        "mini:sound:bd:0",
        "mini:note:60:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:bd:0", "mini:note:60:0"]
  debug_inspect(ids, content=expected)
}

///|
test "loom recovery matrix row covers direct callback recovery" {
  let ids = projection_boundary_assert_recovery_matrix_row(
    ProjectionProvenanceRecoveryMatrixRow(
      family="direct callback recovery",
      initial="s(\"bd sd\").jux(rev)",
      malformed="s(\"bd sd\").jux(fast(2)",
      recovered="s(\"bd sd\").jux(fast(2))",
      malformed_edit=@core.Edit::replace(15, 18, 22),
      recovery_edit=@core.Edit::insert(22, 1),
      span=ProjectionProvenanceEditSpan(
        old_start=15,
        old_end=18,
        new_end=22,
      ),
      expected_loom_error="loom mini syntax has diagnostics",
      expected_lowered_event_ids=[
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom recovery matrix row covers dollar stack callback recovery" {
  let ids = projection_boundary_assert_recovery_matrix_row(
    ProjectionProvenanceRecoveryMatrixRow(
      family="dollar stack callback recovery",
      initial="$: s(\"bd sd\").jux(rev)",
      malformed="$: s(\"bd sd\").jux(fast(2)",
      recovered="$: s(\"bd sd\").jux(fast(2))",
      malformed_edit=@core.Edit::replace(18, 21, 25),
      recovery_edit=@core.Edit::insert(25, 1),
      span=ProjectionProvenanceEditSpan(
        old_start=18,
        old_end=21,
        new_end=25,
      ),
      expected_loom_error="loom mini syntax has diagnostics",
      expected_lowered_event_ids=[
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|[
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|  "mini:sound:sd:0",
    #|]
  debug_inspect(ids, content=expected)
}

///|
test "loom recovery matrix row covers control method recovery" {
  let ids = projection_boundary_assert_recovery_matrix_row(
    ProjectionProvenanceRecoveryMatrixRow(
      family="control method recovery",
      initial="s(\"bd\").gain(0.5)",
      malformed="s(\"bd\").gain(0.5).pan(-0.25",
      recovered="s(\"bd\").gain(0.5).pan(-0.25)",
      malformed_edit=@core.Edit::insert(17, 11),
      recovery_edit=@core.Edit::insert(27, 1),
      span=ProjectionProvenanceEditSpan(
        old_start=17,
        old_end=17,
        new_end=28,
      ),
      expected_loom_error="loom mini syntax has diagnostics",
      expected_lowered_event_ids=[
        "mini:control:mini:merge_control:mini:sound:bd:0:gain:0.5:pan:-0.25",
      ],
    ),
  )
  let expected =
    #|["mini:control:mini:merge_control:mini:sound:bd:0:gain:0.5:pan:-0.25"]
  debug_inspect(ids, content=expected)
}

///|
test "loom semantic recovery matrix row covers projection-only failure" {
  let ids = projection_boundary_assert_semantic_recovery_matrix_row(
    ProjectionProvenanceSemanticRecoveryMatrixRow(
      family="projection-only recovery",
      initial="s(\"bd sd\")",
      malformed="s(\"2 bd sd\")",
      recovered="s(\"cp bd sd\")",
      malformed_edit=@core.Edit::insert(3, 2),
      recovery_edit=@core.Edit::replace(3, 4, 5),
      malformed_span=ProjectionProvenanceEditSpan(
        old_start=3,
        old_end=3,
        new_end=5,
      ),
      recovered_span=ProjectionProvenanceEditSpan(
        old_start=3,
        old_end=3,
        new_end=6,
      ),
      expected_loom_error="loom atom projection expected sound name",
      expected_lowered_event_ids=[
        "mini:sound:cp:0",
        "mini:sound:bd:0",
        "mini:sound:sd:0",
      ],
    ),
  )
  let expected =
    #|["mini:sound:cp:0", "mini:sound:bd:0", "mini:sound:sd:0"]
  debug_inspect(ids, content=expected)
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
// Method-chained stack arguments (`stack(s("bd").fast(2), …)`) — the grammar
// has accepted these since the Piece 1 Codex review (parser_test.mbt), but the
// projection only gained per-arg method-chain grouping in Piece 2. Value-level
// parity guards that fix.
test "loom atom projection matches mini PatternDoc and events for method-chained stack args" {
  let input = "stack(s(\"bd\").fast(2), note(\"60\").rev())"
  let projection = LoomMiniAtomProjection::new(input)
  let loom_doc = projection_boundary_doc(projection.parse_doc())
  let mini_doc = projection_boundary_doc(@mini.parse_doc(input))
  @debug.assert_eq(loom_doc.root().value(), mini_doc.root().value())
  projection_boundary_assert_value_events_equal(
    projection_boundary_value_events_from_doc(loom_doc),
    projection_boundary_value_events_from_doc(mini_doc),
  )
  projection.dispose()
}

///|
// KNOWN EDGE CHARACTERIZATION: empty quoted notation is CST-only recovery.
// The Loom grammar emits a zero-diagnostic tree for editor partial input, but
// semantic projection rejects it just like production @mini.parse_doc. This is
// not a production mismatch and does not require an upstream Loom/seam fix.
test "known edge case: empty notation is CST-only recovery, projection rejects like mini" {
  let input = "s(\"\")"
  let (_cst, diagnostics) = try! parse_cst(input)
  inspect(diagnostics.length(), content="0")
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Err(msg) =>
      inspect(msg, content="loom atom projection expected at least one atom")
    Ok(_) => abort("expected empty loom projection to fail")
  }
  match @mini.parse_doc(input) {
    Err(msg) => inspect(msg, content="position 0: empty notation")
    Ok(_) => abort("expected empty production parse_doc to fail")
  }
  projection.dispose()
}

///|
// KNOWN EDGE CHARACTERIZATION: trailing-comma notation is also CST-only
// recovery. The CST keeps an empty trailing LayerNode for editor flows, while
// Loom projection and production @mini.parse_doc both reject the empty layer.
test "known edge case: trailing comma is CST-only recovery, projection rejects like mini" {
  let input = "s(\"bd,\")"
  let (_cst, diagnostics) = try! parse_cst(input)
  inspect(diagnostics.length(), content="0")
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Err(msg) =>
      inspect(msg, content="loom atom projection expected at least one atom")
    Ok(_) => abort("expected trailing-comma loom projection to fail")
  }
  match @mini.parse_doc(input) {
    Err(msg) =>
      inspect(msg, content="position 3: expected at least one element in layer")
    Ok(_) => abort("expected trailing-comma production parse_doc to fail")
  }
  projection.dispose()
}

///|
// KNOWN EDGE CHARACTERIZATION: unterminated sub-notation remains a bounded
// CST recovery-quality follow-up. Loom emits diagnostics and projection rejects
// because diagnostics are present; production @mini.parse_doc also rejects the
// malformed bracket, so this is not a production mismatch.
test "known edge case: unterminated bracket has bounded CST recovery and rejects like mini" {
  let input = "s(\"[bd\")"
  let (_cst, diagnostics) = try! parse_cst(input)
  inspect(diagnostics.length() > 0, content="true")
  inspect(diagnostics.length() <= 64, content="true")
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Err(msg) => inspect(msg, content="loom mini syntax has diagnostics")
    Ok(_) => abort("expected unterminated-bracket loom projection to fail")
  }
  match @mini.parse_doc(input) {
    Err(msg) => inspect(msg, content="position 3: expected ']'")
    Ok(_) => abort("expected unterminated-bracket production parse_doc to fail")
  }
  projection.dispose()
}

///|
// KNOWN EDGE CHARACTERIZATION: digit-start sound atoms remain a CST lexer
// limitation, but projection now rejects the mode-incompatible NumberToken
// instead of dropping it and projecting the following IdentToken. Production
// @mini.parse_doc also rejects the digit-start sound atom.
test "known edge case: digit-start sound atom projection rejects like production" {
  let input = "s(\"2bd\")"
  let (_cst, diagnostics) = try! parse_cst(input)
  inspect(diagnostics.length(), content="0")
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Err(msg) => inspect(msg, content="loom atom projection expected sound name")
    Ok(_) => abort("expected digit-start loom projection to fail")
  }
  match @mini.parse_doc(input) {
    Err(msg) => inspect(msg, content="position 0: expected sound name")
    Ok(_) => abort("expected digit-start production parse_doc to fail")
  }
  projection.dispose()
}

///|
test "loom atom projection rejects numeric sound atom instead of dropping it" {
  let input = "s(\"2 bd\")"
  let (_cst, diagnostics) = try! parse_cst(input)
  inspect(diagnostics.length(), content="0")
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Err(msg) => inspect(msg, content="loom atom projection expected sound name")
    Ok(_) => abort("expected numeric sound atom projection to fail")
  }
  match @mini.parse_doc(input) {
    Err(msg) => inspect(msg, content="position 0: expected sound name")
    Ok(_) => abort("expected numeric sound atom production parse_doc to fail")
  }
  projection.dispose()
}

///|
test "loom atom projection rejects identifier note atom instead of dropping it" {
  let input = "note(\"bd 60\")"
  let (_cst, diagnostics) = try! parse_cst(input)
  inspect(diagnostics.length(), content="0")
  let projection = LoomMiniAtomProjection::new(input)
  match projection.parse_doc() {
    Err(msg) => inspect(msg, content="loom atom projection expected note number")
    Ok(_) => abort("expected identifier note atom projection to fail")
  }
  match @mini.parse_doc(input) {
    Err(msg) => inspect(msg, content="position 0: expected number")
    Ok(_) => abort("expected identifier note atom production parse_doc to fail")
  }
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
test "loom atom projection matches mini PatternDoc for dollar stack callback variants" {
  let input =
    #|$: s("bd sd").jux(fast(2))
    #|$: s("bd sd").jux(slow(2))
    #|$: note("60 64").every(2, rev)
    #|$: note("60 64").every(2, slow(2))
  projection_boundary_assert_matches_mini_doc(input)
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
test "loom atom projection matches mini PatternDoc and events for cutoff method" {
  projection_boundary_assert_control_method_matches_mini(
    "s(\"bd\").cutoff(200)",
    "mini:merge_control:mini:sound:bd:0:cutoff:200",
    [("sound", 36.0), ("cutoff", 200.0)],
  )
}

///|
test "loom atom projection matches mini PatternDoc and events for gain pan chain" {
  projection_boundary_assert_control_method_matches_mini(
    "s(\"bd\").gain(0.5).pan(-0.25)",
    "mini:merge_control:mini:merge_control:mini:sound:bd:0:gain:0.5:pan:-0.25",
    [("sound", 36.0), ("gain", 0.5), ("pan", -0.25)],
  )
}

///|
test "loom atom projection reuses control method lowering cache after whitespace edit" {
  projection_boundary_assert_control_method_cache_reused_after_edit(
    "s(\"bd\").gain(0.5).pan(-0.25)",
    "s(\"  bd\").gain(0.5).pan(-0.25)",
    @core.Edit::insert(3, 2),
  )
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

///|
/// Canonical Phase 2 doc-parity corpus (plan Step 1). Seeded from the proven
/// `parse_doc`-compatible literals already exercised across this spike: atoms,
/// sequences, fast/slow/rev chains, euclid, sub-notation, postfix operators,
/// control methods, jux/every, and known-malformed forms. Multiline `$:` stack
/// inputs are covered by the existing dedicated tests and are a tracked corpus
/// follow-up (plan Step 6), not silently dropped.
fn projection_boundary_doc_corpus() -> Array[String] {
  [
    // valid
    "s(\"bd\")", "s(\"bd sd\")", "s(\"bd sd bd\")", "s(\"bd sd hh\")",
    "s(\"bd cp hh\")", "s(\"cp bd sd\")", "s(\"bd bd\")", "s(\"bd   sd\")",
    "note(\"60 60\")", "note(\"60 62 60\")", "note(\"60 64 60\")",
    "s(\"bd sd\").fast(2)", "s(\"bd sd\").slow(2)", "s(\"bd sd hh\").rev()",
    "s(\"bd sd\").fast(2).rev().slow(3)", "s(\"bd*2 sd\")", "s(\"bd/2 sd\")",
    "s(\"bd*2/3 sd\")", "s(\"bd/2*3 sd\")", "s(\"[bd sd] hh\")",
    "s(\"[bd sd]*2 hh\")", "s(\"bd(3,8) sd\")", "s(\"bd(3,8,1) sd\")",
    "s(\"bd(3,8,-1) sd\")", "s(\"bd? sd\")", "s(\"[bd sd]? hh\")",
    "s(\"[bd sd](5,8) hh\")", "s(\"bd\").gain(0.5)",
    "s(\"bd\").gain(0.5).pan(-0.25)", "s(\"bd\").cutoff(200)",
    "s(\"bd sd\").jux(rev)", "s(\"bd sd\").jux(fast(2))",
    "s(\"bd sd\").jux(slow(2))", "s(\"bd sd\").every(2, rev)",
    "s(\"bd sd\").every(2, fast(2))", "s(\"bd sd\").every(2, slow(2))",
    "s(\"bd\").fast(slow(2))",
    // malformed — runner asserts both parsers AGREE on rejection
    "s(\"[bd\")", "s(\"bd sd\").jux(fast(2)", "s(\"bd\").gain(0.5).pan(-0.25",
  ]
}

///|
/// Differential doc-parity runner (plan Step 3): run both parsers on one input
/// and assert they AGREE — both `Ok` (then root-id + value-level event parity)
/// or both `Err` (message text characterized, NOT asserted, per the authoring
/// `Result[_, String]` contract). A one-sided `Ok`/`Err` is a real parity hole
/// and aborts. Returns 1 when a both-`Err` message text divergence was
/// characterized (Phase 3 error-adapter input), else 0.
fn projection_boundary_assert_value_matches_mini(input : String) -> Int {
  let projection = LoomMiniAtomProjection::new(input)
  let loom_result = projection.parse_doc()
  let mini_result = @mini.parse_doc(input)
  let divergence = match (loom_result, mini_result) {
    (Ok(loom_doc), Ok(mini_doc)) => {
      if loom_doc.root().value() != mini_doc.root().value() {
        abort("input '\{input}': root id mismatch")
      }
      projection_boundary_assert_value_events_equal(
        projection_boundary_value_events_from_doc(loom_doc),
        projection_boundary_value_events_from_doc(mini_doc),
      )
      0
    }
    (Err(loom_msg), Err(mini_msg)) => if loom_msg == mini_msg { 0 } else { 1 }
    (Ok(_), Err(mini_msg)) =>
      abort("input '\{input}': loom accepted but mini rejected (\{mini_msg})")
    (Err(loom_msg), Ok(_)) =>
      abort("input '\{input}': mini accepted but loom rejected (\{loom_msg})")
  }
  projection.dispose()
  divergence
}

///|
/// Positive control (plan Step 4): prove the value-level helper is sensitive,
/// not vacuous. Build a divergence the id-only check MISSES (identical node ids
/// and spans, perturbed ControlMap payload) and confirm the value-level helper
/// aborts. The `panic ` prefix means the test PASSES iff an abort occurs.
test "panic phase2 piece1 value parity catches control-only divergence" {
  let doc = projection_boundary_doc(@mini.parse_doc("s(\"bd sd\")"))
  let base = projection_boundary_value_events_from_doc(doc)
  guard base.length() > 0 else {
    abort("positive control needs at least one event")
  }
  let perturbed : Array[BoundaryEvent] = []
  for index in 0..<base.length() {
    let e = base[index]
    if index == 0 {
      let bumped : Map[String, Double] = {}
      e.control.each(fn(k, v) { bumped[k] = v })
      bumped["__divergence__"] = 1.0
      perturbed.push({ id: e.id, control: bumped, whole: e.whole, part: e.part })
    } else {
      perturbed.push(e)
    }
  }
  // Divergence is value-only: id sequences still match, so the id-only check
  // would pass (this must NOT abort) ...
  let base_ids = [for e in base => e.id]
  let perturbed_ids = [for e in perturbed => e.id]
  projection_boundary_assert_ids_equal(base_ids, perturbed_ids)
  // ... but the value-level helper MUST abort on the control delta:
  projection_boundary_assert_value_events_equal(base, perturbed)
}

///|
/// Piece 1 green gate (plan Step 5): the whole canonical corpus passes Ok/Err
/// agreement + value-level parity (any hole aborts in the runner above).
/// Both-`Err` message divergences are characterized, not failed.
test "phase2 piece1 doc value-parity corpus" {
  let corpus = projection_boundary_doc_corpus()
  let mut message_divergences = 0
  for input in corpus {
    message_divergences = message_divergences +
      projection_boundary_assert_value_matches_mini(input)
  }
  ignore(message_divergences)
  inspect(corpus.length() >= 30, content="true")
}
