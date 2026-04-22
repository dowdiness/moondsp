# Control-Binding Orphan Detection — Design Spec

**Date:** 2026-04-18
**Status:** Draft — awaiting user review
**Related:** PR #8 (orphan-ADSR detection) — this spec applies the same failure-mode fix to the sibling silent footgun.

## Goal

Make it impossible to construct a `ControlBindingMap` whose bindings point at nodes eliminated by `optimize_graph`. Today such bindings silently no-op at runtime (`CompiledGraph.index_map[i] = -1` → `set_param` returns without effect). After this change, `ControlBindingBuilder::build` rejects them up front with a specific error.

## Motivation

Current `ControlBindingBuilder::build(template)` validates three properties against the raw template: `node_index` bounds, slot-vs-kind compatibility, and duplicate keys. It does **not** consider optimization. If a bound node is dead-code-eliminated, every `resolve_controls` call emits a `GraphControl::set_param` that the compiled graph silently drops. Audio looks plausible (no errors, no crashes) but control knobs do nothing.

PR #8 shipped this exact fix for orphan ADSR nodes. Memory entry `project_phase5_todos.md` captured the sibling case: control-binding orphans. Failure mode identical (silent no-op via `index_map[i] < 0`); validation site different.

## Non-goals

- **`VoicePool::set_template` binding staleness is out of scope.** After a successful template swap, a `ControlBindingMap` validated against the *old* template remains proven-valid by its type invariant but silently retargets or no-ops against the new template. This is a distinct footgun with its own design space (identity-check at apply, `BoundVoicePool` composite, atomic `set_template_with_bindings`) and deserves its own brainstorm. A TODO is captured in memory; a docstring warning is added to `ControlBindingMap` in this PR.
- **`VoiceSlot.template_snapshot` deduplication is out of scope.** It exists for note_off correctness (needs the template that was active at note_on). Could later redirect through `CompiledTemplate`; not part of this fix.
- **Raw `GraphControl::set_param` callers who bypass `ControlBindingMap` remain at risk.** This PR protects the binding-construction path only. Direct-GraphControl callers are a separate concern.
- **Exposing public `orphan_binding_count` is out of scope.** PR #8 needed `orphan_adsr_count` public because `VoicePool` lives in a different package from `CompiledDsp`. `ControlBindingBuilder::build` lives in the same package as `CompiledTemplate`, so the orphan check happens inline — no public query method is needed.

## Design

### Core insight

Binding validation needs two things: the **template snapshot** (for slot-vs-kind lookups and bounds) and the **optimization result** (for liveness). Both are topology concerns, not runtime concerns — no buffers, no envelope state, no feedback registers needed. `CompiledDsp` today conflates topology with runtime state, which is why `orphan_adsr_count(template)` needs the template passed back in (the compiled artifact discarded its source).

Further: `optimize_graph` takes `Array[DspNode]` only — no `DspContext`. Topology (which nodes survive) is a pure function of the template. So the topology artifact needs no sample-rate, no block-size, and cannot fail — `analyze` is infallible.

### New artifact: `CompiledTemplate`

New file `graph/compiled_template.mbt`. ~35 lines.

```moonbit
/// Topology artifact: template snapshot plus its optimize_graph result.
/// Holds the minimum information needed to answer post-optimization
/// questions ("is this node live?", "how many ADSRs were eliminated?")
/// without allocating runtime state.
pub struct CompiledTemplate {
  priv template : Array[DspNode]      // defensive copy at analyze time
  priv index_map : FixedArray[Int]     // from optimize_graph
}

/// Infallible — optimize_graph always returns a valid topology.
pub fn CompiledTemplate::analyze(
  template : Array[DspNode]
) -> CompiledTemplate

/// Count of Adsr nodes in the authoring template whose compiled index is < 0
/// (eliminated as dead code). Parameterless — kills the template-arg leak
/// Codex flagged against the PR #8 shape.
pub fn CompiledTemplate::orphan_adsr_count(self) -> Int

// Package-private — only graph/ callers need these.
fn CompiledTemplate::is_node_live(self, index : Int) -> Bool
fn CompiledTemplate::node_at(self, index : Int) -> DspNode    // for slot check
fn CompiledTemplate::length(self) -> Int                       // for bounds check
```

**Why defensive copy in `analyze`:** `optimize_graph` does not mutate its input today, but callers can mutate the array afterwards. A `CompiledTemplate` that aliased the caller's array would break its own invariants on any post-analysis mutation. Single copy at analyze time, then frozen.

**Why `analyze` is infallible:** `optimize_graph` returns `(Array[DspNode], FixedArray[Int])` unconditionally. No failure mode to propagate.

### `ControlBindingBuilder::build` — new signature

```moonbit
// Before:
pub fn ControlBindingBuilder::build(
  self, template : Array[DspNode]
) -> Result[ControlBindingMap, ControlBindingError]

// After:
pub fn ControlBindingBuilder::build(
  self, compiled_template : CompiledTemplate
) -> Result[ControlBindingMap, ControlBindingError]
```

Validation order per binding (first failure returned; mirrors the current per-iteration loop):
1. `node_index` in `[0, compiled_template.length())` — else `InvalidNodeIndex`
2. `node_accepts_slot(compiled_template.node_at(i), slot)` — else `InvalidSlotForNode`
3. `compiled_template.is_node_live(i)` — else `OrphanBinding(key, i)` (NEW)
4. Key not in `seen_keys` — else `DuplicateKey`

Rationale: bounds first because out-of-bounds makes the slot check meaningless; slot before orphan because "wrong slot for this kind" is a more specific authoring error than "node got eliminated"; orphan before duplicate because duplicate is the most caller-facing typo-like mistake and the least useful to report when the bindings targeting are structurally wrong.

### New error variant

```moonbit
pub(all) enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, GraphParamSlot)
  DuplicateKey(String)
  OrphanBinding(String, Int)   // NEW — (key, node_index)
}
```

**Why `(String, Int)` not bare `Int`:** multiple bindings can target the same node. The key is what the user wrote; the node_index is what the optimizer eliminated. Both are load-bearing for diagnosis.

### `CompiledDsp` changes

Remove the public `CompiledDsp::orphan_adsr_count(template)` method added in PR #8. It is replaced by `CompiledTemplate::orphan_adsr_count()` (parameterless). No other public API on `CompiledDsp` changes.

### `VoicePool` migration

`VoicePool::new` and `VoicePool::set_template` replace their current shape:

```moonbit
// Before (PR #8):
let test_compile = CompiledDsp::compile(template, context)?
if test_compile.orphan_adsr_count(template) > 0 { return None }

// After:
let ct = CompiledTemplate::analyze(template)
if ct.orphan_adsr_count() > 0 { return None }
// Still need to verify compile succeeds for other invariants (feedback cycles etc.):
CompiledDsp::compile(template, context)?  // result discarded
```

Performance note: `CompiledTemplate::analyze` skips all buffer and state allocation, which is a small win for pool creation and `set_template`. The subsequent compile-then-discard preserves the current "compile succeeds" sanity check that catches non-orphan problems (feedback cycle validation, etc.).

### `ControlBindingMap` docstring warning

Add to the `ControlBindingMap` struct doc:

```
/// Proven-valid control bindings. Validated against a specific
/// CompiledTemplate at build time.
///
/// WARNING: After VoicePool::set_template swaps the pool template,
/// a ControlBindingMap validated against the prior template may
/// silently target wrong node kinds or no-op on eliminated nodes.
/// Rebuild ControlBindingMap whenever the template changes.
/// Addressing this structurally is tracked as a follow-up.
```

### Scope

| File | Change | Est. LOC |
|------|--------|----------|
| `graph/compiled_template.mbt` | New file — struct + 4 methods (2 pub, 3 priv) | ~45 |
| `graph/control_binding.mbt` | `build` signature, orphan check inline, new variant, doc warning | ~20 |
| `graph/graph_compile.mbt` | Remove public `CompiledDsp::orphan_adsr_count(template)` | −10 |
| `voice/voice.mbt` | Two call sites migrate to `CompiledTemplate::analyze` | ~10 |
| `lib/control_binding_test.mbt` | ~16 call sites: `build(template)` → `build(CompiledTemplate::analyze(template))` | ~25 |
| `scheduler/scheduler_test.mbt` | 4 call sites, same shape | ~10 |
| `browser/browser_scheduler.mbt` | 2 call sites | ~5 |
| `graph/graph_optimize_test.mbt` | Migrate orphan-ADSR tests from PR #8 to `CompiledTemplate` | ~15 |
| `lib/control_binding_test.mbt` | New orphan-binding tests (mirror PR #8 shape; existing tests for this API already live here) | ~50 |
| `graph/compiled_template_wbtest.mbt` (new) | Whitebox tests for `CompiledTemplate::analyze`, `orphan_adsr_count`, and the priv `is_node_live` primitive | ~35 |
| `lib/reexport.mbt` | Add `type CompiledTemplate` to the re-export list | ~1 |
| `graph/pkg.generated.mbti`, `voice/pkg.generated.mbti` | Regenerated via `moon info` | (auto) |

**Total:** ~200 lines net (substantially bigger than original ~30 estimate because the `CompiledTemplate` abstraction touches every current `build` call site; consolidates the `orphan_adsr_count` parameterless refactor; and fixes the real architectural narrowing Codex flagged).

## Testing

All new tests mirror the PR #8 shape in `graph/graph_optimize_test.mbt` and `voice/voice_test.mbt`.

### `CompiledTemplate` direct tests (whitebox, in `graph/compiled_template_wbtest.mbt`)

1. **`analyze` snapshots template** — mutate input array after analyze; verify the stored template is unchanged (indirectly via `orphan_adsr_count` on a pre-mutation ADSR).
2. **`orphan_adsr_count` live ADSR** — template with ADSR wired to Output → count is 0.
3. **`orphan_adsr_count` dead ADSR** — template with ADSR not wired (PR #8 reproduction case) → count is 1.
4. **`orphan_adsr_count` multiple** — template with 3 dead ADSRs → count is 3.
5. **`is_node_live` live node** — returns true for surviving nodes.
6. **`is_node_live` dead node** — returns false for eliminated nodes.
7. **`is_node_live` out-of-bounds** — returns false for negative or past-end indices (must not abort).

### Orphan-binding rejection tests

8. **Live binding passes** — binding on surviving `Oscillator`.value0 → `Ok`.
9. **Orphan binding rejected** — binding on a dead node (an unwired `Oscillator`; `Value0` must be a slot the node kind accepts, so we cannot use an ADSR here — `node_accepts_slot(Adsr, *)` is always false, making the slot check preempt the orphan check) → `Err(OrphanBinding(key, i))`.
10. **Error reports correct key** — two orphan bindings on the same node but different keys; assert the error carries the specific offending key.
11. **Slot error preempts orphan** — binding at index `i` with both a wrong slot AND where `template[i]` gets eliminated by optimize → reports `InvalidSlotForNode`, not `OrphanBinding` (slot check runs first per the ordering above).
12. **Bounds error preempts everything** — binding with out-of-range `node_index` still reports `InvalidNodeIndex` regardless of optimization state.
13. **Orphan preempts duplicate** — two bindings with the same key, the first pointing at an orphan node → reports `OrphanBinding` on the first binding, never reaches the duplicate check on the second.
14. **`DuplicateKey` still works on live nodes** — regression.
15. **Empty builder** — zero bindings → `Ok` with empty resolve.

### `VoicePool` regression tests

16. **`VoicePool::new` still rejects orphan-ADSR template** — port PR #8 test, verify the reject path still works after migration from `test_compile.orphan_adsr_count` to `CompiledTemplate::analyze`.
17. **`VoicePool::set_template` still rejects orphan-ADSR template, transactional** — port PR #8 test; assert rollback.

### Existing test migration

All ~22 `build(template)` call sites in `lib/`, `scheduler/`, `browser/` get mechanical `build(CompiledTemplate::analyze(template))` updates. No behavioral change expected.

## Migration plan

1. Add `graph/compiled_template.mbt`. `moon check`.
2. Wire `ControlBindingBuilder::build(compiled_template)`. New error variant. Docstring. `moon check` — will fail at all existing call sites.
3. Mechanical migration of call sites in `lib/`, `scheduler/`, `browser/`, `voice/`. `moon check` green.
4. Migrate `VoicePool::new` / `set_template` to `CompiledTemplate::analyze`. Remove `CompiledDsp::orphan_adsr_count`. `moon check` + `moon test` green.
5. Add new tests (CompiledTemplate direct, orphan-binding rejection, VoicePool regression). `moon test` green.
6. `moon info && moon fmt`. Diff review of `.mbti`.
7. Codex review.
8. PR to `feat/control-binding-orphan-detection`.

## Follow-ups (explicit TODOs)

Added to `memory/project_phase5_todos.md`:

- **`set_template` bindings staleness (NEW FOOTGUN)** — Codex-identified sibling to this fix. After a successful `VoicePool::set_template`, any `ControlBindingMap` held by `PatternScheduler` (or any external caller) remains type-level valid but targets the old template. Design options: (a) `CompiledTemplate` identity check at `PatternScheduler::apply`, (b) `BoundVoicePool` composite owning pool + bindings atomically, (c) `set_template_with_bindings(template, builder)` atomic rebuild. Each has tradeoffs; deserves its own brainstorm + spec.
- **Strike `CompiledDsp::orphan_adsr_count(template)` reference from `project_phase5_todos.md`** — this spec subsumes the "store at compile time" TODO by moving the count onto `CompiledTemplate`.
- **`VoiceSlot.template_snapshot` via `CompiledTemplate`** — currently stores its own array reference; could redirect through a per-slot `CompiledTemplate` for symmetry. YAGNI until someone wants it.

## Risks

- **Test call-site churn** — ~22 sites updated mechanically. Low risk; compiler guides the migration.
- **`.mbti` surface shifts** — adding `CompiledTemplate` + `analyze` + `orphan_adsr_count`; removing `CompiledDsp::orphan_adsr_count`. Reviewer check: `git diff *.mbti` focuses on these specific deltas.
- **Performance at pool creation** — `CompiledTemplate::analyze` replaces full `CompiledDsp::compile` for the orphan-ADSR gate → net LESS allocation. Subsequent `CompiledDsp::compile` still runs for its other invariants (feedback cycle etc.); not a regression.
- **`set_template` staleness remains a footgun** — mitigated by docstring + memory TODO, but not structurally fixed. Accepted because bundling the fix would double PR scope and force design choices that deserve dedicated treatment.
