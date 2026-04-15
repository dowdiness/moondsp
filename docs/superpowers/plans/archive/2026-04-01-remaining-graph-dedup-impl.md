# Remaining Graph Dedup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate remaining mono/stereo code duplication across 7 items, saving ~490 lines from `lib/graph.mbt`, `lib/graph_hotswap.mbt`, and `lib/graph_topology_edit.mbt`.

**Architecture:** Pure refactoring — extract shared implementations, make mono/stereo wrappers thin. No new public API, no new tests (271 existing tests are the regression suite). Benchmarks in `lib/graph_benchmark.mbt` must remain comparable.

**Tech Stack:** MoonBit

**Spec:** `docs/superpowers/plans/2026-04-01-remaining-graph-dedup.md`

**Verification after every task:**
```bash
moon check && moon test && moon bench --release -p lib -f graph_benchmark.mbt
```

---

### Task 1: Unify `compile_internal` (HIGH — ~130 lines saved)

**Files:**
- Modify: `lib/graph.mbt:660-788` (`CompiledDsp::compile_internal`)
- Modify: `lib/graph.mbt:1284-1415` (`CompiledStereoDsp::compile_internal`)

**Problem:** Both functions are ~130 lines, nearly identical. Differences:
1. Mono calls `mono_compile_plan`, stereo calls `stereo_compile_plan`
2. Mono validates with `valid_terminal_mono_shapes` / `valid_feedback_terminal_mono_graph`, stereo uses `valid_terminal_stereo_shapes` / `valid_feedback_terminal_stereo_graph`
3. Mono wraps result in `CompiledDsp(...)`, stereo wraps in `CompiledStereoDsp(...)`
4. Mono inlines `self_left_values`/`self_right_values` in the struct literal; stereo pre-declares them

- [ ] **Step 1: Read both functions and diff them**

Read `lib/graph.mbt` lines 660-788 (mono) and 1284-1415 (stereo). Identify every line that differs.

- [ ] **Step 2: Extract `CompiledGraph::compile_graph_impl`**

Create a new function on `CompiledGraph` that takes callbacks for the differing parts:

```moonbit
fn CompiledGraph::compile_graph_impl(
  nodes : Array[DspNode],
  context : DspContext,
  original_count : Int,
  opt_map : FixedArray[Int],
  compile_plan_fn : (Array[DspNode], DspContext) -> (FixedArray[Int], FixedArray[(Int, Int, Int)])?,
  valid_terminal_fn : (FixedArray[DspNode]) -> Bool,
  valid_feedback_terminal_fn : (FixedArray[DspNode], FixedArray[(Int, Int, Int)]) -> Bool,
) -> CompiledGraph?
```

The body is the shared code from either `compile_internal`, returning `Some(CompiledGraph { ... })` or `None`. All state allocation (buffers, osc_states, etc.) is identical — the only differences are the three callbacks and the struct literal field order for `self_left_values`/`self_right_values` (normalize to the same order).

- [ ] **Step 3: Run `moon check`**

Expected: No errors.

- [ ] **Step 4: Rewrite `CompiledDsp::compile_internal` as thin wrapper**

Replace the body with:
```moonbit
CompiledGraph::compile_graph_impl(
  nodes, context, original_count, opt_map,
  fn(n, c) { mono_compile_plan(n, c) },
  valid_terminal_mono_shapes,
  valid_feedback_terminal_mono_graph,
).map(CompiledDsp(_))
```

Note: The callback signatures must match exactly. `mono_compile_plan` returns `(FixedArray[Int], FixedArray[(Int, Int, Int)])?` — verify this.

- [ ] **Step 5: Run `moon check`**

Expected: No errors.

- [ ] **Step 6: Rewrite `CompiledStereoDsp::compile_internal` as thin wrapper**

Same pattern but with stereo callbacks:
```moonbit
CompiledGraph::compile_graph_impl(
  nodes, context, original_count, opt_map,
  fn(n, c) { stereo_compile_plan(n, c) },
  valid_terminal_stereo_shapes,
  valid_feedback_terminal_stereo_graph,
).map(CompiledStereoDsp(_))
```

- [ ] **Step 7: Run `moon check`**

Expected: No errors.

- [ ] **Step 8: Run full test suite**

Run: `moon test`
Expected: 271 tests pass.

- [ ] **Step 9: Run benchmarks**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All benchmarks run with comparable times. Compile benchmarks may differ slightly due to the extra closure indirection.

- [ ] **Step 10: Commit**

```bash
git add lib/graph.mbt
git commit -m "refactor: unify compile_internal via CompiledGraph::compile_graph_impl"
```

---

### Task 2: Unify `process_feedback_graph` (HIGH — ~280 lines saved)

**Files:**
- Modify: `lib/graph.mbt:968` (`CompiledDsp::process_feedback_graph`)
- Modify: `lib/graph.mbt:1617` (`CompiledStereoDsp::process_feedback_graph`)

**Problem:** Both ~280-line methods have identical structure. The inner per-node logic for all 16 shared node kinds is letter-for-letter identical. Only the terminal case differs:
- Mono: `Output => copy to sample_values[node_index] and buffer`, `StereoOutput => ()`
- Stereo: `StereoOutput => copy to left/right sample values and buffers`, `Output => ()`

Since validation guarantees a mono graph never has StereoOutput and vice versa, a unified `Output | StereoOutput` arm can handle both.

- [ ] **Step 1: Read both functions**

Read `CompiledDsp::process_feedback_graph` (starts ~line 968) and `CompiledStereoDsp::process_feedback_graph` (starts ~line 1617). Diff them to identify every difference.

- [ ] **Step 2: Extract `CompiledGraph::process_feedback_graph_impl`**

Move the shared body to a new method on `CompiledGraph`. For the terminal node case, use a unified match:

```moonbit
Output => {
  let value = self_register_input_sample(...)
  sample_values[node_index] = value
  self.buffers[node_index].set(sample_index, value)
}
StereoOutput => {
  // copy left/right values to stereo buffers
  let left_val = ...
  let right_val = ...
  left_sv[node_index] = left_val
  right_sv[node_index] = right_val
  self.left_buffers[node_index].set(sample_index, left_val)
  self.right_buffers[node_index].set(sample_index, right_val)
}
```

Both arms are always present. The "unreachable" one (e.g., StereoOutput in a mono graph) simply never matches because validation excluded it — no runtime cost.

The final output copy after the sample loop needs to handle both mono and stereo. Use the last node's kind to determine which copy to perform:
- If last node is `Output`: copy `self.buffers[last]` to the mono output
- If last node is `StereoOutput`: copy `self.left_buffers[last]` and `self.right_buffers[last]` to stereo outputs

Pass the output buffers as parameters: `mono_output : AudioBuffer?, left_output : AudioBuffer?, right_output : AudioBuffer?`

Or simpler: pass all three as `AudioBuffer` with a flag/enum. Choose the cleanest approach that compiles.

- [ ] **Step 3: Run `moon check`**

- [ ] **Step 4: Rewrite `CompiledDsp::process_feedback_graph` to call the shared impl**

```moonbit
fn CompiledDsp::process_feedback_graph(
  self : CompiledDsp,
  context : DspContext,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  self.0.process_feedback_graph_impl(
    context, sample_count,
    mono_output=output, left_output=None, right_output=None,
  )
}
```

Adjust parameter passing to match the signature you chose in Step 2.

- [ ] **Step 5: Run `moon check`**

- [ ] **Step 6: Rewrite `CompiledStereoDsp::process_feedback_graph` to call the shared impl**

```moonbit
fn CompiledStereoDsp::process_feedback_graph(
  self : CompiledStereoDsp,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  self.0.process_feedback_graph_impl(
    context, sample_count,
    mono_output=None, left_output=Some(left_output), right_output=Some(right_output),
  )
}
```

- [ ] **Step 7: Run `moon check`**

- [ ] **Step 8: Delete the old mono and stereo process_feedback_graph bodies**

They should now be thin wrappers. Remove any dead code left behind.

- [ ] **Step 9: Run full test suite**

Run: `moon test`
Expected: 271 tests pass.

- [ ] **Step 10: Run benchmarks**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: Process and feedback_voice benchmarks should show comparable times. This is the critical check — the feedback path is the most expensive codepath.

- [ ] **Step 11: Commit**

```bash
git add lib/graph.mbt
git commit -m "refactor: unify process_feedback_graph via CompiledGraph::process_feedback_graph_impl"
```

---

### Task 3: Unify `valid_node_inputs` (MEDIUM — ~50 lines saved)

**Files:**
- Modify: `lib/graph.mbt:2208-2261` (`valid_node_inputs`)
- Modify: `lib/graph.mbt:2264-2317` (`valid_stereo_node_inputs`)

**Problem:** 21 of 22 match arms are identical. Only difference:
- `valid_node_inputs`: `Output => valid_reference(...)`, `StereoOutput => false`
- `valid_stereo_node_inputs`: `Output => false`, `StereoOutput => valid_reference(...)`

- [ ] **Step 1: Create `valid_any_node_inputs`**

```moonbit
fn valid_any_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
  output_kind : DspNodeKind,
) -> Bool {
  match node.kind {
    // ... all 20 shared arms unchanged ...
    Output =>
      if output_kind is Output {
        valid_reference(node.input0, node_count)
      } else {
        false
      }
    StereoOutput =>
      if output_kind is StereoOutput {
        valid_reference(node.input0, node_count)
      } else {
        false
      }
  }
}
```

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Rewrite `valid_node_inputs` and `valid_stereo_node_inputs` as wrappers**

```moonbit
fn valid_node_inputs(node : DspNode, node_count : Int, sample_rate : Double) -> Bool {
  valid_any_node_inputs(node, node_count, sample_rate, DspNodeKind::Output)
}

fn valid_stereo_node_inputs(node : DspNode, node_count : Int, sample_rate : Double) -> Bool {
  valid_any_node_inputs(node, node_count, sample_rate, DspNodeKind::StereoOutput)
}
```

- [ ] **Step 4: Run `moon check`**

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: 271 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/graph.mbt
git commit -m "refactor: unify valid_node_inputs pair via output_kind parameter"
```

---

### Task 4: Unify `from_nodes` topology constructors (LOW — ~15 lines saved)

**Files:**
- Modify: `lib/graph_topology_edit.mbt:230-248` (`CompiledDspTopologyController::from_nodes`)
- Modify: `lib/graph_topology_edit.mbt:985-1006` (`CompiledStereoDspTopologyController::from_nodes`)

**Problem:** Both are structurally identical: compile_raw → from_graph → build TopologyGraph. Only difference is which compile/hotswap types.

- [ ] **Step 1: Extract `TopologyGraph::new_from_nodes_impl`**

```moonbit
fn TopologyGraph::new_from_nodes_impl(
  nodes : Array[DspNode],
  context : DspContext,
  crossfade_samples : Int,
  compile_fn : (Array[DspNode], DspContext) -> CompiledGraph?,
) -> TopologyGraph? {
  let compiled = match compile_fn(nodes, context) {
    Some(compiled) => compiled
    None => return None
  }
  let clamped_crossfade = if crossfade_samples > 0 { crossfade_samples } else { 0 }
  let capacity = compiled.compiled_buffer_capacity()
  Some({
    authoring_nodes: nodes.copy(),
    compile_sample_rate: context.sample_rate(),
    compile_block_size: context.block_size(),
    hot_swap: {
      active: compiled,
      pending: None,
      crossfade_samples: clamped_crossfade,
      crossfade_position: 0,
      old_output: AudioBuffer::filled(capacity),
      new_output: AudioBuffer::filled(capacity),
      old_left: AudioBuffer::filled(0),
      old_right: AudioBuffer::filled(0),
      new_left: AudioBuffer::filled(0),
      new_right: AudioBuffer::filled(0),
    },
  })
}
```

Note: The mono `from_nodes` goes through `CompiledDsp::compile_raw` → `CompiledDspHotSwap::from_graph`, but the shared impl should construct the `HotSwapGraph` directly from `CompiledGraph`. Check whether the mono vs stereo from_graph allocates different buffer sizes (mono: `old_output`/`new_output` at capacity, stereo: `old_left`/`old_right`/`new_left`/`new_right` at capacity). If they differ, the impl needs a `is_stereo` flag or separate buffer allocation.

- [ ] **Step 2: Run `moon check`**

- [ ] **Step 3: Rewrite both `from_nodes` as wrappers**

Mono:
```moonbit
pub fn CompiledDspTopologyController::from_nodes(
  nodes : Array[DspNode], context : DspContext, crossfade_samples? : Int = 0,
) -> CompiledDspTopologyController? {
  TopologyGraph::new_from_nodes_impl(
    nodes, context, crossfade_samples,
    fn(n, c) { CompiledDsp::compile_raw(n, c).map(fn(d) { d.0 }) },
  ).map(CompiledDspTopologyController(_))
}
```

Stereo:
```moonbit
pub fn CompiledStereoDspTopologyController::from_nodes(
  nodes : Array[DspNode], context : DspContext, crossfade_samples? : Int = 0,
) -> CompiledStereoDspTopologyController? {
  TopologyGraph::new_from_nodes_impl(
    nodes, context, crossfade_samples,
    fn(n, c) { CompiledStereoDsp::compile_raw(n, c).map(fn(d) { d.0 }) },
  ).map(CompiledStereoDspTopologyController(_))
}
```

- [ ] **Step 4: Run `moon check` and `moon test`**

- [ ] **Step 5: Commit**

```bash
git add lib/graph_topology_edit.mbt
git commit -m "refactor: unify from_nodes topology constructors via new_from_nodes_impl"
```

---

### Task 5: Extract `apply_crossfade_sample` helper (LOW — ~10 lines saved)

**Files:**
- Modify: `lib/graph_hotswap.mbt:183-217` (`CompiledDspHotSwap::mix_hot_swap_outputs`)
- Modify: `lib/graph_hotswap.mbt:319-366` (`CompiledStereoDspHotSwap::mix_hot_swap_outputs`)

**Problem:** The crossfade gain calculation (progress, old_gain, new_gain, position increment) is identical in both. Mono writes 1 channel, stereo writes 2.

- [ ] **Step 1: Extract `apply_crossfade_sample`**

```moonbit
fn apply_crossfade_sample(
  old_val : Double,
  new_val : Double,
  old_gain : Double,
  new_gain : Double,
) -> Double {
  old_val * old_gain + new_val * new_gain
}
```

- [ ] **Step 2: Replace inline math in both `mix_hot_swap_outputs`**

In mono (line 206-210):
```moonbit
output.set(index, apply_crossfade_sample(
  self.0.old_output.get(index), self.0.new_output.get(index), old_gain, new_gain,
))
```

In stereo (lines 347-356):
```moonbit
left_output.set(index, apply_crossfade_sample(
  self.0.old_left.get(index), self.0.new_left.get(index), old_gain, new_gain,
))
right_output.set(index, apply_crossfade_sample(
  self.0.old_right.get(index), self.0.new_right.get(index), old_gain, new_gain,
))
```

- [ ] **Step 3: Run `moon check` and `moon test`**

- [ ] **Step 4: Commit**

```bash
git add lib/graph_hotswap.mbt
git commit -m "refactor: extract apply_crossfade_sample helper in hot-swap"
```

---

### Task 6: Unify `from_graph` crossfade clamp (LOW — ~5 lines saved)

**Files:**
- Modify: `lib/graph_hotswap.mbt:99-121` (`CompiledDspHotSwap::from_graph`)
- Modify: `lib/graph_hotswap.mbt:221-243` (`CompiledStereoDspHotSwap::from_graph`)

**Problem:** Both `from_graph` constructors have identical crossfade clamping logic:
```moonbit
let clamped_crossfade = if crossfade_samples > 0 { crossfade_samples } else { 0 }
```

Note: If Task 4 already moved this logic into `TopologyGraph::new_from_nodes_impl`, the `from_graph` functions may still exist for direct use. Check if the clamp can be moved to `HotSwapGraph` as a shared constructor or helper.

- [ ] **Step 1: Check if `from_graph` is still called directly (outside `from_nodes`)**

Search for all call sites of `CompiledDspHotSwap::from_graph` and `CompiledStereoDspHotSwap::from_graph`. If they are only called from `from_nodes`, the clamp is already handled by Task 4 and this task becomes a no-op.

If they are still called directly (e.g., from benchmarks or tests), extract a shared `clamp_crossfade_samples` helper:

```moonbit
fn clamp_crossfade_samples(crossfade_samples : Int) -> Int {
  if crossfade_samples > 0 { crossfade_samples } else { 0 }
}
```

- [ ] **Step 2: Replace inline clamp in both `from_graph`**

- [ ] **Step 3: Run `moon check` and `moon test`**

- [ ] **Step 4: Commit**

```bash
git add lib/graph_hotswap.mbt
git commit -m "refactor: extract clamp_crossfade_samples helper"
```

---

### Task 7: Simplify `compile_mono_graph` / `compile_stereo_graph` (LOW — ~5 lines saved)

**Files:**
- Modify: `lib/graph_topology_edit.mbt:1110-1130`

**Problem:** Both functions are just `match ... { Some(c) => Some(c.0) None => None }` — this is `Option::map`.

- [ ] **Step 1: Replace both functions**

```moonbit
fn compile_mono_graph(nodes : Array[DspNode], context : DspContext) -> CompiledGraph? {
  CompiledDsp::compile_raw(nodes, context).map(fn(c) { c.0 })
}

fn compile_stereo_graph(nodes : Array[DspNode], context : DspContext) -> CompiledGraph? {
  CompiledStereoDsp::compile_raw(nodes, context).map(fn(c) { c.0 })
}
```

- [ ] **Step 2: Run `moon check` and `moon test`**

- [ ] **Step 3: Commit**

```bash
git add lib/graph_topology_edit.mbt
git commit -m "refactor: simplify compile_mono_graph/compile_stereo_graph with Option::map"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

Run: `moon test`
Expected: 271 tests pass.

- [ ] **Step 2: Run full benchmark suite**

Run: `moon bench --release -p lib -f graph_benchmark.mbt`
Expected: All benchmarks pass with comparable times to baseline.

- [ ] **Step 3: Regenerate interfaces and format**

Run: `moon info && moon fmt`
Expected: No changes to .mbti files (all changes are internal).

- [ ] **Step 4: Check line count reduction**

Run: `wc -l lib/graph.mbt lib/graph_hotswap.mbt lib/graph_topology_edit.mbt`
Expected: Significant reduction from the baseline of 5848 total lines.

- [ ] **Step 5: Commit any formatting changes**

```bash
git add -A && git status
# If changes: git commit -m "chore: format after graph dedup"
```
