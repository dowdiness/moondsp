# Phase 2 Stereo MixDown Design Brief

This document defines the next stereo-specific design step after the current
stereo post-processing checkpoint.

It does not attempt to solve full multichannel routing. The goal is narrower:
introduce the first explicit `Stereo -> Mono` graph node without relaxing the
strict channel-shape rules already established in Phase 2.

## Goal

Introduce `StereoMixDown` in a way that:

- preserves the existing mono `CompiledDsp` path
- preserves the current `CompiledStereoDsp` path
- keeps one `DspNode` authoring language
- adds the first explicit `Stereo -> Mono` node
- continues to reject implicit `Stereo -> Mono` downmix
- avoids collapsing the graph model into generic multichannel semantics

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase2-stereo-graph-design-brief.md`
- `docs/phase2-stereo-post-processing-design-brief.md`
- `graph.mbt`
- `integration_test.mbt`

## Current Checkpoint

The repository already implements:

- `CompiledDsp` for mono graphs
- `CompiledStereoDsp` for stereo graphs
- strict compile-time shape checking
- `Pan` as `Mono -> Stereo`
- `StereoGain` and `StereoClip` as `Stereo -> Stereo`
- `StereoOutput` as the current stereo terminal node
- runtime and batched control on the compiled stereo path

Current limit:

- stereo graphs cannot explicitly return to mono
- `Stereo -> Mono` is still only a rejected implicit conversion
- there is no graph-level equivalent of a deliberate stereo fold-down

That is now the main barrier to expressing graphs such as:

- `Oscillator -> Pan -> StereoGain -> StereoMixDown -> Output`
- `Noise -> Pan -> StereoClip -> StereoMixDown -> Biquad -> Output`

## Problem

The current stereo graph model can create and process stereo signals, but it
cannot intentionally collapse them back into mono within the graph.

That blocks a useful class of graphs:

- stereo widening followed by mono effects
- stereo monitoring paths that must feed a mono output
- future explicit mid-style or fold-down workflows

Without an explicit `Stereo -> Mono` node, the graph has to choose between two
bad options:

- reject the graph entirely
- introduce hidden downmix behavior at compile time

The second option should still be avoided.

## Design Decision

Add a single explicit `Stereo -> Mono` node before considering any wider
multichannel abstraction.

That means:

- keep the current `Mono` / `Stereo` shape model
- keep `Pan` as the only `Mono -> Stereo` node for now
- keep implicit downmix forbidden
- add `StereoMixDown` as the first explicit `Stereo -> Mono` node
- allow graphs to move back into the mono compiler path only through that node

This is the smallest change that makes the graph channel model more expressive
without turning every connection into an implicit channel policy decision.

## Proposed Semantics

### 1. Channel Shapes

Keep the current explicit shape model:

- `Mono`
- `Stereo`

Add one new node kind:

- `StereoMixDown`
  - `Stereo -> Mono`

Do not add any new implicit shape conversions in this slice.

### 2. Connection Rules

Preserve the existing strict compile-time rules:

- `Mono -> Mono` is allowed where shapes match
- `Stereo -> Stereo` is allowed where shapes match
- implicit `Mono -> Stereo` duplication is rejected
- implicit `Stereo -> Mono` downmix is rejected

Add one explicit exception:

- `StereoMixDown` is the only legal `Stereo -> Mono` conversion in this slice

That means the following should be legal:

```text
Mono graph -> Pan -> StereoGain? -> StereoClip? -> StereoMixDown -> Output
```

The following should still be rejected:

- `StereoNode -> Output`
  - without `StereoMixDown`
- `StereoNode -> MonoNode`
  - without `StereoMixDown`
- `CompiledDsp::compile(...)` receiving stereo-only terminal graphs
- `CompiledStereoDsp::compile(...)` receiving graphs whose final output is mono

`CompiledDsp::compile(...)` and `CompiledStereoDsp::compile(...)` should keep
their current terminal-output contracts explicit.

### 3. Node Form

Suggested node constructor:

```moonbit
DspNode::stereo_mixdown(input)
```

Semantics:

- input must be `Stereo`
- output is `Mono`
- the first slice should use one fixed mixdown policy
- no separate per-channel weights yet
- no selectable mixdown modes yet

Recommended first policy:

- equal-weight average of left and right

```text
mono = 0.5 * (left + right)
```

Why this first:

- predictable
- easy to document
- avoids amplitude doubling from naive summation
- keeps runtime control surface minimal

### 4. Runtime Control

Do not add runtime parameters to `StereoMixDown` in the first slice.

Recommended policy:

- `StereoMixDown` has no `set_param(...)` slots
- future weighted or mode-selectable mixdown should be a later design step

Reason:

- the first goal is explicit shape conversion, not a configurable stereo matrix
- fixed semantics keep the API and tests simple

## Compile-Boundary Policy

This slice should keep one `DspNode` authoring language, but still preserve the
separate compiled graph types:

- `CompiledDsp`
  - mono terminal output only
- `CompiledStereoDsp`
  - stereo terminal output only

That implies two explicit compile rules:

- `CompiledDsp::compile(...)` may accept graphs that contain stereo subgraphs,
  but only if they return to mono through `StereoMixDown` before the final
  `Output`
- `CompiledStereoDsp::compile(...)` must reject graphs whose final output shape
  is mono, even if they contain stereo nodes internally

This is the key distinction for this slice:

- authoring graph may now move `Mono -> Stereo -> Mono`
- compiled output type is still determined by the final output shape

## Implementation Strategy

### Preferred Path

Extend the existing shape inference and mono compiler path rather than
introducing another compiled graph type.

Concrete steps:

1. Add `DspNodeKind::StereoMixDown`
2. Add `DspNode::stereo_mixdown(input)`
3. Extend shape inference to allow explicit `Stereo -> Mono`
4. Add a stereo-to-mono processing helper over planar left/right buffers
5. Allow `CompiledDsp::compile(...)` to compile graphs that contain stereo
   segments ending in `StereoMixDown`
6. Keep `CompiledStereoDsp::compile(...)` rejecting mono terminal graphs
7. Add graph and integration tests

### Why Not More General Now

Avoid these in the same slice:

- weighted left/right mix matrices
- configurable downmix laws
- stereo-to-mono sidechain semantics
- arbitrary channel reshaping
- generalized `N -> M` graph nodes
- full shared mono/stereo compiled-core refactor

Those decisions belong to a later multichannel design step.

## Explicit Non-Goals

Not in scope for this slice:

- full multichannel routing
- configurable stereo mixdown modes
- separate left/right weight control
- stereo feedback design
- stereo filter or delay redesign
- implicit channel conversions
- redesign of `apply_control(...)` or `apply_controls(...)`

## Suggested First Stereo MixDown Slice

1. Add `StereoMixDown`
2. Allow `Pan -> StereoMixDown -> Output`
3. Allow `Pan -> StereoGain -> StereoClip -> StereoMixDown -> Output`
4. Keep `StereoMixDown` fixed-policy and non-dynamic
5. Add compile-time rejection tests for implicit downmix
6. Add one end-to-end integration test for:
   - center pan before mixdown
   - hard-left pan before mixdown
   - hard-right pan before mixdown

## Success Criteria

- A graph can explicitly move from stereo back to mono
- Implicit `Stereo -> Mono` conversion is still rejected
- `CompiledDsp` can compile graphs with internal stereo segments that end in
  `StereoMixDown`
- `CompiledStereoDsp` still only accepts stereo-terminal graphs
- `StereoMixDown` behavior is documented and fixed
- Tests cover both graph-shape rejection and end-to-end mono result after
  stereo mixdown

## Open Questions

- Should the first mixdown policy remain permanently fixed, or should future
  design allow selectable laws such as sum, average, or weighted fold-down?
- Should later stereo-aware nodes share a common stereo processing helper layer
  before more `Stereo -> Mono` or `Stereo -> Stereo` nodes are added?
- After `StereoMixDown`, is the next higher-value node a weighted mixdown
  variant, `StereoBiquad`, or a broader channel-shaped graph refactor?

## Recommendation

Do not jump from the current stereo checkpoint to generic channel reshaping.

Take one constrained step:

- add `StereoMixDown`
- keep it fixed-policy
- keep implicit downmix forbidden
- let mono graphs contain explicit stereo segments only when they return through
  `StereoMixDown`

If that works cleanly, the project can later decide whether to generalize
stereo/mono reshaping or keep adding narrowly-scoped channel-explicit nodes.
