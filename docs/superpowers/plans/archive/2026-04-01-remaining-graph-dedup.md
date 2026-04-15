# Remaining Graph Duplication — Research Findings

> **Source:** Code reuse + code quality review of `feature/mono-stereo-unification` branch (2026-04-01).
> These are the remaining mono/stereo duplication opportunities that were too large
> for the initial unification pass.

**Tech Stack:** MoonBit

---

## HIGH Priority

### 1. Unify `compile_internal` (~130 lines each)

**Files:** `lib/graph.mbt` — `CompiledDsp::compile_internal` (~line 650) and `CompiledStereoDsp::compile_internal` (~line 1274)

**Problem:** Both functions are nearly identical (~130 lines each). They share every line from `topo_map` construction through the feedback-edge loop and the final struct literal. Differences:
- Which `compile_plan` function is called (mono vs stereo)
- Which shape validator is called
- The wrapping constructor (`CompiledDsp(…)` vs `CompiledStereoDsp(…)`)
- Mono initialises `self_left_values`/`self_right_values` inline; stereo pre-declares them

**Approach:** Extract a `compile_graph_impl` function that takes `compile_plan_fn` and `validate_shapes_fn` callbacks and returns `CompiledGraph?`. Both `compile_internal` functions call it and wrap the result.

**Lines saved:** ~130

---

### 2. Unify `process_feedback_graph` (~280 lines each)

**Files:** `lib/graph.mbt` — `CompiledDsp::process_feedback_graph` (~line 958) and `CompiledStereoDsp::process_feedback_graph` (~line 1607)

**Problem:** These ~280-line methods contain the same structure: clear buffers, prepare biquads, zero scratch arrays, pre-compute pan gains, then a double loop. The inner per-node logic for all 16 shared node kinds is letter-for-letter identical. Only the terminal case differs:
- Mono: `Output` passes through, `StereoOutput => ()`
- Stereo: `StereoOutput` passes through, `Output => ()`

**Approach:** Move to `CompiledGraph::process_feedback_graph_impl`. Since a mono graph never has `StereoOutput` and vice versa (validation guarantees this), a single `match node.kind { Output | StereoOutput => … }` arm with uniform pass-through semantics works. The only remaining difference is the final output copy (mono: 1 buffer, stereo: 2 buffers) — pass the output write as a callback or handle after the shared loop.

**Lines saved:** ~280

---

## MEDIUM Priority

### 3. Unify `valid_node_inputs` / `valid_stereo_node_inputs` (~50 lines each)

**Files:** `lib/graph.mbt` — `valid_node_inputs` (~line 2198) and `valid_stereo_node_inputs` (~line 2253)

**Problem:** 21 out of 22 match arms are identical. The only difference is `Output`/`StereoOutput` arms:
- `valid_node_inputs`: `Output => valid_reference(…)`, `StereoOutput => false`
- `valid_stereo_node_inputs`: `Output => false`, `StereoOutput => valid_reference(…)`

**Approach:** Single `valid_any_node_inputs(node, node_count, sample_rate, output_kind : DspNodeKind)` that takes the allowed output kind as a parameter.

**Lines saved:** ~50

---

## LOW Priority

### 4. `from_nodes` topology constructors (~15 lines each)

**Files:** `lib/graph_topology_edit.mbt` — `CompiledDspTopologyController::from_nodes` (~line 230) and `CompiledStereoDspTopologyController::from_nodes` (~line 979)

**Problem:** Structurally identical: compile → from_graph → build TopologyGraph. Only difference is which compile/hotswap types are used.

**Approach:** `TopologyGraph::new_impl(compiled : CompiledGraph, nodes, context, crossfade_samples)` shared constructor.

### 5. `mix_hot_swap_outputs` crossfade gain

**Files:** `lib/graph_hotswap.mbt` — `CompiledDspHotSwap::mix_hot_swap_outputs` (~line 182) and `CompiledStereoDspHotSwap::mix_hot_swap_outputs` (~line 318)

**Problem:** Crossfade loop body (progress calculation, gain computation, position increment) is identical. Mono writes 1 channel, stereo writes 2.

**Approach:** Extract `fn apply_crossfade_sample(old, new_val, old_gain, new_gain) -> Double` helper.

### 6. `from_graph` crossfade clamp

**Files:** `lib/graph_hotswap.mbt` — both `from_graph` constructors (~line 98, ~line 220)

**Problem:** Identical crossfade clamping logic duplicated.

**Approach:** Move to shared helper or `HotSwapGraph::new_impl` constructor.

### 7. `compile_mono_graph` / `compile_stereo_graph` simplification

**Files:** `lib/graph_topology_edit.mbt` (~line 1104, ~line 1116)

**Problem:** Both are `match … { Some(compiled) => Some(compiled.0) None => None }` — this is `Option::map`.

**Approach:** Use `Option::map(fn(c) { c.0 })` if available.

---

## Estimated Total Savings

| Item | Lines saved |
|------|-------------|
| `compile_internal` | ~130 |
| `process_feedback_graph` | ~280 |
| `valid_node_inputs` | ~50 |
| Low-priority items | ~30 |
| **Total** | **~490** |

Combined with the 334 lines already saved in the initial unification, the full dedup would remove ~824 lines from the original 6242.
