///|
fn path_bench_id(value : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string(value) catch {
    _ => abort("expected valid path benchmark id")
  }
}

///|
fn path_bench_ids(
  prefix : String,
  count : Int,
) -> Array[@identity.PatternNodeId] {
  Array::makei(count, index => path_bench_id("\{prefix}-\{index}"))
}

///|
fn bench_path_prepend_and_query(
  b : @bench.T,
  name : String,
  ids : Array[@identity.PatternNodeId],
) -> Unit {
  let mut iteration = 0
  b.bench(name~, fn() {
    let depth = ids.length() / 64
    let offset = iteration * depth
    iteration = (iteration + 1) % 64
    let mut path = PatternNodePath(ids[offset + depth - 1])
    for index = depth - 2; index >= 0; index = index - 1 {
      path = path.prepend(ids[offset + index])
    }
    let nodes = path.nodes()
    b.keep((nodes, path.leaf()))
  })
}

///|
test "bench/pattern-node-path/prepend-query" (b : @bench.T) {
  let depth1 = path_bench_ids("path-depth-1", 64)
  let depth4 = path_bench_ids("path-depth-4", 4 * 64)
  let depth12 = path_bench_ids("path-depth-12", 12 * 64)
  bench_path_prepend_and_query(b, "depth_1", depth1)
  bench_path_prepend_and_query(b, "depth_4", depth4)
  bench_path_prepend_and_query(b, "depth_12", depth12)
}
