# Phase 1 Long-Stretch Task: Biquad Filter

This document is the execution brief for the next long autonomous coding run.
It adds the first serious tone-shaping primitive to the Phase 1 DSP surface.

## Goal

Introduce a reusable biquad filter primitive with explicit filter state,
coefficient calculation, block processing via `DspContext`, and tests for basic
LPF, HPF, and BPF behavior.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `docs/phase1-mix-long-stretch.md`
- `RESULTS.md`

## Why This Task

Phase 1 explicitly calls for a biquad module using the Bristow-Johnson
cookbook. After sources and simple utility processors exist, the filter is the
next major primitive that unlocks meaningful synthesis timbre.

## Scope

In scope:

- Add `filter.mbt`
- Implement one reusable biquad state type
- Support at least LPF, HPF, and BPF coefficient generation
- Process `AudioBuffer` in place with `DspContext`
- Add tests for coefficient sanity and basic filtering behavior

Out of scope:

- Shelving and peaking EQ modes unless they fall out naturally
- Filter modulation routing
- Oversampling
- Graph integration

## Success Criteria

- There is a public biquad filter primitive in the package API
- LPF, HPF, and BPF modes are supported
- Tests cover coefficient validity, invalid parameter handling, and representative output behavior
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside audio-rate loops
- Keep filter state explicit and reusable
- Handle invalid cutoff/Q inputs explicitly
- Prefer cookbook formulas from the reference doc and keep comments minimal but precise

## Proposed Work Plan

1. Add `filter.mbt`
2. Define filter mode and state
3. Implement coefficient update and sample/block processing
4. Add tests for parameter validation and basic behavior
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type Biquad`
- explicit constructor or setup method
- mode/coefficient update API
- `process(context, buffer)`

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor naming or mode-enum choices
- Prefer the smallest coherent biquad primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- biquad filter implementation
- tests
- updated generated interface files
- concise summary of what changed and which shaping or dynamics primitive should come next
