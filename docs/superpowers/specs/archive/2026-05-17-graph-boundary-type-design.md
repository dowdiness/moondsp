# Graph Boundary Type Design — `CompiledTemplate` as Runtime Exchange

**Date:** 2026-05-17
**Status:** Draft (awaiting user review)
**Related:**
- `docs/decisions/0001-layered-package-architecture.md` (ADR-0001)
- `docs/decisions/0003-compiled-template-topology-artifact.md` (ADR-0003)
- `docs/decisions/0010-compiled-template-runtime-boundary.md` (ADR-0010, to be added)
- `docs/superpowers/specs/2026-05-12-phase6-incremental-playback-design.md`
- `docs/next-actions.md` → "Recommended Next Slice" (2026-05-17 state) —
  external framing of this work as the recommended pre-1.0 slice.

## Goal

Decide whether `Array[DspNode]` stays the public boundary type for the
`graph/` package's runtime side, or whether `CompiledTemplate` (introduced
in ADR-0003 for orphan detection) is promoted to that role across the
public surface. Decide before v1.0.

**Outcome:** promote `CompiledTemplate` to the runtime exchange boundary.
Keep `Array[DspNode]` as the authoring exchange type. Encode the split as
a documented contract.

## Context

By v0.3.1, `Array[DspNode]` is the public exchange type across 14 entries
in `graph/pkg.generated.mbti` (counting `optimize_graph`, `replay`, both
mono/stereo `compile`, both mono/stereo topology controller `from_nodes`,
`CompiledTemplate::analyze`, `GraphBuilder::nodes`,
`GraphTemplateDoc::{from_nodes, insert_chain, nodes}`,
`GraphIndexMap::insert_chain`, and `GraphTopologyEdit::{InsertChain,
insert_chain}`) and 4 more in `voice/pkg.generated.mbti`.
`CompiledTemplate` exists as a topology artifact (ADR-0003) accessed via
the side door `CompiledDsp::compile_template(CompiledTemplate, ctx)`, but
the front door `CompiledDsp::compile(Array, ctx)` makes the side door
optional. Three consequences:

1. `optimize_graph` runs multiple times per template — once inside
   `CompiledDsp::compile`, again inside `CompiledStereoDsp::compile`,
   again inside `CompiledTemplate::analyze`. Wasted work, with no
   type-level way to share the result.
2. ADR-0003's principle — "topology questions go to a topology artifact,
   runtime questions go to `CompiledDsp`" — is not enforced. The Array
   front door re-conflates the two.
3. Future capabilities (incremental computation via `dowdiness/incr`,
   Phase 7+ structural editing) need a stable runtime-side type. Building
   them on raw `Array[DspNode]` would either thread additional metadata
   through every signature or introduce a new type later as a breaking
   change.

The Phase 6+ incremental pipeline (`Signal[Array[DspNode]]` →
`Memo[CompiledTemplate]` → `Memo[CompiledDsp?]`) works best when each stage
is a stable, well-named value type. Salsa-style memoization keys on inputs;
having `CompiledTemplate` as the runtime-side input to `compile` keeps the
optimize result inside Salsa's caching boundary.

## Decision

**`Array[DspNode]` is the authoring exchange type. `CompiledTemplate` is
the runtime exchange type. New public functions take whichever side they
belong on; they do not take both.**

The principle, restated tighter:

> Runtime types do not accept bare `Array[DspNode]`. Only authoring owner
> types (`GraphBuilder`, `GraphTemplateDoc`, `GraphIndexMap`,
> `GraphTopologyEdit`) and `CompiledTemplate::analyze` do.

The boundary is crossed by exactly one canonical operation:
`CompiledTemplate::analyze(Array[DspNode]) -> CompiledTemplate`.

Two categories of remaining `Array[DspNode]` in the public surface:

- **Allowed authoring APIs**: types and methods on the authoring side of
  the boundary. `GraphBuilder::nodes`, `GraphTemplateDoc` authoring
  surface (`from_nodes`, `insert_chain`, `nodes`, `compile`,
  `compile_stereo`), `GraphIndexMap::insert_chain`, and all
  `GraphTopologyEdit` variants. These do not cross the boundary — they
  live on the authoring side.
- **Boundary exceptions**: two cross-boundary cases documented in
  ADR-0010 as exceptions, not precedent: `replay(Array[DspNode])` for
  pre-optimize debug/round-trip; `Compiled{Mono,Stereo}DspTopologyController::from_nodes`
  for edit-as-you-go composites that own authoring topology internally
  but produce runtime artifacts.

## Public Surface Migration

### Boundary-side (migrate to `CompiledTemplate`)

| Current signature | New signature |
|---|---|
| `CompiledDsp::compile(Array[DspNode], DspContext) -> Self?` | `CompiledDsp::compile(CompiledTemplate, DspContext) -> Self?` |
| `CompiledStereoDsp::compile(Array[DspNode], DspContext) -> Self?` | `CompiledStereoDsp::compile(CompiledTemplate, DspContext) -> Self?` |
| `CompiledDsp::compile_template(CompiledTemplate, DspContext) -> Self?` | **removed** (collapses into `compile`) |
| `CompiledStereoDsp::compile_template(CompiledTemplate, DspContext) -> Self?` | **removed** |
| `optimize_graph(Array[DspNode]) -> (Array[DspNode], FixedArray[Int])` | **package-private** |
| `VoicePool::new(Array[DspNode], DspContext, max_voices?) -> Self?` | `VoicePool::new(CompiledTemplate, DspContext, max_voices?) -> Result[Self, VoicePoolError]` |
| `VoicePool::set_template(Self, Array[DspNode]) -> Bool` | `VoicePool::set_template(Self, CompiledTemplate) -> Result[Unit, VoicePoolError]` |
| `BoundVoicePool::new(Array[DspNode], DspContext, ControlBindingBuilder, max_voices?) -> Result[Self, BoundVoicePoolError]` | `BoundVoicePool::new(CompiledTemplate, DspContext, ControlBindingBuilder, max_voices?) -> Result[Self, BoundVoicePoolError]` |
| `BoundVoicePool::set_template(Self, Array[DspNode], ControlBindingBuilder) -> Result[Unit, BoundVoicePoolError]` | `BoundVoicePool::set_template(Self, CompiledTemplate, ControlBindingBuilder) -> Result[Unit, BoundVoicePoolError]` |

### New public additions

```moonbit
// graph/compiled_template.mbt
pub fn CompiledTemplate::adsr_authoring_indices(Self) -> FixedArray[Int]

// graph/graph_builder.mbt
pub fn GraphBuilder::analyze(Self) -> CompiledTemplate

// voice/voice.mbt
pub(all) enum VoicePoolError {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
} derive(Eq, @debug.Debug)
pub impl Show for VoicePoolError
```

### Allowed authoring APIs (`Array[DspNode]` on the authoring side)

These remain on the authoring side of the boundary and continue to take
or return `Array[DspNode]`. They are not exceptions — they are the
authoring surface.

- `CompiledTemplate::analyze(Array[DspNode]) -> Self` — the single
  canonical boundary crossing.
- `GraphBuilder::nodes(Self) -> Array[DspNode]` — authoring/inspection
  accessor; returns the internal mutable array directly. Tests and
  serialization/export depend on it.
- `GraphTemplateDoc::nodes(Self) -> Array[DspNode]` — authoring snapshot
  for inspection/export.
- `GraphTemplateDoc::from_nodes`, `::insert_chain`, `::compile`,
  `::compile_stereo` — authoring artifact's surface. `::compile` and
  `::compile_stereo` are public convenience over an identity-bearing
  document; their internals migrate to call the new
  `CompiledDsp::compile(CompiledTemplate, ctx)`.
- `GraphIndexMap::insert_chain(GraphNodeId, GraphTopologyInputSlot, Array[DspNode]) -> GraphTopologyEdit?`
  — authoring translation layer.
- `GraphTopologyEdit::InsertChain(Int, GraphTopologyInputSlot, Array[DspNode])`
  and `GraphTopologyEdit::insert_chain(...)` — authoring payload value
  carried through edit operations.

### Boundary exceptions (cross-boundary; NOT precedent)

These cross from authoring to runtime in their public surface. They are
documented in ADR-0010 as exceptions; new public functions outside this
list may not take `Array[DspNode]` for runtime purposes.

- `replay(Array[DspNode]) -> T?` — pre-optimize debug/round-trip. Every
  current call site round-trips authoring nodes; changing to post-optimize
  would break the debug semantics.
- `Compiled{Mono,Stereo}DspTopologyController::from_nodes(Array, ctx, crossfade?)`
  — edit-as-you-go composites. Controllers own authoring topology
  internally and use `compile_raw` (not `compile_template`); migrating
  them to `from_template(CompiledTemplate)` would either break authoring
  indices (if they used optimized nodes) or waste the optimize pass (if
  they re-extracted the authoring snapshot from CompiledTemplate).

Adding any new public function taking `Array[DspNode]` for runtime
purposes (i.e., outside the allowed authoring APIs above and outside
these documented boundary exceptions) is a contract violation; the
meta-test in §Test Strategy C9 enforces this socially.

### Per-package surface after migration

| Layer | Sees `Array[DspNode]` publicly? | Sees `CompiledTemplate` publicly? |
|---|---|---|
| `dsp/` | No | No |
| `graph/` | Yes (authoring APIs + boundary exceptions) | Yes (boundary type defined here) |
| `voice/` | **No** | Yes |
| `scheduler/` | No | Indirectly via `voice/` |
| `mini/`, `pattern/` | No | No (operate on `ControlMap`) |
| `browser/` | No | Indirectly |

`voice/` losing `Array[DspNode]` from its public AND internal surface is a
meaningful tightening. Downstream consumers cannot accidentally end up
holding authoring nodes — they're forced to go through `CompiledTemplate`.

## `CompiledTemplate` Accessor Surface

### Public (final for v1.0)

```moonbit
pub fn CompiledTemplate::analyze(Array[DspNode]) -> Self
pub fn CompiledTemplate::orphan_adsr_count(Self) -> Int
pub fn CompiledTemplate::adsr_authoring_indices(Self) -> FixedArray[Int]   // new
```

### Package-private (unchanged)

```moonbit
fn CompiledTemplate::length(Self) -> Int
fn CompiledTemplate::node_at(Self, Int) -> DspNode
fn CompiledTemplate::is_node_live(Self, Int) -> Bool
```

Used by `ControlBindingBuilder::build` (same package). Promotion to
public deferred per principle 7 (reserve space, don't pre-build) until a
concrete consumer asks (likely Phase 7+ structural editor).

### `adsr_authoring_indices` contract

Returns the authoring indices of all ADSR nodes that survived
optimization, in authoring order:

```
adsr_authoring_indices(T) = [ i for i in 0..<T.template.length()
                                if T.template[i].kind == Adsr
                                  && T.index_map[i] >= 0 ]
```

Authoring indices, not runtime indices: this matches
`CompiledDsp::gate_on/gate_off`, which take authoring indices and map
through `index_map` internally (`graph/graph_runtime_control.mbt:19, 36, 494`).
Returning runtime indices would cause voice/ to double-map and target
wrong nodes.

### Eq / Debug derivation deferred

`CompiledTemplate` does NOT derive `Eq` or `Debug` in this PR. Reasons:

- `DspNode` has 4 `Double` fields (`graph/graph_node.mbt:115`); `analyze`
  is infallible, so NaN-bearing templates exist. Structural `Eq` would
  give non-reflexive equality (NaN != NaN). NaN policy needs separate
  design.
- `derive(Debug)` on `DspNode` would cascade through `Waveform` /
  `BiquadMode` in `dsp/` (both currently derive only `Eq`). Out of scope.
- `Memo[CompiledTemplate]` keyed on `Array[DspNode]` input requires `Eq`
  on the **input**, not on the output. Salsa-style "early cutoff"
  (skipping downstream when output value unchanged) is an optimization,
  not a correctness requirement. Adding it later via manual
  `eq_ignore_nan` or content-fingerprint is non-breaking.

Deferral details and the NaN-policy options are recorded canonically
in §What's Deferred below; ADR-0010 cross-references this section.

### Field invariants

The module-level doc on `graph/compiled_template.mbt` documents:

```
template.length() == index_map.length()
optimized.length() <= template.length()
optimized.length() == count(index_map[i] >= 0)
```

## `voice/` Internal Storage Migration

After migration, `voice/` holds **no** `Array[DspNode]`. The internal
fields change:

```moonbit
// Before
struct VoicePool {
  template : Array[DspNode]
  // ...
}
struct VoiceSlot {
  template_snapshot : Array[DspNode]
  // ...
}

// After
struct VoicePool {
  adsr_authoring_indices : FixedArray[Int]   // snapshot at construction
  // ...
}
struct VoiceSlot {
  adsr_authoring_indices_snapshot : FixedArray[Int]   // snapshot at allocation
  // ...
}
```

`VoicePool::new(CompiledTemplate, ctx, max_voices?)`:

1. Validates `max_voices > 0` → `Err(InvalidMaxVoices)`.
2. Calls `validate_voice_template(template, ctx) -> Result[Unit, VoicePoolError]`:
   - Checks `template.orphan_adsr_count() == 0` → `Err(OrphanAdsr)` otherwise.
   - Runs one **sanity compile** via `CompiledDsp::compile(template, ctx)`;
     discards the result; returns `Err(CompileRejected)` on `None`. This
     matches current behavior at `voice/voice.mbt:168-181`: per-voice
     slots stay empty at construction and compile their own graph on
     `note_on` (`voice/voice.mbt:490`).
3. Snapshots `template.adsr_authoring_indices()` into `self.adsr_authoring_indices`
   (defensive copy of the `FixedArray[Int]`; not a shared reference).
4. Allocates `max_voices` empty `VoiceSlot`s (matches `voice/voice.mbt:197`).
5. Returns `Ok(self)`.

`BoundVoicePool::new` calls the same `validate_voice_template` (mapped
into `BoundVoicePoolError`) and additionally validates bindings. The
shared validator returns `Result[Unit, VoicePoolError]`; the wrapping
mapping helper is:

```moonbit
fn BoundVoicePoolError::from_voice_pool(e : VoicePoolError) -> BoundVoicePoolError {
  match e {
    VoicePoolError::InvalidMaxVoices => BoundVoicePoolError::InvalidMaxVoices
    VoicePoolError::OrphanAdsr => BoundVoicePoolError::OrphanAdsr
    VoicePoolError::CompileRejected => BoundVoicePoolError::CompileRejected
  }
}
```

This inverts today's shape — `validate_voice_template` currently returns
`BoundVoicePoolError` because that was the only typed error in `voice/`.
After migration, the lower-level type owns the variants; the
higher-level type wraps.

`VoiceSlot` snapshots `pool.adsr_authoring_indices` at allocation via
`slot.adsr_authoring_indices_snapshot = pool.adsr_authoring_indices.copy()`
(defensive copy — not a shared reference), so that a hot-swap via
`set_template` does not invalidate already-sounding voices that still
need to gate the OLD ADSR set. (This is the same invariant the current
`template_snapshot` field provides; only the storage type changes from
`Array[DspNode]` to `FixedArray[Int]`.)

Long field names (`adsr_authoring_indices` vs the shorter
`adsr_indices`) are intentional: the `_authoring` suffix prevents future
contributors from mistaking these for runtime indices, which would
re-introduce the wrong-mapping bug Codex caught.

## Error Handling Shape

No new error variants for compile in this PR.

### `VoicePoolError`

```moonbit
pub(all) enum VoicePoolError {
  InvalidMaxVoices    // max_voices <= 0
  OrphanAdsr          // template has dead-code ADSR nodes
  CompileRejected     // CompiledDsp::compile returned None
} derive(Eq, @debug.Debug)
pub impl Show for VoicePoolError
```

Variants mirror `BoundVoicePoolError` minus `Binding(...)` (VoicePool has
no bindings). `CompileRejected` is intentionally coarse: it collapses
missing/multiple output, feedback rejection, invalid sample rate,
invalid refs, shape errors. Splitting these is blocked on
`CompiledDsp::compile` migrating from `Self?` to
`Result[Self, GraphCompileError]`, which is a separate redesign listed
in §What's Deferred.

### Pipeline error stages

| Stage | Shape |
|---|---|
| 1. Authoring | infallible (`Array[DspNode]`) |
| 2. Analyze (`CompiledTemplate::analyze`) | infallible |
| 3. Validate (pool-internal) | `Result[..., VoicePoolError]` / `Result[..., BoundVoicePoolError]` |
| 4. Bind controls (`ControlBindingBuilder::build`) | `Result[..., ControlBindingError]` |
| 5. Compile (`CompiledDsp::compile`) | `Option` (`Self?`) |
| 6. Run (`process`) | infallible per-block |

Stage 5's Option-return remains the one Option in the pipeline post-
migration. Migration to `Result[Self, GraphCompileError]` is the next
pre-1.0 hygiene slice after this one lands.

### Pool-side orphan check retained

`VoicePool::new` and `BoundVoicePool::new` keep their internal
orphan-ADSR check post-migration (defense-in-depth). Callers may
preflight `template.orphan_adsr_count() == 0` themselves to avoid the
redundant traversal, but constructors are the invariant boundary;
removing the check assumes every caller preflights correctly.

## Test Strategy

Three categories, executed in this order:

### A. Pin current behavior (PR 2)

Property tests using `@qc.quick_check_fn` generators producing both
well-formed templates AND adversarial inputs (cycles, orphan ADSRs, NaN
values, missing Output, max_voices boundary cases). PR 2 introduces no
new signatures — these tests run against the **current** API surface and
assert two-sided equivalence between the existing `Array`-taking front
door and the existing `CompiledTemplate`-taking side door.

- **A1 — `compile` equivalence**: for any `Array[DspNode]` (well-formed
  or adversarial), `CompiledDsp::compile(nodes, ctx)` (current Array
  front door) produces output equivalent block-for-block to
  `CompiledDsp::compile_template(CompiledTemplate::analyze(nodes), ctx)`
  (current CT side door). On adversarial input, both return `None`.
  Same for stereo.
- **A2 — `VoicePool` construction**: parameterized on a closure
  `mk : (Array[DspNode], ctx, max_voices) -> Result[VoicePool, A2Reason]`
  where `A2Reason` is a PR-2-local enum with the same three variants as
  the future `VoicePoolError` (`InvalidMaxVoices`, `OrphanAdsr`,
  `CompileRejected`). In PR 2, the closure body **pre-classifies**: it
  checks `max_voices <= 0`, runs `CompiledTemplate::analyze(nodes).orphan_adsr_count() > 0`,
  then calls the current `VoicePool::new(Array, ctx, max_voices?) -> Self?`
  and treats `None` as `CompileRejected`. This is the only way to assert
  "failure with the right reason" against the current Option-returning
  API, since `None` collapses all reasons. The test asserts success on
  well-formed templates AND failure-with-correct-reason on each adversarial
  case. In PR 3, the closure body collapses to one line —
  `VoicePool::new(CompiledTemplate::analyze(nodes), ctx, max_voices?)
   .map_err(A2Reason::from_voice_pool)` — and the pre-classifier inside
  the closure is deleted.
- **A3 — `VoicePool::set_template`**: same closure pattern with
  `A3Reason` PR-2-local enum, Bool→Result; pre-classifier strategy
  identical.
- **A4 — `BoundVoicePool`**: same closure pattern; already Result-typed
  with `BoundVoicePoolError`, closure passes through unchanged. In PR 3,
  the closure body changes only the input type (Array → CompiledTemplate).

PR 2 file organization:

- **`*_temporary_equivalence_pins.mbt`** — A1-style direct
  side-door-vs-front-door equivalence tests. Deleted in PR 3 (the front
  door ceases to exist).
- **`*_behavior_test.mbt`** — A2-A4 property tests parameterized over
  the closure. Closure body is the only thing that changes in PR 3.

If A1 reveals that `compile(Array)` validates something
`compile_template(CompiledTemplate)` does not (or vice versa), discover
it here, not after migration.

### B. New surface (PR 3)

B5 and B6 reference private fields (`template`, `index_map`) on
`CompiledTemplate`. They live in `graph/compiled_template_wbtest.mbt`
(whitebox test, same package as `CompiledTemplate`). Public-API-only
variants would require promoting `length`/`node_at`/`is_node_live`,
which §CompiledTemplate Accessor Surface defers.

- **B5 — `adsr_authoring_indices` property test** (whitebox):
  ```
  ∀ source nodes : Array[DspNode], let T = CompiledTemplate::analyze(nodes):
    adsr_authoring_indices(T).length() + orphan_adsr_count(T)
      == count(i in 0..<T.template.length() : T.template[i].kind == Adsr)
    ∀ i in adsr_authoring_indices(T):
      T.template[i].kind == Adsr ∧ T.index_map[i] >= 0
  ```
- **B6 — ordering invariant** (whitebox): `adsr_authoring_indices(T)`
  is monotonically increasing (authoring order preserved).
- **B7 — `VoicePoolError` variant coverage**: one test per variant
  firing under the right condition:
  - `InvalidMaxVoices` → `new(template, ctx, max_voices=0)`
  - `OrphanAdsr` → template with a dead-code ADSR
  - `CompileRejected` → template with feedback cycle or missing Output
- **B8 — `GraphBuilder::analyze` round-trip**: `builder.analyze()`
  produces a `CompiledTemplate` semantically equivalent to
  `CompiledTemplate::analyze(builder.nodes())`. Verified via
  CompiledDsp output equivalence (no `CompiledTemplate Eq` yet).

### C. Contract enforcement (PR 3, persistent)

- **C9 — boundary carve-out audit**: external script
  `scripts/check-public-boundary.sh` runs `moon info`, then greps
  `graph/pkg.generated.mbti`, `voice/pkg.generated.mbti`, and the root
  `pkg.generated.mbti` for `Array[DspNode]` / `Array[@.*DspNode]`
  entries. Asserts only the documented carve-outs (allowed authoring
  APIs + boundary exceptions in §Decision) appear. New entries fail the
  script, forcing explicit acknowledgement in the allowlist hard-coded
  at the top of the script. CI wiring (PR 3): create a dedicated
  workflow `.github/workflows/boundary-check.yml` triggered on PR + push
  to main, OR extend the existing `.github/workflows/browser-smoke.yml`
  with a new job (note: that workflow currently runs only the browser
  smoke harness, not `moon check` / `moon test`, so the script needs its
  own `moon info` invocation regardless of which workflow hosts it).
  The script's exit code is the contract; either workflow shape is
  acceptable.
- **C10 — `.mbti` snapshot**: `pkg.generated.mbti` files committed
  for `graph/`, `voice/`, and root. Any unintended surface change shows
  up in `git diff`.

## ADR-0010 Outline

To be added at `docs/decisions/0010-compiled-template-runtime-boundary.md`
with status `Proposed` in PR 1, flipped to `Accepted` when PR 3 lands.

Sections: Context (state at v0.3.1), Decision (the contract + signature
migration), Carve-outs (full list with rationale), Consequences
(positive: optimize-once, ADR-0003 enforced, voice/ no Array; negative:
breaking change ~530–950 lines, carve-outs remain), Known follow-up
(Eq/NaN policy, CompiledDsp::compile Result migration).

## Sequencing

Three PRs in order:

### PR 1 — Docs prep (doc-only, low-risk, lands first)

PR 1 updates docs **ahead of** the code change. To keep the docs
truthful while ADR-0010 sits in `Proposed` status, each touchpoint
phrases the new surface as "planned per ADR-0010" rather than as current
behavior. PR 3 strips the "planned" qualifiers when it flips ADR-0010
to `Accepted`. Readers between PR 1 and PR 3 see "current behavior is X;
ADR-0010 (Proposed) will change it to Y" — accurate at every moment.

- Rewrite `docs/salat-engine-technical-reference.md` in five touchpoints:
  - Lines around **663** and **797** (compile + compile_template
    documented as separate paths) → describe the unified `compile(CompiledTemplate, ctx)`
    surface and the collapse.
  - Lines **859–878** (voice section) → reflect the new
    `CompiledTemplate`-taking `VoicePool::new` / `set_template`
    signatures plus the `VoicePoolError` enum.
  - Lines **904–906** (currently claims "removes the previous double
    `optimize_graph(...)` pass from the voice-template path") → update
    to reflect that the boundary type now guarantees single optimize
    statically, not just dynamically.
  - Lines **915–925** (hot-swap compile examples using
    `CompiledDsp::compile(old_nodes, context)`) → rewrite examples to
    use `CompiledDsp::compile(CompiledTemplate::analyze(old_nodes), context)`.
  - Update pipeline diagram to reflect the boundary type.
- Update `docs/salat-engine-blueprint.md`:
  - Line **54** (frames `DspNode enum -> compile() -> CompiledDsp`) →
    update to `DspNode -> CompiledTemplate -> CompiledDsp`.
  - Lines **193–195** (similar framing) → same update.
- Add ADR-0010 with status `Proposed` at
  `docs/decisions/0010-compiled-template-runtime-boundary.md`.

The `CLAUDE.md` one-liner update (telling contributors which type to
take for new APIs) is deferred to **PR 3**, not PR 1 — `CLAUDE.md` is
prescriptive contributor guidance and should reflect current behavior,
not a planned-per-ADR state. See §Sequencing PR 3.

### PR 2 — Test pinning (no behavior change)

- Add property tests A1–A4 against current main using
  `CompiledTemplate::analyze(nodes)` as the comparison reference.
- Two files per category: `*_temporary_equivalence_pins.mbt`
  (deleted in PR 3) and `*_behavior_test.mbt` (persists, parameterized
  over `compile_via_template` helper).

If A1–A4 reveal a behavior gap (e.g., `compile(Array)` validates
something `compile_template(CompiledTemplate)` doesn't), discover it
here, not after migration.

### PR 3 — The migration

- Apply all signature changes (graph + voice).
- Add `CompiledTemplate::adsr_authoring_indices`, `GraphBuilder::analyze`.
- Add `VoicePoolError` enum at `voice/voice.mbt` AND add the re-export
  `pub using @voice { type VoicePoolError }` to `moondsp.mbt` (current
  facade re-exports `BoundVoicePoolError`, `VoiceControlError`,
  `VoicePool`, etc. at `moondsp.mbt:114`; root-facade users need the new
  type to pattern-match Results ergonomically).
- Make `optimize_graph` package-private; remove root facade re-export at
  `moondsp.mbt:108`; migrate `graph/graph_optimize_test.mbt` from
  blackbox to whitebox (`*_wbtest.mbt`) since it uses `optimize_graph`
  directly.
- Migrate `voice/` internal fields from `Array[DspNode]` to
  `FixedArray[Int]` snapshots.
- Delete `*_temporary_equivalence_pins.mbt` files from PR 2.
- Add tests B5–B8, C9–C10.
- Add `scripts/check-public-boundary.sh` (new file) and the chosen CI
  workflow (`boundary-check.yml` OR a new job in `browser-smoke.yml`)
  per §Test Strategy C9. Also strip "planned per ADR-0010" qualifiers
  from PR 1's doc updates so docs describe current behavior.
- Add the one-liner under `CLAUDE.md` Architecture section:
  > Graph boundary types: `Array[DspNode]` for authoring,
  > `CompiledTemplate` for runtime. One way across:
  > `CompiledTemplate::analyze`.
- Flip ADR-0010 status to `Accepted`.
- Bump `moon.mod.json` to v0.4.0 (breaking).
- CHANGELOG entry: migration table, `VoicePoolError`, carve-outs
  explicitly listed.
- External Codex CHANGELOG review before tagging — semantic claim drift
  in CHANGELOG entries has bitten prior releases (v0.3.0); an in-house
  review pass misses it. See PR-template / release-process docs (or
  ADR-0010's release-process callout) for the canonical procedure.

### Why three PRs

Reviewer cognitive load. PR 3 is mechanical given PR 1 establishes the
principle and PR 2 establishes the safety net. Reading 500–800 lines of
mixed migration + docs + new tests in a single PR is harder than reading
each in isolation.

## What's Deferred

These items are explicitly out of scope for this design. Each is logged
here as the canonical record; this spec is the source of truth.

- **`CompiledTemplate` / `DspNode` `Eq` with NaN policy** — `DspNode`
  has 4 `Double` fields; `analyze` is infallible, so NaN-bearing
  templates exist. Structural `derive(Eq)` would give non-reflexive
  equality. Land when incr Phase 6+ needs Salsa-style early cutoff.
  Three defensible options at that time: manual `Eq` with NaN-equal-NaN
  policy; `content_fingerprint() -> Bytes` accessor; per-test
  `eq_ignore_nan` helper.
- **`CompiledDsp::compile` Result migration** — `Self?` →
  `Result[Self, GraphCompileError]` with finer variants (MissingOutput /
  FeedbackCycle / InvalidSampleRate / ShapeError / etc.). Blocks
  `VoicePoolError::CompileRejected` from splitting into specific
  variants. Tracked as the next pre-1.0 hygiene slice after this design
  lands.
- **`CompiledTemplate::is_node_live` / `node_at` / `length` public
  promotion** — reserved for Phase 7+ structural editor with a concrete
  use case driving the shape (e.g., `live_indices() -> Iter[Int]` for
  highlighting eliminated nodes in the editor UI).
- **`derive(Debug)` cascade for `DspNode` / `Waveform` / `BiquadMode`** —
  not needed by current consumers; add when first consumer arrives.

## Open Questions

None at design time; all resolved through three rounds of Codex review.
Open items are listed under "What's Deferred" with explicit deferral
rationale.

## References

- `docs/next-actions.md` (2026-05-17 state) frames this as the
  recommended next slice.
- `docs/decisions/0001-layered-package-architecture.md` (ADR-0001) —
  establishes the dsp→graph→voice→scheduler→mini→browser dependency
  direction this contract reinforces.
- `docs/decisions/0003-compiled-template-topology-artifact.md` (ADR-0003) —
  establishes the type whose role this design promotes.
- `docs/decisions/0010-compiled-template-runtime-boundary.md` (ADR-0010,
  to be added in PR 1) — the canonical decision record produced by this
  spec.
- Spec self-review: see "Spec Self-Review" log at end of this file
  before final user review.

## Spec Self-Review

Per the `superpowers:brainstorming` skill's self-review checklist:

- **Placeholder scan:** no TBD / TODO / vague requirements remain. All
  decisions resolved.
- **Internal consistency:** signature migration table (§Public Surface
  Migration) and pipeline-stage error table (§Error Handling Shape)
  cross-reference cleanly. `adsr_authoring_indices` is named identically
  in §CompiledTemplate Accessor Surface, §voice/ Internal Storage
  Migration, and §Test Strategy. Verb conventions (`analyze` for
  producers, `compile`/`new` for consumers) consistent across all
  mentions.
- **Scope check:** focused on the graph runtime-boundary type plus the
  required voice/ migration. Deferred items (Eq, finer compile errors,
  Debug cascade) explicitly listed with deferral rationale, not silently
  in scope.
- **Round-3 Codex fixes (2026-05-17):** updated count (12→14) to match
  current `graph/pkg.generated.mbti`; resolved "two carve-outs" wording
  contradiction by splitting "allowed authoring APIs" from "boundary
  exceptions"; corrected `VoicePool::new` step list to "sanity compile
  once" matching `voice/voice.mbt:168-181`; specified
  `validate_voice_template` returns `Result[Unit, VoicePoolError]` with
  `BoundVoicePoolError` mapping; specified `adsr_authoring_indices`
  snapshot is a defensive copy; B5/B6 located in
  `graph/compiled_template_wbtest.mbt`; PR 2 A1 explicitly covers
  adversarial inputs; PR 1 doc scope expanded to tech-reference 859-878
  / 904-906 / 915-925 and blueprint 54 / 193-195; PR 3 adds root facade
  re-export for `VoicePoolError`; C9 CI wiring (browser-smoke.yml
  extension or dedicated boundary-check.yml workflow) specified. Note:
  earlier deferral cross-references to a private backlog file were
  replaced with inline content in §What's Deferred — that section is
  now the canonical record.
- **Round-4 Codex fixes (2026-05-17):** A2/A3 pre-classifier strategy
  spelled out (PR-2-local `A2Reason`/`A3Reason` enums classify failure
  reasons before calling the Option-returning current API, since `None`
  collapses reasons); `VoiceSlot.adsr_authoring_indices_snapshot`
  explicitly uses `.copy()` at allocation; C9 CI wording corrected
  (browser-smoke.yml has no `moon check`/`moon test` step today, script
  brings its own `moon info`); `scripts/check-public-boundary.sh`
  marked as new file (Add, not Update); PR 1 doc-prep timing clarified
  (touchpoints describe new surface as "planned per ADR-0010
  (Proposed)" until PR 3 strips the qualifier and flips ADR-0010 to
  `Accepted`); per-package surface table column updated from "authoring
  + carve-outs" to "authoring APIs + boundary exceptions"; private
  backlog file cross-references replaced with inline deferral content in
  §What's Deferred.
- **Round-5 Codex fixes (2026-05-17):** `CLAUDE.md` one-liner moved
  from PR 1 to PR 3 — `CLAUDE.md` is prescriptive contributor guidance
  and should reflect current behavior, not a "planned per ADR-0010"
  state. PR 1 defers the one-liner and PR 3 adds it.
- **Ambiguity check:** the contract's principle ("Runtime types do not
  accept bare `Array[DspNode]`") is stated once; carve-outs are
  enumerated explicitly; the rule for new public functions (§Public
  Surface Migration "Carve-outs" closing paragraph) is unambiguous.
  `adsr_authoring_indices` semantics ("authoring indices, not runtime
  indices") explicitly disambiguated against the failure mode Codex
  caught.
