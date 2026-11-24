# ADR-0027: Allocation-free trigonometry is a leaf below dsp and Mini

- **Status:** Proposed
- **Date:** 2026-11-24
- **Source:** [Amp thread T-01a1f1e9](https://ampcode.com/threads/T-01a1f1e9-f526-7738-a2f7-d0eedb4d46b5)
- **Refines:** [ADR-0001](0001-layered-package-architecture.md) (layered
  package architecture)
- **Related:** [signal observation allocation audit](../performance/2026-11-19-signal-observation-allocations.md)

## Context

Core `@math.sin` and `@math.cos` construct objects on wasm-gc each call.
`dsp` holds a scalar kernel that computes the same bits without
constructing anything, for oscillators and biquad coefficients.

Mini's `sine` and `cosine` control signals are evaluated on the audio
thread whenever a voice follows their bus, so they need that kernel too.
Importing it from `dsp` made Mini depend on the DSP layers, which ADR-0001
rules out ("`mini/` and `pattern/` have zero dependency on the DSP
layers"), and `scripts/check-architecture-boundaries.sh` rejected the edge.
Copying the kernel into Mini would leave two copies of target-specific
numeric code to keep bit-identical.

## Decision

The kernel moves, unchanged and with its per-target variants, into its own
package, `trig`. `trig` holds only allocation-free scalar numeric code and
imports no moondsp package.

```
trig/  — allocation-free scalar trigonometry (zero internal deps)
  ↑   ↑
dsp/  mini/
```

- `dsp` imports `trig` and nothing else in moondsp. Its oscillators and
  biquads call `@trig.sine_of_turns`, `@trig.sin`, and `@trig.cos`.
- Mini imports `trig` in addition to control, identity, pattern, score, and
  song, and still nothing from the DSP layers.
- `trig`'s functions are for the ranges its callers use: nonnegative angles
  up to one turn, or `turns` in `[0, 1]`. They are not general-purpose
  trigonometry.

## Consequences

- ADR-0001's guarantees hold. `dsp` has no dependency on any layer above
  it, and Mini has none on the DSP layers. `trig` is not a DSP layer: it
  has no buffers, processors, or audio state.
- `dsp` no longer exports `sine_of_turns` and `cosine_of_turns`. Mini was
  their only user, and it calls `trig` directly.
- The architecture boundary script lists `trig` as a leaf, and as the only
  moondsp import of `dsp` and an allowed import of Mini.
- A future allocation-free numeric helper that both sides need belongs in
  `trig` only if it is scalar trigonometry; anything else needs its own
  decision.
