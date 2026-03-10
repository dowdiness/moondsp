# Phase 1 Long-Stretch Task: Gain Primitive

This document is the execution brief for the next long autonomous coding run.
It follows the oscillator, audio-buffer, and DSP-context work and focuses on
the first simple effect processor: gain.

## Goal

Introduce a `Gain` DSP primitive that processes `AudioBuffer` blocks in place
using `DspContext`, and add tests that establish it as the first reusable
non-source processor in the Phase 1 DSP surface.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-oscillator-long-stretch.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `RESULTS.md`

## Why This Task

The project now has a source primitive (`Oscillator`), a block container
(`AudioBuffer`), and shared runtime context (`DspContext`). The next highest-
value step is to add the simplest reusable processor that transforms an
existing signal in place.

This task is narrower than “continue Phase 1.” It only establishes the gain
processor and its processing shape.

## Scope

In scope:

- Add a gain implementation file, for example `gain.mbt`
- Introduce a public `Gain` type or equivalent public API
- Process `AudioBuffer` in place using `DspContext`
- Handle invalid runtime inputs explicitly
- Add tests for gain processing behavior
- Keep the browser demo operational without redesigning it

Out of scope:

- Filters, envelopes, delay, mix, graph compilation
- Modulation routing or control smoothing
- Multichannel abstractions
- Browser UI redesign
- Broader graph API design beyond what is needed for a standalone gain
  primitive

## Success Criteria

- There is a public `Gain` primitive in the package API
- Gain processing works on `AudioBuffer` with `DspContext`
- There are passing tests for:
  - unity gain
  - zero gain
  - negative gain
  - invalid context or invalid gain handling
- `moon check` passes
- `moon test` passes
- `moon info` reflects the intended public API
- `moon build --target wasm-gc --release` still passes

## Design Constraints

- No allocation inside audio-rate processing loops
- Prefer in-place processing over copy-producing APIs
- Keep the primitive small and explicit
- Make invalid-input behavior deterministic
- Prefer naming and method shape that will remain consistent with future
  filters, envelopes, and mix processors

## Proposed Work Plan

1. Add `gain.mbt`
2. Define the minimal public API:
   - constructor/new if state is needed
   - process/in-place apply method
3. Implement in-place gain processing over `AudioBuffer`
4. Add tests for standard and edge-case gain behavior
5. Run `moon fmt`, `moon check`, `moon test`, `moon info`,
   `moon build --target wasm-gc --release`

## Suggested API Direction

Preferred shape:

- `type Gain`
- `Gain::new(...)` if explicit state is useful, otherwise a simple stateless
  public API is acceptable
- `Gain::process(context, buffer, amount)` or equivalent

The API should remain simple enough that later graph nodes can embed or call it
without adding ownership or lifecycle complexity.

## Verification

Run at minimum:

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

Optional browser smoke test if demo wiring changes:

- `./serve.sh`
- open the printed URL
- click `Start Audio`
- confirm audible output or at least live meter activity

## Autonomy Policy

During the long-stretch run:

- Continue without asking about minor API naming choices
- Prefer the smallest coherent gain primitive that satisfies current Phase 1
  needs
- Stop only for:
  - contradictory source docs
  - destructive actions
  - missing external prerequisites
  - a public API decision that would obviously constrain later DSP blocks

## Deliverables

- `Gain` implementation
- tests
- updated generated interface files
- concise summary of what changed and which DSP primitive should come next
