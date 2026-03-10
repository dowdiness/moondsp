# Phase 1 Long-Stretch Task: Clip Primitive

This document is the execution brief for the next long autonomous coding run.
It adds an explicit range-limiting stage after the current non-clipping mix
behavior.

## Goal

Introduce a hard-clip primitive with explicit threshold handling, block
processing via `DspContext`, and tests that establish clipping as a deliberate
separate stage rather than an accidental side effect of mixing.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-gain-long-stretch.md`
- `docs/phase1-mix-long-stretch.md`
- `RESULTS.md`

## Why This Task

The current `Mix` primitive intentionally does not clip. The next natural
utility is therefore an explicit clip/distortion stage, which is also listed in
the technical reference’s minimum useful primitive set.

## Scope

In scope:

- Add `clip.mbt`
- Implement hard clipping against a configurable threshold
- Process `AudioBuffer` in place using `DspContext`
- Add tests for threshold behavior, sign symmetry, invalid threshold handling, and block-size truncation

Out of scope:

- Soft clipping
- Waveshaping tables
- Oversampling
- Browser UI changes

## Success Criteria

- There is a reusable clip primitive in the package API
- Clipping behavior is explicit and covered by tests
- Tests cover threshold edges, negative samples, invalid threshold handling, and context truncation
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside processing loops
- Keep the current behavior as hard clipping only
- Handle zero or invalid thresholds deterministically
- Keep the API simple enough to compose after `Mix`

## Proposed Work Plan

1. Add `clip.mbt`
2. Define the minimal public API
3. Implement in-place clipping over `AudioBuffer`
4. Add threshold and edge-case tests
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type Clip`
- constructor if state is useful, otherwise a stateless public API is acceptable
- `process(context, buffer, threshold)` or equivalent

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor threshold naming choices
- Prefer the smallest coherent clip primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- clip implementation
- tests
- updated generated interface files
- concise summary of what changed and which utility or filter primitive should come next
