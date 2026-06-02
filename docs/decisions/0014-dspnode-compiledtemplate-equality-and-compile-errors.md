# ADR-0014: Authoring equality and typed graph compile diagnostics

- **Status:** Accepted
- **Date:** 2026-06-02
- **Source:** GitHub issue #119
- **Related:** ADR-0010 (CompiledTemplate as the runtime exchange boundary), ADR-0011 (incr-backed mini authoring pipeline)

## Context

External and incr-backed authoring flows need to keep the last valid audio
runtime alive while the current source may be invalid. That requires two
separate contracts:

1. Equality for authoring graph artifacts must be predictable enough for
   reactive early-cutoff/backdating decisions.
2. Compile rejection must be explainable without replacing the current runtime
   template with an invalid one.

Plain floating-point equality is not enough for the first contract: a `NaN`
inside an invalid authoring graph would make an otherwise unchanged template
compare unequal forever, disabling reactive cutoff at exactly the time the
editor most needs stable invalid-state retention.

## Decision

`DspNode` equality is structural authoring equality, not DSP sample equality.
It compares kind, inputs, discrete parameters, waveform/filter tags, and numeric
parameters after lightweight authoring normalization:

- all `NaN` values compare equal to other `NaN` values;
- `+0.0` and `-0.0` compare equal;
- finite values and infinities otherwise use normal `Double` equality.

`CompiledTemplate` equality is structural artifact equality. It compares the
captured authoring template, optimized template, and authoring-to-optimized
index map using the same node equality policy. Two templates that optimize to
the same runtime graph but came from different authoring graphs are not equal,
because authoring indices and control bindings can differ.

Graph analysis remains infallible: `CompiledTemplate::analyze(...)` snapshots
and optimizes, but does not reject invalid numeric domains or topology shapes.
Compile is the validation boundary. The existing optional compile entry points
remain for compatibility, and result-typed compile entry points expose typed
`GraphCompileError` diagnostics for editor/external DSL callers.

Generic template liveness/introspection helpers stay internal for now. Public
compile diagnostics report graph-level causes and authoring indices where the
analyzed template can map them back; source ranges and stable graph node IDs are
owned by the external authoring layer.

## Consequences

**Positive**

- Invalid-but-unchanged templates containing `NaN` do not cause unbounded
  reactive churn.
- `+0.0` / `-0.0` spelling differences do not cause needless authoring churn.
- External authoring callers can keep a last-good runtime and show a typed
  compile rejection for the current invalid template.
- The `CompiledTemplate::analyze` boundary from ADR-0010 stays cheap and
  context-free.

**Negative**

- `DspNode` equality intentionally differs from IEEE `Double` equality for
  `NaN`.
- Equality is not a performance optimization by itself; wiring it into an
  early-cutoff pipeline still needs benchmark evidence.
- Compile diagnostics report graph-level reasons. Mapping them to editor source
  ranges remains the responsibility of the external authoring layer that owns
  source spans and stable graph node IDs.

## Follow-up

Only add incr early-cutoff/backdating stages after a benchmark reproduces a
meaningful authoring-side cost. Equality alone is a correctness contract for
future authoring pipelines, not proof of a bottleneck.
