# DSP Primitive Unit Tests — Design Spec

> **Date:** 2026-04-01
> **Scope:** Dedicated unit tests for 8 untested DSP primitives using snapshot + property-based testing.

---

## Goal

Add dedicated blackbox test files for the 8 DSP primitives that currently lack isolated unit tests: Oscillator, DelayLine, Adsr, Gain, Clip, Pan, Mix, Noise. Each primitive gets snapshot tests (`inspect`) for deterministic behavior and property-based tests (`@qc`) for invariants.

---

## Primitives and Test Strategy

### 1. Oscillator (`lib/osc_test.mbt`)

**Snapshot tests:**
- Sine wave at 440 Hz / 48kHz produces expected phase accumulation
- Each waveform (Sine, Saw, Square, Triangle) produces distinct output
- `tick_waveform` matches `process_waveform` output sample-by-sample
- `reset()` returns phase to 0

**Property tests (`@qc`):**
- All waveforms output ∈ [-1, 1] for any finite positive frequency and sample rate

**Edge cases:**
- Frequency = 0 (DC, no phase advance)
- Very high frequency (near Nyquist)

### 2. DelayLine (`lib/delay_test.mbt`)

**Snapshot tests:**
- Impulse delayed by exactly `delay_samples`
- Feedback coefficient accumulates energy across ticks
- `set_delay_samples` changes delay mid-stream
- `reset()` clears the buffer

**Property tests:**
- Zero feedback: `output[i] == input[i - delay_samples]` for impulse input

**Edge cases:**
- delay_samples = 0 (passthrough)
- delay_samples = max_delay_samples (full buffer)
- Feedback clamped to [-0.995, 0.995]

### 3. Adsr (`lib/env_test.mbt`)

**Snapshot tests:**
- Stage transitions: idle → attack → decay → sustain → release → idle
- `gate_on()` / `gate_off()` trigger transitions
- Attack ramps from 0 to 1, decay ramps from 1 to sustain level
- `reset()` returns to idle

**Property tests:**
- Output ∈ [0, 1] for any stage
- Level monotonically increases during attack, decreases during decay/release

**Edge cases:**
- Zero-length attack (instant ramp to 1)
- Zero-length decay (instant drop to sustain)
- Zero-length release (instant off)
- Sustain = 0 and sustain = 1

### 4. Gain (`lib/gain_test.mbt`)

**Snapshot tests:**
- Scalar multiplication: `output[i] == input[i] * gain_value`
- Zero gain produces silence
- Negative gain inverts signal

**Property tests:**
- `output[i] == input[i] * gain_value` for any finite input and gain

**Edge cases:**
- gain = 0 (silence)
- gain = 1 (passthrough)
- Empty buffer (length 0)

### 5. Clip (`lib/clip_test.mbt`)

**Snapshot tests:**
- Values within threshold pass through unchanged
- Values exceeding threshold are clamped to ±threshold
- Threshold = 1.0 (standard clipping)

**Property tests:**
- `|output[i]| <= threshold` for any input and positive threshold

**Edge cases:**
- threshold = 0 (everything clips to 0)
- All-zero input (unchanged)

### 6. Pan (`lib/pan_test.mbt`)

**Snapshot tests:**
- Center (0.0): equal power split
- Hard left (-1.0): signal only in left channel
- Hard right (+1.0): signal only in right channel

**Property tests:**
- Energy conservation: `left² + right² ≈ input²` within epsilon (equal-power law)

**Edge cases:**
- Zero input (both channels zero regardless of pan)
- Pan values at extremes (-1, 0, +1)

### 7. Mix (`lib/mix_test.mbt`)

**Snapshot tests:**
- Additive: `output[i] == a[i] + b[i]`
- Mixing with silence (zero buffer) is identity
- Mixing with itself doubles amplitude

**Property tests:**
- `output[i] == a[i] + b[i]` for any finite inputs

**Edge cases:**
- Empty buffers
- One buffer shorter than the other (mix up to shorter length)

### 8. Noise (`lib/noise_test.mbt`)

**Snapshot tests:**
- Same seed produces same sequence (deterministic)
- Different seeds produce different sequences
- `reset(seed)` reproduces the original sequence

**Property tests:**
- Output ∈ [-1, 1] for any seed

**Edge cases:**
- Seed = 0
- Seed = UInt max

---

## File Structure

All tests are blackbox (`*_test.mbt`), using the public API only.

```
lib/osc_test.mbt       — Oscillator tests
lib/delay_test.mbt      — DelayLine tests
lib/env_test.mbt        — Adsr tests
lib/gain_test.mbt       — Gain tests
lib/clip_test.mbt       — Clip tests
lib/pan_test.mbt        — Pan tests
lib/mix_test.mbt        — Mix tests
lib/noise_test.mbt      — Noise tests
```

Requires adding `@qc` (moonbitlang/core/quickcheck) to `lib/moon.pkg` imports.

---

## Testing Conventions

- Use `inspect` for snapshot verification of specific output values
- Use `@qc.declare` for property-based tests with the naming pattern `"prop: <invariant description>"`
- Use `assert_true` for boundary/edge-case assertions that aren't snapshot-friendly
- Test context: `DspContext::new(48000.0, 16)` for most tests (small block for readable snapshots)
- Panic tests (name starts with `"panic "`) where applicable for invalid inputs

---

## Success Criteria

1. All new tests pass under `moon test -p lib`
2. Existing 271 tests remain green
3. Every primitive has at least one `@qc` property test
4. Edge cases (zero, NaN, boundary values) are covered
5. No `.mbti` changes (tests are blackbox, no new public API)
