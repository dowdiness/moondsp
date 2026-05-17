# PR 1: Graph Boundary Type — Docs Prep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land doc-only changes that establish the `CompiledTemplate`-as-runtime-boundary contract, ahead of the code migration in PR 3. ADR-0010 lands as `Proposed`; technical reference and blueprint are updated with "planned per ADR-0010" qualifiers that PR 3 strips.

**Architecture:** Five touchpoints in `docs/salat-engine-technical-reference.md`, two in `docs/salat-engine-blueprint.md`, plus one new ADR file. No code changes, no test changes. `CLAUDE.md` one-liner deferred to PR 3 (prescriptive guidance should reflect current behavior).

**Tech Stack:** Markdown only.

**Spec:** `docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md` → §Sequencing PR 1.

**Branch:** `feat/graph-boundary-docs-prep` off `main`.

**Landing path:** Single PR against `main`. Doc-only, no CI risk beyond markdown lint (if any).

---

### Task 1: Verify line-number assumptions before editing

**Files:**
- Read: `docs/salat-engine-technical-reference.md`
- Read: `docs/salat-engine-blueprint.md`

- [ ] **Step 1: Verify tech-ref line 663 area**

Run: `sed -n '655,675p' docs/salat-engine-technical-reference.md`
Expected: text mentions `CompiledDsp::compile` taking nodes, or describes the compile path as accepting `Array[DspNode]`. If not at exactly 663, find the actual line range with `grep -n "CompiledDsp::compile\|compile_template" docs/salat-engine-technical-reference.md` and record the correct ranges. The spec's line numbers were verified by Codex at spec-writing time but may have drifted.

- [ ] **Step 2: Verify tech-ref line 797 area**

Run: `sed -n '790,810p' docs/salat-engine-technical-reference.md`
Expected: similar text about `compile_template`. Record actual line if drifted.

- [ ] **Step 3: Verify tech-ref voice section (859-878)**

Run: `sed -n '855,880p' docs/salat-engine-technical-reference.md`
Expected: describes `VoicePool`, `BoundVoicePool`, references current `Array`-taking signatures. Record drift.

- [ ] **Step 4: Verify tech-ref optimize_graph claim (904-906)**

Run: `sed -n '900,910p' docs/salat-engine-technical-reference.md`
Expected: text claims "removes the previous double `optimize_graph(...)` pass." Record drift.

- [ ] **Step 5: Verify tech-ref hot-swap examples (915-925)**

Run: `sed -n '910,935p' docs/salat-engine-technical-reference.md`
Expected: `CompiledDsp::compile(old_nodes, context)` examples. Record drift.

- [ ] **Step 6: Verify blueprint line 54**

Run: `sed -n '50,60p' docs/salat-engine-blueprint.md`
Expected: text frames `DspNode enum -> compile() -> CompiledDsp`. Record drift.

- [ ] **Step 7: Verify blueprint lines 193-195**

Run: `sed -n '190,200p' docs/salat-engine-blueprint.md`
Expected: similar `DspNode -> compile -> CompiledDsp` framing. Record drift.

- [ ] **Step 8: Commit nothing yet**

This is a read-only verification task. No git activity. Proceed to Task 2 with the actual line ranges in hand.

---

### Task 2: Rewrite tech-ref compile path (around line 663)

**Files:**
- Modify: `docs/salat-engine-technical-reference.md` (lines around 663, exact range from Task 1)

- [ ] **Step 1: Apply the edit**

Replace the text describing `CompiledDsp::compile(nodes, context)` and `compile_template(template, context)` as separate paths with:

```markdown
**Planned per ADR-0010 (Proposed):** `CompiledDsp::compile` will accept
`CompiledTemplate` directly; the current `Array[DspNode]` overload and
the separate `compile_template` accessor collapse into a single entry
point. The boundary type is produced via `CompiledTemplate::analyze`.
Current behavior: `CompiledDsp::compile(Array[DspNode], DspContext) -> Self?`
alongside `CompiledDsp::compile_template(CompiledTemplate, DspContext) -> Self?`.
```

Use the Edit tool with the exact current text as `old_string` and the above as `new_string` (prepended to the current text so both states are visible).

- [ ] **Step 2: Visual review**

Run: `sed -n '655,680p' docs/salat-engine-technical-reference.md`
Expected: new "Planned per ADR-0010" paragraph appears before or alongside the current behavior description.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-technical-reference.md
git commit -m "$(cat <<'EOF'
docs(tech-ref): note planned CompiledTemplate boundary at compile path

ADR-0010 (Proposed) promotes CompiledTemplate to the runtime exchange
type; CompiledDsp::compile(Array) and compile_template collapse into
a single entry point. PR 3 strips the "planned" qualifier.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Rewrite tech-ref compile_template area (around line 797)

**Files:**
- Modify: `docs/salat-engine-technical-reference.md` (lines around 797)

- [ ] **Step 1: Apply the edit**

Replace text describing `compile_template` as a separate side door with:

```markdown
**Planned per ADR-0010 (Proposed):** `compile_template` is removed; its
behavior becomes the new `compile(CompiledTemplate, ctx)` signature.
Current behavior: separate side-door entry; see compile-path section
above for the unified shape.
```

- [ ] **Step 2: Visual review**

Run: `sed -n '790,810p' docs/salat-engine-technical-reference.md`
Expected: planned-state paragraph appears.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-technical-reference.md
git commit -m "$(cat <<'EOF'
docs(tech-ref): note planned compile_template removal at side-door section

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Rewrite tech-ref voice section (859-878)

**Files:**
- Modify: `docs/salat-engine-technical-reference.md` (lines 859-878 area)

- [ ] **Step 1: Apply the edit**

Prepend to the voice-section subsection:

```markdown
**Planned per ADR-0010 (Proposed):** `VoicePool::new` /
`VoicePool::set_template` migrate from `Array[DspNode]` to
`CompiledTemplate` inputs and from Option/Bool to
`Result[..., VoicePoolError]` returns (variants:
`InvalidMaxVoices`, `OrphanAdsr`, `CompileRejected`).
`BoundVoicePool` migrates analogously, keeping `BoundVoicePoolError`.
Current behavior described below.
```

Leave the current behavior bullets untouched.

- [ ] **Step 2: Visual review**

Run: `sed -n '855,885p' docs/salat-engine-technical-reference.md`
Expected: planned-state paragraph precedes current-behavior bullets.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-technical-reference.md
git commit -m "$(cat <<'EOF'
docs(tech-ref): note planned VoicePool CompiledTemplate + Result migration

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Rewrite tech-ref optimize_graph claim (904-906)

**Files:**
- Modify: `docs/salat-engine-technical-reference.md` (lines 904-906 area)

- [ ] **Step 1: Apply the edit**

Find the exact text: `"removes the previous double optimize_graph(...) pass from the voice-template path"` and replace with:

```markdown
removes the previous double `optimize_graph(...)` pass from the
voice-template path. **Planned per ADR-0010 (Proposed):** the boundary
type makes single-optimize a static guarantee, not just a dynamic
property — `optimize_graph` becomes package-private and runs exactly
once inside `CompiledTemplate::analyze`.
```

- [ ] **Step 2: Visual review**

Run: `sed -n '900,915p' docs/salat-engine-technical-reference.md`
Expected: planned-state addition after the original sentence.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-technical-reference.md
git commit -m "$(cat <<'EOF'
docs(tech-ref): note planned optimize_graph privatization for single-optimize guarantee

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Rewrite tech-ref hot-swap examples (915-925)

**Files:**
- Modify: `docs/salat-engine-technical-reference.md` (lines 915-925 area)

- [ ] **Step 1: Apply the edit**

Find the current mono hot-swap code block (`let active = CompiledDsp::compile(old_nodes, context).unwrap()` etc.) and add a planned-state comment block immediately above it:

````markdown
**Planned per ADR-0010 (Proposed):** the examples below become:

```moonbit
let old_template = CompiledTemplate::analyze(old_nodes)
let new_template = CompiledTemplate::analyze(new_nodes)
let active = CompiledDsp::compile(old_template, context).unwrap()
let replacement = CompiledDsp::compile(new_template, context).unwrap()
let hot_swap = CompiledDspHotSwap::from_graph(active, crossfade_samples=128)

assert(hot_swap.queue_swap(replacement))
hot_swap.process(context, output)
```

Current behavior below.
````

Do the same for the stereo example (`let active_stereo = ...`).

- [ ] **Step 2: Visual review**

Run: `sed -n '910,945p' docs/salat-engine-technical-reference.md`
Expected: planned-state code blocks appear before current-state code blocks for both mono and stereo.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-technical-reference.md
git commit -m "$(cat <<'EOF'
docs(tech-ref): note planned CompiledTemplate-first hot-swap examples

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Update tech-ref pipeline diagram

**Files:**
- Modify: `docs/salat-engine-technical-reference.md` (find the pipeline diagram)

- [ ] **Step 1: Locate the pipeline diagram**

Run: `grep -n "Array\[DspNode\]\|DspNode enum" docs/salat-engine-technical-reference.md | head -20`
Find any ASCII / mermaid / textual pipeline diagram showing the authoring→compile→runtime flow. If none, skip this task.

- [ ] **Step 2: Apply the edit (if diagram exists)**

Add an annotation alongside the diagram:

```markdown
**Planned per ADR-0010 (Proposed):** the pipeline becomes
`Array[DspNode] → CompiledTemplate::analyze → CompiledTemplate →
CompiledDsp::compile → CompiledDsp`. `CompiledTemplate` is the single
runtime exchange type. See ADR-0010 for the contract.
```

- [ ] **Step 3: Visual review**

Run: `grep -B2 -A20 "pipeline\|Pipeline" docs/salat-engine-technical-reference.md | head -50`
Expected: annotation appears alongside the diagram. If no diagram exists, this task is a no-op.

- [ ] **Step 4: Commit (if changed)**

```bash
git add docs/salat-engine-technical-reference.md
git commit -m "$(cat <<'EOF'
docs(tech-ref): annotate pipeline diagram with planned boundary type

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Update blueprint compile-flow framing (line 54)

**Files:**
- Modify: `docs/salat-engine-blueprint.md` (line 54 area)

- [ ] **Step 1: Apply the edit**

Find the text framing `DspNode enum -> compile() -> CompiledDsp` and append an inline note:

```markdown
DspNode enum -> compile() -> CompiledDsp _(planned per ADR-0010
(Proposed): DspNode -> CompiledTemplate::analyze -> CompiledTemplate ->
CompiledDsp::compile -> CompiledDsp)_
```

- [ ] **Step 2: Visual review**

Run: `sed -n '50,60p' docs/salat-engine-blueprint.md`
Expected: planned-state parenthetical present.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-blueprint.md
git commit -m "$(cat <<'EOF'
docs(blueprint): annotate compile-flow framing with planned boundary type

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Update blueprint compile-flow framing (lines 193-195)

**Files:**
- Modify: `docs/salat-engine-blueprint.md` (lines 193-195 area)

- [ ] **Step 1: Apply the edit**

Find the similar framing and apply the same inline parenthetical pattern as Task 8.

- [ ] **Step 2: Visual review**

Run: `sed -n '190,200p' docs/salat-engine-blueprint.md`
Expected: planned-state parenthetical present.

- [ ] **Step 3: Commit**

```bash
git add docs/salat-engine-blueprint.md
git commit -m "$(cat <<'EOF'
docs(blueprint): annotate second compile-flow framing with planned boundary type

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Create ADR-0010 with status Proposed

**Files:**
- Create: `docs/decisions/0010-compiled-template-runtime-boundary.md`

- [ ] **Step 1: Write the ADR file**

Create `docs/decisions/0010-compiled-template-runtime-boundary.md`:

```markdown
# ADR-0010: CompiledTemplate as the runtime exchange boundary

- **Status:** Proposed (will flip to Accepted when PR 3 lands)
- **Date:** 2026-05-17
- **Source:** [`docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md`](../superpowers/specs/2026-05-17-graph-boundary-type-design.md)
- **Related:** ADR-0001 (layered package architecture), ADR-0003 (CompiledTemplate as topology artifact)

## Context

By v0.3.1, `Array[DspNode]` is the public exchange type across 14
entries in `graph/pkg.generated.mbti` and 4 more in
`voice/pkg.generated.mbti`. `CompiledTemplate` (ADR-0003) exists as a
side-door artifact via `CompiledDsp::compile_template(CompiledTemplate, ctx)`,
but the front door `CompiledDsp::compile(Array, ctx)` makes the side
door optional. Three consequences:

1. `optimize_graph` runs multiple times per template — wasted work,
   with no type-level way to share the result.
2. ADR-0003's principle — "topology questions go to a topology
   artifact, runtime questions go to `CompiledDsp`" — is not enforced.
3. Future capabilities (incremental computation via `dowdiness/incr`,
   Phase 7+ structural editing) need a stable runtime-side type.

## Decision

`Array[DspNode]` is the **authoring** exchange type. `CompiledTemplate`
is the **runtime** exchange type. New public functions take whichever
side they belong on; they do not take both.

Stated tighter: **Runtime types do not accept bare `Array[DspNode]`.
Only authoring owner types and `CompiledTemplate::analyze` do.**

The boundary is crossed by exactly one canonical operation:
`CompiledTemplate::analyze(Array[DspNode]) -> CompiledTemplate`.

### Signature migration (graph/)

- `CompiledDsp::compile(Array, ctx) -> Self?` → `compile(CompiledTemplate, ctx) -> Self?`
- `CompiledStereoDsp::compile(Array, ctx) -> Self?` → `compile(CompiledTemplate, ctx) -> Self?`
- `compile_template(CompiledTemplate, ctx)` → **removed** (collapses into `compile`)
- `optimize_graph(Array) -> (..., ...)` → **package-private**

### Signature migration (voice/)

- `VoicePool::new(Array, ctx, max_voices?) -> Self?`
  → `new(CompiledTemplate, ctx, max_voices?) -> Result[Self, VoicePoolError]`
- `VoicePool::set_template(Self, Array) -> Bool`
  → `set_template(Self, CompiledTemplate) -> Result[Unit, VoicePoolError]`
- `BoundVoicePool::new(Array, ctx, builder, ...)` → `new(CompiledTemplate, ctx, builder, ...)`
- `BoundVoicePool::set_template(Self, Array, builder)` → `set_template(Self, CompiledTemplate, builder)`

### New public additions

- `CompiledTemplate::adsr_authoring_indices(Self) -> FixedArray[Int]`
  — runtime gating for voice/.
- `GraphBuilder::analyze(Self) -> CompiledTemplate` — sugar.
- `VoicePoolError { InvalidMaxVoices, OrphanAdsr, CompileRejected }` —
  mirrors `BoundVoicePoolError` minus `Binding(...)`.

## Boundary exceptions (NOT precedent)

These cross from authoring to runtime in their public surface. They are
documented exceptions; new public functions outside this list may not
take `Array[DspNode]` for runtime purposes.

- `replay(Array[DspNode]) -> T?` — pre-optimize debug/round-trip.
- `Compiled{Mono,Stereo}DspTopologyController::from_nodes(Array, ctx, crossfade?)`
  — edit-as-you-go composites; they own authoring topology internally
  and use `compile_raw` (not `compile_template`).

## Allowed authoring APIs

These remain on the authoring side and continue to take or return
`Array[DspNode]`:

- `CompiledTemplate::analyze` (single canonical boundary crossing)
- `GraphBuilder::nodes`
- `GraphTemplateDoc::nodes`, `::from_nodes`, `::insert_chain`,
  `::compile`, `::compile_stereo`
- `GraphIndexMap::insert_chain`
- `GraphTopologyEdit::InsertChain` and constructor

## Consequences

**Positive**

- `optimize_graph` runs exactly once per template, statically enforced.
- ADR-0003's principle enforced at the type level.
- `voice/` no longer holds `Array[DspNode]` in its public surface (or
  internal storage — `Array[DspNode]` snapshots become
  `FixedArray[Int]` ADSR index snapshots).
- VoicePool's silent Option/Bool returns become named-error Results,
  reaching parity with BoundVoicePool.
- Future incr-driven incremental pipeline has a clear stage type.

**Negative**

- Breaking change across ~530–800 lines (graph + voice + tests).
- Boundary exceptions remain — principled but not absolute.
- Eq derivation for CompiledTemplate deferred (NaN policy needs
  separate design).

**Known follow-up (not addressed in PR 3)**

- `CompiledTemplate` / `DspNode` `Eq` with NaN policy. Land when incr
  Phase 6+ needs Salsa-style early cutoff.
- `CompiledDsp::compile` Result migration (`Self?` → `Result[Self,
  GraphCompileError]`). Blocks splitting
  `VoicePoolError::CompileRejected` into finer variants.

## Test enforcement

`scripts/check-public-boundary.sh` (added in PR 3) audits the public
`.mbti` files for `Array[DspNode]` entries and asserts only the
documented boundary exceptions and allowed authoring APIs appear. New
entries require explicit allowlist updates.
```

- [ ] **Step 2: Verify file structure matches existing ADRs**

Run: `head -10 docs/decisions/0003-compiled-template-topology-artifact.md`
Compare to the new file's header — Status, Date, Source, Related sections should be in the same shape.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0010-compiled-template-runtime-boundary.md
git commit -m "$(cat <<'EOF'
docs(adr): add ADR-0010 CompiledTemplate as runtime exchange boundary (Proposed)

ADR records the pre-1.0 decision to promote CompiledTemplate to the
runtime exchange boundary, collapse compile_template into compile, and
migrate VoicePool to Result-typed errors. Status flips to Accepted in
PR 3 when the code migration lands.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Update docs README index (if it lists ADRs)

**Files:**
- Modify: `docs/decisions/README.md` (if it exists and indexes ADRs)

- [ ] **Step 1: Check if the index needs updating**

Run: `cat docs/decisions/README.md 2>/dev/null | grep -E "ADR-000[0-9]|0010"`
Expected: if a list of ADRs is present, add ADR-0010 to it. If no README, skip.

- [ ] **Step 2: Apply the edit (if index exists)**

Add `- [ADR-0010: CompiledTemplate as the runtime exchange boundary](0010-compiled-template-runtime-boundary.md) (Proposed)` to the index list, preserving alphabetical/numerical order.

- [ ] **Step 3: Commit (if changed)**

```bash
git add docs/decisions/README.md
git commit -m "$(cat <<'EOF'
docs(adr): index ADR-0010 in decisions README

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Final review and push

**Files:**
- Read: all modified files

- [ ] **Step 1: Visual review of full diff**

Run: `git log --oneline main..HEAD`
Expected: 7–10 commits (one per touchpoint).

Run: `git diff main..HEAD --stat`
Expected: only `docs/` files changed. No `.mbt` files, no code, no test changes.

- [ ] **Step 2: Confirm no `memory/` references introduced**

Run: `git diff main..HEAD | grep -i "memory/"`
Expected: empty output. If matches appear, edit them out (canonical references live in the spec file's §What's Deferred).

- [ ] **Step 3: Confirm `Planned per ADR-0010` wording is consistent**

Run: `git diff main..HEAD | grep -c "Planned per ADR-0010"`
Expected: ≥ 7 (one per technical-reference touchpoint + blueprint mentions). If fewer, a touchpoint was missed.

- [ ] **Step 4: Push branch and open PR**

```bash
git push -u origin feat/graph-boundary-docs-prep
gh pr create --base main --title "docs: prep for ADR-0010 (CompiledTemplate runtime boundary)" --body "$(cat <<'EOF'
## Summary

- Adds ADR-0010 (Proposed) for the CompiledTemplate-as-runtime-boundary contract.
- Updates `salat-engine-technical-reference.md` at 5 touchpoints to note planned migration ahead of code change in PR 3.
- Updates `salat-engine-blueprint.md` at 2 touchpoints with the same "planned per ADR-0010" framing.

## Why three PRs

- PR 1 (this one): doc-only prep, low risk.
- PR 2: test pinning (no behavior change), establishes safety net for migration.
- PR 3: the code migration; flips ADR-0010 to Accepted and strips "planned" qualifiers.

## Test plan

- [ ] Read every "Planned per ADR-0010" annotation — accurate and unambiguous.
- [ ] ADR-0010 reads as a complete decision record.
- [ ] No `.mbt` files touched.

Spec: `docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Wait for review**

PR 1 is doc-only. Once approved + merged, proceed to PR 2 (test pinning).
