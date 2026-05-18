# PR 3: Graph Boundary Type — Migration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the graph + voice public surface to take `CompiledTemplate` as the runtime exchange type. Collapses `compile_template` into `compile`. Adds `VoicePoolError` Result-typed returns. Migrates voice/ internal storage from `Array[DspNode]` to `FixedArray[Int]` ADSR index snapshots. Flips ADR-0010 to Accepted; bumps version to 0.4.0.

**Architecture:** Five phases:
1. **Additive** (Tasks 1-3): add new APIs alongside old (TDD-driven where the API is genuinely new).
2. **Internal migration** (Tasks 4-9): rewrite internal callers + `voice/` storage to the new APIs without changing external signatures yet.
3. **Surface swap** (Tasks 10-14): change the public signatures — collapse `compile_template` into `compile`, migrate VoicePool/BoundVoicePool, privatize `optimize_graph`.
4. **Cleanup** (Tasks 15-20): delete temporary pins from PR 2, swap closures in persistent tests, add boundary-check CI, strip "planned per ADR-0010" qualifiers.
5. **Release** (Tasks 21-25): ADR-0010 → Accepted, CLAUDE.md one-liner, CHANGELOG, version bump, Codex CHANGELOG review.

**Tech Stack:** MoonBit; `moon check / test / fmt / info`; bash for CI script; GitHub Actions YAML.

**Spec:** `docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md` → §Sequencing PR 3.

**Branch:** `feat/graph-boundary-migration` off `main` (after PRs 1 + 2 land).

**Landing path:** Single PR against `main`, sized ~530–800 lines per Codex's estimate. Breaking change → v0.4.0 release.

**Verification gates:**
- After every task: `moon check` clean.
- After every phase: `moon test` green.
- Before merge: `moon check && moon test && moon fmt --check && moon info` clean; `scripts/check-public-boundary.sh` exits 0; PR-2 behavior tests still pass after closure-body swap.

---

## Phase 1 — Additive (new APIs alongside old)

### Task 1: Add `CompiledTemplate::adsr_authoring_indices` (TDD)

**Files:**
- Modify: `graph/compiled_template.mbt`
- Modify: `graph/compiled_template_wbtest.mbt`

- [ ] **Step 1: Write the B5 + B6 whitebox tests first (failing)**

Append to `graph/compiled_template_wbtest.mbt`:

```moonbit
///| B5: adsr_authoring_indices count + orphan_adsr_count equals total ADSRs.
test "B5: adsr_authoring_indices accounts for all authoring ADSRs" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    DspNode::output(2),
  ]
  let t = CompiledTemplate::analyze(nodes)
  let live = t.adsr_authoring_indices()
  @debug.assert_eq(live.length() + t.orphan_adsr_count(), 1)
  for i in 0..<live.length() {
    let idx = live[i]
    @debug.assert_eq(t.template[idx].kind() is Adsr, true)
    @debug.assert_eq(t.index_map[idx] >= 0, true)
  }
}

///| B5: orphan ADSR excluded from adsr_authoring_indices.
test "B5: orphan ADSR is excluded from adsr_authoring_indices" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::output(0),  // ADSR at index 1 is orphan
  ]
  let t = CompiledTemplate::analyze(nodes)
  @debug.assert_eq(t.adsr_authoring_indices().length(), 0)
  @debug.assert_eq(t.orphan_adsr_count(), 1)
}

///| B6: adsr_authoring_indices is monotonically increasing (authoring order).
test "B6: adsr_authoring_indices preserves authoring order" {
  let nodes : Array[DspNode] = [
    DspNode::adsr(attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0),
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=25.0, sustain=0.7, release_ms=50.0),
    DspNode::envelope_gain(input=1, envelope=0, amount=1.0),
    DspNode::envelope_gain(input=3, envelope=2, amount=1.0),
    DspNode::output(4),
  ]
  let live = CompiledTemplate::analyze(nodes).adsr_authoring_indices()
  @debug.assert_eq(live.length(), 2)
  for i in 1..<live.length() {
    @debug.assert_eq(live[i - 1] < live[i], true)
  }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `moon test graph/ -p compiled_template`
Expected: 3 failures with `adsr_authoring_indices: function not defined` or similar.

- [ ] **Step 3: Implement `adsr_authoring_indices`**

Append to `graph/compiled_template.mbt`:

```moonbit
///|
/// Authoring indices of ADSR nodes that survived optimize_graph,
/// in authoring order. Used by voice/ to gate the surviving ADSRs
/// on note_on / note_off — they call CompiledDsp::gate_on/gate_off
/// which take authoring indices and remap through index_map internally.
///
/// WHY authoring indices, not runtime: CompiledDsp::gate_on/gate_off
/// expect the original authoring index; returning runtime indices
/// would cause voice/ to double-map and target wrong nodes.
///
/// WHY a separate accessor instead of exposing length/node_at:
/// keeps the accessor surface minimal (principle 7). Specific
/// validation patterns get their own public method; generic
/// introspection waits for a concrete consumer.
pub fn CompiledTemplate::adsr_authoring_indices(
  self : CompiledTemplate,
) -> FixedArray[Int] {
  let result = FixedArray::make(self.template.length(), -1)
  let mut n = 0
  for i in 0..<self.template.length() {
    if self.template[i].kind() is Adsr && self.index_map[i] >= 0 {
      result[n] = i
      n = n + 1
    }
  }
  let snapshot = FixedArray::make(n, 0)
  for i in 0..<n {
    snapshot[i] = result[i]
  }
  snapshot
}
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `moon test graph/ -p compiled_template`
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add graph/compiled_template.mbt graph/compiled_template_wbtest.mbt
git commit -m "$(cat <<'EOF'
feat(graph): add CompiledTemplate::adsr_authoring_indices accessor

Returns authoring indices of surviving ADSR nodes in authoring order.
Used by voice/ to gate ADSRs on note_on/note_off (CompiledDsp::gate_on
takes authoring indices and remaps via index_map internally).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add `GraphBuilder::analyze` (TDD)

**Files:**
- Modify: `graph/graph_builder.mbt`
- Modify: `graph/graph_builder_test.mbt`

- [ ] **Step 1: Write the B8 round-trip test (failing)**

Append to `graph/graph_builder_test.mbt`:

```moonbit
///| B8: GraphBuilder::analyze produces a CompiledTemplate semantically
///| equivalent to CompiledTemplate::analyze(builder.nodes()). Verified
///| via downstream CompiledDsp output equivalence.
test "B8: GraphBuilder::analyze ≡ CompiledTemplate::analyze(builder.nodes())" {
  let builder = GraphBuilder::new()
  let _ = builder.osc(@dsp.Waveform::Sine, 440.0).output()
  let template_a = builder.analyze()
  let template_b = CompiledTemplate::analyze(builder.nodes())
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled_a = CompiledDsp::compile_template(template_a, ctx).unwrap()
  let compiled_b = CompiledDsp::compile_template(template_b, ctx).unwrap()
  let buf_a = @dsp.AudioBuffer::filled(128)
  let buf_b = @dsp.AudioBuffer::filled(128)
  compiled_a.process(ctx, buf_a)
  compiled_b.process(ctx, buf_b)
  for i in 0..<128 {
    @debug.assert_eq(buf_a.get(i), buf_b.get(i))
  }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `moon test graph/ -p graph_builder`
Expected: failure on `analyze: function not defined`.

- [ ] **Step 3: Implement `GraphBuilder::analyze`**

Append to `graph/graph_builder.mbt`:

```moonbit
///|
/// Produce a CompiledTemplate from the builder's current node list.
/// Sugar over `CompiledTemplate::analyze(self.nodes())` — exists
/// because GraphBuilder is the canonical entry point and the runtime
/// boundary is CompiledTemplate. See ADR-0010.
pub fn GraphBuilder::analyze(self : GraphBuilder) -> CompiledTemplate {
  CompiledTemplate::analyze(self.nodes())
}
```

- [ ] **Step 4: Run tests**

Run: `moon test graph/ -p graph_builder`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add graph/graph_builder.mbt graph/graph_builder_test.mbt
git commit -m "$(cat <<'EOF'
feat(graph): add GraphBuilder::analyze sugar method

Returns CompiledTemplate from the builder's accumulated nodes. The
.nodes() accessor is retained for authoring/inspection (per the
boundary contract in ADR-0010 — Array[DspNode] stays on the authoring
side).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add `VoicePoolError` enum + `BoundVoicePoolError::from_voice_pool` mapping

**Files:**
- Modify: `voice/voice.mbt`

- [ ] **Step 1: Add the enum + mapping helper**

Insert into `voice/voice.mbt` near the existing `BoundVoicePoolError` definition (around line 40-50):

```moonbit
///|
/// Failure modes for VoicePool construction and template replacement.
/// Mirrors BoundVoicePoolError minus the Binding(...) variant
/// (VoicePool has no bindings).
pub(all) enum VoicePoolError {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
} derive(Eq, @debug.Debug)

///|
pub impl Show for VoicePoolError with output(self, logger) {
  match self {
    VoicePoolError::InvalidMaxVoices =>
      logger.write_string("VoicePoolError::InvalidMaxVoices")
    VoicePoolError::OrphanAdsr =>
      logger.write_string("VoicePoolError::OrphanAdsr")
    VoicePoolError::CompileRejected =>
      logger.write_string("VoicePoolError::CompileRejected")
  }
}

///|
/// Lift a VoicePoolError to a BoundVoicePoolError. Used by
/// BoundVoicePool's constructors after delegating to
/// validate_voice_template (which now returns VoicePoolError after
/// the boundary-type migration per ADR-0010).
pub fn BoundVoicePoolError::from_voice_pool(
  e : VoicePoolError,
) -> BoundVoicePoolError {
  match e {
    VoicePoolError::InvalidMaxVoices => BoundVoicePoolError::InvalidMaxVoices
    VoicePoolError::OrphanAdsr => BoundVoicePoolError::OrphanAdsr
    VoicePoolError::CompileRejected => BoundVoicePoolError::CompileRejected
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `moon check`
Expected: clean. Type is declared but not yet used.

- [ ] **Step 3: Commit**

```bash
git add voice/voice.mbt
git commit -m "$(cat <<'EOF'
feat(voice): add VoicePoolError enum + BoundVoicePoolError::from_voice_pool

Mirrors BoundVoicePoolError minus Binding(...) (VoicePool has no
bindings). Mapping helper lifts a VoicePoolError into the
BoundVoicePoolError that BoundVoicePool's public API still returns.

Type is unused until later tasks migrate VoicePool to Result-typed
returns and rewire validate_voice_template.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Internal migration (no public-surface change yet)

### Task 4: Rewire `validate_voice_template` to return `Result[Unit, VoicePoolError]`

**Files:**
- Modify: `voice/voice.mbt` (lines around 168-181)

- [ ] **Step 1: Change the return type and error variants**

In `voice/voice.mbt`, replace the `validate_voice_template` body:

```moonbit
///|
fn validate_voice_template(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> Result[Unit, VoicePoolError] {
  if compiled_template.orphan_adsr_count() > 0 {
    return Err(VoicePoolError::OrphanAdsr)
  }
  if CompiledDsp::compile_template(compiled_template, context) is None {
    return Err(VoicePoolError::CompileRejected)
  }
  Ok(())
}
```

- [ ] **Step 2: Update callers to map**

Find the existing caller in `VoicePool::new_validated` (around line 184-208). Update the match arm:

```moonbit
  match validate_voice_template(compiled_template, context) {
    Err(error) => return Err(error)  // already returns VoicePoolError, no map needed at the inner pool
    Ok(_) => ()
  }
```

For `BoundVoicePool::new` (find via `grep -n "validate_voice_template" voice/voice.mbt`), update the call site to map:

```moonbit
  match validate_voice_template(compiled_template, context) {
    Err(error) => return Err(BoundVoicePoolError::from_voice_pool(error))
    Ok(_) => ()
  }
```

Note: `VoicePool::new_validated` currently returns `Result[..., BoundVoicePoolError]`. That signature is updated later (Task 10); for now, also adjust this call site to lift:

```moonbit
  match validate_voice_template(compiled_template, context) {
    Err(error) => return Err(BoundVoicePoolError::from_voice_pool(error))
    Ok(_) => ()
  }
```

- [ ] **Step 3: Run check + test**

Run: `moon check && moon test voice/`
Expected: green. The change is type-internal — `validate_voice_template` now returns the lower-level type, and the only callers (which already return BoundVoicePoolError) map via `from_voice_pool`.

- [ ] **Step 4: Commit**

```bash
git add voice/voice.mbt
git commit -m "$(cat <<'EOF'
refactor(voice): validate_voice_template returns VoicePoolError, callers map

Lower-level type owns the variants; higher-level type wraps. Callers
that still return BoundVoicePoolError use BoundVoicePoolError::from_voice_pool.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Migrate `VoicePool` internal storage to `FixedArray[Int]` ADSR snapshot

**Files:**
- Modify: `voice/voice.mbt` (struct + constructor + gate_all_adsrs callers)

- [ ] **Step 1: Update VoicePool struct fields**

Find the `pub struct VoicePool` block (around line 157) and replace:

```moonbit
pub struct VoicePool {
  priv slots : FixedArray[VoiceSlot]
  priv adsr_authoring_indices : FixedArray[Int]  // was: mut template : Array[DspNode]
  priv mut compiled_template : CompiledTemplate
  priv compile_context : DspContext
  priv mut next_allocation_order : Int
  priv max_voices : Int
  priv mut last_sanitized_count : Int
}
```

(The `template` field is removed; `adsr_authoring_indices` replaces it.)

- [ ] **Step 2: Update `VoicePool::new_validated` to compute the snapshot**

Replace the field-population block in `new_validated`:

```moonbit
  Ok({
    slots,
    adsr_authoring_indices: compiled_template.adsr_authoring_indices(),
    compiled_template,
    compile_context: context,
    next_allocation_order: 0,
    max_voices,
    last_sanitized_count: 0,
  })
```

The `template` parameter to `new_validated` (Array[DspNode]) is now unused for storage — it's only needed for the deprecated public `VoicePool::new(Array, ...)` adapter that Task 11 removes. Keep it for now (Phase 2 preserves public signatures).

- [ ] **Step 3: Find and update VoiceSlot struct + allocation**

Find `pub struct VoiceSlot` (around line ~70-80). Replace `template_snapshot : Array[DspNode]` with `adsr_authoring_indices_snapshot : FixedArray[Int]`. Update `VoiceSlot::new` accordingly to initialize the new field (empty FixedArray).

Find slot allocation (the line where `slot.template_snapshot = self.template` exists at line 506) and replace:

```moonbit
slot.adsr_authoring_indices_snapshot = self.adsr_authoring_indices.copy()
```

`.copy()` is a defensive copy — required to avoid sharing the mutable FixedArray across slots that need to survive a hot-swap.

- [ ] **Step 4: Update `gate_all_adsrs` signature**

Find `fn gate_all_adsrs` (around line 123). Replace:

```moonbit
///|
/// Gate on or off all surviving ADSR nodes using authoring indices.
/// WHY authoring indices: CompiledDsp::gate_on/gate_off accept original
/// authoring indices and internally map through index_map (which
/// accounts for optimizer elimination + topological reordering).
fn gate_all_adsrs(
  compiled : CompiledDsp,
  authoring_indices : FixedArray[Int],
  gate_on : Bool,
) -> Unit {
  for n in 0..<authoring_indices.length() {
    let i = authoring_indices[n]
    if gate_on {
      ignore(compiled.gate_on(i))
    } else {
      ignore(compiled.gate_off(i))
    }
  }
}
```

- [ ] **Step 5: Update all `gate_all_adsrs` call sites**

Find call sites with `moon ide find-references gate_all_adsrs` (semantic — won't match comments or string literals). Cross-check with grep:

```bash
grep -n "gate_all_adsrs" voice/voice.mbt
```

The two lists should match. Two argument patterns to update:

- Calls passing `self.template` → pass `self.adsr_authoring_indices`
- Calls passing `slot.template_snapshot` → pass `slot.adsr_authoring_indices_snapshot`

Around lines 540 and 571, replace `slot.template_snapshot` arguments with `slot.adsr_authoring_indices_snapshot`.

- [ ] **Step 6: Verify compilation**

Run: `moon check`
Expected: clean. If any uses of `self.template` or `slot.template_snapshot` remain, the compiler will flag them.

- [ ] **Step 7: Run tests**

Run: `moon test voice/`
Expected: all existing voice tests + PR-2 pinning tests pass. If any fail, the snapshot semantics drifted — investigate.

- [ ] **Step 8: Commit**

```bash
git add voice/voice.mbt
git commit -m "$(cat <<'EOF'
refactor(voice): replace template Array[DspNode] storage with adsr_authoring_indices FixedArray[Int]

VoicePool and VoiceSlot no longer hold the authoring template — only
the indices needed for gating. gate_all_adsrs now takes the snapshot
directly. VoiceSlot copies the snapshot at allocation so hot-swap
preserves OLD ADSR set for already-sounding voices.

Public signatures unchanged in this commit; surface swap in later
task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Migrate `GraphTemplateDoc::compile` / `compile_stereo` internals

**Files:**
- Modify: `graph/graph_identity.mbt` (around line 247, `GraphTemplateDoc::compile`)

- [ ] **Step 1: Find current implementations**

Run: `grep -n "fn GraphTemplateDoc::compile" graph/graph_identity.mbt`
Expected: two matches (`compile` and `compile_stereo`).

- [ ] **Step 2: Update both to use `compile_template`**

Replace the body of `GraphTemplateDoc::compile`:

```moonbit
pub fn GraphTemplateDoc::compile(
  self : GraphTemplateDoc,
  context : DspContext,
) -> CompiledDsp? {
  CompiledDsp::compile_template(self.analyze(), context)
}
```

And the stereo variant:

```moonbit
pub fn GraphTemplateDoc::compile_stereo(
  self : GraphTemplateDoc,
  context : DspContext,
) -> CompiledStereoDsp? {
  CompiledStereoDsp::compile_template(self.analyze(), context)
}
```

Public signatures unchanged.

- [ ] **Step 3: Run check + test**

Run: `moon check && moon test graph/`
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add graph/graph_identity.mbt
git commit -m "$(cat <<'EOF'
refactor(graph): route GraphTemplateDoc::compile through compile_template internally

Public signatures unchanged. After Task 10 collapses compile_template
into compile(CompiledTemplate, ctx), this routing keeps working.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Audit other internal callers of `CompiledDsp::compile(Array, ctx)`

**Files:**
- Read: all `.mbt` files under `scheduler/`, `browser/`, `cmd/`, `song/`, root.

**Tooling note:** This task uses `moon ide find-references` for the audit. Per the MoonBit agent guide, `moon ide find-references` is semantic-aware — it finds actual call sites, not matches in comments or strings. The list it returns is authoritative; the `grep` fallback below is a sanity check, not the primary tool.

- [ ] **Step 1: Find all internal call sites with `moon ide`**

Run: `moon ide find-references CompiledDsp::compile`
Expected: a list of every call site of `CompiledDsp::compile` (currently the Array-taking overload). Likely locations: `scheduler/`, `browser/`, integration tests, root `moondsp_test.mbt`.

Run: `moon ide find-references CompiledStereoDsp::compile`
Expected: same for stereo.

Save both lists. Task 10's `moon ide rename` will cross-check this set after the surface swap.

- [ ] **Step 1b: Sanity-check with grep**

Run: `grep -rn "CompiledDsp::compile\b\|CompiledStereoDsp::compile\b" --include="*.mbt" | grep -v "_build\|.worktrees\|archive" | grep -v "compile_template\|compile_raw"`
Expected: should approximately match `moon ide find-references` output. If grep finds *more* matches than `find-references`, the extras are in comments or strings (ignore). If `find-references` finds matches grep missed, investigate (rare — usually means a generic call you wouldn't catch with literal text).

- [ ] **Step 2: Rewrite each call site**

For each call `CompiledDsp::compile(nodes, ctx)` (where `nodes` is `Array[DspNode]`), replace with:

```moonbit
CompiledDsp::compile_template(CompiledTemplate::analyze(nodes), ctx)
```

Do the same for stereo. After Task 10 renames `compile_template` back to `compile`, these become `CompiledDsp::compile(CompiledTemplate::analyze(nodes), ctx)`.

- [ ] **Step 3: Run check + test after each file edited**

Run: `moon check`
Expected: clean. If a file is missed, `moon check` flags it.

After all files done:

Run: `moon test`
Expected: all tests pass.

- [ ] **Step 4: Commit (one commit per file, or single if minimal)**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: route internal CompiledDsp::compile callers through compile_template

Prepares for Task 10's surface swap (compile_template → compile). All
call sites now use the CompiledTemplate-taking form; the Array-taking
overload exists only at the public surface and is removed in Task 10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Audit internal callers of `VoicePool::new(Array, ...)` and `set_template`

**Files:**
- Read: `scheduler/`, `browser/`, `cmd/`, integration tests.

- [ ] **Step 1: Find call sites with `moon ide find-references`**

Run each:
```bash
moon ide find-references VoicePool::new
moon ide find-references VoicePool::set_template
moon ide find-references BoundVoicePool::new
moon ide find-references BoundVoicePool::set_template
```

Expected: a list of every call site, semantic-aware (won't match comments / string literals).

- [ ] **Step 1b: Sanity-check with grep**

```bash
grep -rn "VoicePool::new\|VoicePool::set_template\|BoundVoicePool::new\|BoundVoicePool::set_template" --include="*.mbt" | grep -v "_build\|.worktrees\|archive\|voice_pinning_test"
```

Approximately matches `find-references` output; divergences are informative (grep extras = comments; `find-references` extras = generic calls).

- [ ] **Step 2: Adjust internal callers to pre-analyze**

For each call where the caller has an `Array[DspNode]`, change to first construct a CompiledTemplate:

Before:
```moonbit
let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
```

After (during Phase 2 — public sig still takes Array, so this is identity):
```moonbit
let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()  // unchanged for now
```

Actually skip this task. Internal callers don't need to change until Task 11/12 swaps the public signature. The reason internal `CompiledDsp::compile` callers got rewritten in Task 7 is that the surface swap in Task 10 RENAMES the function (compile_template → compile); we have to update internal callers FIRST to use the new name. For VoicePool, the function name `VoicePool::new` doesn't change — only its parameters do — so internal callers naturally migrate when the signature swaps in Task 11.

- [ ] **Step 3: No commit (task is a no-op verification)**

Verified: internal callers don't need pre-migration for VoicePool because the function name is preserved.

---

### Task 9: Run full check before surface swap

**Files:**
- None to edit.

- [ ] **Step 1: Verify Phase 2 baseline**

Run: `moon check && moon test && moon fmt --check`
Expected: all green.

- [ ] **Step 2: Verify .mbti hasn't drifted from Phase 1 baseline**

Run: `moon info && git diff --stat | grep "\.mbti$"`
Expected: only the .mbti changes you intend (new public functions from Phase 1: `CompiledTemplate::adsr_authoring_indices`, `GraphBuilder::analyze`, `VoicePoolError`, `BoundVoicePoolError::from_voice_pool`).

If any unintended .mbti drift, audit the offending diff.

- [ ] **Step 3: Commit any .mbti regeneration**

```bash
git add -A
git commit -m "chore: regenerate .mbti for Phase 1 additions" || echo "no changes"
```

---

## Phase 3 — Surface swap (the breaking changes)

### Task 10: Collapse `compile_template` into `compile` (mono + stereo)

**Files:**
- Modify: `graph/graph_compile.mbt` (or wherever `CompiledDsp::compile` / `compile_template` live — confirm location via `moon ide peek-def`)

**Tooling note:** This task uses `moon ide rename` for the call-site migration. Per the MoonBit agent guide, `moon ide rename` is semantic — it won't match `compile_template` inside a comment, string literal, or already-deprecated wrapper, the way a `grep` migration would. Always prefer `moon ide rename` over manual find/replace for symbol renames.

- [ ] **Step 1: Locate the symbols**

Run: `moon ide peek-def CompiledDsp::compile_template`
Expected: shows the file and line number of the definition. Record this location — you need it for `moon ide rename` if there are multiple symbols named `compile_template` (e.g., mono + stereo).

Run: `moon ide peek-def CompiledStereoDsp::compile_template`
Expected: same for stereo.

Run: `moon ide find-references CompiledDsp::compile`
Expected: shows every call site of the *Array-taking* version that's about to be deleted. Save this list — you'll cross-check against it after Step 4.

- [ ] **Step 2: Delete `CompiledDsp::compile(Array, ctx)` and the stereo counterpart**

Find `pub fn CompiledDsp::compile(nodes : Array[DspNode], context : DspContext) -> CompiledDsp?` (use `moon ide peek-def` from Step 1) and delete it.

Same for `pub fn CompiledStereoDsp::compile(nodes : Array[DspNode], context : DspContext) -> CompiledStereoDsp?`.

At this point `moon check` will fail at every call site that used the deleted overload (the ones `find-references` listed in Step 1). That's intentional — Step 4 fixes them.

- [ ] **Step 3: Rename `compile_template` → `compile` via `moon ide rename`**

For mono:

```bash
moon ide rename compile_template compile --loc <file>:<line>:<col>
```

Use the `--loc` from Step 1's `peek-def` output. The tool atomically renames the definition AND every call site in the project, semantic-aware (skips comments, strings, deprecated wrappers).

For stereo:

```bash
moon ide rename compile_template compile --loc <stereo-file>:<line>:<col>
```

If the mono rename already produced a name collision because both `CompiledDsp::compile_template` and `CompiledStereoDsp::compile_template` exist in the same scope, run the second `--loc`-disambiguated rename after the first.

- [ ] **Step 4: Verify no `compile_template` remnants**

Run: `moon ide find-references compile_template`
Expected: empty (the symbol no longer exists).

Run: `grep -rn "compile_template\b" --include="*.mbt" | grep -v "_build\|.worktrees\|archive\|temporary_equivalence_pins"`
Expected: empty. If any matches appear, they're in comments or docstrings the rename didn't touch — update manually.

Sites that should have been auto-updated: `voice/voice.mbt` (in `validate_voice_template`), `graph/graph_identity.mbt` (in `GraphTemplateDoc::compile/compile_stereo`), and the callers rewritten in Task 7.

- [ ] **Step 5: Run check + test**

Run: `moon check`
Expected: clean except for the PR-2 `*_temporary_equivalence_pins.mbt` file, which still references the deleted `CompiledDsp::compile(Array, ctx)`. Task 16 deletes that file.

Run: `moon test`
Expected: most tests pass. The PR-2 equivalence pins fail (as just noted) — that's expected.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(graph)!: collapse compile_template into compile(CompiledTemplate, ctx)

CompiledDsp::compile(Array) is removed. CompiledDsp::compile now takes
CompiledTemplate directly. Same for stereo. The PR-2 temporary
equivalence pins now FAIL — Task 16 deletes them.

BREAKING: external consumers must migrate
  CompiledDsp::compile(nodes, ctx)
→ CompiledDsp::compile(CompiledTemplate::analyze(nodes), ctx)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Migrate `VoicePool::new` to take `CompiledTemplate` and return `Result`

**Files:**
- Modify: `voice/voice.mbt` (around line 213-291)

- [ ] **Step 1: Update `VoicePool::new` signature and body**

Find `pub fn VoicePool::new(template : Array[DspNode], context : DspContext, max_voices~ : Int = 16) -> VoicePool?` and replace:

```moonbit
///|
pub fn VoicePool::new(
  compiled_template : CompiledTemplate,
  context : DspContext,
  max_voices~ : Int = 16,
) -> Result[VoicePool, VoicePoolError] {
  if max_voices <= 0 {
    return Err(VoicePoolError::InvalidMaxVoices)
  }
  match validate_voice_template(compiled_template, context) {
    Err(error) => Err(error)  // already VoicePoolError, no map
    Ok(_) => {
      let block_size = context.block_size()
      let slots = FixedArray::makei(max_voices, _ => VoiceSlot::new(block_size))
      Ok({
        slots,
        adsr_authoring_indices: compiled_template.adsr_authoring_indices(),
        compiled_template,
        compile_context: context,
        next_allocation_order: 0,
        max_voices,
        last_sanitized_count: 0,
      })
    }
  }
}
```

The `new_validated` private function may be redundant after this — if so, remove it (and update `BoundVoicePool::new` to call `VoicePool::new` directly with the mapping).

- [ ] **Step 2: Update `VoicePool::set_template` signature**

Find and replace:

```moonbit
///|
pub fn VoicePool::set_template(
  self : VoicePool,
  compiled_template : CompiledTemplate,
) -> Result[Unit, VoicePoolError] {
  match validate_voice_template(compiled_template, self.compile_context) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.compiled_template = compiled_template
  self.adsr_authoring_indices = compiled_template.adsr_authoring_indices()
  Ok(())
}
```

- [ ] **Step 3: Update internal callers**

Primary lookup (semantic, ignores comments and matches by symbol identity):

```bash
moon ide find-references VoicePool::new
moon ide find-references VoicePool::set_template
```

Sanity check (catches any sites the semantic search misses — comments, doc snippets, mbt.md tests):

```bash
grep -rn "VoicePool::new\b\|VoicePool::set_template\b" --include="*.mbt" --include="*.mbt.md" \
  | grep -v "_build\|.worktrees\|archive"
```

The two lists should agree on every `.mbt` call site. Discrepancies usually mean a doc snippet or a `.mbt.md` block — review by hand.

For each caller passing `Array[DspNode]`, wrap with `CompiledTemplate::analyze(...)`:

Before:
```moonbit
let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
```

After:
```moonbit
let pool = VoicePool::new(
  CompiledTemplate::analyze(nodes), ctx, max_voices=4,
).unwrap()
```

For `unwrap()` on the new Result type: `.unwrap()` still works on `Result[T, _]`. If you want to be explicit, use `.unwrap()` or `match` to handle the error.

PR-2 closure `pr2_a2_closure` in `voice/voice_pinning_test.mbt` needs the closure body swap from Phase 4 Task 17 — defer until then.

- [ ] **Step 4: Run check + test**

Run: `moon check`
Expected: clean.

Run: `moon test`
Expected: most tests pass. The temporary equivalence pins still fail (deleted in Task 16).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(voice)!: VoicePool::new and set_template migrate to CompiledTemplate + Result

VoicePool::new(CompiledTemplate, ctx, max_voices?) -> Result[Self, VoicePoolError]
VoicePool::set_template(Self, CompiledTemplate) -> Result[Unit, VoicePoolError]

Internal callers wrap arrays via CompiledTemplate::analyze.

BREAKING: external consumers must migrate to the new shape. See
ADR-0010 for the contract.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Migrate `BoundVoicePool::new` and `set_template`

**Files:**
- Modify: `voice/voice.mbt`

- [ ] **Step 1: Update `BoundVoicePool::new` signature**

Find `pub fn BoundVoicePool::new(template : Array[DspNode], context : DspContext, builder : ControlBindingBuilder, max_voices~ : Int = 16) -> Result[BoundVoicePool, BoundVoicePoolError]`. Replace `template : Array[DspNode]` with `compiled_template : CompiledTemplate`. Replace internal `CompiledTemplate::analyze(template)` calls with direct use of `compiled_template`. Internal mapping via `BoundVoicePoolError::from_voice_pool` already in place from Task 4.

- [ ] **Step 2: Update `BoundVoicePool::set_template` signature**

Same pattern: replace `template : Array[DspNode]` with `compiled_template : CompiledTemplate` in the parameter list; remove internal `analyze` call.

- [ ] **Step 3: Update internal callers**

Primary lookup:

```bash
moon ide find-references BoundVoicePool::new
moon ide find-references BoundVoicePool::set_template
```

Sanity check:

```bash
grep -rn "BoundVoicePool::new\b\|BoundVoicePool::set_template\b" --include="*.mbt" --include="*.mbt.md" \
  | grep -v "_build\|.worktrees\|archive"
```

The two lists should agree on every `.mbt` call site. Discrepancies usually mean a doc snippet or a `.mbt.md` block — review by hand.

For each caller passing `Array[DspNode]`, wrap with `CompiledTemplate::analyze(...)`.

- [ ] **Step 4: Run check + test**

Run: `moon check && moon test`
Expected: most tests pass; A4 tests in `voice_pinning_test.mbt` will pass since the closure passes through.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(voice)!: BoundVoicePool::new and set_template migrate to CompiledTemplate input

Signatures change input type only — Result[..., BoundVoicePoolError]
return is unchanged. Internal callers wrap via CompiledTemplate::analyze.

BREAKING: external consumers update input type.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Make `optimize_graph` package-private

**Files:**
- Modify: `graph/graph_optimize.mbt`
- Move: `graph/graph_optimize_test.mbt` → `graph/graph_optimize_wbtest.mbt`
- Modify: `moondsp.mbt` (remove re-export at line 108)

- [ ] **Step 1: Drop `pub` from `optimize_graph`**

In `graph/graph_optimize.mbt`, find `pub fn optimize_graph(...)` and remove `pub`:

```moonbit
fn optimize_graph(
  nodes : Array[DspNode],
) -> (Array[DspNode], FixedArray[Int]) {
  // body unchanged
}
```

- [ ] **Step 2: Rename blackbox test to whitebox**

```bash
mv graph/graph_optimize_test.mbt graph/graph_optimize_wbtest.mbt
```

Whitebox tests run in the same package and can access package-private functions.

- [ ] **Step 3: Remove `optimize_graph` from root facade**

Open `moondsp.mbt`. Find the re-export at line 108 (`  optimize_graph,`) inside the `pub using @graph { ... }` block and delete it.

- [ ] **Step 4: Verify check + test**

Run: `moon check`
Expected: clean. If `optimize_graph` is called from outside `graph/` package without going through the now-removed re-export, the compiler flags it.

Run: `moon test graph/`
Expected: all graph tests pass, including the migrated `graph_optimize_wbtest.mbt`.

- [ ] **Step 5: Commit**

```bash
git add graph/graph_optimize.mbt graph/graph_optimize_wbtest.mbt moondsp.mbt
git rm graph/graph_optimize_test.mbt 2>/dev/null || true
git commit -m "$(cat <<'EOF'
refactor(graph)!: make optimize_graph package-private; migrate test to whitebox

CompiledTemplate::analyze is the only blessed caller. Root facade
re-export removed. Test moved from blackbox to whitebox to retain
direct access to the now-private function.

BREAKING: external consumers must use CompiledTemplate::analyze instead.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Add `VoicePoolError` re-export to root facade

**Files:**
- Modify: `moondsp.mbt` (around line 114)

- [ ] **Step 1: Add the re-export**

In `moondsp.mbt`, inside the `pub using @voice { ... }` block, add `VoicePoolError` to the alphabetically-sorted type list:

```moonbit
pub using @voice {
  type BoundVoicePool,
  type BoundVoicePoolError,
  type VoiceControlError,
  type VoiceHandle,
  type VoicePool,
  type VoicePoolError,   // new
  type VoiceState,
}
```

- [ ] **Step 2: Verify check + .mbti regeneration**

Run: `moon check && moon info`
Expected: clean. The root `.mbti` now includes `VoicePoolError` as a re-exported type.

- [ ] **Step 3: Commit**

```bash
git add moondsp.mbt pkg.generated.mbti
git commit -m "$(cat <<'EOF'
feat: re-export VoicePoolError from root facade

Root-facade users can now pattern-match VoicePool::new Results
ergonomically via @moondsp.VoicePoolError variants.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Cleanup

### Task 15: Add tests B7 (VoicePoolError variant coverage)

**Files:**
- Modify: `voice/voice_test.mbt` (or create `voice/voice_pool_error_test.mbt`)

- [ ] **Step 1: Write variant coverage tests**

Append to `voice/voice_test.mbt` (or create the new file):

```moonbit
///| B7: VoicePoolError::InvalidMaxVoices fires under max_voices <= 0.
test "B7: VoicePool::new with max_voices=0 returns InvalidMaxVoices" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let template = @graph.CompiledTemplate::analyze(nodes)
  @debug.assert_eq(
    VoicePool::new(template, ctx, max_voices=0),
    Err(VoicePoolError::InvalidMaxVoices),
  )
}

///| B7: VoicePoolError::OrphanAdsr fires for dead-code ADSR.
test "B7: VoicePool::new with orphan ADSR returns OrphanAdsr" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::adsr(
      attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0,
    ),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let template = @graph.CompiledTemplate::analyze(nodes)
  @debug.assert_eq(
    VoicePool::new(template, ctx, max_voices=4),
    Err(VoicePoolError::OrphanAdsr),
  )
}

///| B7: VoicePoolError::CompileRejected fires for missing Output.
test "B7: VoicePool::new with missing Output returns CompileRejected" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let template = @graph.CompiledTemplate::analyze(nodes)
  @debug.assert_eq(
    VoicePool::new(template, ctx, max_voices=4),
    Err(VoicePoolError::CompileRejected),
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon test voice/`
Expected: 3 new tests pass.

- [ ] **Step 3: Commit**

```bash
git add voice/voice_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): add B7 VoicePoolError variant coverage tests

Each VoicePoolError variant verified to fire under the right condition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Delete PR-2 temporary equivalence pins

**Files:**
- Delete: `graph/graph_compile_temporary_equivalence_pins.mbt`

- [ ] **Step 1: Delete the file**

```bash
git rm graph/graph_compile_temporary_equivalence_pins.mbt
```

The file's tests reference `CompiledDsp::compile(Array, ctx)` which no longer exists; deleting is the planned cleanup.

- [ ] **Step 2: Verify check + test**

Run: `moon check && moon test`
Expected: all tests pass. Test count drops by 3 (the A1 pins).

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(graph): delete A1 temporary equivalence pins from PR 2

Pins compared compile(Array) vs compile_template(analyze(...)); both
no longer exist after the migration (compile_template renamed to
compile, compile(Array) removed). Persistent A2/A3/A4 behavior tests
in voice/voice_pinning_test.mbt survive after closure-body swap in
Task 17.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Swap PR-2 closures to use new APIs

**Files:**
- Modify: `voice/voice_pinning_test.mbt`

- [ ] **Step 1: Rewrite `pr2_a2_closure`**

Replace the body:

```moonbit
fn pr2_a2_closure(
  nodes : Array[@graph.DspNode],
  ctx : @dsp.DspContext,
  max_voices : Int,
) -> Result[@voice.VoicePool, A2Reason] {
  @voice.VoicePool::new(
    @graph.CompiledTemplate::analyze(nodes), ctx, max_voices~,
  )
    .map_err(fn (e) {
      match e {
        @voice.VoicePoolError::InvalidMaxVoices => A2Reason::InvalidMaxVoices
        @voice.VoicePoolError::OrphanAdsr => A2Reason::OrphanAdsr
        @voice.VoicePoolError::CompileRejected => A2Reason::CompileRejected
      }
    })
}
```

The pre-classifier is deleted — the real API returns the variant directly.

- [ ] **Step 2: Rewrite `pr2_a3_closure`**

```moonbit
fn pr2_a3_closure(
  pool : @voice.VoicePool,
  nodes : Array[@graph.DspNode],
) -> Result[Unit, A3Reason] {
  @voice.VoicePool::set_template(pool, @graph.CompiledTemplate::analyze(nodes))
    .map_err(fn (e) {
      match e {
        @voice.VoicePoolError::OrphanAdsr => A3Reason::OrphanAdsr
        @voice.VoicePoolError::CompileRejected => A3Reason::CompileRejected
        @voice.VoicePoolError::InvalidMaxVoices => A3Reason::CompileRejected
        // unreachable: set_template doesn't take max_voices, but match must be total
      }
    })
}
```

- [ ] **Step 3: Rewrite `pr2_a4_closure`**

```moonbit
fn pr2_a4_closure(
  nodes : Array[@graph.DspNode],
  ctx : @dsp.DspContext,
  builder : @graph.ControlBindingBuilder,
  max_voices : Int,
) -> Result[@voice.BoundVoicePool, @voice.BoundVoicePoolError] {
  @voice.BoundVoicePool::new(
    @graph.CompiledTemplate::analyze(nodes), ctx, builder, max_voices~,
  )
}
```

Only the input wrapper changed.

- [ ] **Step 4: Run tests**

Run: `moon test voice/`
Expected: all PR-2 persistent tests still pass with the new closure bodies. If any fail, the behavior pinned in PR 2 has drifted — investigate before continuing.

- [ ] **Step 5: Commit**

```bash
git add voice/voice_pinning_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): swap PR-2 closures to use new Result-typed VoicePool APIs

Pre-classifiers deleted; closures now collapse to one-line calls plus
a variant map. Persistent property tests survive unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: Add `scripts/check-public-boundary.sh`

**Files:**
- Create: `scripts/check-public-boundary.sh`

- [ ] **Step 1: Write the script**

Create `scripts/check-public-boundary.sh`:

```bash
#!/usr/bin/env bash
#
# Audits public .mbti files for Array[DspNode] entries. Asserts only
# documented boundary exceptions and allowed authoring APIs appear.
# New entries fail the script.
#
# See docs/decisions/0010-compiled-template-runtime-boundary.md for
# the complete carve-out list.

set -euo pipefail

# Regenerate .mbti files
moon info >/dev/null

# Allowed patterns (regex, matches the full line from .mbti).
# Update this list when ADR-0010 carve-outs change.
ALLOWED_PATTERNS=(
  # Boundary exceptions
  "^pub fn\[T : .*\] replay\(Array\[DspNode\]\)"
  "^pub fn CompiledDspTopologyController::from_nodes\(Array\[DspNode\]"
  "^pub fn CompiledStereoDspTopologyController::from_nodes\(Array\[DspNode\]"
  # Allowed authoring APIs
  "^pub fn CompiledTemplate::analyze\(Array\[DspNode\]\)"
  "^pub fn GraphBuilder::nodes\(Self\) -> Array\[DspNode\]"
  "^pub fn GraphTemplateDoc::nodes\(Self\) -> Array\[DspNode\]"
  "^pub fn GraphTemplateDoc::from_nodes\("
  "^pub fn GraphTemplateDoc::insert_chain\("
  "^pub fn GraphIndexMap::insert_chain\("
  "^pub fn GraphTopologyEdit::insert_chain\("
  "^  InsertChain\(Int, GraphTopologyInputSlot, Array\[DspNode\]\)"
)

FILES=(
  "graph/pkg.generated.mbti"
  "voice/pkg.generated.mbti"
  "pkg.generated.mbti"
)

violations=()
for file in "${FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi
  while IFS= read -r line; do
    # Skip lines without Array[DspNode] reference
    if ! echo "$line" | grep -qE 'Array\[(@?[a-z]+\.)?DspNode\]'; then
      continue
    fi
    matched=0
    for pat in "${ALLOWED_PATTERNS[@]}"; do
      if echo "$line" | grep -qE "$pat"; then
        matched=1
        break
      fi
    done
    if [[ $matched -eq 0 ]]; then
      violations+=("$file: $line")
    fi
  done < "$file"
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: Public Array[DspNode] entries not in ADR-0010 carve-out list:"
  printf '  %s\n' "${violations[@]}"
  echo ""
  echo "Either:"
  echo "  1. Migrate the entry to CompiledTemplate (preferred), or"
  echo "  2. Update ALLOWED_PATTERNS in scripts/check-public-boundary.sh"
  echo "     AND add the new exception to ADR-0010 with rationale."
  exit 1
fi

echo "OK: all public Array[DspNode] entries match ADR-0010 carve-outs."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/check-public-boundary.sh
```

- [ ] **Step 3: Run locally**

Run: `./scripts/check-public-boundary.sh`
Expected: `OK: all public Array[DspNode] entries match ADR-0010 carve-outs.` If violations reported, the allowed patterns are incomplete or a public API leaked — investigate.

- [ ] **Step 4: Commit**

```bash
git add scripts/check-public-boundary.sh
git commit -m "$(cat <<'EOF'
ci(scripts): add check-public-boundary.sh enforcing ADR-0010 carve-outs

Greps public .mbti files for Array[DspNode] entries; fails on entries
not in the allowlist. Allowlist mirrors ADR-0010's documented
boundary exceptions and allowed authoring APIs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: Add GitHub Actions workflow for the boundary check

**Files:**
- Create: `.github/workflows/boundary-check.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/boundary-check.yml`:

```yaml
name: Boundary Check

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  check-boundary:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install MoonBit
        run: |
          curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
          echo "$HOME/.moon/bin" >> $GITHUB_PATH

      - name: Update moon
        run: moon update

      - name: Install deps
        run: moon install

      - name: Run boundary check
        run: ./scripts/check-public-boundary.sh
```

- [ ] **Step 2: Verify locally**

Run: `cat .github/workflows/boundary-check.yml | grep -c "scripts/check-public-boundary"`
Expected: `1`. If the existing browser-smoke.yml workflow has a setup section worth copying for the moon install steps, copy that pattern.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/boundary-check.yml
git commit -m "$(cat <<'EOF'
ci: add boundary-check workflow enforcing ADR-0010 carve-outs on PRs

Triggers on PR + push to main. Fails if scripts/check-public-boundary.sh
finds a public Array[DspNode] entry outside the documented allowlist.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: Strip "planned per ADR-0010" qualifiers from PR 1 docs

**Files:**
- Modify: `docs/salat-engine-technical-reference.md`
- Modify: `docs/salat-engine-blueprint.md`

- [ ] **Step 1: Find all "planned per ADR-0010" markers**

Run: `grep -n "planned per ADR-0010\|Planned per ADR-0010" docs/salat-engine-technical-reference.md docs/salat-engine-blueprint.md`
Expected: ~9 matches from PR 1 (5 tech-ref + 2 blueprint + 2 hot-swap mono/stereo).

- [ ] **Step 2: Rewrite each touchpoint**

For each marker, remove the "Planned per ADR-0010 (Proposed): X. Current behavior: Y." structure. Keep only the new-behavior description. Example:

Before (PR 1 wording):
```markdown
**Planned per ADR-0010 (Proposed):** `CompiledDsp::compile` will accept
`CompiledTemplate` directly; the current `Array[DspNode]` overload and
the separate `compile_template` accessor collapse into a single entry
point. Current behavior: ...
```

After (PR 3 wording):
```markdown
`CompiledDsp::compile(CompiledTemplate, DspContext) -> Self?` is the
single entry point. `CompiledTemplate::analyze(Array[DspNode])`
produces the input; see ADR-0010 for the boundary contract.
```

Do this for all touchpoints in tech-ref and blueprint. Hot-swap examples keep only the new CompiledTemplate-based form.

- [ ] **Step 3: Verify no "planned" markers remain**

Run: `grep -c "planned per ADR-0010\|Planned per ADR-0010" docs/salat-engine-technical-reference.md docs/salat-engine-blueprint.md`
Expected: `0:filename` for each.

- [ ] **Step 4: Commit**

```bash
git add docs/salat-engine-technical-reference.md docs/salat-engine-blueprint.md
git commit -m "$(cat <<'EOF'
docs: strip 'planned per ADR-0010' qualifiers; describe current behavior

ADR-0010 flips to Accepted in this PR (next task), so the docs no
longer hedge — the new boundary type is current behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — Release

### Task 21: Flip ADR-0010 status to Accepted

**Files:**
- Modify: `docs/decisions/0010-compiled-template-runtime-boundary.md`

- [ ] **Step 1: Update status line**

Find the first lines:

```markdown
- **Status:** Proposed (will flip to Accepted when PR 3 lands)
```

Replace with:

```markdown
- **Status:** Accepted
```

- [ ] **Step 2: Update the decisions README index if it tracks status**

Run: `grep "ADR-0010" docs/decisions/README.md 2>/dev/null`
If found with "Proposed", update to remove the qualifier.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0010-compiled-template-runtime-boundary.md docs/decisions/README.md 2>/dev/null
git commit -m "$(cat <<'EOF'
docs(adr): flip ADR-0010 status from Proposed to Accepted

Code migration landed this PR; the decision is in force.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 22: Add CLAUDE.md contributor one-liner

**Files:**
- Modify: `CLAUDE.md` (find the Architecture section)

- [ ] **Step 1: Find the Architecture section**

Run: `grep -n "^## Architecture" CLAUDE.md`
Expected: a line number for the Architecture heading.

- [ ] **Step 2: Add the one-liner**

In the Architecture section, after the existing bullets, add:

```markdown
- **Graph boundary types:** `Array[DspNode]` is the authoring exchange
  type; `CompiledTemplate` is the runtime exchange type. One canonical
  crossing: `CompiledTemplate::analyze`. See ADR-0010 for the contract
  and `scripts/check-public-boundary.sh` for enforcement.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude-md): add graph boundary-type contributor guidance

One-liner under Architecture: which type to take for new public APIs.
References ADR-0010 and the boundary-check script.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 23: Write CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md` (top of file)

- [ ] **Step 1: Read existing format**

Run: `head -40 CHANGELOG.md`
Note the existing format (release shape, dates, bullet style).

- [ ] **Step 2: Add v0.4.0 entry**

Insert near the top (after any "Unreleased" section if present):

```markdown
## v0.4.0 — 2026-MM-DD

**Breaking — graph runtime exchange boundary now `CompiledTemplate`.** See ADR-0010 (`docs/decisions/0010-compiled-template-runtime-boundary.md`).

### Migration

```moonbit
// Before
CompiledDsp::compile(nodes, ctx)
CompiledStereoDsp::compile(nodes, ctx)
VoicePool::new(nodes, ctx, max_voices=4)              // -> VoicePool?
VoicePool::set_template(pool, nodes)                  // -> Bool
BoundVoicePool::new(nodes, ctx, builder, max_voices=4)
BoundVoicePool::set_template(pool, nodes, builder)

// After
let template = CompiledTemplate::analyze(nodes)
CompiledDsp::compile(template, ctx)
CompiledStereoDsp::compile(template, ctx)
VoicePool::new(template, ctx, max_voices=4)           // -> Result[VoicePool, VoicePoolError]
VoicePool::set_template(pool, template)               // -> Result[Unit, VoicePoolError]
BoundVoicePool::new(template, ctx, builder, max_voices=4)
BoundVoicePool::set_template(pool, template, builder)
```

### Changes

- `CompiledDsp::compile(Array[DspNode], DspContext)` removed; `compile_template` renamed to `compile(CompiledTemplate, DspContext)`. Same for stereo.
- `VoicePool::new` and `set_template` now take `CompiledTemplate` and return `Result[..., VoicePoolError]` (variants `InvalidMaxVoices`, `OrphanAdsr`, `CompileRejected`). Mirrors `BoundVoicePoolError` minus `Binding(...)`.
- `BoundVoicePool::new` and `set_template` now take `CompiledTemplate`. Return shape unchanged.
- `optimize_graph` is now package-private. Use `CompiledTemplate::analyze` instead.
- Added `CompiledTemplate::adsr_authoring_indices(Self) -> FixedArray[Int]`.
- Added `GraphBuilder::analyze(Self) -> CompiledTemplate` sugar accessor.
- Added root-facade re-export of `VoicePoolError`.

### Not changed (carve-outs documented in ADR-0010)

- `replay(Array[DspNode])` — pre-optimize debug/round-trip.
- `Compiled{Mono,Stereo}DspTopologyController::from_nodes(Array, ctx, crossfade?)` — edit-as-you-go composites.
- `GraphBuilder::nodes`, `GraphTemplateDoc::nodes` — authoring/inspection accessors.
- `GraphTemplateDoc::from_nodes`, `::insert_chain`, `::compile`, `::compile_stereo` — authoring artifact surface.
- `GraphIndexMap::insert_chain`, `GraphTopologyEdit::InsertChain` (and constructor) — authoring payloads.

### Internal changes

- `voice/` internal storage migrated from `Array[DspNode]` snapshots to `FixedArray[Int]` ADSR-authoring-index snapshots. No behavior change for already-sounding voices across `set_template` hot-swap.
- Added `scripts/check-public-boundary.sh` + `.github/workflows/boundary-check.yml` enforcing ADR-0010 carve-outs in CI.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(changelog): add v0.4.0 entry for graph boundary-type migration

Itemizes migration table, VoicePoolError, carve-outs, and internal
voice/ storage migration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 24: External Codex CHANGELOG review

**Files:**
- None to edit (review only).

- [ ] **Step 1: Run Codex on the CHANGELOG**

Use the `mcp__codex__codex` tool with prompt:

```
Review the new v0.4.0 entry in CHANGELOG.md against the actual code
changes in this PR and the design spec at
docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md and
ADR-0010 at docs/decisions/0010-compiled-template-runtime-boundary.md.

Check:
1. Migration table accuracy — do "before" signatures match what was
   actually removed, do "after" signatures match what was actually added?
2. Carve-out list accuracy — does it match ADR-0010's carve-outs?
3. Semantic claim drift — any claim in the CHANGELOG that isn't
   supported by the actual code change?
4. Missing items — any breaking change shipped this PR that isn't in
   the CHANGELOG?

Project policy: external Codex CHANGELOG review before tagging is
required because in-house review has historically missed semantic claim
drift (this was the trigger for the v0.3.0 changelog amendment, commit
a92a3a3). Be adversarial.
```

- [ ] **Step 2: Apply Codex's findings**

For each finding, decide: edit the CHANGELOG, or push back if the finding is wrong. Re-run if substantial changes.

- [ ] **Step 3: Commit edits (if any)**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): apply Codex review feedback" || echo "no changes"
```

---

### Task 25: Bump version + final verification + push

**Files:**
- Modify: `moon.mod.json`

- [ ] **Step 1: Bump version to 0.4.0**

Find the `"version"` field in `moon.mod.json` (currently `"0.3.1"`) and update to `"0.4.0"`.

- [ ] **Step 2: Final verification**

Run:
```bash
moon check && moon test && moon fmt --check && moon info
./scripts/check-public-boundary.sh
git diff main..HEAD --stat
```

Expected:
- `moon check` clean.
- `moon test` green.
- `moon fmt --check` clean.
- `moon info` no spurious .mbti drift.
- `check-public-boundary.sh` exits 0.
- diff stat shows changes in `graph/`, `voice/`, root `moondsp.mbt`, `docs/`, `scripts/`, `.github/workflows/`, `CHANGELOG.md`, `moon.mod.json`, `CLAUDE.md`.

- [ ] **Step 3: Commit version bump**

```bash
git add moon.mod.json
git commit -m "$(cat <<'EOF'
chore: bump moon.mod.json to 0.4.0 (breaking — boundary-type migration)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Push branch and open PR**

```bash
git push -u origin feat/graph-boundary-migration
gh pr create --base main --title "feat!: promote CompiledTemplate to runtime exchange boundary (v0.4.0)" --body "$(cat <<'EOF'
## Summary

- Migrates `CompiledDsp::compile`, `CompiledStereoDsp::compile`, `VoicePool::new`/`set_template`, `BoundVoicePool::new`/`set_template` to take `CompiledTemplate` instead of `Array[DspNode]`.
- Adds `VoicePoolError` enum for Result-typed `VoicePool` returns; mirrors `BoundVoicePoolError`.
- Adds `CompiledTemplate::adsr_authoring_indices` accessor for `voice/` runtime gating.
- Adds `GraphBuilder::analyze` sugar.
- Privatizes `optimize_graph`; removes root facade re-export.
- Migrates `voice/` internal storage from `Array[DspNode]` to `FixedArray[Int]` ADSR-authoring-index snapshots.
- Flips ADR-0010 to Accepted.
- Adds `scripts/check-public-boundary.sh` + CI workflow enforcing ADR-0010 carve-outs.
- Bumps `moon.mod.json` to 0.4.0.

## Why this PR

Pre-1.0 hygiene per ADR-0010. The `Array[DspNode]` front door let `optimize_graph` run multiple times per template; the `CompiledTemplate` boundary makes single-optimize a static guarantee. ADR-0003's "topology vs runtime" principle is now enforced at the type level.

See spec: `docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md`

## Test plan

- [x] `moon check` clean.
- [x] `moon test` green (PR-2 persistent tests survive closure-body swap; B5/B6/B7/B8 new tests pass).
- [x] `moon info` shows the new public surface; .mbti diff matches the migration table in CHANGELOG.
- [x] `./scripts/check-public-boundary.sh` exits 0.
- [x] Browser smoke (`browser-smoke.yml`) green.
- [x] CHANGELOG reviewed by Codex.

## Carve-outs (NOT changed — intentional)

See ADR-0010 § Boundary exceptions for rationale.

- `replay(Array[DspNode])`
- `Compiled{Mono,Stereo}DspTopologyController::from_nodes`
- `GraphBuilder::nodes`, `GraphTemplateDoc::nodes`
- `GraphTemplateDoc::from_nodes`, `::insert_chain`, `::compile`, `::compile_stereo`
- `GraphIndexMap::insert_chain`, `GraphTopologyEdit::InsertChain`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Wait for review + merge + tag**

After PR merges:

```bash
git checkout main && git pull
git tag v0.4.0
git push origin v0.4.0
```

Then publish to mooncakes:

```bash
moon publish --dry-run    # inspect bundle; verify exclude list is complete
moon publish              # only if dry-run output is clean
```

Verify mooncakes shows v0.4.0 at `https://mooncakes.io/docs/dowdiness/moondsp@0.4.0` before announcing.
