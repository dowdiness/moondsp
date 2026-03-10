# Phase 1 Long-Stretch Task: Noise Source

This document is the execution brief for the next long autonomous coding run.
It adds a dedicated noise source to the Phase 1 DSP primitive set.

## Goal

Introduce a white-noise source with explicit RNG state, block processing via
`DspContext`, and tests that establish deterministic, audio-safe noise
generation as a reusable Phase 1 source primitive.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-oscillator-long-stretch.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `RESULTS.md`

## Why This Task

The technical reference explicitly calls out white noise as part of the minimum
primitive set. It is the next useful non-periodic source after oscillator
waveforms and exercises explicit state without introducing graph complexity.

## Scope

In scope:

- Add a dedicated noise source file, for example `noise.mbt`
- Use explicit RNG state suitable for audio-rate generation
- Process into `AudioBuffer` with `DspContext`
- Add deterministic tests around range and state evolution

Out of scope:

- Colored noise
- Sample-and-hold or random modulation utilities
- Browser UI changes

## Success Criteria

- There is a public or clearly reusable noise source primitive
- Output stays in a documented numeric range
- Tests cover range, determinism from a seed, and invalid-context handling
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside audio-rate loops
- Keep RNG simple, explicit, and reproducible
- Prefer integer-state PRNG over floating-point ad hoc generation

## Proposed Work Plan

1. Add `noise.mbt`
2. Define explicit RNG state and constructor/seed path
3. Add block processing
4. Add tests for range and deterministic state progression
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type Noise`
- explicit seeded constructor
- `tick` and/or `process(context, output)`

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor RNG naming choices
- Prefer the smallest coherent white-noise primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- noise source implementation
- tests
- updated generated interface files
- concise summary of what changed and which source or utility primitive should come next
