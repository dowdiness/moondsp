# Phase 2 Stereo Post-Processing Design Brief

This document defines the next stereo-specific design step after the current
terminal-stereo checkpoint.

It does not attempt to solve full multichannel routing. The goal is narrower:
allow a small amount of explicit stereo post-processing after `Pan` without
collapsing the graph model into implicit channel expansion rules.

## Goal

Introduce the first stereo post-processing model that:

- preserves the existing mono `CompiledDsp` path
- preserves the current terminal-stereo `CompiledStereoDsp` path
- allows selected `Stereo -> Stereo` nodes after `Pan`
- keeps one `DspNode` authoring language
- avoids implicit `Mono -> Stereo` duplication or `Stereo -> Mono` downmix
- does not expand into full multichannel semantics yet

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase2-stereo-graph-design-brief.md`
- `graph.mbt`
- `pan.mbt`
- `integration_test.mbt`

## Current Checkpoint

The repository already implements:

- `CompiledDsp` for mono graphs
- `CompiledStereoDsp` for terminal stereo graphs
- strict stereo shape rules
- `Pan` as the first `Mono -> Stereo` node
- `StereoOutput` as the terminal stereo output
- runtime `Pan` updates and stereo integration coverage

Current limit:

- stereo is terminal only: `Mono -> Pan -> StereoOutput`
- no node may appear after `Pan` except `StereoOutput`

That limit is now the main barrier to making stereo graphs more useful.

## Problem

The current stereo graph model proves channel-shape semantics, but it cannot
express even small practical stereo chains such as:

- `Oscillator -> Gain -> Pan -> StereoGain -> StereoOutput`
- `Noise -> Pan -> StereoClip -> StereoOutput`

Without some explicit `Stereo -> Stereo` support, the graph layer stalls at the
moment stereo begins.

## Design Decision

Add a small explicit stereo node set before designing a general stereo channel
system.

That means:

- keep the current strict shape rules
- keep `Pan` as the only `Mono -> Stereo` node for now
- add a small number of dedicated `Stereo -> Stereo` processors
- keep stereo routing explicit, not implicit

Recommended first stereo post-processing nodes:

- `StereoGain`
- `StereoClip`

Why these first:

- both are simple and already have clear mono semantics in the codebase
- both operate independently per channel, so they do not require new cross-
  channel DSP logic
- both are useful immediately after `Pan`
- both are lower risk than starting with stereo filters or stereo mix/downmix

## Proposed Semantics

### 1. Channel Shapes

Keep the current explicit shape model:

- `Mono`
- `Stereo`

Add two new node kinds:

- `StereoGain`
  - `Stereo -> Stereo`
- `StereoClip`
  - `Stereo -> Stereo`

The first stereo post-processing slice should not add any new `Mono -> Stereo`
or `Stereo -> Mono` node kinds.

### 2. Connection Rules

Preserve the existing strict compile-time rules:

- `Mono -> Mono` is allowed where shapes match
- `Stereo -> Stereo` is allowed where shapes match
- implicit `Mono -> Stereo` duplication is rejected
- implicit `Stereo -> Mono` downmix is rejected
- `CompiledDsp::compile(...)` must reject stereo-only nodes such as
  `StereoGain`, `StereoClip`, and `StereoOutput`

Only explicit nodes may change channel shape.

That means the next legal stereo chain shape becomes:

```text
Mono graph -> Pan -> StereoGain? -> StereoClip? -> StereoOutput
```

The graph compiler should still reject:

- `Mono -> StereoOutput`
- `Pan -> MonoNode`
- `StereoNode -> MonoNode`

### 3. Node Forms

Suggested node constructors:

```moonbit
DspNode::stereo_gain(input, amount)
DspNode::stereo_clip(input, threshold)
```

Semantics:

- `stereo_gain`
  - input must be `Stereo`
  - applies one scalar gain equally to left and right
  - first slice does not require separate left/right gains
- `stereo_clip`
  - input must be `Stereo`
  - applies one threshold equally to left and right
  - first slice does not require asymmetric thresholds

This keeps the public API small and avoids inventing per-channel parameter
shapes too early.

### 4. Runtime Control

The first stereo post-processing slice should fit the existing control model.

Recommended runtime support:

- `StereoGain`
  - `Value0`
- `StereoClip`
  - `Value0`

This mirrors the mono `Gain` and `Clip` behavior and keeps
`apply_control(...)` / `apply_controls(...)` coherent.

## Implementation Strategy

### Preferred Path

Extend `CompiledStereoDsp` incrementally rather than redesigning the whole graph
compiler.

Concrete steps:

1. Add `DspNodeKind::StereoGain`
2. Add `DspNodeKind::StereoClip`
3. Extend stereo shape validation to allow `Stereo -> Stereo`
4. Add stereo planar processing helpers:
   - apply gain to left/right
   - apply clip to left/right
5. Extend stereo runtime param validation and side effects
6. Add graph tests and one end-to-end integration test

### Why Not Generalize More Now

Avoid these in the same slice:

- `StereoBiquad`
- `StereoDelay`
- `StereoMixDown`
- arbitrary stereo bus routing
- generic per-channel parameter vectors
- channel-polymorphic nodes

Those all push the design toward full multichannel semantics. This slice should
only prove that stereo can continue past `Pan` in a controlled way.

## Explicit Non-Goals

Not in scope for this slice:

- full multichannel graph semantics
- stereo feedback design
- implicit upmix/downmix rules
- separate left/right parameter control
- stereo filter or stereo delay design
- graph hot-swap redesign
- sample-accurate stereo automation

## Suggested First Stereo Post-Processing Slice

1. Add `StereoGain`
2. Add `StereoClip`
3. Allow `Pan -> StereoGain -> StereoOutput`
4. Allow `Pan -> StereoClip -> StereoOutput`
5. Add runtime `set_param(...)` support for both
6. Add one compiled stereo integration test with batched runtime updates

## Success Criteria

- A stereo graph can legally continue after `Pan`
- The compiler still rejects implicit shape conversions
- `CompiledStereoDsp` remains explicit and separate from `CompiledDsp`
- `StereoGain` and `StereoClip` work on planar left/right buffers
- Runtime updates for stereo post-processing fit the existing control API
- Tests cover both graph-shape rejection and end-to-end stereo processing

## Open Questions

- Should the first stereo post-processing slice expose one scalar parameter per
  stereo node, or should it immediately allow separate left/right control?
- Should mono and stereo gain/clip share more internal helper code before adding
  more stereo node kinds?
- After `StereoGain` and `StereoClip`, is the next stereo node more likely to be
  `StereoMixDown`, `StereoBiquad`, or a generalized channel-shaped processor
  model?

## Recommendation

Do not jump straight from terminal stereo to general stereo DSP.

Take one constrained step:

- add `StereoGain`
- add `StereoClip`
- keep all connection rules explicit

If that works cleanly, the project can then decide whether the next slice should
stay incremental or move toward a wider stereo/multichannel node system.
