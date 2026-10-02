///|
fn path_test_id(value : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string(value) catch {
    _ => abort("expected valid pattern node id")
  }
}

///|
test "PatternNodePath preserves duplicate order and nodes ownership" {
  let descendants = [
    path_test_id("dup"),
    path_test_id("leaf"),
    path_test_id("leaf"),
  ]
  let path = PatternNodePath(path_test_id("dup"), descendants~)
  descendants[0] = path_test_id("changed")
  @debug.assert_eq(path.nodes().map(id => id.value()), [
    "dup", "dup", "leaf", "leaf",
  ])
  @debug.assert_eq(path.leaf(), path_test_id("leaf"))
  let returned = path.nodes()
  returned[0] = path_test_id("changed")
  @debug.assert_eq(path.nodes().map(id => id.value()), [
    "dup", "dup", "leaf", "leaf",
  ])
}

///|
test "PatternNodePath prepends branch without changing shared source" {
  let source = PatternNodePath(path_test_id("root"), descendants=[
    path_test_id("leaf"),
  ])
  let left = source.prepend(path_test_id("left"))
  let right = source.prepend(path_test_id("right"))
  @debug.assert_eq(source.nodes().map(id => id.value()), ["root", "leaf"])
  @debug.assert_eq(left.nodes().map(id => id.value()), ["left", "root", "leaf"])
  @debug.assert_eq(right.nodes().map(id => id.value()), [
    "right", "root", "leaf",
  ])
  @debug.assert_eq(
    left,
    PatternNodePath(path_test_id("left"), descendants=[
      path_test_id("root"),
      path_test_id("leaf"),
    ]),
  )
}
