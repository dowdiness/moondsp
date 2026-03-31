# Mono/Stereo Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate ~1500 lines of structural duplication between `CompiledDsp` and `CompiledStereoDsp` (and their hotswap/topology variants) by unifying the field-identical structs via a shared `CompiledGraph` internal struct with newtype wrappers.

**Architecture:** Both `CompiledDsp` and `CompiledStereoDsp` have 27 identical fields. We create a single `CompiledGraph` struct, then define `type CompiledDsp CompiledGraph` and `type CompiledStereoDsp CompiledGraph` as newtype wrappers. All duplicated free functions that are logic-identical (A-type) collapse into single implementations on `CompiledGraph`. The `process` methods (B-type, differing only in mono vs stereo output buffers) remain separate on the wrapper types but share internal helpers where possible. Same pattern applies to hotswap and topology controller types.

**Tech Stack:** MoonBit

**Prerequisite:** Complete the helper-dedup-and-eq plan first.

---

## Strategy

The duplication analysis classified each pair as:
- **A) Identical** — same logic, different type names only → delete stereo variant, share implementation
- **B) Near-identical** — same logic, mono takes 1 output buffer, stereo takes 2 → keep separate methods, share helpers

| Category | Pairs | Lines saved |
|----------|-------|-------------|
| A-identical control functions (graph.mbt) | 6 pairs | ~200 lines |
| A-identical state copy (graph_topology_edit.mbt) | 1 pair | ~70 lines |
| Struct duplication (graph.mbt) | 1 pair (27 fields) | ~30 lines |
| Hotswap struct + methods (graph_hotswap.mbt) | ~5 pairs | ~200 lines |
| Topology struct + methods (graph_topology_edit.mbt) | ~5 pairs | ~150 lines |
| B-near-identical compile/process (graph.mbt) | 4 pairs | ~400 lines via shared helpers |

**Transformation pattern:**

Before (duplicated):
```moonbit
struct CompiledDsp { nodes : FixedArray[DspNode], ... }
struct CompiledStereoDsp { nodes : FixedArray[DspNode], ... }

fn apply_graph_gate_control(compiled : CompiledDsp, index : Int) -> Bool {
  // logic using compiled.nodes, compiled.index_map, etc.
}
fn apply_graph_gate_control_stereo(compiled : CompiledStereoDsp, index : Int) -> Bool {
  // identical logic using compiled.nodes, compiled.index_map, etc.
}
```

After (unified):
```moonbit
struct CompiledGraph { nodes : FixedArray[DspNode], ... }
type CompiledDsp CompiledGraph
type CompiledStereoDsp CompiledGraph

fn apply_graph_gate_control(graph : CompiledGraph, index : Int) -> Bool {
  // single implementation
}

pub fn CompiledDsp::apply_control(self : CompiledDsp, control : GraphControl) -> Bool {
  apply_graph_control(self.0, control)  // unwrap via .0
}
pub fn CompiledStereoDsp::apply_control(self : CompiledStereoDsp, control : GraphControl) -> Bool {
  apply_graph_control(self.0, control)  // same shared function
}
```

---

### Task 1: Create `CompiledGraph` struct and convert `CompiledDsp` to newtype

**Files:**
- Modify: `lib/graph.mbt`

This is the largest single task. It creates the shared struct and converts `CompiledDsp` from a direct struct to a newtype wrapper. All `CompiledDsp` method bodies must change field access from `self.field` to `self.0.field`.

- [ ] **Step 1: Create `CompiledGraph` struct**

At the top of `lib/graph.mbt` (replacing the current `CompiledDsp` struct definition at lines 141-172), define:

```moonbit
///|
/// Shared internal graph state for both mono and stereo compiled DSP graphs.
/// Both CompiledDsp and CompiledStereoDsp wrap this struct as newtypes.
struct CompiledGraph {
  compile_sample_rate : Double
  nodes : FixedArray[DspNode]
  index_map : FixedArray[Int]
  buffers : FixedArray[AudioBuffer]
  left_buffers : FixedArray[AudioBuffer]
  right_buffers : FixedArray[AudioBuffer]
  osc_states : FixedArray[Oscillator?]
  noise_states : FixedArray[Noise?]
  env_states : FixedArray[Adsr?]
  biquad_states : FixedArray[Biquad?]
  stereo_biquad_left_states : FixedArray[Biquad?]
  stereo_biquad_right_states : FixedArray[Biquad?]
  delay_states : FixedArray[DelayLine?]
  stereo_delay_left_states : FixedArray[DelayLine?]
  stereo_delay_right_states : FixedArray[DelayLine?]
  feedback_edges : FixedArray[(Int, Int, Int)]
  self_values : FixedArray[Double]
  self_left_values : FixedArray[Double]
  self_right_values : FixedArray[Double]
  self_enabled : FixedArray[Bool]
  back_edge_input0_source : FixedArray[Int]
  back_edge_input1_source : FixedArray[Int]
  sample_values : FixedArray[Double]
  left_sample_values : FixedArray[Double]
  right_sample_values : FixedArray[Double]
  pan_left_gains : FixedArray[Double]
  pan_right_gains : FixedArray[Double]
}
```

- [ ] **Step 2: Replace `CompiledDsp` struct with newtype**

Replace the old `struct CompiledDsp { ... }` (lines 141-172) with:

```moonbit
///|
/// Executable buffer-based DSP graph compiled from `DspNode`s.
type CompiledDsp CompiledGraph
```

- [ ] **Step 3: Update all `CompiledDsp` methods — field access `self.X` → `self.0.X`**

Every method on `CompiledDsp` (compile, compile_raw, compile_internal, process, process_feedback_graph, apply_control, apply_controls, gate_on, gate_off, set_param, compiled_buffer_capacity, compiled_index_for) and every free function taking `CompiledDsp` must update field access.

For methods: `self.nodes` → `self.0.nodes`, `self.index_map` → `self.0.index_map`, etc.

For free functions: `compiled.nodes` → `compiled.0.nodes`, etc.

**Construction also changes.** Anywhere a `CompiledDsp` is constructed with `{ compile_sample_rate: ..., nodes: ..., ... }`, it becomes `CompiledDsp({ compile_sample_rate: ..., nodes: ..., ... })` (wrapping a `CompiledGraph` value).

The affected functions in graph.mbt for `CompiledDsp`:
- `CompiledDsp::compile` (line ~604)
- `CompiledDsp::compile_raw` (line ~618)
- `CompiledDsp::compile_internal` (line ~664)
- `CompiledDsp::process` (line ~795)
- `CompiledDsp::process_feedback_graph` (line ~966)
- `CompiledDsp::apply_control` (line ~1917)
- `CompiledDsp::apply_controls` (line ~1938)
- `CompiledDsp::gate_on` (line ~2016)
- `CompiledDsp::gate_off` (line ~2026)
- `CompiledDsp::set_param` (line ~2036)
- `CompiledDsp::compiled_buffer_capacity` (line ~2448)
- `CompiledDsp::compiled_index_for` (line ~2455)
- `apply_graph_gate_control` (line ~2066)
- `apply_graph_param_control` (line ~2112)
- `valid_graph_control` (line ~2156)
- `valid_graph_gate_control` (line ~2196)
- `valid_graph_param_control` (line ~2215)
- `apply_runtime_param_side_effect` (line ~2595)

- [ ] **Step 4: Run `moon check`**

Run: `moon check 2>&1`
Fix any compilation errors. The most common issue will be missed `.0` insertions.

- [ ] **Step 5: Run `moon test`**

Run: `moon test 2>&1 | tail -1`
Expected: 264 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/graph.mbt
git commit -m "refactor: create CompiledGraph struct, convert CompiledDsp to newtype wrapper"
```

---

### Task 2: Convert `CompiledStereoDsp` to newtype wrapper

**Files:**
- Modify: `lib/graph.mbt`

Same pattern as Task 1 but for `CompiledStereoDsp`.

- [ ] **Step 1: Replace `CompiledStereoDsp` struct with newtype**

Replace the old `struct CompiledStereoDsp { ... }` (lines ~174-206) with:

```moonbit
///|
/// Executable terminal-stereo graph compiled from `DspNode`s.
type CompiledStereoDsp CompiledGraph
```

- [ ] **Step 2: Update all `CompiledStereoDsp` methods — field access `self.X` → `self.0.X`**

Same transformation as Task 1 Step 3, but for all stereo methods:
- `CompiledStereoDsp::compile` (line ~1260)
- `CompiledStereoDsp::compile_raw` (line ~1270)
- `CompiledStereoDsp::compile_internal` (line ~1280)
- `CompiledStereoDsp::process` (line ~1416)
- `CompiledStereoDsp::process_feedback_graph` (line ~1607)
- `CompiledStereoDsp::apply_control` (line ~1961)
- `CompiledStereoDsp::apply_controls` (line ~1980)
- `CompiledStereoDsp::gate_on` (line ~2036)
- `CompiledStereoDsp::gate_off` (line ~2046)
- `CompiledStereoDsp::set_param` (line ~2056)
- `CompiledStereoDsp::compiled_buffer_capacity` (line ~2458)
- `CompiledStereoDsp::compiled_index_for` (line ~2467)
- `apply_graph_gate_control_stereo` (line ~2089)
- `apply_graph_param_control_stereo` (line ~2133)
- `valid_graph_control_stereo` (line ~2176)
- `valid_graph_gate_control_stereo` (line ~2204)
- `valid_graph_param_control_stereo` (line ~2241)
- `apply_runtime_param_side_effect_stereo` (line ~2659)

Construction: `{ compile_sample_rate: ..., ... }` → `CompiledStereoDsp({ compile_sample_rate: ..., ... })`

- [ ] **Step 3: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/graph.mbt
git commit -m "refactor: convert CompiledStereoDsp to newtype wrapper around CompiledGraph"
```

---

### Task 3: Unify A-identical control and validation functions

**Files:**
- Modify: `lib/graph.mbt`

Now that both types wrap `CompiledGraph`, the 6 pairs of A-identical free functions can be collapsed. Each stereo variant is deleted and its mono counterpart is changed to take `CompiledGraph` instead of `CompiledDsp`. Both types' methods call the shared version via `.0`.

- [ ] **Step 1: Convert `apply_graph_gate_control` to take `CompiledGraph`**

Change:
```moonbit
fn apply_graph_gate_control(compiled : CompiledDsp, index : Int) -> Bool {
  let nodes = compiled.0.nodes
```
to:
```moonbit
fn apply_graph_gate_control(graph : CompiledGraph, index : Int) -> Bool {
  let nodes = graph.nodes
```

Remove all `.0` from field access inside this function since it now takes `CompiledGraph` directly.

- [ ] **Step 2: Delete `apply_graph_gate_control_stereo`**

Delete the entire function. It's identical to the mono version.

- [ ] **Step 3: Update callers of both functions to pass `.0`**

In `CompiledDsp::apply_control` and any other caller:
```moonbit
apply_graph_gate_control(self.0, control.node_index)
```

In `CompiledStereoDsp::apply_control`:
```moonbit
apply_graph_gate_control(self.0, control.node_index)  // was: apply_graph_gate_control_stereo
```

- [ ] **Step 4: Run `moon check`**

- [ ] **Step 5: Repeat Steps 1-4 for remaining 5 pairs**

Apply the same pattern to each pair:

| Mono function | Stereo function (delete) |
|--------------|--------------------------|
| `apply_graph_param_control` | `apply_graph_param_control_stereo` |
| `valid_graph_control` | `valid_graph_control_stereo` |
| `valid_graph_gate_control` | `valid_graph_gate_control_stereo` |
| `valid_graph_param_control` | `valid_graph_param_control_stereo` |
| `apply_runtime_param_side_effect` | `apply_runtime_param_side_effect_stereo` |

For each:
1. Change parameter type from `CompiledDsp` to `CompiledGraph`
2. Remove `.0` from field access inside the function
3. Delete the `_stereo` variant
4. Update all callers to pass `.0`
5. Run `moon check` after each pair

- [ ] **Step 6: Unify `compiled_buffer_capacity` and `compiled_index_for`**

Both `CompiledDsp` and `CompiledStereoDsp` have identical `compiled_buffer_capacity` and `compiled_index_for` methods. Create shared versions on `CompiledGraph`:

```moonbit
fn CompiledGraph::compiled_buffer_capacity(self : CompiledGraph) -> Int {
  self.nodes.length()
}

fn CompiledGraph::compiled_index_for(self : CompiledGraph, authoring_index : Int) -> Int {
  if authoring_index >= 0 && authoring_index < self.index_map.length() {
    self.index_map[authoring_index]
  } else {
    -1
  }
}
```

Update `CompiledDsp` and `CompiledStereoDsp` methods to delegate:
```moonbit
fn CompiledDsp::compiled_buffer_capacity(self : CompiledDsp) -> Int {
  self.0.compiled_buffer_capacity()
}
```

Or delete the wrapper methods and have callers use `.0.compiled_buffer_capacity()` directly (only used internally).

- [ ] **Step 7: Unify `apply_control`, `apply_controls`, `gate_on`, `gate_off`, `set_param`**

These method pairs on `CompiledDsp` and `CompiledStereoDsp` are identical. They call the now-shared free functions. Extract the logic into `CompiledGraph` methods:

```moonbit
fn CompiledGraph::apply_control_impl(self : CompiledGraph, control : GraphControl) -> Bool {
  if !valid_graph_control(self, control) { return false }
  match control.kind {
    GateOn => apply_graph_gate_control(self, control.node_index)
    GateOff => apply_graph_gate_control(self, control.node_index)
    SetParam => apply_graph_param_control(self, control.node_index, control.slot, control.value)
  }
}
```

Then both wrappers delegate:
```moonbit
pub fn CompiledDsp::apply_control(self : CompiledDsp, control : GraphControl) -> Bool {
  self.0.apply_control_impl(control)
}
pub fn CompiledStereoDsp::apply_control(self : CompiledStereoDsp, control : GraphControl) -> Bool {
  self.0.apply_control_impl(control)
}
```

Apply same pattern for `apply_controls`, `gate_on`, `gate_off`, `set_param`.

- [ ] **Step 8: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/graph.mbt
git commit -m "refactor: unify A-identical control/validation functions via CompiledGraph"
```

---

### Task 4: Unify hotswap types

**Files:**
- Modify: `lib/graph_hotswap.mbt`

`CompiledDspHotSwap` and `CompiledStereoDspHotSwap` differ in:
- Mono: 2 output buffers (old_output, new_output)
- Stereo: 4 output buffers (old_left, old_right, new_left, new_right)

Since the crossfade logic is identical, create a shared `HotSwapGraph` struct.

- [ ] **Step 1: Create shared `HotSwapGraph` struct**

```moonbit
///|
/// Shared hot-swap state for both mono and stereo compiled graphs.
struct HotSwapGraph {
  mut active : CompiledGraph
  mut pending : CompiledGraph?
  crossfade_samples : Int
  mut crossfade_position : Int
  old_output : AudioBuffer
  new_output : AudioBuffer
  old_left : AudioBuffer
  old_right : AudioBuffer
  new_left : AudioBuffer
  new_right : AudioBuffer
}
```

This struct carries both mono and stereo buffers. Mono uses `old_output`/`new_output`. Stereo uses `old_left`/`old_right`/`new_left`/`new_right`. Unused buffers are zero-length.

- [ ] **Step 2: Convert `CompiledDspHotSwap` and `CompiledStereoDspHotSwap` to newtype wrappers**

```moonbit
type CompiledDspHotSwap HotSwapGraph
type CompiledStereoDspHotSwap HotSwapGraph
```

- [ ] **Step 3: Unify `queue_swap` (A-identical)**

Create shared implementation on `HotSwapGraph`:
```moonbit
fn HotSwapGraph::queue_swap_impl(self : HotSwapGraph, new_graph : CompiledGraph) -> Bool {
  if self.pending is Some(_) { return false }
  if new_graph.nodes.length() != self.active.nodes.length() { return false }
  self.pending = Some(new_graph)
  true
}
```

Both wrappers delegate:
```moonbit
pub fn CompiledDspHotSwap::queue_swap(self : CompiledDspHotSwap, new_graph : CompiledDsp) -> Bool {
  self.0.queue_swap_impl(new_graph.0)
}
pub fn CompiledStereoDspHotSwap::queue_swap(self : CompiledStereoDspHotSwap, new_graph : CompiledStereoDsp) -> Bool {
  self.0.queue_swap_impl(new_graph.0)
}
```

- [ ] **Step 4: Unify `from_graph` constructors**

Mono constructs with mono buffers, stereo with stereo buffers. Both share the core initialization. Create a shared helper:

```moonbit
fn HotSwapGraph::new_impl(
  active : CompiledGraph,
  crossfade_samples : Int,
  old_output : AudioBuffer,
  new_output : AudioBuffer,
  old_left : AudioBuffer,
  old_right : AudioBuffer,
  new_left : AudioBuffer,
  new_right : AudioBuffer,
) -> HotSwapGraph {
  {
    active,
    pending: None,
    crossfade_samples: if crossfade_samples > 0 { crossfade_samples } else { 128 },
    crossfade_position: 0,
    old_output, new_output,
    old_left, old_right, new_left, new_right,
  }
}
```

Mono `from_graph` creates mono buffers + zero-length stereo buffers. Stereo does the opposite.

- [ ] **Step 5: Unify `apply_control` and `apply_controls` (A-identical)**

Both delegate to the active graph's `apply_control_impl`:
```moonbit
fn HotSwapGraph::apply_control_impl(self : HotSwapGraph, control : GraphControl) -> Bool {
  self.active.apply_control_impl(control)
}
```

- [ ] **Step 6: Update process methods**

The process methods differ only in output buffer passing. Keep separate methods on the wrapper types, but share the crossfade calculation logic.

- [ ] **Step 7: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/graph_hotswap.mbt
git commit -m "refactor: unify hotswap types via shared HotSwapGraph struct"
```

---

### Task 5: Unify topology controller types

**Files:**
- Modify: `lib/graph_topology_edit.mbt`

`CompiledDspTopologyController` and `CompiledStereoDspTopologyController` differ only in their `hot_swap` field type. With unified hotswap types, we can create a shared `TopologyGraph` struct.

- [ ] **Step 1: Create shared `TopologyGraph` struct**

```moonbit
struct TopologyGraph {
  mut authoring_nodes : Array[DspNode]
  compile_sample_rate : Double
  compile_block_size : Int
  hot_swap : HotSwapGraph
}
```

- [ ] **Step 2: Convert both controller types to newtype wrappers**

```moonbit
type CompiledDspTopologyController TopologyGraph
type CompiledStereoDspTopologyController TopologyGraph
```

- [ ] **Step 3: Unify `copy_compiled_dsp_state` / `copy_compiled_stereo_dsp_state` (A-identical)**

Both functions are logic-identical. Create single version:
```moonbit
fn copy_compiled_graph_state(old_graph : CompiledGraph, new_graph : CompiledGraph) -> Unit {
  // shared implementation
}
```

Delete `copy_compiled_stereo_dsp_state`.

- [ ] **Step 4: Unify shared methods**

`apply_control`, `apply_controls`, `queue_topology_edit`, `queue_topology_edits` can share implementations through `TopologyGraph` methods.

The `from_nodes` constructors differ in calling `CompiledDsp::compile_raw` vs `CompiledStereoDsp::compile_raw` — these stay separate on the wrapper types but delegate to a shared `TopologyGraph::new_impl`.

The `process` methods stay separate (mono vs stereo output buffers).

- [ ] **Step 5: Run `moon check` and `moon test`**

Run: `moon check 2>&1 && moon test 2>&1 | tail -1`
Expected: no errors, 264 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/graph_topology_edit.mbt
git commit -m "refactor: unify topology controller types via shared TopologyGraph struct"
```

---

### Task 6: Update browser packages for newtype access

**Files:**
- Modify: `browser/browser.mbt` (if any direct field access to compiled graph types)
- Modify: `browser_test/main.mbt` (same check)

Since `CompiledDsp` and `CompiledStereoDsp` are opaque types (no public field access), browser code only uses public methods (`compile`, `process`, `apply_controls`, etc.). These methods' signatures are unchanged. This task should only need a `moon check` verification.

- [ ] **Step 1: Verify browser packages compile**

Run: `moon check 2>&1`
Expected: no errors. If there are errors, they indicate a method signature changed — fix the caller.

- [ ] **Step 2: Run full test suite**

Run: `moon test 2>&1 | tail -1`
Expected: 264 tests pass.

---

### Task 7: Final verification and cleanup

- [ ] **Step 1: Run full test suite**

Run: `moon test 2>&1`
Expected: 264 tests pass, zero warnings.

- [ ] **Step 2: Run JS build**

Run: `moon build --target js 2>&1`
Expected: build succeeds.

- [ ] **Step 3: Regenerate interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 4: Review .mbti changes**

Run: `git diff -- '*.mbti'`
Expected: `CompiledDsp` and `CompiledStereoDsp` remain as opaque types. Public API methods are unchanged. `CompiledGraph` does NOT appear in the .mbti (it's internal). `HotSwapGraph` and `TopologyGraph` do NOT appear (internal).

- [ ] **Step 5: Count lines saved**

Run: `wc -l lib/graph.mbt lib/graph_hotswap.mbt lib/graph_topology_edit.mbt`
Expected: significant reduction from the original 6242 total lines.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "refactor: complete mono/stereo unification via shared graph structs

Reduce graph.mbt + graph_hotswap.mbt + graph_topology_edit.mbt from
6242 lines by unifying CompiledDsp/CompiledStereoDsp into CompiledGraph
newtype wrappers. All A-identical function pairs collapsed into single
implementations. Public API unchanged."
```
