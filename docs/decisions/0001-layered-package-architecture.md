# ADR-0001: Layered package architecture

- **Status:** Accepted
- **Date:** 2026-04-22 (decision shipped 2026-04-15; lib facade collapse shipped later)
- **Source:** [`docs/superpowers/plans/archive/2026-04-15-graph-voice-extraction.md`](../superpowers/plans/archive/2026-04-15-graph-voice-extraction.md)

## Context

By 2026-04-14 the `lib/` package held everything: the compiled-graph runtime,
voice pool, control bindings, all the graph optimizers, plus a `using @dsp`
re-export of the DSP primitives that lived in their own `dsp/` package.
`lib/` had grown to ~30 source files and ~20 test files — a monolith with
internal layering that was not enforced by the type system.

The audit on 2026-04-02 (`docs/archive/audit-2026-04-02.md`) flagged this
shape as a structural risk: every change touched the same package, no
package-boundary check existed to catch a runtime concern leaking into the
graph compiler or vice versa, and the test suite ran at the granularity of
the whole monolith.

## Decision

Split into a strict, acyclic layered package layout:

```
dsp/        — primitives, tagless algebra, pan math (zero internal deps)
  ↑
graph/      — compile, optimize, runtime control, hot-swap, control binding
  ↑       ↑
voice/    │ — polyphonic voice pool with priority stealing
  ↑       │
pattern/  │ — rational-time pattern engine (zero DSP deps)
  ↑       │
scheduler/└ — bridges pattern engine to voice pool
  ↑
mini/       — text → Pat[ControlMap] parser
  ↑
browser/    — AudioWorklet export wrapper
```

Re-exports from sub-packages are surfaced through a single root facade
`dowdiness/moondsp` using MoonBit's `pub using @pkg { type T, ... }` syntax.
External consumers and internal sub-packages alike write `@moondsp.X`.

A transitional `lib/` facade (2026-04-15 to early 2026-04 PR cycle) was
collapsed into the root package once consumers had migrated.

## Consequences

**Positive**

- Dependency direction is enforced by the compiler — `dsp/` cannot accidentally
  call into `graph/`; `graph/` cannot reach `voice/`.
- Each layer has its own test suite that runs in isolation.
- `mini/` and `pattern/` have zero dependency on the DSP layers, so they can
  be reused by future non-audio consumers (e.g. a structural editor).
- Single facade path (`@moondsp.X`) means consumers see one stable import.

**Negative**

- Source files inside `graph/` need explicit `@dsp.is_finite(...)` / etc. for
  free functions from `dsp/`, because MoonBit's `using` syntax imports types
  but not free functions. Adds visual noise compared to the pre-split state.
- Re-exporting bare enum constructors via `pub using` does not work — consumers
  who pattern-match on `@dsp` enum constructors must use the source package
  prefix or `using @pkg { type T }` plus `T::Constructor(args)`.
- Adding a new sub-package requires updates to both `moon.pkg.json` and the
  root facade's `pub using` block.

**Neutral**

- Test count stayed unchanged across the split — the boundary changes were
  purely structural.
