# Phase 1 Long-Stretch Task: ADSR Envelope

This document is the execution brief for the next long autonomous coding run.
It adds the first time-varying control primitive to the Phase 1 DSP surface.

## Goal

Introduce an ADSR envelope primitive with explicit state transitions, block or
sample processing, and tests that establish reliable attack/decay/sustain/
release behavior.

## Source Of Truth

- `AGENTS.md`
- `docs/salat-engine-blueprint.md`
- `docs/salat-engine-technical-reference.md`
- `docs/phase1-dsp-context-long-stretch.md`
- `docs/phase1-gain-long-stretch.md`
- `RESULTS.md`

## Why This Task

The envelope is the first essential control-rate building block for turning raw
oscillators into playable synth voices. It is explicitly part of the Phase 1
package map and will later combine naturally with gain and filters.

## Scope

In scope:

- Add `env.mbt`
- Implement ADSR state and gate transitions
- Support context-driven progression over time
- Add tests for attack, decay, sustain, release, and note-off edge cases

Out of scope:

- Multi-stage breakpoint envelopes
- Tempo-synced envelopes
- Polyphonic voice allocation
- Browser UI changes

## Success Criteria

- There is a reusable ADSR primitive in the package API
- Envelope state evolves correctly across gate on/off transitions
- Tests cover each stage and release-from-current-level behavior
- `moon check`, `moon test`, `moon info`, and `moon build --target wasm-gc --release` pass

## Design Constraints

- No allocation inside processing loops
- Keep stage transitions explicit
- Handle zero or invalid times deterministically
- Prefer simple, inspectable math over clever compressed logic

## Proposed Work Plan

1. Add `env.mbt`
2. Define envelope state and stage enum
3. Implement gate handling and sample/block processing
4. Add stage and edge-case tests
5. Run verification and inspect `.mbti`

## Suggested API Direction

Preferred shape:

- `type Adsr`
- explicit constructor with timing parameters
- `gate_on`, `gate_off`
- `tick` and/or `process(context, output)`

## Verification

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon build --target wasm-gc --release`

## Autonomy Policy

- Continue without asking about minor stage naming choices
- Prefer the smallest coherent ADSR primitive that satisfies current Phase 1 needs
- Stop only for contradictory docs, destructive actions, missing prerequisites, or a public API decision that obviously constrains later DSP blocks

## Deliverables

- ADSR implementation
- tests
- updated generated interface files
- concise summary of what changed and which modulation or voice-related primitive should come next
