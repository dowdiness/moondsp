# AudioBuffer Write-Time Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MoonBit-owned `AudioBuffer` writes normalize non-finite samples to `0.0` through one shared internal path.

**Architecture:** Keep the public API signatures unchanged. Add a private finite-only sample normalizer in `dsp/buffer.mbt`, then route `AudioBuffer::new`, `AudioBuffer::filled`, `AudioBuffer::fill`, and `AudioBuffer::set` through it. Preserve `AudioBuffer::adopt` as the explicit zero-copy bypass for retained source-handle mutation.

**Tech Stack:** MoonBit 0.9.2, `moon` toolchain (`update`, `check`, `test`, `info`, `fmt`), existing `moonbitlang/core/double` test import. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-20-audiobuffer-write-time-validation-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `dsp/buffer.mbt` | Modify | Define private finite-only normalizer and route `new`, `filled`, `fill`, and `set` through it; refresh docstrings for current validation behavior |
| `dsp/mdsp_test.mbt` | Modify | Add storage-invariant regression tests near existing AudioBuffer tests |
| `dsp/util_test.mbt` | Modify | Inject raw non-finite samples through the `adopt` bypass instead of through `set` |
| `CHANGELOG.md` | Modify | Record the public behavior change under `## [Unreleased]` |
| `dsp/pkg.generated.mbti` | Regenerate/check | Expected no signature change after `moon info` |

No package split, new dependency, public enum, constructor parameter, or error type is introduced.

---

## Task 1: Preflight

**Files:**
- N/A

- [ ] **Step 1: Confirm branch and clean status**

Run: `git branch --show-current && git status --short`

Expected:

```text
design/audiobuffer-write-validation
```

No working-tree changes. If there are changes, inspect them and make sure they are from this plan before continuing.

- [ ] **Step 2: Refresh MoonBit dependencies**

Run: `moon update`

Expected: dependency resolution succeeds without changing the intended scope. If the command fails because a dependency cannot be fetched or resolved, stop and report the exact dependency/version error.

- [ ] **Step 3: Verify baseline build**

Run: `moon check`

Expected: check succeeds. Known upstream quickcheck deprecation warnings may appear in broader commands, but this implementation must not add new warnings.

---

## Task 2: Add AudioBuffer Storage-Invariant Tests

**Files:**
- Modify: `dsp/mdsp_test.mbt`

- [ ] **Step 1: Add failing AudioBuffer validation regression tests**

Insert the following blocks immediately after the existing test `"audio buffer new does not share storage with source array"`:

```moonbit
///|
test "audio buffer set normalizes non-finite samples" {
  let buffer = AudioBuffer::filled(4, init=0.25)

  buffer.set(0, @double.not_a_number)
  buffer.set(1, @double.infinity)
  buffer.set(2, @double.neg_infinity)
  buffer.set(3, 1.5)

  @debug.assert_eq(buffer.get(0), 0.0)
  @debug.assert_eq(buffer.get(1), 0.0)
  @debug.assert_eq(buffer.get(2), 0.0)
  @debug.assert_eq(buffer.get(3), 1.5)
}

///|
test "audio buffer fill normalizes non-finite value once" {
  let buffer = AudioBuffer::filled(4, init=0.25)

  buffer.fill(@double.infinity)

  @debug.assert_eq(buffer.get(0), 0.0)
  @debug.assert_eq(buffer.get(1), 0.0)
  @debug.assert_eq(buffer.get(2), 0.0)
  @debug.assert_eq(buffer.get(3), 0.0)
}

///|
test "audio buffer new normalizes copied source samples" {
  let samples = FixedArray::make(4, 0.0)
  samples[0] = @double.not_a_number
  samples[1] = @double.infinity
  samples[2] = @double.neg_infinity
  samples[3] = 1.5

  let buffer = AudioBuffer::new(samples)

  @debug.assert_eq(buffer.get(0), 0.0)
  @debug.assert_eq(buffer.get(1), 0.0)
  @debug.assert_eq(buffer.get(2), 0.0)
  @debug.assert_eq(buffer.get(3), 1.5)

  samples[3] = 0.25
  @debug.assert_eq(buffer.get(3), 1.5)
  buffer.set(3, 2.0)
  @debug.assert_eq(samples[3], 0.25)
}

///|
test "audio buffer filled normalizes non-finite initializer" {
  let buffer = AudioBuffer::filled(3, init=@double.neg_infinity)

  @debug.assert_eq(buffer.get(0), 0.0)
  @debug.assert_eq(buffer.get(1), 0.0)
  @debug.assert_eq(buffer.get(2), 0.0)
}

///|
test "audio buffer adopt source handle remains validation bypass" {
  let samples = FixedArray::make(3, 0.0)
  let buffer = AudioBuffer::adopt(samples)

  samples[0] = @double.not_a_number
  samples[1] = @double.infinity
  samples[2] = -1.5

  assert_true(buffer.get(0).is_nan())
  assert_true(buffer.get(1).is_inf())
  @debug.assert_eq(buffer.get(2), -1.5)
}

///|
test "audio buffer adopted writes through methods still normalize" {
  let samples = FixedArray::make(2, 0.25)
  let buffer = AudioBuffer::adopt(samples)

  buffer.set(0, @double.not_a_number)
  @debug.assert_eq(buffer.get(0), 0.0)
  @debug.assert_eq(samples[0], 0.0)

  buffer.fill(@double.infinity)
  @debug.assert_eq(buffer.get(0), 0.0)
  @debug.assert_eq(buffer.get(1), 0.0)
  @debug.assert_eq(samples[0], 0.0)
  @debug.assert_eq(samples[1], 0.0)
}
```

- [ ] **Step 2: Run tests and verify the expected failures**

Run: `moon test dsp --filter '*audio buffer*'`

Expected: the new tests fail because `set`, `fill`, `new`, and `filled` still store non-finite values without normalization. The existing `adopt` bypass test should pass.

---

## Task 3: Implement The Shared Internal Normalization Path

**Files:**
- Modify: `dsp/buffer.mbt`

- [ ] **Step 1: Add private helpers after the `AudioBuffer` struct**

In `dsp/buffer.mbt`, immediately after the `AudioBuffer` struct block, add:

```moonbit
///|
fn normalize_audio_sample(value : Double) -> Double {
  if is_finite(value) {
    value
  } else {
    0.0
  }
}

///|
fn normalize_audio_samples(data : FixedArray[Double]) -> Unit {
  for index in 0..<data.length() {
    data[index] = normalize_audio_sample(data[index])
  }
}
```

- [ ] **Step 2: Route `AudioBuffer::new` through the helper**

Replace the constructor body with:

```moonbit
pub fn AudioBuffer::AudioBuffer(data : FixedArray[Double]) -> AudioBuffer {
  let copy = data.copy()
  normalize_audio_samples(copy)
  AudioBuffer::adopt(copy)
}
```

Update the constructor docstring to add this sentence after the storage-isolation paragraph:

```text
Non-finite source samples (`NaN`, `+Inf`, `-Inf`) are normalized to `0.0`
in the copied storage; finite samples pass through unchanged.
```

- [ ] **Step 3: Refresh the `adopt` docstring**

In the `AudioBuffer::adopt` docstring, replace the future-validation language with current behavior:

```text
Two specific bypasses follow from this: (a) the buffer's initial
contents are whatever the source array holds at adoption time, not
run through the normal non-finite-to-0.0 normalization path; and
(b) any later mutation through the retained source handle skips
AudioBuffer validation entirely. Writes through `buf.set(...)` or
`buf.fill(...)` on an adopted buffer still go through those methods
and normalize non-finite values to `0.0`.
```

- [ ] **Step 4: Route `AudioBuffer::filled` through the helper**

Replace the `filled` body with:

```moonbit
pub fn AudioBuffer::filled(size : Int, init? : Double = 0.0) -> AudioBuffer {
  AudioBuffer::adopt(FixedArray::make(size, normalize_audio_sample(init)))
}
```

Update the `filled` docstring to say:

```text
The initializer is normalized once before allocation: non-finite values
become `0.0`, while finite values pass through unchanged.
```

- [ ] **Step 5: Route `AudioBuffer::fill` and `AudioBuffer::set` through the helper**

Replace `fill` with:

```moonbit
///|
/// Fill the buffer with a single sample value.
///
/// Non-finite values (`NaN`, `+Inf`, `-Inf`) are normalized to `0.0`.
pub fn AudioBuffer::fill(self : AudioBuffer, value : Double) -> Unit {
  self.data.fill(normalize_audio_sample(value))
}
```

Replace `set` with:

```moonbit
///|
/// Write one sample into the buffer.
///
/// Non-finite values (`NaN`, `+Inf`, `-Inf`) are normalized to `0.0`.
pub fn AudioBuffer::set(
  self : AudioBuffer,
  index : Int,
  value : Double,
) -> Unit {
  self.data[index] = normalize_audio_sample(value)
}
```

- [ ] **Step 6: Verify targeted AudioBuffer tests now pass**

Run: `moon test dsp --filter '*audio buffer*'`

Expected: all AudioBuffer tests pass.

- [ ] **Step 7: Run package check**

Run: `moon check`

Expected: check succeeds.

---

## Task 4: Update `sanitize_buffer` Tests To Use The Explicit Bypass

**Files:**
- Modify: `dsp/util_test.mbt`

- [ ] **Step 1: Change raw non-finite injection in the NaN test**

In test `"sanitize_buffer: NaN replaced with 0.0"`, replace the setup with:

```moonbit
  let samples = FixedArray::make(4, 0.0)
  let buf = AudioBuffer::adopt(samples)
  samples[0] = 0.5
  samples[1] = @double.not_a_number
  samples[2] = @double.not_a_number
  samples[3] = 0.5
```

Leave the `sanitize_buffer` call and assertions unchanged.

- [ ] **Step 2: Change raw non-finite injection in the infinity test**

In test `"sanitize_buffer: +Inf and -Inf replaced"`, replace the setup with:

```moonbit
  let samples = FixedArray::make(4, 0.0)
  let buf = AudioBuffer::adopt(samples)
  samples[0] = @double.infinity
  samples[1] = @double.neg_infinity
  samples[2] = 0.5
  samples[3] = @double.not_a_number
```

Leave the `sanitize_buffer` call and assertions unchanged.

- [ ] **Step 3: Change raw non-finite injection in the sample-count clamp test**

In test `"sanitize_buffer: sample_count clamped to buffer length"`, replace the setup with:

```moonbit
  let samples = FixedArray::make(2, 0.0)
  let buf = AudioBuffer::adopt(samples)
  samples[0] = @double.not_a_number
  samples[1] = 0.5
```

Leave the `sanitize_buffer` call and assertions unchanged.

- [ ] **Step 4: Change raw non-finite injection in the zero-count test**

In test `"sanitize_buffer: zero sample_count returns 0"`, replace the setup with:

```moonbit
  let samples = FixedArray::make(4, 0.0)
  let buf = AudioBuffer::adopt(samples)
  samples[0] = @double.not_a_number
```

Leave the `sanitize_buffer` call and assertions unchanged.

- [ ] **Step 5: Change raw non-finite injection in the idempotence test**

In test `"sanitize_buffer: idempotent — sanitized buffer returns 0"`, replace the setup with:

```moonbit
  let samples = FixedArray::make(4, 0.0)
  let buf = AudioBuffer::adopt(samples)
  samples[0] = @double.not_a_number
  samples[1] = @double.infinity
```

Leave the `sanitize_buffer` calls and assertions unchanged.

- [ ] **Step 6: Run targeted util tests**

Run: `moon test dsp --filter '*sanitize_buffer*'`

Expected: all `sanitize_buffer` tests pass.

---

## Task 5: Record Public Behavior Change

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a second AudioBuffer breaking-change bullet**

Under `## [Unreleased]` → `### Breaking changes`, after the existing `AudioBuffer::new` defensive-copy bullet, add:

```markdown
- **`AudioBuffer` now normalizes non-finite samples on MoonBit-owned
  writes.** Values written through `AudioBuffer::new`, `AudioBuffer::filled`,
  `AudioBuffer::fill`, and `AudioBuffer::set` convert `NaN`, `+Inf`, and
  `-Inf` to `0.0`; finite values, including values outside `[-1, 1]`, pass
  through unchanged. `AudioBuffer::adopt` remains the explicit zero-copy
  bypass for retained source-handle mutation, though writes through
  `buf.set(...)` and `buf.fill(...)` on an adopted buffer still normalize.
```

- [ ] **Step 2: Run prose sanity check**

Run: `grep -n "AudioBuffer.*normalizes\\|non-finite samples" CHANGELOG.md`

Expected: the new changelog entry appears under `## [Unreleased]`.

---

## Task 6: Regenerate Interface And Run Verification

**Files:**
- Check/regenerate: `dsp/pkg.generated.mbti`

- [ ] **Step 1: Run package tests**

Run: `moon test dsp`

Expected: all `dsp` tests pass.

- [ ] **Step 2: Run full test suite**

Run: `moon test`

Expected: all tests pass.

- [ ] **Step 3: Regenerate interface files**

Run: `moon info`

Expected: `dsp/pkg.generated.mbti` has no signature change for `AudioBuffer`; implementation-only behavior changes do not alter `.mbti`.

- [ ] **Step 4: Format**

Run: `moon fmt`

Expected: formatting completes.

- [ ] **Step 5: Run CI-style check**

Run: `moon check --deny-warn`

Expected: no warnings or errors introduced by this slice.

- [ ] **Step 6: Review final diff**

Run: `git diff --stat && git diff -- dsp/buffer.mbt dsp/mdsp_test.mbt dsp/util_test.mbt CHANGELOG.md dsp/pkg.generated.mbti`

Expected:

- `dsp/buffer.mbt` contains the private normalizer and routed writes.
- `dsp/mdsp_test.mbt` contains the storage-invariant regressions.
- `dsp/util_test.mbt` uses `adopt` source-handle mutation for raw non-finite samples.
- `CHANGELOG.md` contains the public behavior note.
- `dsp/pkg.generated.mbti` is unchanged or only mechanically refreshed with no AudioBuffer signature change.

- [ ] **Step 7: Commit implementation**

```bash
git add dsp/buffer.mbt dsp/mdsp_test.mbt dsp/util_test.mbt CHANGELOG.md dsp/pkg.generated.mbti
git commit -m "refactor(dsp)!: normalize AudioBuffer non-finite writes"
```

---

## Self-Review Checklist

- The plan implements every spec entrypoint: `new`, `filled`, `fill`, and `set`.
- `adopt` remains a bypass only for construction-time contents and retained source-handle mutation.
- Finite values outside `[-1, 1]` are explicitly tested as pass-through.
- `sanitize_buffer` tests still verify the output firewall by injecting raw non-finite storage through `adopt`.
- No public API signature change is planned.
- No clipping, counters, configurable policy, debug shadow buffer, or graph runtime-control behavior is included.
