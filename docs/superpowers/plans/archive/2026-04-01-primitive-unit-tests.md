# DSP Primitive Unit Tests — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dedicated unit tests for 8 untested DSP primitives with snapshot verification and property-based testing.

**Architecture:** One blackbox test file per primitive. Snapshot tests via `inspect`, property tests via `@qc.quick_check_fn!` from `moonbitlang/quickcheck`. Each task is independent — any can be implemented in any order.

**Tech Stack:** MoonBit, `moonbitlang/quickcheck` (external), `moonbitlang/core/quickcheck` (core Arbitrary)

**Spec:** `docs/superpowers/specs/2026-04-01-primitive-unit-tests-design.md`

---

### Task 0: Add quickcheck import to lib/moon.pkg

**Files:**
- Modify: `lib/moon.pkg`

The `moonbitlang/quickcheck` dependency was added to `moon.mod.json` but `lib/moon.pkg` doesn't import it yet.

- [ ] **Step 1: Add the import**

Add `"moonbitlang/quickcheck" @qc` to `lib/moon.pkg`:

```
import {
  "moonbitlang/core/bench" @bench,
  "moonbitlang/core/math" @math,
  "moonbitlang/core/ref" @ref,
  "moonbitlang/quickcheck" @qc,
}
```

- [ ] **Step 2: Verify**

Run: `moon check`
Expected: No errors (warnings about unused import are OK).

- [ ] **Step 3: Commit**

```bash
git add lib/moon.pkg moon.mod.json
git commit -m "chore: add moonbitlang/quickcheck dependency and import"
```

---

### Task 1: Oscillator tests (`lib/osc_test.mbt`)

**Files:**
- Create: `lib/osc_test.mbt`

- [ ] **Step 1: Write snapshot and property tests**

Create `lib/osc_test.mbt`:

```moonbit
///|
test "sine oscillator accumulates phase correctly" {
  let osc = Oscillator::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4)
  osc.process_waveform(ctx, buf, Waveform::Sine, 12000.0)
  // At 12 kHz / 48 kHz, phase advances 0.25 per sample (quarter cycle)
  // Sine at phase 0.25 = sin(2π * 0.25) = sin(π/2) = 1.0
  inspect!(buf.get(0) > 0.99 && buf.get(0) <= 1.0, content="true")
}

///|
test "saw oscillator produces distinct output from sine" {
  let osc_sine = Oscillator::new()
  let osc_saw = Oscillator::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf_sine = AudioBuffer::filled(4)
  let buf_saw = AudioBuffer::filled(4)
  osc_sine.process_waveform(ctx, buf_sine, Waveform::Sine, 440.0)
  osc_saw.process_waveform(ctx, buf_saw, Waveform::Saw, 440.0)
  assert_true(buf_sine.get(0) != buf_saw.get(0))
}

///|
test "oscillator tick matches process output" {
  let osc1 = Oscillator::new()
  let osc2 = Oscillator::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4)
  osc1.process_waveform(ctx, buf, Waveform::Sine, 440.0)
  for i = 0; i < 4; i = i + 1 {
    let sample = osc2.tick_waveform(Waveform::Sine, 440.0, 48000.0)
    assert_true((buf.get(i) - sample).abs() < 0.000001)
  }
}

///|
test "oscillator reset returns phase to zero" {
  let osc = Oscillator::new()
  ignore(osc.tick(440.0, 48000.0))
  ignore(osc.tick(440.0, 48000.0))
  assert_true(osc.phase() > 0.0)
  osc.reset()
  assert_true(osc.phase() == 0.0)
}

///|
test "oscillator with zero frequency produces zero (sine)" {
  let osc = Oscillator::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4)
  osc.process_waveform(ctx, buf, Waveform::Sine, 0.0)
  // sin(0) = 0 for all samples (no phase advance)
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "prop: all waveforms output in [-1, 1]" {
  @qc.quick_check_fn!(
    fn(raw_freq : Double) {
      // Map [0,1) to a useful frequency range [1, 20000]
      let freq = raw_freq.abs() * 19999.0 + 1.0
      let osc = Oscillator::new()
      let ctx = DspContext::new(48000.0, 128)
      let waveforms : FixedArray[Waveform] = [
        Waveform::Sine,
        Waveform::Saw,
        Waveform::Square,
        Waveform::Triangle,
      ]
      for w = 0; w < waveforms.length(); w = w + 1 {
        osc.reset()
        let buf = AudioBuffer::filled(128)
        osc.process_waveform(ctx, buf, waveforms[w], freq)
        for i = 0; i < 128; i = i + 1 {
          if buf.get(i) < -1.0 || buf.get(i) > 1.0 {
            return false
          }
        }
      }
      true
    },
    max_success=100,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f osc_test.mbt`
Expected: All tests pass. If `inspect!` snapshots need updating, run `moon test --update`.

- [ ] **Step 3: Commit**

```bash
git add lib/osc_test.mbt
git commit -m "test: add oscillator unit tests with property-based output bounds"
```

---

### Task 2: Noise tests (`lib/noise_test.mbt`)

**Files:**
- Create: `lib/noise_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/noise_test.mbt`:

```moonbit
///|
test "noise is deterministic given same seed" {
  let noise1 = Noise::new(42U)
  let noise2 = Noise::new(42U)
  let ctx = DspContext::new(48000.0, 8)
  let buf1 = AudioBuffer::filled(8)
  let buf2 = AudioBuffer::filled(8)
  noise1.process(ctx, buf1)
  noise2.process(ctx, buf2)
  for i = 0; i < 8; i = i + 1 {
    assert_true(buf1.get(i) == buf2.get(i))
  }
}

///|
test "different seeds produce different sequences" {
  let noise1 = Noise::new(1U)
  let noise2 = Noise::new(2U)
  let mut differs = false
  for i = 0; i < 16; i = i + 1 {
    if noise1.tick() != noise2.tick() {
      differs = true
      break
    }
  }
  assert_true(differs)
}

///|
test "noise reset reproduces original sequence" {
  let noise = Noise::new(42U)
  let first = noise.tick()
  let second = noise.tick()
  noise.reset(42U)
  assert_true(noise.tick() == first)
  assert_true(noise.tick() == second)
}

///|
test "prop: noise output in [-1, 1]" {
  @qc.quick_check_fn!(
    fn(raw_seed : UInt) {
      let seed = if raw_seed == 0U { 1U } else { raw_seed }
      let noise = Noise::new(seed)
      for i = 0; i < 256; i = i + 1 {
        let sample = noise.tick()
        if sample < -1.0 || sample > 1.0 {
          return false
        }
      }
      true
    },
    max_success=100,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f noise_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/noise_test.mbt
git commit -m "test: add noise unit tests with determinism and output bounds"
```

---

### Task 3: Gain tests (`lib/gain_test.mbt`)

**Files:**
- Create: `lib/gain_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/gain_test.mbt`:

```moonbit
///|
test "gain scales samples by gain value" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.5)
  gain.process(ctx, buf, 0.8)
  for i = 0; i < 4; i = i + 1 {
    assert_true((buf.get(i) - 0.4).abs() < 0.000001)
  }
}

///|
test "zero gain produces silence" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=1.0)
  gain.process(ctx, buf, 0.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "unity gain is passthrough" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.7)
  gain.process(ctx, buf, 1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true((buf.get(i) - 0.7).abs() < 0.000001)
  }
}

///|
test "negative gain inverts signal" {
  let gain = Gain::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.5)
  gain.process(ctx, buf, -1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true((buf.get(i) - -0.5).abs() < 0.000001)
  }
}

///|
test "prop: gain is exact multiplication" {
  @qc.quick_check_fn!(
    fn(pair : (Double, Double)) {
      let (input, gain_val) = pair
      // Skip non-finite values
      if input.is_nan() || input.is_inf() || gain_val.is_nan() || gain_val.is_inf() {
        return true
      }
      let gain = Gain::new()
      let ctx = DspContext::new(48000.0, 1)
      let buf = AudioBuffer::filled(1, init=input)
      gain.process(ctx, buf, gain_val)
      let expected = input * gain_val
      if expected.is_nan() || expected.is_inf() {
        return true
      }
      (buf.get(0) - expected).abs() < 0.000001
    },
    max_success=200,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f gain_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/gain_test.mbt
git commit -m "test: add gain unit tests with property-based exact multiplication"
```

---

### Task 4: Clip tests (`lib/clip_test.mbt`)

**Files:**
- Create: `lib/clip_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/clip_test.mbt`:

```moonbit
///|
test "clip clamps values exceeding threshold" {
  let clip = Clip::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::new(FixedArray::from_array([2.0, -2.0, 0.5, -0.3]))
  clip.process(ctx, buf, 0.5)
  assert_true(buf.get(0) == 0.5)
  assert_true(buf.get(1) == -0.5)
  assert_true(buf.get(2) == 0.5)
  assert_true(buf.get(3) == -0.3)
}

///|
test "clip with threshold 1.0 clamps to standard range" {
  let clip = Clip::new()
  let ctx = DspContext::new(48000.0, 2)
  let buf = AudioBuffer::new(FixedArray::from_array([1.5, -1.5]))
  clip.process(ctx, buf, 1.0)
  assert_true(buf.get(0) == 1.0)
  assert_true(buf.get(1) == -1.0)
}

///|
test "clip with zero threshold produces silence" {
  let clip = Clip::new()
  let ctx = DspContext::new(48000.0, 4)
  let buf = AudioBuffer::filled(4, init=0.5)
  clip.process(ctx, buf, 0.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(buf.get(i) == 0.0)
  }
}

///|
test "prop: clip output within threshold" {
  @qc.quick_check_fn!(
    fn(pair : (Double, Double)) {
      let (input, raw_threshold) = pair
      if input.is_nan() || input.is_inf() || raw_threshold.is_nan() || raw_threshold.is_inf() {
        return true
      }
      let threshold = raw_threshold.abs()
      let clip = Clip::new()
      let ctx = DspContext::new(48000.0, 1)
      let buf = AudioBuffer::filled(1, init=input)
      clip.process(ctx, buf, threshold)
      let out = buf.get(0)
      out >= -threshold && out <= threshold
    },
    max_success=200,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f clip_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/clip_test.mbt
git commit -m "test: add clip unit tests with property-based threshold bounds"
```

---

### Task 5: Mix tests (`lib/mix_test.mbt`)

**Files:**
- Create: `lib/mix_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/mix_test.mbt`:

```moonbit
///|
test "mix adds two buffers sample-wise" {
  let mix = Mix::new()
  let ctx = DspContext::new(48000.0, 4)
  let dst = AudioBuffer::new(FixedArray::from_array([1.0, 2.0, 3.0, 4.0]))
  let src = AudioBuffer::new(FixedArray::from_array([0.1, 0.2, 0.3, 0.4]))
  mix.process(ctx, dst, src)
  assert_true((dst.get(0) - 1.1).abs() < 0.000001)
  assert_true((dst.get(1) - 2.2).abs() < 0.000001)
  assert_true((dst.get(2) - 3.3).abs() < 0.000001)
  assert_true((dst.get(3) - 4.4).abs() < 0.000001)
}

///|
test "mix with silence is identity" {
  let mix = Mix::new()
  let ctx = DspContext::new(48000.0, 4)
  let dst = AudioBuffer::new(FixedArray::from_array([1.0, 2.0, 3.0, 4.0]))
  let silent = AudioBuffer::filled(4)
  mix.process(ctx, dst, silent)
  assert_true(dst.get(0) == 1.0)
  assert_true(dst.get(3) == 4.0)
}

///|
test "prop: mix is additive" {
  @qc.quick_check_fn!(
    fn(pair : (Double, Double)) {
      let (a, b) = pair
      if a.is_nan() || a.is_inf() || b.is_nan() || b.is_inf() {
        return true
      }
      let mix = Mix::new()
      let ctx = DspContext::new(48000.0, 1)
      let dst = AudioBuffer::filled(1, init=a)
      let src = AudioBuffer::filled(1, init=b)
      mix.process(ctx, dst, src)
      let expected = a + b
      if expected.is_nan() || expected.is_inf() {
        return true
      }
      (dst.get(0) - expected).abs() < 0.000001
    },
    max_success=200,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f mix_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/mix_test.mbt
git commit -m "test: add mix unit tests with property-based additivity"
```

---

### Task 6: Pan tests (`lib/pan_test.mbt`)

**Files:**
- Create: `lib/pan_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/pan_test.mbt`:

```moonbit
///|
test "pan center splits signal equally" {
  let pan = Pan::new()
  let ctx = DspContext::new(48000.0, 4)
  let input = AudioBuffer::filled(4, init=1.0)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, 0.0)
  // Equal-power center: cos(π/4) = sin(π/4) ≈ 0.7071
  for i = 0; i < 4; i = i + 1 {
    assert_true((left.get(i) - 0.7071067811865476).abs() < 0.0001)
    assert_true((right.get(i) - 0.7071067811865476).abs() < 0.0001)
  }
}

///|
test "pan hard left sends signal only to left" {
  let pan = Pan::new()
  let ctx = DspContext::new(48000.0, 4)
  let input = AudioBuffer::filled(4, init=1.0)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, -1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.99)
    assert_true(right.get(i).abs() < 0.0001)
  }
}

///|
test "pan hard right sends signal only to right" {
  let pan = Pan::new()
  let ctx = DspContext::new(48000.0, 4)
  let input = AudioBuffer::filled(4, init=1.0)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, 1.0)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i).abs() < 0.0001)
    assert_true(right.get(i) > 0.99)
  }
}

///|
test "pan zero input produces zero output regardless of position" {
  let pan = Pan::new()
  let ctx = DspContext::new(48000.0, 4)
  let input = AudioBuffer::filled(4)
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pan.process(ctx, input, left, right, 0.5)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) == 0.0)
    assert_true(right.get(i) == 0.0)
  }
}

///|
test "prop: pan preserves energy (equal-power law)" {
  @qc.quick_check_fn!(
    fn(raw_pan : Double) {
      // Map [0,1) to pan range [-1, 1]
      let pan_pos = raw_pan * 2.0 - 1.0
      if pan_pos.is_nan() || pan_pos.is_inf() {
        return true
      }
      let pan = Pan::new()
      let ctx = DspContext::new(48000.0, 1)
      let input = AudioBuffer::filled(1, init=1.0)
      let left = AudioBuffer::filled(1)
      let right = AudioBuffer::filled(1)
      pan.process(ctx, input, left, right, pan_pos)
      let l = left.get(0)
      let r = right.get(0)
      // Equal-power: left² + right² ≈ input² = 1.0
      let energy = l * l + r * r
      (energy - 1.0).abs() < 0.01
    },
    max_success=200,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f pan_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/pan_test.mbt
git commit -m "test: add pan unit tests with property-based energy conservation"
```

---

### Task 7: DelayLine tests (`lib/delay_test.mbt`)

**Files:**
- Create: `lib/delay_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/delay_test.mbt`:

```moonbit
///|
test "delay line delays impulse by delay_samples" {
  let delay = DelayLine::new(8, delay_samples=3)
  // Feed an impulse: 1.0 followed by zeros
  assert_true(delay.tick(1.0) == 0.0) // sample 0: not yet delayed
  assert_true(delay.tick(0.0) == 0.0) // sample 1
  assert_true(delay.tick(0.0) == 0.0) // sample 2
  assert_true(delay.tick(0.0) == 1.0) // sample 3: impulse arrives
  assert_true(delay.tick(0.0) == 0.0) // sample 4: gone
}

///|
test "delay with zero delay_samples is passthrough" {
  let delay = DelayLine::new(8, delay_samples=0)
  assert_true(delay.tick(0.5) == 0.5)
  assert_true(delay.tick(0.7) == 0.7)
}

///|
test "delay with max delay_samples uses full buffer" {
  let delay = DelayLine::new(4, delay_samples=4)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
}

///|
test "delay feedback accumulates energy" {
  let delay = DelayLine::new(2, delay_samples=1, feedback=0.5)
  let first = delay.tick(1.0) // output 0, write 1.0
  assert_true(first == 0.0)
  let second = delay.tick(0.0) // output 1.0, write 1.0*0.5=0.5
  assert_true(second == 1.0)
  let third = delay.tick(0.0) // output 0.5, write 0.5*0.5=0.25
  assert_true((third - 0.5).abs() < 0.000001)
}

///|
test "delay set_delay_samples changes delay mid-stream" {
  let delay = DelayLine::new(8, delay_samples=2)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  assert_true(delay.tick(0.0) == 1.0) // arrives after 2 samples
  delay.set_delay_samples(1)
  ignore(delay.tick(0.5))
  assert_true(delay.tick(0.0) == 0.5) // arrives after 1 sample
}

///|
test "delay reset clears buffer" {
  let delay = DelayLine::new(4, delay_samples=1)
  ignore(delay.tick(1.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0) // buffer cleared, no delayed output
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f delay_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/delay_test.mbt
git commit -m "test: add delay line unit tests with impulse response and feedback"
```

---

### Task 8: Adsr tests (`lib/env_test.mbt`)

**Files:**
- Create: `lib/env_test.mbt`

- [ ] **Step 1: Write tests**

Create `lib/env_test.mbt`:

```moonbit
///|
test "adsr starts in idle stage" {
  let env = Adsr::new(5.0, 5.0, 0.5, 10.0)
  assert_true(env.stage() is EnvStage::Idle)
  assert_true(env.level() == 0.0)
}

///|
test "adsr gate_on triggers attack" {
  let env = Adsr::new(5.0, 5.0, 0.5, 10.0)
  env.gate_on()
  assert_true(env.stage() is EnvStage::Attack)
}

///|
test "adsr transitions through all stages" {
  // 1 ms attack, 1 ms decay, 0.5 sustain, 1 ms release at 1000 Hz sample rate
  let env = Adsr::new(1.0, 1.0, 0.5, 1.0)
  let ctx = DspContext::new(1000.0, 8)
  let buf = AudioBuffer::filled(8)

  env.gate_on()
  env.process(ctx, buf)
  // After 1 sample at 1000Hz with 1ms attack, should have reached peak
  // After 2 samples, should be in decay or sustain
  assert_true(env.stage() is EnvStage::Sustain)

  env.gate_off()
  assert_true(env.stage() is EnvStage::Release)

  env.process(ctx, buf)
  // After 1ms release at 1000Hz (1 sample), should be idle
  assert_true(env.stage() is EnvStage::Idle)
}

///|
test "adsr zero attack reaches peak immediately" {
  let env = Adsr::new(0.0, 5.0, 0.5, 10.0)
  let ctx = DspContext::new(48000.0, 1)
  let buf = AudioBuffer::filled(1)
  env.gate_on()
  env.process(ctx, buf)
  // With zero attack, level should jump to 1.0 then start decay
  assert_true(buf.get(0) >= 0.99)
}

///|
test "adsr reset returns to idle" {
  let env = Adsr::new(5.0, 5.0, 0.5, 10.0)
  env.gate_on()
  assert_true(env.stage() is EnvStage::Attack)
  env.reset()
  assert_true(env.stage() is EnvStage::Idle)
  assert_true(env.level() == 0.0)
}

///|
test "prop: adsr output in [0, 1]" {
  @qc.quick_check_fn!(
    fn(params : (Double, Double, Double, Double)) {
      let (raw_a, raw_d, raw_s, raw_r) = params
      // Map to useful ranges: times [0, 100] ms, sustain [0, 1]
      let attack_ms = raw_a.abs() * 100.0
      let decay_ms = raw_d.abs() * 100.0
      let sustain = raw_s.abs()
      let sustain_clamped = if sustain > 1.0 { 1.0 } else { sustain }
      let release_ms = raw_r.abs() * 100.0
      if attack_ms.is_nan() || decay_ms.is_nan() || release_ms.is_nan() || sustain_clamped.is_nan() {
        return true
      }
      let env = Adsr::new(attack_ms, decay_ms, sustain_clamped, release_ms)
      let ctx = DspContext::new(48000.0, 64)
      let buf = AudioBuffer::filled(64)
      env.gate_on()
      env.process(ctx, buf)
      for i = 0; i < 64; i = i + 1 {
        let v = buf.get(i)
        if v < -0.001 || v > 1.001 {
          return false
        }
      }
      env.gate_off()
      env.process(ctx, buf)
      for i = 0; i < 64; i = i + 1 {
        let v = buf.get(i)
        if v < -0.001 || v > 1.001 {
          return false
        }
      }
      true
    },
    max_success=100,
  )
}
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test -p lib -f env_test.mbt`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/env_test.mbt
git commit -m "test: add ADSR envelope unit tests with stage transitions and output bounds"
```

---

### Task 9: Final verification

- [ ] **Step 1: Run full test suite**

Run: `moon test`
Expected: 271 existing + ~40 new tests all pass.

- [ ] **Step 2: Verify no API changes**

Run: `moon info && moon fmt && git diff -- '*.mbti'`
Expected: No .mbti changes.

- [ ] **Step 3: Commit any formatting**

```bash
git add -A && git status
# If changes: git commit -m "chore: format after adding primitive unit tests"
```
