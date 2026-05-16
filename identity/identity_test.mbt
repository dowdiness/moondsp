///|
using @identity {
  type GraphNodeId,
  type OccurrenceId,
  type PatternNodeId,
  type Revision,
  type SectionId,
  type SectionLayerId,
  type StableIdError,
}

///|
test "Revision starts at zero and increments" {
  let zero = Revision::zero()
  @debug.assert_eq(zero.value(), 0L)
  @debug.assert_eq(zero.next().value(), 1L)
}

///|
test "Revision::max keeps the newer token" {
  let zero = Revision::zero()
  let one = zero.next()
  @debug.assert_eq(zero.max(one).value(), 1L)
  @debug.assert_eq(one.max(zero).value(), 1L)
}

///|
test "Revision::combine mixes ordered aggregate tokens" {
  let zero = Revision::zero()
  let one = Revision::zero().next()
  let two = one.next()
  @debug.assert_eq(zero.combine(zero).value(), 0L)
  assert_true(one.combine(two) != two.combine(one))
}

///|
test "Revision::combine preserves aggregate identity beyond compact value" {
  let zero = Revision::zero()
  let aggregate = zero.combine(zero)
  @debug.assert_eq(aggregate.value(), zero.value())
  assert_true(aggregate != zero)
}

///|
test "Revision::max breaks compact value ties deterministically" {
  let zero = Revision::zero()
  let aggregate = zero.combine(zero)
  @debug.assert_eq(zero.value(), aggregate.value())
  assert_true(zero.max(aggregate) == aggregate)
  assert_true(aggregate.max(zero) == aggregate)
}

///|
test "stable IDs accept portable authoring strings" {
  let pattern = try? PatternNodeId::from_string("pat:intro_1")
  let section = try? SectionId::from_string("section.intro")
  let layer = try? SectionLayerId::from_string("layer-main")
  let occurrence = try? OccurrenceId::from_string("verse:2")
  let graph = try? GraphNodeId::from_string("graph.node_3")
  match (pattern, section, layer, occurrence, graph) {
    (Ok(pattern), Ok(section), Ok(layer), Ok(occurrence), Ok(graph)) => {
      @debug.assert_eq(pattern.value(), "pat:intro_1")
      @debug.assert_eq(section.value(), "section.intro")
      @debug.assert_eq(layer.value(), "layer-main")
      @debug.assert_eq(occurrence.value(), "verse:2")
      @debug.assert_eq(graph.value(), "graph.node_3")
    }
    _ => abort("expected valid IDs")
  }
}

///|
test "stable IDs reject empty strings" {
  let result = try? OccurrenceId::from_string("")
  match result {
    Err(StableIdError::EmptyId) => ()
    _ => abort("expected EmptyId")
  }
}

///|
test "stable IDs reject non-portable characters" {
  let result = try? OccurrenceId::from_string("bad id")
  match result {
    Err(StableIdError::InvalidId("bad id")) => ()
    _ => abort("expected InvalidId")
  }
}
