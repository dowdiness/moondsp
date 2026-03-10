# Phase 1 Long-Stretch Task: Mix Primitive

This document is the execution brief for the next long autonomous coding run.
It follows the oscillator, audio-buffer, DSP-context, and gain work and focuses
on the next simple DSP utility: mixing signals.

## Goal

Introduce a `Mix` DSP primitive that combines audio buffers using `DspContext`,
and add tests that establish it as the first reusable signal-combining block in
the Phase 1 DSP surface.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-oscillator-long-stretch.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `docs/phase1-gain-long-stretch.md`
- `RESULTS.md`

## Why This Task

The project now has a source primitive (`Oscillator`) and a simple in-place
processor (`Gain`). The next highest-value step is to add a reusable primitive
for combining signals before moving on to more complex filters or envelopes.

This task is narrower than “continue Phase 1.” It only establishes the mixing
shape and its edge-case behavior.

## Scope

In scope:

- Add a mix implementation file, for example `mix.mbt`
- Introduce a public `Mix` type or equivalent public API
- Combine one or more `AudioBuffer` values using `DspContext`
- Define and test the project’s current clipping or non-clipping policy
- Add tests for standard and edge-case mix behavior
- Keep the browser demo operational without redesigning it

Out of scope:

- Filters, envelopes, delay, graph compilation
- Dynamic voice allocation or graph scheduling
- Multichannel routing abstractions
- Control smoothing or modulation routing
- Browser UI redesign

## Success Criteria

- There is a public `Mix` primitive in the package API
- Mix processing works with `AudioBuffer` and `DspContext`
- There are passing tests for:
  - summing two buffers
  - block-size truncation behavior
  - invalid context handling
  - the chosen clipping or range policy
- `moon check` passes
- `moon test` passes
- `moon info` reflects the intended public API
- `moon build --target wasm-gc --release` still passes

## Design Constraints

- No allocation inside audio-rate processing loops
- Prefer explicit buffer-to-buffer operations over hidden copies
- Keep the primitive small and deterministic
- Make clipping behavior intentional rather than accidental
- Prefer a method shape that composes cleanly with later gain, filter, and
  graph-node work

## Proposed Work Plan

1. Add `mix.mbt`
2. Define the minimal public API:
   - constructor/new if state is useful
   - one or more mix/process methods
3. Implement block mixing over `AudioBuffer`
4. Add tests for standard and edge-case behavior
5. Run `moon fmt`, `moon check`, `moon test`, `moon info`,
   `moon build --target wasm-gc --release`

## Suggested API Direction

Preferred shape:

- `type Mix`
- `Mix::new(...)` if explicit state is useful, otherwise a simple stateless
  public API is acceptable
- `Mix::process(context, output, input)` or equivalent
- If multiple input buffers are supported later, start with the simplest
  two-buffer form now

The API should remain simple enough that later compiled DSP graphs can call it
without ownership or allocation complications.

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
- Prefer the smallest coherent mix primitive that satisfies current Phase 1
  needs
- Stop only for:
  - contradictory source docs
  - destructive actions
  - missing external prerequisites
  - a public API decision that would obviously constrain later DSP blocks

## Deliverables

- `Mix` implementation
- tests
- updated generated interface files
- concise summary of what changed and which DSP primitive should come next
