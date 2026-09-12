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
  let pattern = PatternNodeId::from_string("pat:intro_1")
  let section = SectionId::from_string("section.intro")
  let layer = SectionLayerId::from_string("layer-main")
  let occurrence = OccurrenceId::from_string("verse:2")
  let graph = GraphNodeId::from_string("graph.node_3")
  @debug.assert_eq(pattern.value(), "pat:intro_1")
  @debug.assert_eq(section.value(), "section.intro")
  @debug.assert_eq(layer.value(), "layer-main")
  @debug.assert_eq(occurrence.value(), "verse:2")
  @debug.assert_eq(graph.value(), "graph.node_3")
}

///|
test "stable IDs reject empty strings" {
  try OccurrenceId::from_string("") catch {
    error =>
      match error {
        StableIdError::EmptyId => ()
        _ => abort("expected EmptyId")
      }
  } noraise {
    _ => abort("expected EmptyId")
  }
}

///|
test "stable IDs reject non-portable characters" {
  try OccurrenceId::from_string("bad id") catch {
    error =>
      match error {
        StableIdError::InvalidId("bad id") => ()
        _ => abort("expected InvalidId")
      }
  } noraise {
    _ => abort("expected InvalidId")
  }
}
