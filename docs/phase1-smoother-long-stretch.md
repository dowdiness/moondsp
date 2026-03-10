# Phase 1 Long-Stretch Task: Parameter Smoother

This document is the execution brief for the next long autonomous coding run.
It adds the first dedicated control-smoothing primitive to the Phase 1 DSP
surface.

## Goal

Introduce a one-pole parameter smoother with explicit state, context-aware
coefficient setup, and tests that establish it as the standard Phase 1 answer
for click-free control changes.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `docs/phase1-gain-long-stretch.md`
- `docs/phase1-filter-long-stretch.md`
- `RESULTS.md`

## Why This Task

The blueprint calls out one-pole smoothing explicitly for parameter updates.
Before richer modulation or real-time control mapping arrives, a dedicated
smoother primitive gives later Phase 1 blocks a consistent way to handle
control-rate changes without zipper noise.

## Scope

In scope:

- Add `smooth.mbt`
- Implement one-pole smoothing with explicit state
- Support setup from smoothing time and sample rate
- Add tests for convergence, monotonic approach, and invalid parameter handling

Out of scope:

- Complex modulation systems
- Multi-stage or adaptive smoothing
- Browser UI changes

## Success Criteria

- There is a reusable parameter smoother in the package API
- Coefficient setup is context-aware and deterministic
- Tests cover convergence toward target, smoothing-time behavior, and invalid input handling
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside processing loops
- Keep state explicit and reusable
- Prefer a conventional one-pole formulation over clever abstractions
- Handle zero or invalid smoothing times deterministically

## Proposed Work Plan

1. Add `smooth.mbt`
2. Define smoother state and constructor/setup API
3. Implement `tick` and/or block-friendly update helpers
4. Add convergence and edge-case tests
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type ParamSmoother`
- constructor with initial value and smoothing time
- target-update API
- `tick()` and/or block helper methods

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor coefficient naming choices
- Prefer the smallest coherent smoother primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- smoother implementation
- tests
- updated generated interface files
- concise summary of what changed and which control or graph-related primitive should come next
