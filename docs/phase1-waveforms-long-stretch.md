# Phase 1 Long-Stretch Task: Oscillator Waveforms

This document is the execution brief for the next long autonomous coding run.
It follows the initial sine oscillator work and expands `osc.mbt` into a more
useful Phase 1 oscillator surface.

## Goal

Extend the oscillator primitive beyond sine so the package can generate saw,
square, and triangle waveforms with explicit state and tests, while preserving
the current browser demo path.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-oscillator-long-stretch.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `RESULTS.md`

## Why This Task

The current oscillator only covers the sine case. Phase 1 in the blueprint
calls for a practical oscillator module, and the next highest-value extension
is to add the common subtractive-synthesis waveforms before more advanced
modulation or graph work.

## Scope

In scope:

- Expand `osc.mbt` to support saw, square, and triangle
- Keep oscillator state explicit
- Add tests for waveform range and basic shape behavior
- Preserve the exported demo wrapper functions

Out of scope:

- PolyBLEP or anti-aliasing refinement unless strictly needed
- Noise generation
- FM, sync, wavetable playback, or phase modulation
- Browser UI redesign

## Success Criteria

- The oscillator API supports sine, saw, square, and triangle
- Block processing works with `DspContext` and `AudioBuffer`
- Tests cover waveform output range and expected qualitative behavior
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside audio-rate loops
- Keep phase wrapping explicit and shared where possible
- Avoid hidden branching costs that make later oscillator expansion awkward
- Preserve the current demo exports even if new waveform APIs stay internal to MoonBit for now

## Proposed Work Plan

1. Extend `osc.mbt` with waveform selection or dedicated oscillator variants
2. Reuse the current phase-accumulator path
3. Add one-sample and block-processing tests for each waveform
4. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- extend `Oscillator`
- expose a waveform selection mechanism that still keeps state explicit
- keep direct `tick(freq, sample_rate)` demo wrappers unchanged

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor naming choices
- Prefer the smallest coherent waveform expansion that fits the current oscillator API
- Stop only for contradictory source docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- oscillator waveform expansion
- tests
- updated generated interface files
- concise summary of what changed and what Phase 1 source primitive should come next
