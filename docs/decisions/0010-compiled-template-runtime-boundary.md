# ADR-0010: CompiledTemplate as the runtime exchange boundary

- **Status:** Accepted
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

| Current signature | New signature |
|---|---|
| `CompiledDsp::compile(Array[DspNode], DspContext) -> Self?` | `CompiledDsp::compile(CompiledTemplate, DspContext) -> Self?` |
| `CompiledStereoDsp::compile(Array[DspNode], DspContext) -> Self?` | `CompiledStereoDsp::compile(CompiledTemplate, DspContext) -> Self?` |
| `CompiledDsp::compile_template(CompiledTemplate, DspContext) -> Self?` | **removed** (collapses into `compile`) |
| `CompiledStereoDsp::compile_template(CompiledTemplate, DspContext) -> Self?` | **removed** |
| `optimize_graph(Array[DspNode]) -> (Array[DspNode], FixedArray[Int])` | **package-private** |

### Signature migration (voice/)

| Current signature | New signature |
|---|---|
| `VoicePool::new(Array[DspNode], DspContext, max_voices?) -> Self?` | `VoicePool::new(CompiledTemplate, DspContext, max_voices?) -> Result[Self, VoicePoolError]` |
| `VoicePool::set_template(Self, Array[DspNode]) -> Bool` | `VoicePool::set_template(Self, CompiledTemplate) -> Result[Unit, VoicePoolError]` |
| `BoundVoicePool::new(Array[DspNode], DspContext, ControlBindingBuilder, max_voices?) -> Result[Self, BoundVoicePoolError]` | `BoundVoicePool::new(CompiledTemplate, DspContext, ControlBindingBuilder, max_voices?) -> Result[Self, BoundVoicePoolError]` |
| `BoundVoicePool::set_template(Self, Array[DspNode], ControlBindingBuilder) -> Result[Unit, BoundVoicePoolError]` | `BoundVoicePool::set_template(Self, CompiledTemplate, ControlBindingBuilder) -> Result[Unit, BoundVoicePoolError]` |

### New public additions

- `CompiledTemplate::adsr_authoring_indices(Self) -> FixedArray[Int]`
  — runtime gating for voice/. Returns **authoring** indices of ADSR
  nodes that survived optimization, in authoring order — never runtime
  indices. (Authoring-vs-runtime matters: `CompiledDsp::gate_on/gate_off`
  take authoring indices and map through `index_map` internally;
  returning runtime indices would double-map and target wrong nodes.)
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
- `GraphTopologyEdit::InsertChain(...)` variant and `GraphTopologyEdit::insert_chain(...)` constructor

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
- `CompiledTemplate::is_node_live` / `node_at` / `length` public
  promotion. Reserved for the Phase 7+ structural editor; promote when
  a concrete consumer drives the shape (e.g., `live_indices() -> Iter[Int]`
  for highlighting eliminated nodes in the editor UI).
- `derive(Debug)` cascade for `DspNode` / `Waveform` / `BiquadMode`.
  Not needed by current consumers; add when the first consumer arrives.

See the source spec's §What's Deferred for the canonical list and the
deferral rationale per item.

## Test enforcement

`scripts/check-public-boundary.sh` (added in PR 3) audits the public
`.mbti` files for `Array[DspNode]` entries and asserts only the
documented boundary exceptions and allowed authoring APIs appear. New
entries require explicit allowlist updates.
