# ADR-0015: Graph internal boundaries and maintainability roadmap

- **Status:** Proposed
- **Date:** 2026-06-03
- **Source:** Architecture redesign pass after external-authoring, editor-preview,
  typed compile diagnostic, and benchmark follow-ups
- **Related:** ADR-0001 (layered package architecture), ADR-0010
  (`CompiledTemplate` as the runtime exchange boundary), ADR-0014 (authoring
  equality and typed graph compile diagnostics),
  [`../external-dsl-lowering.md`](../external-dsl-lowering.md),
  [`../editor-audio-preview-handoff.md`](../editor-audio-preview-handoff.md),
  [`../mini-graph-authoring-boundary.md`](../mini-graph-authoring-boundary.md)

## Context

ADR-0001 split the old `lib/` monolith into `dsp/`, `graph/`, `voice/`,
`pattern/`, `song/`, `scheduler/`, `mini/`, and `browser/`. That package
layout still gives the project the right top-level shape, but `graph/` has now
absorbed several distinct responsibilities:

- the flat `DspNode` authoring model and node-kind semantics;
- `CompiledTemplate`, optimization, liveness, and index-map behavior;
- `ControlBindingBuilder` / `ControlBindingMap` validation;
- mono and terminal-stereo compiled runtime state and audio processing;
- runtime `GraphControl` validation and application;
- hot-swap and topology-edit staging;
- identity-bearing `GraphTemplateDoc` / `GraphIndexMap` authoring helpers;
- typed compile diagnostics and debug validation.

This is a concrete change pressure, not just a cosmetic organization concern.
External authoring, editor preview handoff, Mini-to-graph template selection,
and last-good-runtime behavior now all rely on graph boundaries being stable
and explainable. Future graph editor work or node-kind additions would currently
touch many unrelated graph files and can accidentally couple authoring/control
logic to audio-hot runtime logic.

A smaller boundary leak also exists: `graph/` publicly re-exports several
`dsp/` types and helper functions mainly for local source/test convenience. That
makes `graph/` look like a secondary DSP facade even though the root package is
the intended public facade.

## Decision

Keep `dowdiness/moondsp/graph` as the public facade, but evolve its
implementation into compiler-enforced internal packages. The intended long-term
shape is:

```text
graph/                         public facade; preserves source-facing API
graph/internal/model/           DspNode, GraphControl, slots, node-kind semantics
graph/internal/template/        CompiledTemplate, optimize/liveness/index maps
graph/internal/binding/         ControlBindingBuilder / ControlBindingMap
graph/internal/runtime/         CompiledDsp/Stereo, process, runtime control, diagnostics
graph/internal/staging/         hot-swap and topology controllers
graph/internal/authoring/       GraphTemplateDoc, GraphIndexMap, stable-ID edits
```

The runtime boundary from ADR-0010 remains unchanged:

- `Array[DspNode]` is an authoring exchange type.
- `CompiledTemplate` is the runtime exchange type.
- `CompiledTemplate::analyze(Array[DspNode])` is the canonical crossing.
- Runtime APIs must not accept bare `Array[DspNode]` except the documented
  topology-controller and authoring exceptions.

Additional boundary rules for the split:

- `graph/internal/runtime` must not import `identity`, `pattern`, `song`,
  `mini`, `scheduler`, `browser`, or the root facade.
- `graph/internal/model` must stay independent of graph authoring and runtime
  staging. It may depend on `dsp` for waveform/filter tags and shape constants.
- `graph/internal/template` may depend on model-level graph semantics, but not
  on authoring docs or runtime state.
- `graph/internal/authoring` may depend on `identity` and may lower stable IDs
  to authoring indices, but runtime processing must not depend on it.
- `graph/` may re-export internal symbols through `pub using`; external
  consumers should continue to import `dowdiness/moondsp/graph` or the root
  `dowdiness/moondsp` facade, not `graph/internal/*`.

The same pressure exists at a smaller scale in `scheduler/` and `browser/`, but
those splits are follow-ups. The first priority is the graph boundary, because
it owns the audio-hot/runtime-control contract and has the largest public API.

## Migration plan

This is an incremental migration, not a rewrite.

1. **Pin boundaries first.** Add checks that document allowed package imports and
   future internal-package direction. Continue running
   `scripts/check-public-boundary.sh` for ADR-0010.
2. **Remove accidental graph DSP re-export pressure.** Migrate graph tests and
   local source toward explicit `@dsp` imports where needed, then deprecate or
   remove graph-level DSP re-exports in a deliberate API window.
3. **Extract `graph/internal/model`.** Move the flat graph model and pure
   node-kind semantics first. Re-export from `graph/` and review generated
   `.mbti` output for source compatibility.
4. **Extract template and binding.** Move `CompiledTemplate`, optimization,
   liveness, and control-binding validation after the model package is stable.
5. **Extract runtime.** Move compile/process/runtime-control/debug internals
   without changing hot loops or allocation behavior.
6. **Extract staging and authoring.** Move hot-swap/topology controllers and
   `GraphTemplateDoc` / `GraphIndexMap` once runtime no longer depends on
   authoring helpers.
7. **Only then split scheduler/browser internals.** Scheduler transport/edit
   policy and browser ABI/demo-host splits should follow the same facade-plus-
   internal-packages pattern after graph boundaries are stable.

## Consequences

**Positive**

- The compiler can enforce boundaries that are currently maintained by review
  discipline inside one large package.
- Audio-hot runtime code becomes easier to protect from authoring/editor
  concerns.
- Node-kind additions get a clearer checklist: update model semantics,
  template/compile validation, runtime processing/control, and public docs.
- External authoring and editor preview contracts remain anchored on
  `CompiledTemplate`, not on runtime internals.
- Public imports can stay stable through the `graph/` facade.

**Negative**

- Internal packages require additional `moon.pkg` manifests and explicit
  re-export maintenance.
- `pub using` through a facade can change generated `.mbti` origin paths; every
  extraction must review `moon info` output and run an external facade smoke
  test.
- Some helpers that were package-private may need to become `pub` inside
  `graph/internal/*`. The `internal/` path prevents downstream imports, but it
  still increases intra-module API surface.
- The migration adds short-term indirection before it removes complexity.

## Non-goals

- No full rewrite.
- No change to DSP algorithms or runtime processing hot loops.
- No Mini parser replacement or Loom production routing; ADR-0013 remains the
  promotion gate for that decision.
- No sample-accurate scheduler redesign.
- No browser wasm ABI rename.
- No performance optimization without benchmark evidence.

## Verification

For every stage:

```bash
moon check
moon test
moon info
scripts/check-public-boundary.sh
scripts/check-architecture-boundaries.sh
```

For graph runtime-control changes, update
`docs/salat-engine-technical-reference.md` first. For runtime extraction stages,
also run `moon build --target wasm-gc` and the graph/browser integration checks
when feasible.
