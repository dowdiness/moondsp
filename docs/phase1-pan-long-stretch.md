# Phase 1 Long-Stretch Task: Pan Primitive

This document is the execution brief for the next long autonomous coding run.
It adds the first stereo-positioning utility to the Phase 1 DSP surface.

## Goal

Introduce a panning primitive with equal-power behavior, explicit current
policy for mono-to-stereo handling, and tests that establish the first
stereo-aware utility in the Phase 1 DSP set.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-gain-long-stretch.md`
- `docs/phase1-mix-long-stretch.md`
- `RESULTS.md`

## Why This Task

The technical reference includes pan alongside gain and mix. After those two
utilities exist, panning is the next smallest signal-shaping helper before more
complex multichannel work.

## Scope

In scope:

- Add `pan.mbt` or add a pan-focused primitive to the current utility layer
- Implement equal-power or otherwise explicitly documented panning math
- Define how mono input maps to stereo output for the current project stage
- Add tests for left, center, and right positions plus invalid input handling

Out of scope:

- General multichannel routing
- Surround semantics
- Browser UI changes

## Success Criteria

- There is a reusable pan primitive in the package API
- The pan policy is explicit and covered by tests
- Tests cover left, center, right, and invalid-position behavior
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside processing loops
- Keep stereo math explicit and documented
- Make invalid position handling deterministic
- Avoid overdesigning channel-layout abstractions this early

## Proposed Work Plan

1. Add `pan.mbt`
2. Define the current mono-to-stereo pan API
3. Implement equal-power pan math
4. Add tests for edge positions and center behavior
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type Pan`
- constructor if state is needed, otherwise stateless public API is acceptable
- `process(context, mono_input, left_output, right_output, position)` or equivalent

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor stereo naming choices
- Prefer the smallest coherent pan primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- pan implementation
- tests
- updated generated interface files
- concise summary of what changed and which stereo or utility primitive should come next
