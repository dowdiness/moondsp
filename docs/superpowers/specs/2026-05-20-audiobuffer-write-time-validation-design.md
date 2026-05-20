# AudioBuffer Write-Time Validation

**Date:** 2026-05-20
**Status:** Draft design
**Tracker:** follow-on slice from `docs/superpowers/specs/2026-05-19-audiobuffer-constructor-design.md`

## Context

PR #62 closed the write-side aliasing leak by making `AudioBuffer::new`
defensively copy its source array and adding `AudioBuffer::adopt` as the
explicit zero-copy constructor. That restored `AudioBuffer::new` as a safe
ingest boundary, but it deliberately did not add validation.

The remaining gap is broader than `AudioBuffer::set`. The current storage
entrypoints are:

- `AudioBuffer::new`, which copies caller data into owned storage.
- `AudioBuffer::filled`, which creates owned storage with `FixedArray::make`.
- `AudioBuffer::fill`, which writes through `FixedArray::fill`.
- `AudioBuffer::set`, which writes one sample directly.
- `AudioBuffer::adopt`, which wraps caller-owned storage and documents that
  retained source-handle mutations bypass MoonBit validation.

Existing runtime code writes through `set` and `fill` from DSP primitives,
graph block helpers, feedback processing, hot-swap crossfade, browser scheduler
accumulation, scheduler clearing, and voice mixdown. The design must therefore
centralize value normalization in `AudioBuffer` itself rather than adding
ad hoc checks at call sites.

## Decision

Adopt a storage invariant for MoonBit-owned writes:

**Any value written into an `AudioBuffer` through MoonBit-owned `AudioBuffer`
APIs is finite after the write completes.**

The normalization policy is intentionally narrow:

- `NaN` becomes `0.0`.
- `+Inf` becomes `0.0`.
- `-Inf` becomes `0.0`.
- All finite values pass through unchanged, including values outside `[-1, 1]`.

This aligns with the existing output-firewall policy in `sanitize_buffer`
without turning `AudioBuffer` into an implicit clipper. Hard clipping remains
the responsibility of the explicit `Clip` primitive and graph clip nodes. `Mix`
continues to be non-clipping.

## Design Shape

Introduce one private sample-level normalization helper inside the `dsp`
package, near `AudioBuffer`, and route all MoonBit-owned storage writes through
it.

The helper owns only the finite-sample rule. It does not allocate, count,
raise, or inspect buffer context. Keeping it sample-level lets `set` normalize
one value cheaply, while constructor and bulk-fill paths can reuse the same
policy without duplicating branches or creating a second semantic source of
truth.

`AudioBuffer::set` applies the helper before storing a sample. `AudioBuffer::fill`
applies the helper once to the fill value, then delegates to the underlying
bulk fill with the normalized value. `AudioBuffer::new` copies the source array
to preserve the PR #62 storage-isolation contract, then normalizes the owned
copy before returning. `AudioBuffer::filled` normalizes the initializer before
creating the array, so the one-allocation hot path remains intact.

This is a behavior change, but not a signature change. No new constructor
parameters, public policy enum, public error type, or fallible constructor is
introduced in this slice.

## `adopt` Boundary

`AudioBuffer::adopt` remains the explicit zero-copy bypass. The constructor may
wrap whatever values are present in the source array at adoption time, and
later mutations through the retained source handle remain outside MoonBit's
validation model.

Writes performed through `buf.set(...)` and `buf.fill(...)` on an adopted
buffer still use the normal write-time validation path. Only direct mutation
through the retained source handle bypasses it.

Do not add a `validate_after_adopt` parameter in this slice. It would imply a
partial safety guarantee that cannot cover post-adoption source-handle writes,
and it would complicate the audit-friendly zero-copy contract introduced by
PR #62. Callers that need validated initial contents should use
`AudioBuffer::new` and pay the copy cost, or validate the source before
calling `adopt`.

## Output Firewall And Telemetry

`sanitize_buffer` remains public and remains the output-boundary firewall. Its
policy stays the same: replace non-finite samples with `0.0` and return the
number replaced.

Write-time normalization changes what the firewall can observe. Non-finite
values written through ordinary `AudioBuffer::set`, `fill`, `new`, or `filled`
will be normalized before they reach graph or voice output sanitization, so
`last_sanitized_count` should be understood as last-resort firewall telemetry,
not as a complete count of every attempted non-finite write.

The firewall still has value:

- It catches non-finite values introduced through `adopt` source-handle
  mutation.
- It protects against any future raw/FFI storage path that bypasses
  `AudioBuffer`.
- It preserves a public utility for callers that intentionally audit a buffer
  after unsafe ingestion.

Tests for `sanitize_buffer` that need raw non-finite samples must inject them
through a documented bypass such as `AudioBuffer::adopt` with retained source
mutation, not through `AudioBuffer::set`.

## Cost Model

The normalizer is allocation-free and fixed-work per written sample.

`set` pays one finite check per sample. Most audio-rate writes already flow
through `set`, so this adds a branch to hot loops. That branch is the cost of
making the storage invariant real. The branch should be predictable for clean
audio data.

`fill` normalizes once per call, not once per element. This preserves the fast
path used heavily for silence clearing.

`filled` normalizes the initializer once and preserves the single allocation
from PR #62.

`new` copies first for storage isolation and then normalizes the owned copy.
That pass happens at ingest time. Callers choosing `new` have already selected
the safe-copy path; callers that cannot afford the copy/pass use `adopt` and
accept its bypass contract.

No allocating validation pass should be introduced on the audio thread. If a
future design needs counters or diagnostics for attempted invalid writes, that
is a separate debug/instrumentation feature.

## Public API Impact

No `.mbti` signature change is intended.

The behavior change is public because `AudioBuffer` is re-exported from the
root facade. Release notes must call out that non-finite samples written through
MoonBit-owned `AudioBuffer` APIs are normalized to silence, and that
`AudioBuffer::adopt` remains the documented bypass.

## Tests

Add focused regression tests near the existing `AudioBuffer` tests in
`dsp/mdsp_test.mbt`:

- `AudioBuffer::set` normalizes `NaN`, `+Inf`, and `-Inf` to `0.0`.
- `AudioBuffer::fill` normalizes a non-finite fill value to `0.0` across the
  buffer.
- `AudioBuffer::new` normalizes non-finite source samples while preserving the
  defensive-copy contract.
- `AudioBuffer::filled` normalizes a non-finite initializer.
- Finite values outside `[-1, 1]` pass through unchanged, proving this is not
  implicit clipping.
- `AudioBuffer::adopt` plus retained source-handle mutation can still expose
  non-finite values, documenting the explicit bypass.
- Writes through `set` or `fill` on an adopted buffer still normalize.

Adjust `dsp/util_test.mbt` so `sanitize_buffer` tests that require raw
non-finite storage use the adopt bypass rather than `set`. Keep the
`sanitize_buffer` behavioral assertions intact: clean buffers return zero,
non-finite raw samples are replaced with `0.0`, sample counts are bounded, and
idempotence still holds.

Graph and voice output-sanitization tests should continue to assert that clean
graphs report zero sanitized samples. Tests that expect graph or voice
`last_sanitized_count` to observe non-finite writes through normal
`AudioBuffer` APIs would be asserting the old model and should be rewritten to
inject through an explicit bypass if such coverage is needed.

## Alternatives Considered

### Keep Validation Only At Output Boundaries

This preserves existing `last_sanitized_count` semantics, but it leaves
`AudioBuffer` storage free to hold non-finite samples during intermediate DSP
and graph processing. That misses the point of the PR #62 follow-on: `new`,
`filled`, `fill`, and `set` need a shared validation path, not just a final
cleanup step.

### Clip To `[-1, 1]`

This would create a stronger amplitude invariant, but it conflicts with
existing design. `Mix` intentionally does not clip, finite values above unity
appear in tests and integration helpers, and `Clip` is the explicit range
limiting primitive. `AudioBuffer` should not silently turn every write into a
clip stage.

### Add Configurable Validation Policy

A public policy enum or constructor parameter would make the API more flexible,
but the current project has one clear policy need: finite storage. Configurable
behavior would expand the public surface before there is evidence that callers
need it.

### Validate `adopt` At Construction Time

A construction-time pass would catch initial non-finite values, but it would
not catch post-adoption mutation through the retained source handle. That makes
the safety story easy to misunderstand while adding another branch to the
zero-copy API. Keep `adopt` simple and explicit.

## Out Of Scope

- Changing the PR #62 constructor decision. `AudioBuffer::new` remains
  defensive-copy.
- Adding public validation policy types or constructor parameters.
- Clipping, soft-knee compression, normalization to peak amplitude, or any
  dynamic gain behavior.
- Counting attempted invalid writes.
- Debug shadow buffers for `adopt`.
- Any graph runtime-control behavior change.

## Verification For The Implementation Slice

The later implementation plan should require:

- `moon check`
- targeted `moon test dsp`
- full `moon test`
- `moon info` with no intended `.mbti` signature change
- `moon fmt`

If implementation touches root facade docs or release notes, run the usual
prose review against the spec before opening a PR.
