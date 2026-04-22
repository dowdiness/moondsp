# Control-Binding Orphan Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject `ControlBindingMap`s whose bindings point at optimizer-eliminated nodes, by introducing a `CompiledTemplate` topology artifact that `ControlBindingBuilder::build` validates against. Subsumes the PR #8 "store orphan_adsr_count at compile time" follow-up.

**Architecture:** Introduce `graph/compiled_template.mbt` holding `(template_snapshot, index_map)` — the minimum needed to answer post-optimization topology questions without runtime buffers. `CompiledTemplate::analyze(template)` runs `optimize_graph` once. Both `VoicePool` (orphan-ADSR gate) and `ControlBindingBuilder::build` (orphan-binding check) consume `CompiledTemplate`. `CompiledDsp::compile` stays unchanged; `CompiledDsp::orphan_adsr_count(template)` is removed. `set_template` binding staleness is explicitly deferred with docstring warning + follow-up TODO.

**Tech Stack:** MoonBit (wasm-gc target for browser, native for tests), `moonbitlang/core` stdlib, `moon` build tool. DSP library in `graph/` + `voice/` + `lib/` packages.

**Spec reference:** `docs/superpowers/specs/2026-04-18-control-binding-orphan-design.md`

---

## File Map

| Task | File | Purpose |
|------|------|---------|
| 1 | **NEW** `graph/compiled_template.mbt` | `CompiledTemplate` struct, `analyze`, public methods |
| 1 | **NEW** `graph/compiled_template_wbtest.mbt` | Whitebox tests — snapshot + `is_node_live` + `node_at` + `length` |
| 1 | MOD `lib/reexport.mbt` | Add `type CompiledTemplate` to graph re-export block |
| 2 | MOD `graph/compiled_template.mbt` | Add `orphan_adsr_count` method + wbtest cases |
| 3 | MOD `graph/compiled_template.mbt` | Add private helpers `is_node_live`, `node_at`, `length` + wbtest cases |
| 4 | MOD `graph/control_binding.mbt` | Add `OrphanBinding(String, Int)` variant (additive, unused yet) |
| 5 | MOD `voice/voice.mbt` | Replace `test_compile.orphan_adsr_count(template)` with `CompiledTemplate::analyze(template).orphan_adsr_count()` |
| 6 | MOD `graph/control_binding.mbt` | Change `build(template)` → `build(compiled_template)`; internal switch to `compiled_template.node_at(i)` / `length()` |
| 6 | MOD `lib/control_binding_test.mbt` | Migrate ~16 call sites |
| 6 | MOD `scheduler/scheduler_test.mbt` | Migrate 4 call sites |
| 6 | MOD `browser/browser_scheduler.mbt` | Migrate 2 call sites |
| 7 | MOD `graph/control_binding.mbt` | Add orphan check inside `build`; emit `OrphanBinding` |
| 7 | MOD `lib/control_binding_test.mbt` | Add 8 new tests (rejection, ordering, key-carrying payload) |
| 8 | MOD `graph/graph_compile.mbt` | Remove `CompiledDsp::orphan_adsr_count(template)` |
| 8 | MOD `graph/graph_optimize_test.mbt` | Migrate any tests that called the removed method |
| 9 | MOD `graph/control_binding.mbt` | Add docstring warning on `ControlBindingMap` struct |
| 9 | **MEMORY** `project_phase5_todos.md` | Record new `set_template` staleness TODO; strike the subsumed store-orphan-at-compile-time bullet |

Auto-regenerated (via `moon info`): `graph/pkg.generated.mbti`, `voice/pkg.generated.mbti`, `lib/pkg.generated.mbti`, `scheduler/pkg.generated.mbti`.

**Delegation notes:** Task 6's mechanical call-site migration (~22 sites) is a delegation-shaped trigger (Haiku-appropriate). Tasks 1-5, 7-9 involve design judgment and stay in main context.

---

## Task 1: Add `CompiledTemplate` struct + `analyze`

**Files:**
- Create: `graph/compiled_template.mbt`
- Create: `graph/compiled_template_wbtest.mbt`
- Modify: `lib/reexport.mbt`

- [ ] **Step 1: Write failing whitebox test for `analyze` existence and snapshot semantics**

Write `graph/compiled_template_wbtest.mbt`:

```moonbit
///|
test "analyze: returns CompiledTemplate with snapshot that survives caller mutation" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ct = CompiledTemplate::analyze(template)
  // Mutate the caller's array post-analyze.
  template[0] = DspNode::constant(1.0)
  // Snapshot inside CompiledTemplate is independent.
  assert_true(ct.node_at(0).kind is DspNodeKind::Oscillator(_))
}

///|
test "analyze: length matches input template length" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.5),
    DspNode::output(1),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.length(), 3)
}
```

- [ ] **Step 2: Run test to confirm failure**

Run: `moon test -p dowdiness/moondsp/graph`
Expected: compile error — `CompiledTemplate` not defined.

- [ ] **Step 3: Create `graph/compiled_template.mbt` with minimal skeleton**

```moonbit
///|
/// Topology artifact: template snapshot paired with its optimize_graph
/// result. Holds the minimum needed to answer post-optimization topology
/// questions ("is this node live?", "how many ADSRs were eliminated?")
/// without allocating runtime buffers or per-voice state.
///
/// WHY a separate artifact from CompiledDsp: CompiledDsp conflates topology
/// with runtime state. Binding validation and pool-level orphan gates only
/// need topology — making that a lightweight standalone type avoids
/// paying for buffers we never use, and keeps the API mono/stereo-agnostic
/// (the same CompiledTemplate shape applies to any graph variant).
pub struct CompiledTemplate {
  priv template : Array[DspNode]
  priv index_map : FixedArray[Int]
}

///|
/// Snapshot the template and run optimize_graph once.
///
/// WHY defensive copy: optimize_graph does not mutate its input today, but
/// callers can mutate the source array after analyze returns. A snapshot
/// keeps CompiledTemplate's invariants independent of caller code.
///
/// WHY no DspContext: optimize_graph is a pure function of Array[DspNode];
/// sample rate and block size do not affect which nodes survive
/// dead-code elimination. Omitting the context makes analyze infallible
/// and cheap.
pub fn CompiledTemplate::analyze(
  template : Array[DspNode],
) -> CompiledTemplate {
  let snapshot = template.copy()
  let (_, index_map) = optimize_graph(snapshot)
  { template: snapshot, index_map }
}

///|
/// Length of the authoring template snapshot.
fn CompiledTemplate::length(self : CompiledTemplate) -> Int {
  self.template.length()
}

///|
/// Return the authoring node at `index` (panics if out of range; callers
/// are expected to bounds-check first).
fn CompiledTemplate::node_at(self : CompiledTemplate, index : Int) -> DspNode {
  self.template[index]
}
```

- [ ] **Step 4: Run whitebox tests to confirm pass**

Run: `moon test -p dowdiness/moondsp/graph`
Expected: both new tests PASS. No other test regressions.

- [ ] **Step 5: Re-export `CompiledTemplate` from `lib/`**

Modify `lib/reexport.mbt:69-104` — add `type CompiledTemplate` to the graph re-export block. The block already lists other graph types:

```moonbit
pub using @graph {
  type CompiledDsp,
  type CompiledDspHotSwap,
  type CompiledDspTopologyController,
  type CompiledStereoDsp,
  type CompiledStereoDspHotSwap,
  type CompiledStereoDspTopologyController,
  type CompiledTemplate,         // NEW — add in alphabetical/grouping order
  type DspNode,
  // ... rest unchanged
}
```

- [ ] **Step 6: Run `moon info && moon fmt && moon check`**

```
moon info && moon fmt && moon check
```
Expected: no errors. `lib/pkg.generated.mbti` and `graph/pkg.generated.mbti` regenerated with the new type.

- [ ] **Step 7: Commit**

```bash
git add graph/compiled_template.mbt graph/compiled_template_wbtest.mbt lib/reexport.mbt graph/pkg.generated.mbti lib/pkg.generated.mbti
git commit -m "$(cat <<'EOF'
feat(graph): add CompiledTemplate topology artifact

Introduces a lightweight alternative to CompiledDsp for queries that need
only post-optimization topology (which nodes survived, what kinds they are)
without paying for runtime buffers or per-voice state. CompiledTemplate
holds (template_snapshot, index_map) — a defensive copy of the authoring
template plus the optimize_graph output — and exposes length/node_at as
package-private primitives plus a public analyze constructor.

No DspContext argument: optimize_graph is a pure function of Array[DspNode],
so analyze is infallible.

Preparing follow-up commits to move orphan-ADSR counting and add
orphan-binding detection on this artifact.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `orphan_adsr_count` (parameterless) on `CompiledTemplate`

**Files:**
- Modify: `graph/compiled_template.mbt`
- Modify: `graph/compiled_template_wbtest.mbt`

- [ ] **Step 1: Write failing tests for `orphan_adsr_count`**

Append to `graph/compiled_template_wbtest.mbt`:

```moonbit
///|
test "orphan_adsr_count: live ADSR returns 0" {
  // ADSR wired through envelope_gain to Output — survives optimization.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),
    DspNode::envelope_gain(0, 1, 1.0),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.orphan_adsr_count(), 0)
}

///|
test "orphan_adsr_count: dead ADSR returns 1" {
  // ADSR present but not consumed by Output path — orphan.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.orphan_adsr_count(), 1)
}

///|
test "orphan_adsr_count: multiple dead ADSRs returns correct count" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),  // orphan
    DspNode::adsr(5.0, 50.0, 0.5, 100.0),    // orphan
    DspNode::adsr(1.0, 10.0, 0.9, 20.0),     // orphan
    DspNode::gain(0, 0.3),
    DspNode::output(4),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_eq(ct.orphan_adsr_count(), 3)
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `moon test -p dowdiness/moondsp/graph`
Expected: three failures — `orphan_adsr_count` undefined on `CompiledTemplate`.

- [ ] **Step 3: Implement `orphan_adsr_count` in `graph/compiled_template.mbt`**

Append after the existing methods:

```moonbit
///|
/// Count Adsr nodes in the template snapshot whose compiled index is < 0
/// (eliminated by optimize_graph as dead code). An orphan ADSR silently
/// no-ops its gate_on, producing voices that never envelope — VoicePool::new
/// and set_template reject templates where this count is > 0.
///
/// Parameterless because the template snapshot is owned by self; callers
/// do not need to remember which template was compiled.
pub fn CompiledTemplate::orphan_adsr_count(self : CompiledTemplate) -> Int {
  let mut count = 0
  for i = 0;
      i < self.template.length() && i < self.index_map.length();
      i = i + 1 {
    if self.template[i].kind is Adsr && self.index_map[i] < 0 {
      count = count + 1
    }
  }
  count
}
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `moon test -p dowdiness/moondsp/graph`
Expected: three new tests PASS; existing PR #8 tests (which call `CompiledDsp::orphan_adsr_count(template)`) continue to PASS because that method is unchanged.

- [ ] **Step 5: Run `moon info && moon fmt`**

```
moon info && moon fmt
```
Expected: `graph/pkg.generated.mbti` updated with `CompiledTemplate::orphan_adsr_count`.

- [ ] **Step 6: Commit**

```bash
git add graph/compiled_template.mbt graph/compiled_template_wbtest.mbt graph/pkg.generated.mbti
git commit -m "$(cat <<'EOF'
feat(graph): orphan_adsr_count as parameterless method on CompiledTemplate

Mirrors CompiledDsp::orphan_adsr_count(template) but without the leaky
template parameter Codex flagged on PR #8 — CompiledTemplate owns the
snapshot so callers cannot accidentally pass a different template than
the one that was compiled.

The existing CompiledDsp::orphan_adsr_count(template) stays in place
until the VoicePool migration and call-site cleanup finish.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `is_node_live` package-private primitive

**Files:**
- Modify: `graph/compiled_template.mbt`
- Modify: `graph/compiled_template_wbtest.mbt`

- [ ] **Step 1: Write failing tests for `is_node_live`**

Append to `graph/compiled_template_wbtest.mbt`:

```moonbit
///|
test "is_node_live: surviving node returns true" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_true(ct.is_node_live(0))  // Oscillator survives (feeds Output)
  assert_true(ct.is_node_live(1))  // Output survives
}

///|
test "is_node_live: eliminated node returns false" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),  // orphan — eliminated
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let ct = CompiledTemplate::analyze(template)
  assert_false(ct.is_node_live(1))  // ADSR dead
  assert_true(ct.is_node_live(0))   // Osc survives
  assert_true(ct.is_node_live(2))   // Gain survives
  assert_true(ct.is_node_live(3))   // Output survives
}

///|
test "is_node_live: out-of-bounds index returns false (does not abort)" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let ct = CompiledTemplate::analyze(template)
  assert_false(ct.is_node_live(-1))
  assert_false(ct.is_node_live(100))
  assert_false(ct.is_node_live(2))   // exactly one past end
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `moon test -p dowdiness/moondsp/graph`
Expected: `is_node_live` undefined.

- [ ] **Step 3: Implement `is_node_live`**

Append to `graph/compiled_template.mbt`:

```moonbit
///|
/// Does authoring index `i` survive the optimizer? Returns false for
/// out-of-range indices (no abort).
///
/// Package-private: binding validation in control_binding.mbt uses this;
/// external callers should not need raw liveness queries — orphan counts
/// (for diagnostics) or the build rejection flow (for enforcement) are
/// sufficient.
fn CompiledTemplate::is_node_live(self : CompiledTemplate, index : Int) -> Bool {
  index >= 0 && index < self.index_map.length() && self.index_map[index] >= 0
}
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `moon test -p dowdiness/moondsp/graph`
Expected: three new tests PASS.

- [ ] **Step 5: Run `moon info && moon fmt && moon check`**

Expected: `.mbti` does NOT expose `is_node_live` (it is package-private, no `pub`).

- [ ] **Step 6: Commit**

```bash
git add graph/compiled_template.mbt graph/compiled_template_wbtest.mbt
git commit -m "$(cat <<'EOF'
feat(graph): CompiledTemplate::is_node_live — liveness primitive

Package-private predicate answering "did authoring index i survive
optimize_graph?" Returns false for out-of-range indices (no abort),
matching how downstream validators prefer recoverable errors over panics.

Used by the upcoming orphan-binding check inside ControlBindingBuilder::build.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `OrphanBinding(String, Int)` error variant (additive)

**Files:**
- Modify: `graph/control_binding.mbt`

- [ ] **Step 1: Extend `ControlBindingError` enum**

Modify `graph/control_binding.mbt:24-28` — replace:

```moonbit
pub(all) enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, GraphParamSlot)
  DuplicateKey(String)
} derive(Debug, Eq)
```

with:

```moonbit
pub(all) enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, GraphParamSlot)
  DuplicateKey(String)
  /// Binding (key, node_index) targets a template node that
  /// optimize_graph eliminated. Prevents silent set_param no-ops.
  OrphanBinding(String, Int)
} derive(Debug, Eq)
```

- [ ] **Step 2: Run `moon check`**

Expected: clean — this is purely additive. `pub(all)` enums are `pub(open)` by default rules — but verify no existing callers pattern-match exhaustively on `ControlBindingError` in a way that breaks with the new variant.

Run: `moon check`

If any `match` on `ControlBindingError` without a wildcard arm is flagged, add the new case; the existing tests and production code use `assert_eq` or `is Err(_)` which are fine.

- [ ] **Step 3: Run full test suite**

Run: `moon test`
Expected: all green. No behavioral change.

- [ ] **Step 4: Run `moon info && moon fmt`**

Expected: `graph/pkg.generated.mbti` reflects the new variant.

- [ ] **Step 5: Commit**

```bash
git add graph/control_binding.mbt graph/pkg.generated.mbti
git commit -m "$(cat <<'EOF'
feat(graph): add OrphanBinding(String, Int) error variant

Additive-only. The variant will be produced by ControlBindingBuilder::build
in a following commit; this commit only reserves the API surface so the
error-handling change is reviewable independently of the validation-site
refactor.

Payload is (key, node_index) — multiple bindings can target the same node,
so key identifies the offending user-facing label, node_index the
structural fault.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Migrate `VoicePool::new` + `set_template` to `CompiledTemplate`

**Files:**
- Modify: `voice/voice.mbt`

- [ ] **Step 1: Read existing orphan-gate sites**

Read `voice/voice.mbt` around `VoicePool::new` (~line 145) and `VoicePool::set_template` (~line 174). Current shape:

```moonbit
let test_compile = match CompiledDsp::compile(template, context) {
  Some(c) => c
  None => return None
}
if test_compile.orphan_adsr_count(template) > 0 {
  return None
}
```

- [ ] **Step 2: Add `@graph` import for `CompiledTemplate`**

Modify `voice/voice.mbt:5`:

```moonbit
using @graph {type CompiledDsp, type CompiledTemplate, type DspNode, type GraphControl}
```

- [ ] **Step 3: Replace orphan gate in `VoicePool::new`**

In `VoicePool::new`, replace the block from Step 1 with:

```moonbit
let compiled_template = CompiledTemplate::analyze(template)
if compiled_template.orphan_adsr_count() > 0 {
  return None
}
// Sanity-compile to catch non-orphan problems (feedback cycle validation etc.).
// Result discarded — per-voice slots compile their own on note_on.
if CompiledDsp::compile(template, context) is None {
  return None
}
```

Keep the rest of the function identical (allocation of slots, etc.).

- [ ] **Step 4: Replace orphan gate in `VoicePool::set_template` identically**

The `set_template` body (~line 174+) uses the same pattern. Apply the identical replacement there.

- [ ] **Step 5: Run `moon test -p dowdiness/moondsp/voice`**

Run: `moon test -p dowdiness/moondsp/voice`
Expected: all PR #8 tests PASS unchanged — `voice_test.mbt`'s orphan-ADSR rejection tests still produce `None` / `false` for the same offending templates. The transactional rollback test (set_template returning false leaves prior template intact) still holds because the two gates are run sequentially before any state mutation, matching the original.

- [ ] **Step 6: Run full test suite**

Run: `moon test`
Expected: all green.

- [ ] **Step 7: Run `moon info && moon fmt`**

Expected: `voice/pkg.generated.mbti` unchanged (internal migration only, no public API shift).

- [ ] **Step 8: Commit**

```bash
git add voice/voice.mbt
git commit -m "$(cat <<'EOF'
refactor(voice): migrate orphan-ADSR gate to CompiledTemplate

VoicePool::new and set_template now run CompiledTemplate::analyze(template)
for the orphan check, then CompiledDsp::compile separately for the other
compile-time invariants (feedback cycle validation etc.). Net effect:
skips the buffer/state allocations that test_compile was discarding
after orphan_adsr_count, at the cost of one additional optimize_graph
pass (deterministic, cheap).

No behavioral change visible to callers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Change `ControlBindingBuilder::build` signature + migrate all callers

> **Delegation note:** Steps 3-5 (~22 mechanical call-site updates) are a delegation-shaped trigger. Before starting the migration: state aloud the delegation decision per CLAUDE.md `Delegation Checkpoint` and append to `~/.claude/memory/delegation-log.md`. Recommendation: Haiku for the call-site sweep, main context for Steps 1-2 and 6-8.

**Files:**
- Modify: `graph/control_binding.mbt`
- Modify: `lib/control_binding_test.mbt`
- Modify: `scheduler/scheduler_test.mbt`
- Modify: `browser/browser_scheduler.mbt`

- [ ] **Step 1: Change `build` signature + internal implementation**

Modify `graph/control_binding.mbt:70-97` — replace:

```moonbit
pub fn ControlBindingBuilder::build(
  self : ControlBindingBuilder,
  template : Array[DspNode],
) -> Result[ControlBindingMap, ControlBindingError] {
  let seen_keys : Map[String, Bool] = {}
  for i = 0; i < self.bindings.length(); i = i + 1 {
    let binding = self.bindings[i]
    if binding.node_index < 0 || binding.node_index >= template.length() {
      return Err(ControlBindingError::InvalidNodeIndex(binding.node_index))
    }
    if !node_accepts_slot(template[binding.node_index], binding.slot) {
      return Err(
        ControlBindingError::InvalidSlotForNode(
          binding.node_index,
          binding.slot,
        ),
      )
    }
    if seen_keys.contains(binding.key) {
      return Err(ControlBindingError::DuplicateKey(binding.key))
    }
    seen_keys[binding.key] = true
  }
  Ok({ bindings: self.bindings.copy() })
}
```

with:

```moonbit
pub fn ControlBindingBuilder::build(
  self : ControlBindingBuilder,
  compiled_template : CompiledTemplate,
) -> Result[ControlBindingMap, ControlBindingError] {
  let seen_keys : Map[String, Bool] = {}
  for i = 0; i < self.bindings.length(); i = i + 1 {
    let binding = self.bindings[i]
    if binding.node_index < 0 ||
      binding.node_index >= compiled_template.length() {
      return Err(ControlBindingError::InvalidNodeIndex(binding.node_index))
    }
    if !node_accepts_slot(
        compiled_template.node_at(binding.node_index),
        binding.slot,
      ) {
      return Err(
        ControlBindingError::InvalidSlotForNode(
          binding.node_index,
          binding.slot,
        ),
      )
    }
    // NB: orphan check is added in Task 7 — this commit keeps build
    // behavior identical apart from the signature.
    if seen_keys.contains(binding.key) {
      return Err(ControlBindingError::DuplicateKey(binding.key))
    }
    seen_keys[binding.key] = true
  }
  Ok({ bindings: self.bindings.copy() })
}
```

- [ ] **Step 2: Run `moon check` to see the cascade of breakages**

Run: `moon check`
Expected: ~22 errors across `lib/control_binding_test.mbt`, `scheduler/scheduler_test.mbt`, `browser/browser_scheduler.mbt`. Each one has `.build(template)` where the argument type is now wrong.

- [ ] **Step 3: Migrate `lib/control_binding_test.mbt` call sites (16 sites)**

For every `.build(template)` call in the file, wrap the argument:

Before:
```moonbit
let result = ControlBindingBuilder::new()
  .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
  .build(template)
```

After:
```moonbit
let result = ControlBindingBuilder::new()
  .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
  .build(CompiledTemplate::analyze(template))
```

Apply the exact same transform at every call site in the file. No tests change behavior — the semantics are identical for every template that has no orphan bindings (which all existing tests use, since orphan detection is added in Task 7).

- [ ] **Step 4: Migrate `scheduler/scheduler_test.mbt` call sites (4 sites)**

Same transform. Search the file for `.build(template)` and wrap each. Check the surrounding test context — if a test constructs `@lib.CompiledTemplate::analyze(...)` (since scheduler tests use the `lib/` re-export), that path works too; prefer whichever prefix the rest of the file uses.

- [ ] **Step 5: Migrate `browser/browser_scheduler.mbt` call sites (2 sites)**

Modify `browser/browser_scheduler.mbt:118`:

Before:
```moonbit
let bindings_result = @lib.ControlBindingBuilder::new().build(template)
```

After:
```moonbit
let bindings_result = @lib.ControlBindingBuilder::new()
  .build(@lib.CompiledTemplate::analyze(template))
```

And `browser/browser_scheduler.mbt:146-148`:

Before:
```moonbit
let bindings_result = @lib.ControlBindingBuilder::new()
  .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
  .build(template)
```

After:
```moonbit
let bindings_result = @lib.ControlBindingBuilder::new()
  .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
  .build(@lib.CompiledTemplate::analyze(template))
```

- [ ] **Step 6: Run `moon check` to confirm no compile errors**

Run: `moon check`
Expected: clean.

- [ ] **Step 7: Run full test suite**

Run: `moon test`
Expected: all green. No behavior change for any existing test; orphan detection is added in the next task.

- [ ] **Step 8: Run `moon info && moon fmt`**

Expected: `graph/pkg.generated.mbti` reflects the new `build` signature.

- [ ] **Step 9: Commit**

```bash
git add graph/control_binding.mbt lib/control_binding_test.mbt scheduler/scheduler_test.mbt browser/browser_scheduler.mbt graph/pkg.generated.mbti
git commit -m "$(cat <<'EOF'
refactor(graph)!: ControlBindingBuilder::build takes CompiledTemplate

Breaking API change. Callers construct a CompiledTemplate via
CompiledTemplate::analyze(template) and pass it to build instead of the
raw template.

Rationale: binding validation needs post-optimization topology
information (what survived), which CompiledTemplate provides. Passing
the raw template today means build cannot detect orphan bindings;
changing the argument is the minimum API shift required to make
orphan detection possible in the following commit.

~22 call sites migrated mechanically — no behavior change; orphan
detection is added in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add orphan check inside `build` + new tests

**Files:**
- Modify: `graph/control_binding.mbt`
- Modify: `lib/control_binding_test.mbt`

- [ ] **Step 1: Write new failing tests for orphan-binding detection**

Append to `lib/control_binding_test.mbt`:

```moonbit
///|
test "build: live binding on surviving node produces Ok" {
  // Oscillator is live (feeds Output via gain). Binding on its Value0 is valid.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_true(result is Ok(_))
}

///|
test "build: orphan binding returns OrphanBinding with key and index" {
  // ADSR at index 1 is orphan (no path to Output — Gain reads Osc directly).
  // optimize_graph eliminates it; binding on its Value0 would silently no-op.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="attack", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("attack", 1)))
}

///|
test "build: orphan error carries the specific binding's key" {
  // Two bindings on the same orphan node but different keys.
  // build should report the FIRST encountered (insertion order).
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),  // orphan
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="env_attack", node_index=1, slot=GraphParamSlot::Value0)
    .bind(key="env_decay", node_index=1, slot=GraphParamSlot::Value1)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("env_attack", 1)))
}

///|
test "build: slot error preempts orphan check" {
  // Node 1 is Output — has no Value0 slot. Even if Output happens to be
  // live (it is), the slot check runs before the orphan check per the
  // per-binding ordering. With a template where Output is index 1:
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder::new()
    .bind(key="x", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(
    result,
    Err(ControlBindingError::InvalidSlotForNode(1, GraphParamSlot::Value0)),
  )
}

///|
test "build: bounds error preempts orphan check" {
  // node_index 99 is out of range — bounds check reports InvalidNodeIndex
  // before the liveness check (which is_node_live would also return
  // false for but as a different error class).
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),  // orphan
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="x", node_index=99, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(99)))
}

///|
test "build: orphan preempts duplicate key" {
  // First binding is orphan; duplicate appears later. Orphan reported first.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),  // orphan
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="dup", node_index=1, slot=GraphParamSlot::Value0)
    .bind(key="dup", node_index=0, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::OrphanBinding("dup", 1)))
}

///|
test "build: duplicate key still reported for live-node bindings" {
  // Regression — no orphans present, duplicate check still works.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder::new()
    .bind(key="g", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="g", node_index=1, slot=GraphParamSlot::Value0)
    .build(CompiledTemplate::analyze(template))
  assert_eq(result, Err(ControlBindingError::DuplicateKey("g")))
}

///|
test "build: empty builder still succeeds on any template" {
  // Regression — no bindings means nothing to validate.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),  // orphan — irrelevant when unbound
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let result = ControlBindingBuilder::new()
    .build(CompiledTemplate::analyze(template))
  assert_true(result is Ok(_))
}
```

- [ ] **Step 2: Run tests to confirm failures (orphan tests fail; others pass)**

Run: `moon test -p dowdiness/moondsp/lib`
Expected: "build: orphan binding returns OrphanBinding with key and index", "build: orphan error carries the specific binding's key", and "build: orphan preempts duplicate key" all FAIL (current implementation has no orphan check so the tests see `Ok(_)` instead of `Err(OrphanBinding(...))`). The other new tests PASS (they exercise paths that already work).

- [ ] **Step 3: Add orphan check to `build`**

Modify `graph/control_binding.mbt` — inside the for-loop in `build`, insert the orphan check between the slot check and the duplicate-key check:

```moonbit
    if !node_accepts_slot(
        compiled_template.node_at(binding.node_index),
        binding.slot,
      ) {
      return Err(
        ControlBindingError::InvalidSlotForNode(
          binding.node_index,
          binding.slot,
        ),
      )
    }
    // Orphan check — binding targets a node that optimize_graph eliminated.
    // Without this, resolve_controls would emit set_param messages that
    // CompiledDsp silently drops via index_map[i] = -1.
    if !compiled_template.is_node_live(binding.node_index) {
      return Err(
        ControlBindingError::OrphanBinding(binding.key, binding.node_index),
      )
    }
    if seen_keys.contains(binding.key) {
      return Err(ControlBindingError::DuplicateKey(binding.key))
    }
```

- [ ] **Step 4: Run tests to confirm all pass**

Run: `moon test -p dowdiness/moondsp/lib`
Expected: all new orphan tests PASS; all existing tests PASS (no regressions).

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: all green.

- [ ] **Step 6: Run `moon info && moon fmt`**

Expected: `.mbti` unchanged (internal logic addition).

- [ ] **Step 7: Commit**

```bash
git add graph/control_binding.mbt lib/control_binding_test.mbt
git commit -m "$(cat <<'EOF'
feat(graph): reject ControlBindingMaps with orphan bindings

ControlBindingBuilder::build now checks every binding against the
CompiledTemplate's liveness map. Bindings whose node_index was
eliminated by optimize_graph produce Err(OrphanBinding(key, node_index))
instead of silently emitting set_param messages that CompiledDsp would
later drop.

Fixes the sibling silent footgun to PR #8's orphan-ADSR detection:
same failure class (index_map[i] = -1 silent no-op), different
validation site.

Per-binding validation order: bounds → slot → orphan → duplicate.
Slot and bounds preempt orphan because they report more specific
authoring errors; orphan preempts duplicate because an orphan is
a structural fault worth surfacing before typo-class mistakes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Remove `CompiledDsp::orphan_adsr_count(template)`

**Files:**
- Modify: `graph/graph_compile.mbt`
- Modify: `graph/graph_optimize_test.mbt` (if tests referenced the method)

- [ ] **Step 1: Grep for callers**

Run: `moon ide find-references CompiledDsp::orphan_adsr_count`

Expected: only references should be in `graph/graph_compile.mbt` (the definition) and possibly `graph/graph_optimize_test.mbt` (PR #8 tests). `voice/voice.mbt` was migrated in Task 5 and should not appear. If any unexpected caller appears, stop and investigate.

- [ ] **Step 2: Delete the method**

Remove `graph/graph_compile.mbt:79-98` (the `CompiledDsp::orphan_adsr_count(self, template)` definition including its doc comment).

- [ ] **Step 3: Migrate any test callers**

If `graph/graph_optimize_test.mbt` tests used `compiled.orphan_adsr_count(template)`, rewrite them against `CompiledTemplate::analyze(template).orphan_adsr_count()`.

For a representative rewrite:

Before:
```moonbit
test "compile: orphan ADSR is detected" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(10.0, 100.0, 0.7, 300.0),
    DspNode::gain(0, 0.3),
    DspNode::output(2),
  ]
  let ctx = DspContext::new(48000.0, 128)
  let compiled = CompiledDsp::compile(template, ctx).unwrap()
  assert_eq(compiled.orphan_adsr_count(template), 1)
}
```

After — delete entirely (coverage now lives in `graph/compiled_template_wbtest.mbt`). Keep any test whose value is distinct from what `compiled_template_wbtest.mbt` already covers; otherwise delete to avoid duplicate coverage.

- [ ] **Step 4: Run `moon check`**

Run: `moon check`
Expected: clean. If compile errors appear, they indicate an untracked caller — investigate before proceeding.

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: all green. Total test count should drop by however many duplicate orphan-ADSR tests got removed from `graph_optimize_test.mbt` (net offset by the new `compiled_template_wbtest.mbt` cases added in Task 2).

- [ ] **Step 6: Run `moon info && moon fmt`**

Expected: `graph/pkg.generated.mbti` no longer lists `CompiledDsp::orphan_adsr_count`. Confirm via `git diff graph/pkg.generated.mbti`.

- [ ] **Step 7: Commit**

```bash
git add graph/graph_compile.mbt graph/graph_optimize_test.mbt graph/pkg.generated.mbti
git commit -m "$(cat <<'EOF'
refactor(graph)!: remove CompiledDsp::orphan_adsr_count(template)

Replaced by CompiledTemplate::orphan_adsr_count() which is parameterless
because the topology artifact owns the template snapshot. Closes the
leaky-parameter design Codex flagged on PR #8.

All production callers migrated in the earlier VoicePool refactor;
duplicate-coverage tests in graph_optimize_test.mbt removed since
compiled_template_wbtest.mbt now owns that coverage.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Docstring warning + memory TODO updates

**Files:**
- Modify: `graph/control_binding.mbt`
- Modify: `~/.claude/projects/-home-antisatori-ghq-github-com-dowdiness-moondsp/memory/project_phase5_todos.md`

- [ ] **Step 1: Add `ControlBindingMap` staleness docstring**

Modify `graph/control_binding.mbt:54-58` — replace the current brief docstring with the warning version. Before:

```moonbit
///|
/// No public constructor — only reachable through ControlBindingBuilder::build().
pub struct ControlBindingMap {
  priv bindings : Array[ControlBinding]
} derive(Debug, Eq)
```

After:

```moonbit
///|
/// Proven-valid control bindings. Validated against a specific
/// CompiledTemplate at build time (bounds + slot compatibility +
/// orphan detection + key uniqueness).
///
/// No public constructor — only reachable through ControlBindingBuilder::build().
///
/// WARNING: A ControlBindingMap's validity is tied to the template it was
/// built against. After VoicePool::set_template swaps to a new template,
/// bindings validated against the prior template remain type-level valid
/// but may silently retarget the wrong kind of node or no-op against
/// nodes the new template's optimize_graph eliminated. Rebuild the
/// ControlBindingMap whenever the template changes. Structural staleness
/// detection is tracked as a follow-up.
pub struct ControlBindingMap {
  priv bindings : Array[ControlBinding]
} derive(Debug, Eq)
```

- [ ] **Step 2: Run `moon check && moon fmt`**

Expected: clean. No `.mbti` change (doc-only).

- [ ] **Step 3: Update the project memory**

Edit `~/.claude/projects/-home-antisatori-ghq-github-com-dowdiness-moondsp/memory/project_phase5_todos.md`:

- Strike the "Store `orphan_adsr_count` at compile time" bullet from the "Silent-failure footgun follow-ups" section (subsumed by this PR).
- Strike the "Control-binding orphan detection" bullet (this PR).
- Add a new bullet:

```markdown
- **set_template bindings staleness**: PatternScheduler owns a ControlBindingMap
  validated against the template that was active at construction. After
  VoicePool::set_template swaps the template, the scheduler's bindings may
  silently retarget wrong kinds or no-op against orphaned nodes of the new
  template. Design space: (a) CompiledTemplate identity check at
  PatternScheduler::apply, (b) BoundVoicePool composite owning pool+bindings
  atomically, (c) set_template_with_bindings(template, builder) atomic rebuild.
  Deserves its own brainstorm + spec — each option has material tradeoffs.
```

Also append a new "Completed" entry near the top of the completed log describing this PR (mirror the PR #8 entry format in the same file).

- [ ] **Step 4: Commit code changes**

```bash
git add graph/control_binding.mbt
git commit -m "$(cat <<'EOF'
docs(graph): warn about ControlBindingMap staleness after set_template

Captures the Codex-identified sibling footgun to orphan-binding
detection: a ControlBindingMap validated against template A silently
mis-targets after VoicePool::set_template swaps to template B. No
structural fix in this PR — the mitigation options (identity check,
composite type, atomic rebuild) each warrant their own design pass.

Tracked as a follow-up.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Verify final state**

Run: `moon check && moon test && moon info && moon fmt`
Expected: 470+ tests pass (original count from CLAUDE.md + new tests from Tasks 1, 2, 3, 7, minus duplicates removed in Task 8). `.mbti` files clean.

Run: `git diff main...HEAD --stat`
Expected: ~200 net LOC across the files listed in the File Map.

- [ ] **Step 6: Pre-PR verification**

```bash
moon check && moon test && moon build --target wasm-gc && moon info && moon fmt
git diff *.mbti
```

Expected: all clean. `.mbti` diff reviewed — matches the spec's API surface section.

- [ ] **Step 7: Codex review**

Ask Codex to review the full diff against `main`. Request:
> "Review PR feat/control-binding-orphan-detection against its design spec at docs/superpowers/specs/2026-04-18-control-binding-orphan-design.md. Focus on: (1) CompiledTemplate defensive-copy correctness, (2) validation-order edge cases, (3) any regressions in VoicePool transactionality from the orphan-gate refactor, (4) .mbti delta matches the spec."

Address any substantive findings before opening the PR.

- [ ] **Step 8: Open PR**

```bash
git push -u origin feat/control-binding-orphan-detection
gh pr create --title "feat(graph): reject ControlBindingMaps with orphan bindings" --body "$(cat <<'EOF'
## Summary
- Introduces `CompiledTemplate` topology artifact — (template snapshot, index_map) without runtime state.
- `ControlBindingBuilder::build(compiled_template)` rejects bindings whose node was eliminated by `optimize_graph`, emitting `OrphanBinding(key, node_index)`.
- Subsumes the PR #8 follow-up: `orphan_adsr_count` moves to `CompiledTemplate` (parameterless) and is removed from `CompiledDsp`.
- `VoicePool::new` / `set_template` orphan-ADSR gate migrated to the new artifact.
- Adds a `ControlBindingMap` docstring warning about set_template staleness (separate follow-up).

## Test plan
- [ ] `moon test` — all passing including new orphan-binding tests and whitebox CompiledTemplate coverage
- [ ] `moon build --target wasm-gc` — browser bundle builds
- [ ] Playwright smoke (manual, optional) — bound drum patterns still play
- [ ] `.mbti` diff reviewed — matches spec §"API surface shifts"

Design spec: `docs/superpowers/specs/2026-04-18-control-binding-orphan-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 9: Push final state (no more local commits)**

All tasks complete. PR URL printed for the user.

---

## Self-Review Checklist (done by plan author before handoff)

- [x] Spec coverage — every section of `2026-04-18-control-binding-orphan-design.md` maps to a task above.
- [x] Placeholder scan — no "TBD" / "implement later" / `"Add appropriate error handling"` anywhere; all steps show actual code.
- [x] Type consistency — `CompiledTemplate` spelling is identical across all tasks; `OrphanBinding(String, Int)` payload shape consistent.
- [x] Validation ordering — bounds → slot → orphan → dup — written identically in spec §Design and Task 7 Step 3.
- [x] `.mbti` migrations spelled out at each affected task, not assumed.
- [x] Breaking-change commits flagged with `!` in their subject lines (Tasks 6 and 8).
- [x] Delegation note attached to Task 6 per CLAUDE.md's `Delegation Checkpoint` rule.
