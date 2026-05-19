# AudioBuffer Constructor Encapsulation

Date: 2026-05-19
Status: Approved
Tracker: backlog item "AudioBuffer::new(FixedArray) constructor leak" (`memory/project_backlog.md`)
Predecessor: PR #60 (closed the read-side leak by deleting `as_fixed_array`)

## Context

`AudioBuffer::AudioBuffer(FixedArray[Double])` — exposed canonically as `AudioBuffer::new` via `#alias(new)` — is a zero-copy constructor. It stores the caller's `FixedArray` by reference:

```moonbit
#alias(new)
pub fn AudioBuffer::AudioBuffer(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}
```

Callers can retain the original handle and mutate it after construction, bypassing `AudioBuffer::set` and any write-time validation built on top of it.

Write-time validation/instrumentation on `AudioBuffer::set` is **near-term planned** (NaN/Inf checks, denormal handling, write-rate counters — exact list TBD by that slice). The current zero-copy constructor would silently bypass all of it.

## Constraint

Downstream consumers (e.g., FFI bridges wrapping a `TypedArray`- or `SharedArrayBuffer`-backed `FixedArray`) have legitimate zero-copy needs. The fix cannot eliminate zero-copy entirely — it must make zero-copy opt-in by name.

## Design

Keep the existing public API surface — `AudioBuffer::AudioBuffer(FixedArray)` and `#alias(new)` — but swap the implementation from zero-copy to defensive copy. Add a new explicit zero-copy constructor named `AudioBuffer::adopt`.

```moonbit
/// Wrap a `FixedArray[Double]` by copying its contents.
///
/// The buffer is fully owned after construction; mutating the source
/// array has no effect on the buffer. Use this when ingesting external
/// data of unclear lifetime. For explicit zero-copy adoption, see
/// `AudioBuffer::adopt`.
#alias(new)
pub fn AudioBuffer::AudioBuffer(data : FixedArray[Double]) -> AudioBuffer {
  { data: data.copy() }
}

/// Wrap a `FixedArray[Double]` without copying.
///
/// The caller forfeits write access to the source array: any subsequent
/// mutation through the original handle bypasses `AudioBuffer::set` and
/// any associated validation/instrumentation. Use this only for
/// FFI-bridged buffers (e.g., `TypedArray` or `SharedArrayBuffer`
/// wrappers) where the copy cost is genuinely prohibitive and the
/// caller controls the source lifetime.
pub fn AudioBuffer::adopt(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}
```

`AudioBuffer::filled(size, init?)` is unchanged — it constructs the array inline and was never affected by the leak.

### Why this shape

- **Safe by default.** Callers of `AudioBuffer::new(data)` — including all current internal tests and any downstream code — automatically get encapsulation. Future write-time validation covers the canonical path uniformly.
- **Zero API churn.** The exposed signature for `AudioBuffer::AudioBuffer` and the `new` alias are unchanged in `dsp/pkg.generated.mbti`. No mooncake consumer recompile, no test migration, no deprecation period.
- **Explicit escape hatch.** `adopt` names the dangerous contract verbally. The asymmetry with the default constructor (no `from_`/`new` prefix) telegraphs that this is not a normal conversion — it's an ownership transfer.
- **Audit-friendly.** A grep for `AudioBuffer::adopt` enumerates every zero-copy adoption site for review. The default path needs no such audit.

### Behavioral change (silent for unchanged callers)

This is a behavioral change for any caller relying on post-construction aliasing — i.e., constructing an `AudioBuffer`, then mutating the source `FixedArray` and expecting the buffer to observe it.

In-repo audit (2026-05-19):

- **Production callers**: zero. All non-test construction in `graph/`, `voice/`, `browser/`, `scheduler/`, etc. goes through `AudioBuffer::filled(size)`.
- **Test callers**: ~45 sites, all passing transient `FixedArray::from_array([...])` literals or freshly-built helper-returned arrays. None retain the source.

Pre-1.0 leeway covers the silent change. The CHANGELOG must call it out explicitly so any downstream consumer relying on aliasing can migrate to `AudioBuffer::adopt`.

## Implementation

1. **Update `dsp/buffer.mbt`:**
   - Change body of `AudioBuffer::AudioBuffer` from `{ data, }` to `{ data: data.copy() }`.
   - Add `AudioBuffer::adopt(data : FixedArray[Double]) -> AudioBuffer` with the previous zero-copy body.
   - Add docstrings describing the contract on both.

2. **Add encapsulation tests in `dsp/mdsp_test.mbt` (or a new `dsp/buffer_test.mbt`):**
   - `AudioBuffer::new(arr)` does NOT alias `arr`: construct, mutate `arr[0]`, read the buffer at index 0, assert unchanged.
   - `AudioBuffer::adopt(arr)` DOES alias `arr`: construct, mutate `arr[0]`, read the buffer at index 0, assert reflected.

3. **Refresh `.mbti`:**
   - `moon info` should produce a one-line addition (`pub fn AudioBuffer::adopt(FixedArray[Double]) -> Self`) and no change to the existing constructor line.

4. **CHANGELOG (Unreleased):**
   - Under "Changed": "AudioBuffer::new / AudioBuffer::AudioBuffer now defensively copies its argument. Callers that relied on post-construction aliasing must migrate to the new AudioBuffer::adopt constructor."
   - Under "Added": "AudioBuffer::adopt for explicit zero-copy adoption."

5. **Backlog cleanup:**
   - Mark the "AudioBuffer::new constructor leak" item resolved in `memory/project_backlog.md`.
   - Update `docs/next-actions.md` to drop the slice from "Alternative Slices".

## Verification

- `moon check && moon test` — clean (839+ tests pass, including the two new encapsulation tests)
- `moon info && moon fmt` — clean
- `git diff dsp/pkg.generated.mbti` — exactly one line added for `adopt`; existing constructor line unchanged
- Spot-check no production regressions (already verified pre-design: production uses `filled` exclusively)

## Future considerations

When write-time validation/instrumentation lands on `AudioBuffer::set`:

- The default path (`AudioBuffer::new`) is fully covered — the buffer is genuinely owned, so every write goes through `set`.
- `AudioBuffer::adopt` buffers bypass validation by design — this is the documented contract. Callers needing validation on externally-sourced data should either use the default constructor (paying the copy cost) or instrument the source array themselves.

## Out of scope

- Adding `from_copy` / `from_owned` synonyms — the existing `new` name + the new `adopt` name are sufficient.
- Renaming or deprecating `#alias(new)` — kept exactly as-is.
- Write-time validation / instrumentation itself — separate slice, this design only restores the *option* of doing it correctly.
- Migrating any of the ~45 test call sites to a different constructor — they remain on `AudioBuffer::new` and benefit silently from the safer semantics.
