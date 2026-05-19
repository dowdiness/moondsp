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

Keep the existing public API surface — `AudioBuffer::AudioBuffer(FixedArray)` and `#alias(new)` — but swap the implementation from zero-copy to defensive copy. Add a new explicit zero-copy constructor named `AudioBuffer::adopt`. Re-point `AudioBuffer::filled` to delegate to `adopt` so it does not double-allocate.

```moonbit
/// Wrap a `FixedArray[Double]` by copying its contents.
///
/// The buffer's underlying storage is distinct from the source array;
/// neither side observes mutations made through the other. Mutating
/// the source has no effect on the buffer, and writes through the
/// buffer (via `set` / `fill`) do not propagate back to the source.
/// Use this when ingesting external data of unclear lifetime. For
/// explicit zero-copy adoption, see `AudioBuffer::adopt`.
#alias(new)
pub fn AudioBuffer::AudioBuffer(data : FixedArray[Double]) -> AudioBuffer {
  AudioBuffer::adopt(data.copy())
}

/// Construct an audio buffer pre-filled with `init` (default 0.0).
///
/// The buffer's storage is freshly allocated and not shared with any
/// caller-visible array. Routed through `adopt` to avoid an
/// unnecessary copy of the freshly-allocated `FixedArray`.
pub fn AudioBuffer::filled(size : Int, init? : Double = 0.0) -> AudioBuffer {
  AudioBuffer::adopt(FixedArray::make(size, init))
}

/// Wrap a `FixedArray[Double]` without copying.
///
/// The buffer and the source array share storage in both directions:
/// writes through the buffer (`set` / `fill`) mutate the source, and
/// mutations through the source handle appear through the buffer.
/// Two specific bypasses follow from this: (a) the buffer's initial
/// contents are whatever the source array holds at adoption time, not
/// run through any normalization that future `set`/`fill` may apply;
/// and (b) any later mutation through the retained source handle
/// skips `AudioBuffer::set` entirely. (Writes through `buf.set(...)`
/// or `buf.fill(...)` on an adopted buffer still go through those
/// methods and pick up whatever validation they perform.) Use this
/// only for FFI-bridged buffers (e.g., `TypedArray` or
/// `SharedArrayBuffer` wrappers) where the copy cost is genuinely
/// prohibitive and the caller can reason about the source lifetime.
/// Otherwise use `AudioBuffer::new`.
pub fn AudioBuffer::adopt(data : FixedArray[Double]) -> AudioBuffer {
  { data, }
}
```

Why route `filled` through `adopt`: `filled` constructs the `FixedArray` itself, so it is the unique owner — there is no external handle to alias. `adopt` is the correct zero-copy primitive here, not a leak. Without this routing, `new`'s defensive copy would force every `filled(size)` call to allocate twice (`FixedArray::make` then `data.copy()`), regressing the production hot path (`graph_compile.mbt`, `graph_hotswap.mbt`).

### Why this shape

- **Safe by default.** Callers of `AudioBuffer::new(data)` — the bulk of internal tests and any uninspected downstream code — automatically get the storage-isolation guarantee. The canonical-name path becomes the validation-friendly path.
- **No source migration for unaliased callers.** The exposed signature for `AudioBuffer::AudioBuffer` and the `new` alias are unchanged in `dsp/pkg.generated.mbti`. Callers that weren't exploiting the aliasing hit no compile error on upgrade — only the silent behavioral change. (Downstream consumers still recompile on a normal upgrade; the point is that no source edits are required.)
- **Explicit escape hatch with audit-friendly name.** `adopt` names the dangerous contract verbally. The asymmetry with the default constructor (no `from_`/`new` prefix) telegraphs that this is not a normal conversion. A grep for `AudioBuffer::adopt` enumerates every zero-copy adoption site for review; the default path needs no such audit.
- **No `filled` regression.** `filled` is re-pointed at `adopt` (legal because `filled` owns the freshly-made array). Production hot paths see no allocation overhead.

### What this design does NOT promise

Write-time validation will require more than swapping `new`'s body. The following paths bypass `AudioBuffer::set`:

- `AudioBuffer::new` (and `filled`) write initial samples into the underlying `FixedArray` directly via `data.copy()` / `FixedArray::make` — not through `set`.
- `AudioBuffer::fill(value)` writes via `self.data.fill(value)`, not via `set`.
- `AudioBuffer::adopt`-constructed buffers can be mutated externally through the retained source handle.

The future write-time-validation slice must factor sample normalization into a shared internal validation/normalization path that all of `new`'s ingest, `filled`'s ingest, `fill`, and `set` route through. The exact shape (e.g., a `validate_sample` helper, a buffer-level `validate_all` pass, or per-method inline checks) is for that slice to decide. This spec only restores the *option* of doing it correctly — it does not deliver validation itself, and the internal-helper refactor is in that slice's scope, not this one.

### Behavioral change

This is a behavioral change for any caller relying on post-construction aliasing in either direction — source-to-buffer (source writes appear in the buffer) or buffer-to-source (buffer writes via `set`/`fill` appear in the source).

In-repo audit (2026-05-19):

- **Production callers**: zero. All non-test construction in `graph/`, `voice/`, `browser/`, `scheduler/`, etc. goes through `AudioBuffer::filled(size)`, which never exposes the FixedArray to callers.
- **Test callers exploiting aliasing**: one — `dsp/mdsp_test.mbt:112` `test "audio buffer can wrap an existing fixed array without copying"` explicitly asserts the bidirectional aliasing contract. It must migrate to `AudioBuffer::adopt` (and the test name should drop "new" in favor of "adopt").
- **Other test callers**: ~45 sites passing transient `FixedArray::from_array([...])` literals or helper-returned arrays. None retain the source; all migrate silently and correctly under the new defensive-copy semantics.

Pre-1.0 leeway covers the change for downstream consumers, but it is **breaking enough that CHANGELOG-only is not sufficient**. The release notes must:

- Surface the change in a prominent "Breaking changes" section, not buried under "Changed".
- Spell out **both** aliasing directions explicitly.
- Provide a one-line migration: "If you relied on `AudioBuffer::new(arr)` sharing storage with `arr`, replace with `AudioBuffer::adopt(arr)`."
- Reference the docstrings on both constructors for the full contract.

## Implementation

1. **Update `dsp/buffer.mbt`:**
   - Add `AudioBuffer::adopt(data : FixedArray[Double]) -> AudioBuffer` with the previous zero-copy body `{ data, }`.
   - Change body of `AudioBuffer::AudioBuffer` to `AudioBuffer::adopt(data.copy())`.
   - Re-point `AudioBuffer::filled` body to `AudioBuffer::adopt(FixedArray::make(size, init))` (was `AudioBuffer::new(...)`).
   - Add docstrings describing the contract on `new`, `adopt`, and an aside-mention of the `filled` routing.

2. **Migrate the existing aliasing-dependent test (`dsp/mdsp_test.mbt:112`):**
   - Rename `test "audio buffer can wrap an existing fixed array without copying"` to `test "audio buffer adopt shares storage with source"` (or similar).
   - Change `AudioBuffer::new(samples)` → `AudioBuffer::adopt(samples)`.
   - Assertions are unchanged — they verify the bidirectional aliasing that `adopt` is now contractually obliged to provide.

3. **Add a new defensive-copy regression test (same file, adjacent):**
   - `test "audio buffer new does not share storage with source"`:
     - Construct `let buf = AudioBuffer::new(samples)`.
     - Mutate `samples[0] = X`; assert `buf.get(0)` unchanged.
     - Mutate `buf.set(1, Y)`; assert `samples[1]` unchanged.
   - This pins the new contract against silent regression.

4. **Refresh `.mbti`:**
   - `moon info` should produce a single addition: `pub fn AudioBuffer::adopt(FixedArray[Double]) -> Self`.
   - No change to the existing `AudioBuffer::AudioBuffer` or `#alias(new)` lines.

5. **CHANGELOG (Unreleased):**
   - **Add a "Breaking changes" subsection** under Unreleased if not present, separate from "Changed":
     > **`AudioBuffer::new` (and `AudioBuffer::AudioBuffer`) now defensively copies its argument.** Previously, the constructor stored the caller's `FixedArray` by reference, so the buffer and the source array shared storage in both directions: writes to the source appeared in the buffer, and writes through `AudioBuffer::set`/`fill` mutated the source. Both directions are now decoupled.
     >
     > **Migration**: callers that depended on the shared-storage behavior should replace `AudioBuffer::new(arr)` with `AudioBuffer::adopt(arr)`. See the constructor docstrings for the full contract.
   - Under "Added":
     > `AudioBuffer::adopt(FixedArray)` — explicit zero-copy adoption for FFI/SAB-style buffer bridging. The buffer and the source array share storage; this bypasses any future write-time validation by design.

6. **Backlog cleanup:**
   - Mark the "AudioBuffer::new constructor leak" item resolved in `memory/project_backlog.md`.
   - Update `docs/next-actions.md` to drop the slice from "Alternative Slices".

## Verification

- `moon check && moon test` — clean (~840 tests pass, including the renamed `adopt` test and the new `new`-encapsulation test).
- `moon info && moon fmt` — clean.
- `git diff dsp/pkg.generated.mbti` — exactly one line added for `adopt`; existing constructor and `#alias(new)` lines unchanged.
- Microbench (informal): a tight loop of `AudioBuffer::filled(128)` shows no allocation regression vs. pre-change. (If a benchmark exists in `graph/graph_benchmark.mbt` covering this, run it; otherwise spot-check is fine — the routing through `adopt` is by inspection a single allocation.)

## Future considerations

When the write-time-validation slice lands:

- It must introduce a shared internal validation/normalization path and route **all** ingest/write paths through it: `AudioBuffer::new`'s `data.copy()` ingest, `AudioBuffer::filled`'s `FixedArray::make` ingest, `AudioBuffer::fill`, and `AudioBuffer::set`. The specific shape (per-sample helper, buffer-level pass, inline checks) is for that slice; the constraint is uniform coverage. Without this refactor, the default constructor's defensive copy is not actually a validation surface — it just ingests bytes raw.
- `AudioBuffer::adopt` buffers bypass validation by design — this is the documented contract. Callers needing validation on externally-sourced data should either use the default constructor (paying the copy cost) or instrument the source array themselves before adoption.

Optional follow-up (not required for this slice): a debug-only shadow-buffer mode for `adopt` buffers — store a snapshot at adoption time and have `set`/`fill` update both, then assert at chosen boundaries that the live data still matches the shadow modulo recorded writes. Catches accidental external mutation during development. Cost: memory and time, so keep it opt-in or `#cfg(debug)`. Scope it only if the validation slice finds real bugs caused by silent `adopt` misuse.

## Out of scope

- Adding `from_copy` / `from_owned` synonyms — the existing `new` name + the new `adopt` name are sufficient.
- Renaming or deprecating `#alias(new)` — kept exactly as-is.
- Write-time validation / instrumentation itself — separate slice. This design only restores the *option* of doing it correctly; the shared-internal-helper refactor lives in that slice.
- The debug-shadow follow-up — proposed conditionally, not committed.
- Migrating any of the other ~45 test call sites — they remain on `AudioBuffer::new` and benefit silently from the safer semantics.
