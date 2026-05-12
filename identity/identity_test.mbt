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
  assert_eq(zero.value(), 0L)
  assert_eq(zero.next().value(), 1L)
}

///|
test "Revision::max keeps the newer token" {
  let zero = Revision::zero()
  let one = zero.next()
  assert_eq(zero.max(one).value(), 1L)
  assert_eq(one.max(zero).value(), 1L)
}

///|
test "Revision::combine mixes ordered aggregate tokens" {
  let zero = Revision::zero()
  let one = Revision::zero().next()
  let two = one.next()
  assert_eq(zero.combine(zero).value(), 0L)
  assert_true(one.combine(two) != two.combine(one))
}

///|
test "Revision::combine preserves aggregate identity beyond compact value" {
  let zero = Revision::zero()
  let aggregate = zero.combine(zero)
  assert_eq(aggregate.value(), zero.value())
  assert_true(aggregate != zero)
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
      assert_eq(pattern.value(), "pat:intro_1")
      assert_eq(section.value(), "section.intro")
      assert_eq(layer.value(), "layer-main")
      assert_eq(occurrence.value(), "verse:2")
      assert_eq(graph.value(), "graph.node_3")
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
