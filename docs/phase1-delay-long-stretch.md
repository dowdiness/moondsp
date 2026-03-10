# Phase 1 Long-Stretch Task: Delay Line

This document is the execution brief for the next long autonomous coding run.
It adds the first circular-buffer effect primitive to the Phase 1 DSP surface.

## Goal

Introduce a reusable delay-line primitive with explicit circular-buffer state,
context-driven processing, and tests that establish correct read/write
behavior, delay length handling, and feedback-safe basics.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `RESULTS.md`

## Why This Task

Phase 1 explicitly calls for a delay primitive. It is the first processor that
needs substantial internal buffer state, making it an important checkpoint for
the project’s “no allocation in audio paths” rule.

## Scope

In scope:

- Add `delay.mbt`
- Implement a circular-buffer delay line with explicit state
- Support configurable delay length within a maximum preallocated size
- Add tests for read/write timing, wraparound, and invalid parameter handling

Out of scope:

- Fractional delay interpolation unless it falls out naturally
- Multi-tap delay
- Modulated delay effects
- Feedback networks

## Success Criteria

- There is a reusable delay primitive in the package API
- Delay processing uses preallocated storage only
- Tests cover wraparound, correct delayed output, and invalid delay-length handling
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside processing loops
- Keep write/read pointer logic explicit
- Clamp or otherwise normalize invalid delay lengths deterministically
- Prefer the simplest correct circular-buffer design first

## Proposed Work Plan

1. Add `delay.mbt`
2. Define delay state and constructor
3. Implement sample or block processing with circular-buffer indexing
4. Add wraparound and edge-case tests
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type DelayLine`
- constructor with maximum delay size
- setter or constructor path for active delay length
- `tick` and/or `process(context, buffer)`

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor pointer naming choices
- Prefer the smallest coherent delay primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- delay-line implementation
- tests
- updated generated interface files
- concise summary of what changed and which effect or control primitive should come next
