///|
/// Constant folding pass: walks nodes in order, replacing foldable nodes
/// whose inputs are all constants with new Constant nodes.
/// Returns (folded_nodes, index_map, changed).
fn fold_constants(
  nodes : Array[DspNode],
) -> (Array[DspNode], FixedArray[Int], Bool) {
  let n = nodes.length()
  // Bail out if nodes are not in topological order (forward references present)
  for i = 0; i < n; i = i + 1 {
    let node = nodes[i]
    if (node.input0 >= 0 && node.input0 >= i) ||
      (node.input1 >= 0 && node.input1 >= i) {
      return (nodes, FixedArray::makei(n, fn(i) { i }), false)
    }
  }
  let folded : Array[DspNode] = []
  let index_map = FixedArray::make(n, -1)
  let mut changed = false
  for i = 0; i < n; i = i + 1 {
    let node = nodes[i]
    let is_constant = node.kind is DspNodeKind::Constant
    if node.is_foldable() && !is_constant {
      // Check if all inputs are Constant in the folded array
      let has_input0 = node.input0 >= 0
      let has_input1 = node.input1 >= 0
      let input0_is_const = if has_input0 {
        let mapped = index_map[node.input0]
        mapped >= 0 && folded[mapped].kind is DspNodeKind::Constant
      } else {
        true
      }
      let input1_is_const = if has_input1 {
        let mapped = index_map[node.input1]
        mapped >= 0 && folded[mapped].kind is DspNodeKind::Constant
      } else {
        true
      }
      if input0_is_const && input1_is_const {
        // Skip folding Clip with invalid threshold — let validation reject it
        if node.kind is DspNodeKind::Clip && !(node.value0 > 0.0) {
          // Invalid Clip threshold — fall through to keep as-is
        } else {
          // Get input values
          let v0 = if has_input0 {
            folded[index_map[node.input0]].value0
          } else {
            0.0
          }
          let v1 = if has_input1 {
            folded[index_map[node.input1]].value0
          } else {
            0.0
          }
          let result = node.fold_value(v0, v1)
          // Skip folding if result is non-finite
          if result.is_nan() || result.is_inf() {
            // Fall through to keep node as-is
          } else {
            let new_index = folded.length()
            folded.push(DspNode::constant(result))
            index_map[i] = new_index
            changed = true
            continue
          }
        }
      }
    }
    // Keep node as-is, remapping inputs
    let new_input0 = if node.input0 >= 0 { index_map[node.input0] } else { -1 }
    let new_input1 = if node.input1 >= 0 { index_map[node.input1] } else { -1 }
    let new_index = folded.length()
    folded.push(
      DspNode(
        node.kind,
        new_input0,
        new_input1,
        node.value0,
        node.value1,
        node.value2,
        node.value3,
        node.waveform,
        node.filter_mode,
        node.delay_max_samples,
        node.delay_samples,
        node.seed,
      ),
    )
    index_map[i] = new_index
  }
  (folded, index_map, changed)
}

///|
/// Dead-node elimination pass: removes nodes not reachable from the output.
/// Returns (live_nodes, index_map, changed).
fn eliminate_dead(
  nodes : Array[DspNode],
) -> (Array[DspNode], FixedArray[Int], Bool) {
  let n = nodes.length()
  if n == 0 {
    return ([], FixedArray::make(0, -1), false)
  }
  // Find output node(s) and mark reachable nodes
  let reachable = FixedArray::make(n, false)
  // Walk backward from all output nodes
  for i = n - 1; i >= 0; i = i - 1 {
    match nodes[i].kind {
      Output | StereoOutput => mark_reachable(nodes, reachable, i)
      _ => ()
    }
  }
  // Check if anything was eliminated
  let mut all_reachable = true
  for i = 0; i < n; i = i + 1 {
    if !reachable[i] {
      all_reachable = false
      break
    }
  }
  if all_reachable {
    return (nodes, FixedArray::makei(n, fn(i) { i }), false)
  }
  // Build compacted array
  let index_map = FixedArray::make(n, -1)
  let live : Array[DspNode] = []
  for i = 0; i < n; i = i + 1 {
    if reachable[i] {
      index_map[i] = live.length()
      live.push(nodes[i])
    }
  }
  // Remap inputs in live nodes
  let remap = index_map
  let result : Array[DspNode] = []
  for i = 0; i < live.length(); i = i + 1 {
    let node = live[i]
    let new_input0 = if node.input0 >= 0 && node.input0 < remap.length() {
      remap[node.input0]
    } else {
      -1
    }
    let new_input1 = if node.input1 >= 0 && node.input1 < remap.length() {
      remap[node.input1]
    } else {
      -1
    }
    result.push(
      DspNode(
        node.kind,
        new_input0,
        new_input1,
        node.value0,
        node.value1,
        node.value2,
        node.value3,
        node.waveform,
        node.filter_mode,
        node.delay_max_samples,
        node.delay_samples,
        node.seed,
      ),
    )
  }
  (result, index_map, true)
}

///|
/// Iteratively mark a node and its inputs as reachable using a worklist.
fn mark_reachable(
  nodes : Array[DspNode],
  reachable : FixedArray[Bool],
  start : Int,
) -> Unit {
  let stack : Array[Int] = [start]
  while stack.length() > 0 {
    let index = stack.pop().unwrap()
    if index < 0 || index >= nodes.length() || reachable[index] {
      continue
    }
    reachable[index] = true
    let node = nodes[index]
    if node.input0 >= 0 {
      stack.push(node.input0)
    }
    if node.input1 >= 0 {
      stack.push(node.input1)
    }
  }
}

///|
/// Compose two index maps: for each original index, follow through
/// map1 then map2 to get the final index. If either step yields -1,
/// the result is -1.
fn compose_index_maps(
  map1 : FixedArray[Int],
  map2 : FixedArray[Int],
) -> FixedArray[Int] {
  FixedArray::makei(map1.length(), fn(i) {
    let mid = map1[i]
    if mid < 0 {
      -1
    } else {
      map2[mid]
    }
  })
}

///|
/// Optimize a DSP graph by repeatedly applying constant folding and
/// dead-node elimination until a fixpoint is reached.
///
/// Returns (optimized_nodes, index_map) where index_map maps each
/// original node index to its final optimized index (-1 if eliminated).
pub fn optimize_graph(
  nodes : Array[DspNode],
) -> (Array[DspNode], FixedArray[Int]) {
  let n = nodes.length()
  let mut current = nodes
  let mut total_map = FixedArray::makei(n, fn(i) { i })
  // Fixpoint loop
  for round = 0; round < n; round = round + 1 {
    let mut any_change = false
    // Constant folding pass
    let (folded, fold_map, fold_changed) = fold_constants(current)
    if fold_changed {
      total_map = compose_index_maps(total_map, fold_map)
      current = folded
      any_change = true
    }
    // Dead-node elimination pass
    let (live, elim_map, elim_changed) = eliminate_dead(current)
    if elim_changed {
      total_map = compose_index_maps(total_map, elim_map)
      current = live
      any_change = true
    }
    if !any_change {
      break
    }
  }
  (current, total_map)
}
