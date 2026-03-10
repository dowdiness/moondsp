# Phase 1 Long-Stretch Task: DSP Context

This document is the execution brief for the next long autonomous coding run.
It follows the oscillator and audio-buffer work and focuses on the next shared
DSP primitive: execution context.

## Goal

Introduce a `DspContext` type that carries shared runtime information such as
sample rate and block size, refactor oscillator block processing to consume it,
and add tests that establish context-driven processing as the standard Phase 1
shape for future DSP blocks.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-oscillator-long-stretch.md`
- `docs/phase1-audiobuffer-long-stretch.md`
- `RESULTS.md`

## Why This Task

The project now has explicit `Oscillator` and `AudioBuffer` primitives, but
runtime parameters are still passed ad hoc to each processing call. The next
highest-value step is to standardize that shared execution context before more
DSP primitives appear.

This task is narrower than “continue Phase 1.” It only establishes the shared
context surface and migrates the oscillator to it.

## Scope

In scope:

- Add a context abstraction file, for example `context.mbt`
- Introduce a public `DspContext` type with at least sample rate and block size
- Provide explicit constructors and accessors that fit the current wrapper API
- Refactor oscillator block processing to use `DspContext`
- Add tests for context creation and context-driven oscillator processing
- Keep the browser demo operational, preserving the exported wrapper functions

Out of scope:

- Filters, envelopes, delay, mix, graph compilation
- Multichannel routing or channel layout abstractions
- Shared buffer pools or allocator design
- Browser UI redesign
- Broad API redesign beyond what is needed to establish context-driven
  processing

## Success Criteria

- There is a public `DspContext` type in the package API
- `DspContext` contains at least sample rate and block size
- Oscillator block processing uses `DspContext` instead of loose scalar
  parameters
- There are passing tests for valid context creation and context-driven
  oscillator output
- Invalid context inputs are handled explicitly and do not poison DSP state
- `moon check` passes
- `moon test` passes
- `moon info` reflects the intended public API
- `moon build --target wasm-gc --release` still passes

## Design Constraints

- No allocation inside audio-rate processing loops
- Keep the type small and explicit
- Preserve direct one-sample oscillator `tick(freq, sample_rate)` for the
  browser demo path unless there is a strong reason to change it
- Do not overdesign for future scheduling or graph execution yet
- Prefer API names that will still make sense for filters, envelopes, and delay
  processors later

## Proposed Work Plan

1. Add `context.mbt` with `DspContext`
2. Implement a minimal API:
   - constructor/new
   - sample-rate accessor
   - block-size accessor
3. Refactor `Oscillator::process` to consume `DspContext`
4. Update oscillator tests to use context-driven processing
5. Add direct `DspContext` tests
6. Run `moon fmt`, `moon check`, `moon test`, `moon info`,
   `moon build --target wasm-gc --release`

## Suggested API Direction

Preferred shape:

- `type DspContext`
- `DspContext::new(sample_rate, block_size)`
- `DspContext::sample_rate`
- `DspContext::block_size`
- `Oscillator::process(context, output, freq)`

The context should remain cheap and unsurprising enough that future processors
can accept it uniformly without hidden ownership or lifecycle complexity.

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
- Prefer the smallest coherent context type that satisfies current Phase 1
  needs
- Stop only for:
  - contradictory source docs
  - destructive actions
  - missing external prerequisites
  - a public API decision that would obviously constrain later DSP blocks

## Deliverables

- `DspContext` implementation
- oscillator refactor onto context-driven processing
- tests
- updated generated interface files
- concise summary of what changed and which DSP primitive should come next
