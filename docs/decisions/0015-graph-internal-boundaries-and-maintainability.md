# ADR-0015: Graph, scheduler, and browser internal boundaries

- **Status:** Accepted
- **Date:** 2026-06-03
- **Implemented:** 2026-06-05
- **Source:** Architecture redesign pass after external-authoring,
  editor-preview, typed compile diagnostic, and benchmark follow-ups
- **Related:** ADR-0001 (layered package architecture), ADR-0010
  (`CompiledTemplate` as the runtime exchange boundary), ADR-0014 (authoring
  equality and typed graph compile diagnostics),
  [`../external-dsl-lowering.md`](../external-dsl-lowering.md),
  [`../editor-audio-preview-handoff.md`](../editor-audio-preview-handoff.md),
  [`../mini-graph-authoring-boundary.md`](../mini-graph-authoring-boundary.md),
  [`../browser-api-contract.md`](../browser-api-contract.md)

## Context

ADR-0001 split the old `lib/` monolith into `dsp/`, `graph/`, `voice/`,
`pattern/`, `song/`, `scheduler/`, `mini/`, and `browser/`. That package
layout still gives the project the right top-level shape, but several packages
had accumulated enough responsibility that review discipline alone was no
longer a sufficient boundary.

The largest pressure was in `graph/`, which had absorbed distinct concerns:

- the flat `DspNode` authoring model and node-kind semantics;
- `CompiledTemplate`, optimization, liveness, and index-map behavior;
- `ControlBindingBuilder` / `ControlBindingMap` validation;
- mono and terminal-stereo compiled runtime state and audio processing;
- runtime `GraphControl` validation and application;
- hot-swap and topology-edit staging;
- identity-bearing `GraphTemplateDoc` / `GraphIndexMap` authoring helpers;
- typed compile diagnostics and debug validation.

This was concrete change pressure, not cosmetic organization. External
authoring, editor preview handoff, Mini-to-graph template selection, and
last-good-runtime behavior all rely on graph boundaries being stable and
explainable. Future graph editor work or node-kind additions would otherwise
risk coupling authoring/control logic to audio-hot runtime logic.

Two smaller pressures followed the same pattern:

- `scheduler/` mixed transport time, playback snapshots, event provenance,
  active-note lifecycle, edit policies, voice dispatch, and public facade
  methods.
- `browser/` mixed the stable worklet ABI with graph-slot lifecycle, demo graph
  templates, playback-host routing, and browser error transport.

A public-surface leak also existed: `graph/` exposed several `dsp/` types and
helpers mainly for local source/test convenience. That made `graph/` look like a
secondary DSP facade even though the root package is the intended combined
facade.

## Decision

Keep the existing top-level packages and public facades, but move implementation
behind compiler-enforced `internal/` packages. This is a boundary hardening
change, not a rewrite.

The shipped graph shape is:

```text
graph/                         public facade; preserves source-facing API
graph/internal/model/           DspNode, GraphControl, slots, node-kind semantics
graph/internal/template/        CompiledTemplate, optimize/liveness/index maps
graph/internal/binding/         ControlBindingBuilder / ControlBindingMap
graph/internal/runtime/         CompiledDsp/Stereo, process, runtime control, diagnostics
graph/internal/staging/         hot-swap and topology controllers
graph/internal/authoring/       GraphTemplateDoc, GraphIndexMap, stable-ID edits
```

The shipped scheduler shape is:

```text
scheduler/                         public facade; preserves scheduler API
scheduler/internal/model/           event provenance, playback-event, and edit-scope value backing
scheduler/internal/transport/       sample/cycle transport helpers
scheduler/internal/playback/        pattern/song playback snapshots
scheduler/internal/voice_runtime/   active-note and voice-side runtime helpers
scheduler/internal/edit_policy/     affected-voice edit policy matching
```

The shipped browser shape is:

```text
browser/                         function-only browser/worklet facade
browser/internal/slot/            reusable graph-slot lifecycle wrapper
browser/internal/demo_templates/  fixed demo graph templates
browser/internal/playback_host/   scheduler playback host and routing internals
```

The runtime boundary from ADR-0010 remains unchanged:

- `Array[DspNode]` is an authoring exchange type.
- `CompiledTemplate` is the runtime exchange type.
- `CompiledTemplate::analyze(Array[DspNode])` is the canonical crossing.
- Runtime APIs must not accept bare `Array[DspNode]` except the documented
  topology-controller and authoring exceptions.

Additional boundary rules:

- `graph/internal/runtime` must not import `identity`, `pattern`, `song`,
  `mini`, `scheduler`, `browser`, or the root facade.
- `graph/internal/model` stays independent of graph authoring and runtime
  staging. It may depend on `dsp` for waveform/filter tags and shape constants.
- `graph/internal/template` may depend on model-level graph semantics, but not
  on authoring docs or runtime state.
- `graph/internal/authoring` may depend on `identity` and may lower stable IDs
  to authoring indices, but runtime processing must not depend on it.
- `scheduler/internal/*` packages may depend on lower-level domain/runtime
  packages they explicitly bridge, but they must not depend on `browser/`.
- `scheduler/internal/voice_runtime` stores active-note provenance with
  `scheduler/internal/model` value backing and delegates affected-voice matching
  to `scheduler/internal/edit_policy`.
- `browser/internal/*` packages may depend on the public runtime, scheduler,
  Mini, pattern, and song surfaces needed by the host, but those packages must
  not depend back on `browser/`.
- Public facades may re-export or wrap internal symbols. External consumers
  should continue to import `dowdiness/moondsp/graph`,
  `dowdiness/moondsp/scheduler`, `dowdiness/moondsp/browser`, or the root
  `dowdiness/moondsp` facade, not `*/internal/*` packages.
- `graph/` is not a secondary DSP facade. Consumers should import DSP APIs from
  `dowdiness/moondsp/dsp` or the root `dowdiness/moondsp` facade.
- `browser/` remains a function-only facade. Browser route/pool/scheduler state
  objects are implementation details unless a future API decision explicitly
  promotes them.

## Migration record

The migration shipped incrementally rather than by replacement:

1. **Boundary checks were added.** `scripts/check-architecture-boundaries.sh`
   documents allowed package imports and facade rules. `scripts/check-public-boundary.sh`
   continues to enforce ADR-0010.
2. **The accidental graph DSP facade was removed.** Graph source and tests now
   use explicit DSP imports where needed, and graph no longer publicly
   re-exports DSP helpers as a convenience surface.
3. **Graph internals were extracted.** Model, template, binding, runtime,
   staging, and authoring responsibilities moved behind `graph/internal/*` while
   `graph/` preserved the public source-facing API.
4. **Scheduler internals were extracted.** Event/provenance and edit-scope
   value backing, transport, playback snapshots, active-note/voice-runtime
   helpers, and edit-policy matching moved behind `scheduler/internal/*` while
   `scheduler/` preserved its public facade.
5. **Browser internals were extracted and tightened.** Graph slots, demo
   templates, and playback-host routing moved behind `browser/internal/*`.
   The package path and JS/wasm-gc worklet export ABI stayed stable, but the
   MoonBit source facade was intentionally narrowed in a breaking cleanup that
   removed the legacy leaked browser route shell types. Follow-up work added
   `scripts/check-browser-abi.sh` plus the browser ABI baseline.

## Consequences

**Positive**

- Package boundaries now enforce rules that previously lived mostly in review
  discipline.
- Audio-hot graph runtime code is better protected from authoring/editor,
  scheduler, Mini, and browser concerns.
- Node-kind additions have a clearer checklist: update model semantics,
  template/compile validation, runtime processing/control, and public docs.
- External authoring and editor preview contracts remain anchored on
  `CompiledTemplate`, not on runtime internals.
- Scheduler public imports remain stable while implementation detail is hidden
  behind `internal/` paths.
- Browser implementation detail is hidden behind `browser/internal/*`; the
  package import path and JS/wasm-gc worklet ABI remained stable, while the
  MoonBit source facade was deliberately narrowed by the route-shell removal.
- Future browser facade/export drift is now observable through an ABI baseline
  check.

**Negative**

- Internal packages require additional `moon.pkg` manifests and explicit facade
  maintenance.
- Facade wrappers and `pub using` can change generated `.mbti` origin paths;
  boundary changes still require `moon info` review.
- Some helpers that used to be package-private are now `pub` inside
  `*/internal/*` packages. The `internal/` path prevents downstream imports, but
  it still increases intra-module API surface.
- The delivered structure adds indirection. It lowers long-term coupling, but it
  can make local navigation less direct until contributors learn the package
  map.

## Non-goals

- No full rewrite.
- No change to DSP algorithms or runtime processing hot loops.
- No Mini parser replacement or Loom production routing; ADR-0013 remains the
  promotion gate for that decision.
- No sample-accurate scheduler redesign.
- No browser wasm ABI rename.
- No performance optimization without benchmark evidence.

## Verification

For boundary-sensitive work, run:

```bash
moon check
moon test
moon info
scripts/check-public-boundary.sh
scripts/check-architecture-boundaries.sh
```

For browser facade/export work, also run:

```bash
scripts/check-browser-abi.sh
```

For graph runtime-control changes, update
`docs/salat-engine-technical-reference.md` first. For runtime extraction or
hot-path changes, also run `moon build --target wasm-gc` and the relevant
benchmarks or browser integration checks when feasible.
