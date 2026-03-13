# Salat Engine — Technical Reference

Companion to `salat-engine-blueprint.md` and `step0-instruction.md`.
This document provides the implementation-level knowledge a coding agent needs.

---

## 1. MoonBit Idioms for Real-Time Audio

### 1.1 The Golden Rule

**In any function called at audio rate (≈375 times/sec for 128-sample blocks, or 48000 times/sec for per-sample), never allocate heap objects.**

According to MoonBit's FFI/runtime documentation, the Wasm and C backends use
compiler-optimized reference counting, while the Wasm GC and JavaScript
backends reuse the host runtime's garbage collector. Either way, allocation in
audio-rate code risks latency spikes and should be treated as unsafe.

### 1.2 Safe Types (No Allocation)

```moonbit
// SAFE — these are value types, live on stack or in registers
let x : Int = 42
let y : Double = 3.14
let z : Bool = true
let b : Byte = b'\x00'

// SAFE — FixedArray is pre-allocated, fixed-length
// Create ONCE outside the hot path, reuse forever
let buffer : FixedArray[Double] = FixedArray::make(128, 0.0)

// SAFE — mutable struct fields (struct is pre-allocated)
struct OscState {
  mut phase : Double
  mut frequency : Double
}
```

### 1.3 Dangerous Patterns (Allocate — Avoid in Hot Path)

```moonbit
// DANGEROUS — Array is dynamically sized, allocates on resize
let a : Array[Double] = []    // allocation
a.push(1.0)                   // possible reallocation

// DANGEROUS — String creation allocates
let s = "hello"               // allocation
let t = "\{x}"                // allocation (interpolation)

// DANGEROUS / SUSPECT — creating fresh composite values
// Depending on representation and optimization, these may allocate or box.
// Treat them as unsafe in the hot path unless you have checked the generated code.
let p = { x: 1.0, y: 2.0 }
let e = Some(42)

// DANGEROUS — closures capture environment → allocate
let f = fn(x) { x + offset }  // captures `offset` → heap allocation

// DANGEROUS — map/filter/collect create new collections
buffer.map(fn(x) { x * 2.0 }) // allocates new array

// DANGEROUS — println / string formatting
println("debug: \{value}")     // allocates String, calls FFI
```

### 1.4 Audio-Safe Patterns

```moonbit
// Pattern: Pre-allocate all buffers at initialization time
struct DspContext {
  sample_rate : Double
  buffer_size : Int
  // Pre-allocated scratch buffers
  temp1 : FixedArray[Double]
  temp2 : FixedArray[Double]
}

fn DspContext::new(sample_rate : Double, buffer_size : Int) -> DspContext {
  {
    sample_rate,
    buffer_size,
    temp1: FixedArray::make(buffer_size, 0.0),
    temp2: FixedArray::make(buffer_size, 0.0),
  }
}

// Pattern: In-place buffer operations (no allocation)
fn apply_gain(buf : FixedArray[Double], gain : Double) -> Unit {
  for i = 0; i < buf.length(); i = i + 1 {
    buf[i] = buf[i] * gain
  }
}

// Pattern: Mutable state in struct fields
struct Oscillator {
  mut phase : Double
}

// This function allocates NOTHING — only reads/writes mut fields and FixedArray slots
fn Oscillator::process(
  self : Oscillator,
  output : FixedArray[Double],
  freq : Double,
  sample_rate : Double,
) -> Unit {
  let phase_inc = freq / sample_rate
  let two_pi = 6.283185307179586
  for i = 0; i < output.length(); i = i + 1 {
    output[i] = @math.sin(self.phase * two_pi)
    self.phase = self.phase + phase_inc
    if self.phase >= 1.0 {
      self.phase = self.phase - 1.0
    }
  }
}
```

### 1.5 ReadOnlyArray for Lookup Tables

MoonBit's `ReadOnlyArray` is statically initialized on C/LLVM/Wasmlinear backends. Ideal for wavetables, filter coefficient tables, and MIDI-to-frequency mappings.

```moonbit
// Statically initialized — no runtime allocation
let MIDI_FREQ : ReadOnlyArray[Double] = [
  8.1758,    // MIDI 0 (C-1)
  8.6620,    // MIDI 1
  9.1770,    // MIDI 2
  // ... 128 entries
  12543.854, // MIDI 127 (G9)
]

// Wavetable (256 samples of one cycle)
let SINE_TABLE : ReadOnlyArray[Double] = [
  // ... 256 pre-computed sin values
]
```

### 1.6 Backend-Specific Code

Use `#cfg` for FFI differences between backends:

```moonbit
#cfg(target="wasm-gc")
fn get_time() -> Double {
  // wasm-gc: call JS performance.now()
  js_performance_now()
}

#cfg(target="js")
fn get_time() -> Double {
  js_performance_now()
}

#cfg(target="native")
fn get_time() -> Double {
  c_clock_gettime()
}
```

### 1.7 MoonBit-Specific Gotchas

- **`@math.sin` / `@math.cos`**: Available in the standard library. Use these, don't implement your own.
- **No `fmod`**: MoonBit doesn't have a float modulus operator. Use `if phase >= 1.0 { phase = phase - 1.0 }` for phase wrapping (sufficient when increment < 1.0). For general modulus: `x - @math.floor(x / y) * y`.
- **`FixedArray` vs `Array`**: `FixedArray` is fixed-length (like C arrays). `Array` is dynamic (like `Vec`). Always use `FixedArray` for audio buffers.
- **Integer division**: `10 / 3 = 3` (integer division). Use `10.0 / 3.0` for float.
- **No implicit numeric conversion**: `let x : Double = 42` works, but in some contexts you need `42.0` explicitly.

---

## 2. DSP Algorithm Cookbook

All algorithms assume:
- `sample_rate`: 48000.0 Hz
- `buffer_size`: 128 samples (WebAudio render quantum)
- All state is `mut` fields on a struct
- All processing is in-place on `FixedArray[Double]`

### 2.1 Oscillators

#### Phase Accumulator (Core Technique)

Every oscillator uses the same principle: a phase variable that increments by `freq / sample_rate` each sample, wrapping at 1.0.

```
phase += freq / sample_rate
if phase >= 1.0: phase -= 1.0
```

The waveform is a function of `phase ∈ [0, 1)`:

| Waveform | Formula | Range |
|----------|---------|-------|
| Sine | `sin(phase * 2π)` | [-1, 1] |
| Saw (naive) | `2 * phase - 1` | [-1, 1] |
| Square (naive) | `if phase < 0.5 then 1 else -1` | {-1, 1} |
| Triangle | `4 * phase - 1 if phase < 0.5 else 3 - 4 * phase` | [-1, 1] |
| Pulse | `if phase < pulse_width then 1 else -1` | {-1, 1} |

**Naive waveforms produce aliasing** (audible artifacts above ~5kHz). For production:
- Use **PolyBLEP** (polynomial bandlimited step) for saw/square — adds a small correction near discontinuities
- Or use **wavetable** synthesis — pre-compute one cycle at multiple sample rates

For the prototype, naive waveforms are fine. Add PolyBLEP in Phase 1 if aliasing is audible.

#### PolyBLEP Correction (Optional Enhancement)

```
fn poly_blep(t : Double, dt : Double) -> Double {
  // t = phase, dt = freq / sample_rate
  if t < dt {
    let t = t / dt
    2.0 * t - t * t - 1.0
  } else if t > 1.0 - dt {
    let t = (t - 1.0) / dt
    t * t + 2.0 * t + 1.0
  } else {
    0.0
  }
}

// Saw with PolyBLEP:
// output = (2 * phase - 1) - poly_blep(phase, phase_inc)

// Helper because MoonBit has no float modulus operator:
fn wrap01(x : Double) -> Double {
  x - @math.floor(x)
}

// Square with PolyBLEP:
// output = (if phase < 0.5 then 1 else -1)
//        - poly_blep(phase, phase_inc)
//        + poly_blep(wrap01(phase + 0.5), phase_inc)
```

### 2.2 Biquad Filter (Robert Bristow-Johnson's Audio EQ Cookbook)

The biquad is the workhorse of audio DSP. One filter handles LPF, HPF, BPF, notch, peaking EQ, low/high shelf — only the coefficient calculation differs.

#### Transfer Function

```
H(z) = (b0 + b1*z⁻¹ + b2*z⁻²) / (a0 + a1*z⁻¹ + a2*z⁻²)
```

Normalize by a0 (divide all coefficients by a0) so the denominator leading coefficient is 1.

#### Direct Form II Transposed (Recommended)

```
y[n] = b0*x[n] + z1
z1   = b1*x[n] - a1*y[n] + z2
z2   = b2*x[n] - a2*y[n]
```

State: `z1`, `z2` (two Doubles). This form has better numerical stability than Direct Form I.

#### Coefficient Calculation

Common intermediate values:
```
w0    = 2π * cutoff_freq / sample_rate
alpha = sin(w0) / (2 * Q)
cos_w0 = cos(w0)
```

**Low-Pass Filter (LPF):**
```
b0 = (1 - cos_w0) / 2
b1 = 1 - cos_w0
b2 = (1 - cos_w0) / 2
a0 = 1 + alpha
a1 = -2 * cos_w0
a2 = 1 - alpha
```

**High-Pass Filter (HPF):**
```
b0 = (1 + cos_w0) / 2
b1 = -(1 + cos_w0)
b2 = (1 + cos_w0) / 2
a0 = 1 + alpha
a1 = -2 * cos_w0
a2 = 1 - alpha
```

**Band-Pass Filter (BPF, constant skirt gain):**
```
b0 = alpha
b1 = 0
b2 = -alpha
a0 = 1 + alpha
a1 = -2 * cos_w0
a2 = 1 - alpha
```

After computing, normalize: `b0/=a0, b1/=a0, b2/=a0, a1/=a0, a2/=a0`.

**Important**: Recalculate coefficients only when cutoff or Q changes, not every sample. Store as `mut` fields and recompute in `set_param()`.

#### Q (Resonance) Values

- `Q = 0.707` (1/√2): Butterworth (maximally flat, no resonance)
- `Q = 1.0`: Slight resonance
- `Q = 10.0`: Strong resonance (careful — can blow up levels)
- `Q` must be positive because the RBJ formulas divide by `Q`
- Smaller `Q` means a broader, less resonant response; use a practical lower
  bound in UI code (for example `0.1`) to avoid degenerate parameter values

### 2.3 ADSR Envelope

Linear ADSR with four stages:

```
         1.0  ──────┐
              /      \
             /        \  sustain_level
            /          ──────────┐
           /                      \
     0.0 ─┘                       └─── 0.0
         │A│  D  │    S    │  R  │

     gate ON ─────────────── gate OFF
```

Per-sample computation:
```
match stage:
  Attack:
    level += 1.0 / (attack_time * sample_rate)
    if level >= 1.0: level = 1.0, stage = Decay
  Decay:
    level -= (1.0 - sustain) / (decay_time * sample_rate)
    if level <= sustain: level = sustain, stage = Sustain
  Sustain:
    level = sustain  (no change)
  Release:
    level -= level_at_release / (release_time * sample_rate)
    if level <= 0.0: level = 0.0, stage = Idle
  Idle:
    level = 0.0
```

**Gotcha**: On `note_off`, store `level_at_release = current_level` so release starts from wherever the envelope actually is (it may not have reached sustain yet).

**Enhancement**: Exponential curves sound more natural than linear:
```
// Exponential attack: level = 1 - e^(-t/τ)
// Approximate with: level += (target - level) * coeff
// where coeff = 1 - e^(-1 / (time * sample_rate))
```

### 2.4 Delay Line

A circular buffer with a read pointer trailing the write pointer.

```moonbit
struct DelayLine {
  buffer : FixedArray[Double]  // length = max_delay_samples
  mut write_pos : Int
  delay_samples : Int
}

fn DelayLine::new(max_delay_samples : Int) -> DelayLine {
  {
    buffer: FixedArray::make(max_delay_samples, 0.0),
    write_pos: 0,
    delay_samples: max_delay_samples,
  }
}

fn DelayLine::process(self : DelayLine, input : Double) -> Double {
  // Write input
  self.buffer[self.write_pos] = input
  // Read from delay_samples ago
  let read_pos = self.write_pos - self.delay_samples
  let read_pos = if read_pos < 0 {
    read_pos + self.buffer.length()
  } else {
    read_pos
  }
  let output = self.buffer[read_pos]
  // Advance write pointer
  self.write_pos = self.write_pos + 1
  if self.write_pos >= self.buffer.length() {
    self.write_pos = 0
  }
  output
}
```

For fractional delay (sub-sample precision), use linear interpolation between adjacent samples.

### 2.5 Parameter Smoothing (One-Pole Filter)

Prevents clicks/pops when parameters change abruptly.

```moonbit
struct ParamSmoother {
  mut current : Double
  mut target : Double
  coeff : Double  // smoothing coefficient
}

fn ParamSmoother::new(initial : Double, smoothing_ms : Double, sample_rate : Double) -> ParamSmoother {
  {
    current: initial,
    target: initial,
    // coeff = e^(-1 / (smoothing_time_in_samples))
    // Typical smoothing_ms = 5-20ms
    coeff: @math.exp(-1000.0 / (smoothing_ms * sample_rate)),
  }
}

// Call once per sample in the audio loop
fn ParamSmoother::tick(self : ParamSmoother) -> Double {
  self.current = self.target + self.coeff * (self.current - self.target)
  self.current
}

// Call from main thread (via postMessage handler)
fn ParamSmoother::set(self : ParamSmoother, value : Double) -> Unit {
  self.target = value
}
```

### 2.6 Noise

```moonbit
// White noise: uniform random in [-1, 1]
// MoonBit has @random, but it may allocate.
// For audio-safe noise, use a simple LCG or xorshift:

struct NoiseGen {
  mut state : UInt  // xorshift state, must be nonzero
}

fn NoiseGen::next(self : NoiseGen) -> Double {
  // xorshift32
  let mut x = self.state
  x = x.lxor(x.lsl(13))
  x = x.lxor(x.lsr(17))
  x = x.lxor(x.lsl(5))
  self.state = x
  // Convert to [-1.0, 1.0]
  x.to_double() / 2147483648.0 - 1.0
}
```

### 2.7 Mix and Gain

Trivial but important to get right:

```
// Gain: output[i] = input[i] * gain_value
// Pan (equal-power): left = input * cos(pan * π/4), right = input * sin(pan * π/4)
//   where pan ∈ [-1, 1], center = 0
// Mix: output[i] = sum(inputs[j][i]) — may need scaling by 1/sqrt(N) to prevent clipping
```

In the current Phase 1 implementation these are split into separate primitives:
`gain.mbt`, `mix.mbt`, `clip.mbt`, and `pan.mbt`, all built around
`DspContext` plus `AudioBuffer`.

---

## 3. Graph Compilation Strategy

Lessons distilled from kabelsalat and noisecraft analysis.

### 3.1 The Pipeline

```
User DSL code
     │
     ▼
Node (tree structure, type + ins[])
     │ flatten()
     ▼
FlatNode[] (array, ins are indices)
     │ topoSort()
     ▼
FlatNode[] (sorted: dependencies before dependents)
     │ compile()
     ▼
Executable form (interpreter loop or generated code)
```

### 3.2 Flatten

Convert the recursive tree into a flat array where `ins` are integer indices:

```
// Before (tree):
{ type: Sine, ins: [{ type: Num, value: 200 }] }

// After (flat array):
[
  { type: Num, value: 200, ins: [] },      // index 0
  { type: Sine, ins: [0] },                // index 1
]
```

### 3.3 Topological Sort

Kahn's algorithm (BFS-based) is simplest:

```
1. Compute in-degree for each node
2. Enqueue all nodes with in-degree 0
3. While queue non-empty:
   a. Dequeue node, add to sorted output
   b. For each node that depends on it, decrement in-degree
   c. If in-degree reaches 0, enqueue it
4. If sorted.length != total nodes → cycle detected
```

After sorting, every node's inputs appear before the node itself in the array.

### 3.4 Cycle Detection and Feedback

Cycles are intentional in DSP (feedback delay, flangers, etc.).

kabelsalat's approach: detect back-edges during topological sort. For each back-edge, insert a **z⁻¹ node** (one-sample delay). The previous sample's output is stored and used as input for the current sample.

```
// During topo sort, if a node references a later (not-yet-processed) node:
// 1. Mark it as a feedback edge
// 2. Insert a FeedbackRead node at the input point
// 3. Insert a FeedbackWrite node at the output point
// 4. FeedbackRead returns last sample's value from a shared register
// 5. FeedbackWrite stores current sample's value to that register
```

### 3.5 Compilation Approaches

#### Approach A: Interpreter (Start Here)

```moonbit
// A flat array of instructions, executed in order per sample
fn run_sample(
  nodes : FixedArray[FlatNode],
  slots : FixedArray[Double],       // output value of each node
  state : FixedArray[ProcessorState], // persistent state per node
  sample_rate : Double,
) -> Double {
  for i = 0; i < nodes.length(); i = i + 1 {
    slots[i] = match nodes[i].node_type {
      Num(v) => v
      Sine => {
        let freq = slots[nodes[i].ins[0]]
        // update phase in state[i], return sin
        process_sine(state[i], freq, sample_rate)
      }
      Mul => slots[nodes[i].ins[0]] * slots[nodes[i].ins[1]]
      Add => slots[nodes[i].ins[0]] + slots[nodes[i].ins[1]]
      LPF => {
        let input = slots[nodes[i].ins[0]]
        let cutoff = slots[nodes[i].ins[1]]
        let q = slots[nodes[i].ins[2]]
        process_biquad(state[i], input, cutoff, q, sample_rate)
      }
      // ... etc
    }
  }
  slots[nodes.length() - 1]  // last node = output
}
```

Advantages: simple, easy to debug, easy to add new node types.
Disadvantage: match dispatch per node per sample. For 50 nodes at 48kHz = 2.4M dispatches/sec.

#### Approach B: Code Generation (kabelsalat/noisecraft Style)

Generate a JS string where each node becomes a line of code:

```javascript
// Generated code (kabelsalat style):
const n0 = 0.5;                          // Num
const n1 = 200;                           // Num
const n2 = nodes[0].update(n1, 0);        // Sine (stateful)
const n3 = n2 * n0;                       // Mul (inlined)
return [n3 * 0.3, n3 * 0.3];             // stereo out
```

Advantages: V8 JIT compiles this to near-native speed. No dispatch overhead.
Disadvantage: requires `new Function()` or `eval()`. Harder to debug.

#### Approach C: Per-Buffer Processing (Recommended for MoonBit)

Process each node for the entire 128-sample buffer before moving to the next node. Better cache locality than per-sample processing.

```moonbit
fn run_buffer(
  nodes : FixedArray[FlatNode],
  buffers : FixedArray[FixedArray[Double]], // one buffer per node
  state : FixedArray[ProcessorState],
  ctx : DspContext,
) -> Unit {
  for i = 0; i < nodes.length(); i = i + 1 {
    let out = buffers[i]
    match nodes[i].node_type {
      Num(v) => {
        for j = 0; j < ctx.buffer_size; j = j + 1 {
          out[j] = v
        }
      }
      Sine => {
        let freq_buf = buffers[nodes[i].ins[0]]
        process_sine_buffer(state[i], freq_buf, out, ctx)
      }
      Mul => {
        let a = buffers[nodes[i].ins[0]]
        let b = buffers[nodes[i].ins[1]]
        for j = 0; j < ctx.buffer_size; j = j + 1 {
          out[j] = a[j] * b[j]
        }
      }
      // ... etc
    }
  }
}
```

Advantages: buffer-based processing enables SIMD optimization, better cache behavior. Match dispatch only happens once per node per buffer (not per sample). Natural fit for MoonBit (no code generation needed).

**Recommendation**: Start with Approach C. It's a good balance of performance and simplicity for MoonBit. If it's not fast enough (unlikely for < 100 nodes), investigate code generation later.

### 3.5.1 Current Phase 2 Status

This section is the authoritative description of the current compiled-graph
runtime-control surface. Update it first when Phase 2 runtime behavior changes;
keep `RESULTS.md` and `docs/salat-engine-blueprint.md` as summary-level
pointers back to this section.

The current repository already implements:

- a compiled mono graph path: `DspNode` authoring graphs compile into an opaque
  `CompiledDsp`, including explicit `Mono -> Stereo -> Mono` subgraphs through
  `Pan` and `StereoMixDown`
- a first stereo graph path: the same `DspNode` authoring language can compile
  into `CompiledStereoDsp` for `Mono -> Pan -> Stereo post-processing ->
  StereoOutput`, where the current stereo post-processing node set is
  `StereoGain`, `StereoClip`, and `StereoBiquad`
- input nodes may be declared in authoring order; the compiler topologically
  sorts reachable nodes from a single terminal output node
- compile rejects:
  - cycles
  - multiple outputs
  - missing outputs
  - unreachable nodes
  - invalid references
  - non-finite constants
  - invalid fixed `Biquad` parameters
- runtime processing fails closed to silence if the caller requests a block size
  larger than the graph was compiled for

Current graph node support:

- `Constant`
- `Oscillator`
- `Noise`
- `Adsr`
- `Biquad`
- `Delay`
- `Gain`
- `Mul`
- `Mix`
- `Clip`
- `Pan`
- `StereoGain`
- `StereoClip`
- `StereoBiquad`
- `StereoMixDown`
- `Output`
- `StereoOutput`

Current runtime control support:

- `apply_control(GraphControl)` is the preferred runtime-control entrypoint
- `apply_controls(Array[GraphControl])` applies control batches transactionally
  in batch order while targeting nodes by authoring index
- compatibility helpers remain available:
  - `gate_on(node_index)` / `gate_off(node_index)` for `Adsr`
- partial `set_param(node_index, slot, value)` for selected numeric params
  (`Gain`, `Clip`, `Biquad`, `Delay`, `Constant`, `Oscillator`, `Pan`,
  `StereoGain`, `StereoClip`, `StereoBiquad`)
- integration coverage now includes successful runtime `Biquad` retunes in
  compiled mono graphs for `LowPass`, `HighPass`, and `BandPass`
- the current graph tests also include directional runtime-retune assertions for
  `HighPass` and `BandPass`, not just output-difference checks
- stereo graph coverage now includes:
  - graph-unit checks for `Pan -> StereoOutput` shape enforcement
  - stereo post-processing through `StereoGain`, `StereoClip`, and
    `StereoBiquad`
  - direct runtime updates for `Pan`, `StereoGain`, `StereoClip`, and
    `StereoBiquad`
  - end-to-end compiled stereo voice-path and batched-control integration tests
- mono graph coverage now includes explicit stereo fold-down through
  `StereoMixDown`, including a stereo-filtered path through `StereoBiquad`

Current `set_param(node_index, slot, value)` support matrix:

| Node kind | Supported slots | Notes |
|-----------|-----------------|-------|
| `Constant` | `Value0` | Finite values only |
| `Oscillator` | `Value0` | Finite frequency values only |
| `Noise` | none | No runtime seed update yet |
| `Adsr` | none | Runtime control is `gate_on` / `gate_off` only |
| `Biquad` | `Value0`, `Value1` | `Value0 = cutoff`, `Value1 = q`; validated against the compile-time sample rate |
| `Delay` | `DelaySamples` | Exact integer values only; applied to the live `DelayLine` state |
| `Gain` | `Value0` | Finite gain only |
| `Mul` | none | No runtime params |
| `Mix` | none | No runtime params |
| `Clip` | `Value0` | Positive finite threshold only |
| `Pan` | `Value0` | Finite pan position only |
| `StereoGain` | `Value0` | Finite gain only |
| `StereoClip` | `Value0` | Positive finite threshold only |
| `StereoBiquad` | `Value0`, `Value1` | `Value0 = cutoff`, `Value1 = q`; validated against the compile-time sample rate |
| `StereoMixDown` | none | Fixed equal-weight fold-down: `0.5 * (left + right)` |
| `Output` | none | No runtime params |
| `StereoOutput` | none | No runtime params |

Current limits:

- stereo graph support is still narrow: terminal stereo remains
  `Pan -> stereo post-processing -> StereoOutput`, while mono graphs may now
  fold stereo back through `StereoMixDown`
- only one stereo filter node exists so far: `StereoBiquad`; no stereo delay
  nodes yet
- no feedback-edge insertion yet
- no graph hot-swap yet
- runtime parameter updates are partial, not universal across node kinds

### 3.5.2 Control Frames

The current graph runtime now has an explicit control-frame model for Phase 2.

A control frame is an ordered batch of `GraphControl` messages applied once
between render blocks:

```moonbit
compiled.apply_controls([
  GraphControl::gate_on(env_node),
  GraphControl::set_param(gain_node, GraphParamSlot::Value0, 0.5),
  GraphControl::set_param(filter_node, GraphParamSlot::Value0, 1200.0),
])
compiled.process(context, output)
```

Current semantics:

- controls are evaluated in the array's batch order
- controls target nodes by original authoring index, not topo-sorted index
- `apply_controls(...)` is transactional:
  - if any control in the batch is invalid, none of them are applied
  - if the batch succeeds, all controls are committed before the next
    `process(...)` call
- `apply_control(...)` remains the single-message form of the same runtime API

This is enough for the current compiled mono and terminal-stereo graph paths to
support per-block parameter and gate updates from a host, UI, or future pattern
engine.

Current limits of the control-frame model:

- controls are still block-boundary updates, not sample-accurate events
- runtime-updatable slots are still limited to the support matrix above
- `GraphControl` does not yet cover topology changes, hot-swap, or stereo graph
  routing changes

### 3.6 Graph Hot-Swap

When the user changes the DSP graph:

```
1. Main thread: compile new graph → new CompiledDsp object
2. Main thread: serialize or transfer to audio thread via postMessage
3. Audio thread: receive new graph
4. Audio thread: crossfade from old to new over ~25ms (≈10 buffers)
   - During crossfade: run BOTH old and new, mix with complementary gains
   - old_gain = cos(t * π/2), new_gain = sin(t * π/2)  (equal-power crossfade)
5. Audio thread: discard old graph
```

Simple version (no crossfade): just swap instantly. May cause a small click, but acceptable for prototyping.

### 3.7 Multichannel Expansion (SuperCollider-Style)

When a node receives an array instead of a scalar, the entire upstream graph is duplicated per channel:

```
sine([200, 300, 400]).out()
// Expands to 3 parallel sine oscillators mixed together
```

Implementation: during flatten(), detect array inputs and duplicate the subgraph. This is a pre-processing step before topological sort.

Defer this to later Phase 2 work. The current implementation starts with mono
only.

---

## 4. AudioWorklet Threading Model

### 4.1 Two Threads, Strict Separation

```
Main Thread                          Audio Thread
─────────────────────                ─────────────────────
- DOM / UI                           - AudioWorkletProcessor.process()
- User input handling                - Called every 128 samples (~2.67ms)
- Graph compilation                  - Must return within deadline
- AudioContext management            - No DOM access
- postMessage sender                 - Avoid loading/network work in the render path
                                     - Do not assume worker-only APIs such as
                                       `importScripts()` exist here
```

### 4.2 Communication Patterns

#### postMessage (Simple, Sufficient for Most Cases)

```
Main → Audio: graph updates, parameter changes, note on/off
Audio → Main: visualization data, meter levels
```

Latency: typically < 1ms on modern browsers, but not guaranteed. Acceptable for parameter changes (smoothed anyway) and graph updates.

#### SharedArrayBuffer (Low-Latency, Complex Setup)

Required for:
- High-frequency parameter automation (100+ changes per second)
- Audio data streaming to main thread for visualization
- MIDI input with minimal latency

Setup requirements:
- Server must send `Cross-Origin-Opener-Policy: same-origin` header
- Server must send `Cross-Origin-Embedder-Policy: require-corp` header
- Use `Int32Array` or `Float32Array` views on the SharedArrayBuffer
- Use `Atomics.load()` / `Atomics.store()` for safe reads/writes
- **Cannot use `Atomics` on `Float64Array`** — use `Float32Array` (sufficient precision for audio parameters) or encode doubles as two Int32 values

For the prototype, use postMessage only. Add SharedArrayBuffer in Phase 5+ if needed.

### 4.3 Loading wasm-gc in AudioWorklet

The AudioWorkletGlobalScope is a restricted environment. Key constraints:

- Load the processor script with `audioWorklet.addModule(...)` on the main
  thread; do not treat AudioWorklet like a classic worker
- Do not rely on worker-only APIs such as `importScripts()`
- Prefer fetching and compiling the Wasm module on the main thread, then
  transfer the compiled `WebAssembly.Module` to the processor

Recommended pattern (Chrome's "Pattern B"):

```javascript
// Main thread:
const wasmBytes = await fetch('module.wasm').then(r => r.arrayBuffer());
const wasmModule = await WebAssembly.compile(wasmBytes);

// Transfer to audio thread via AudioWorkletNode constructor:
const node = new AudioWorkletNode(ctx, 'processor', {
  processorOptions: { wasmModule }
});

// Audio thread (processor.js):
constructor(options) {
  const mod = options.processorOptions.wasmModule;
  this.ready = false;
  this._initWasm(mod);
}

async _initWasm(mod) {
  this.instance = await WebAssembly.instantiate(mod, imports);
  this.ready = true;
}
```

### 4.4 MoonBit wasm-gc Module Loading

The wasm-gc module generated by MoonBit may require specific imports. Common patterns:

```javascript
const imports = {
  // For println support (can be no-op if not needed in DSP)
  "spectest": {
    "print_char": (ch) => {}
  },
  // For closures passed across FFI boundary
  "moonbit:ffi": {
    "make_closure": (funcref, closure) => funcref.bind(null, closure)
  }
};

// If strings cross the boundary outside AudioWorklet, JS string builtins may
// be needed. For the AudioWorklet prototype, prefer main-thread
// fetch/compile + constructor transfer instead of streaming fetch here.
```

For the DSP module, we only export numeric functions (no strings), so the imports should be minimal.

---

## 5. kabelsalat / noisecraft Architecture Summary

### 5.1 What kabelsalat Does

1. **DSL**: JavaScript with method chaining. `sine(200).mul(0.5).out()`
2. **Graph**: `Node` objects form a tree. Each node has `type` and `ins[]`.
3. **Compiler**: Flatten → topo sort → generate JS code string.
4. **Runtime**: Generated code runs in AudioWorkletProcessor via `new Function()`.
5. **Stateful nodes**: Each `AudioNode` (e.g., Sine) keeps its own state (phase, etc.). Stored in a `nodes[]` array, indexed by compiler-assigned ID.

### 5.2 Key Design Decisions and Their Rationale

| Decision | Rationale | Applicable to Salat? |
|----------|-----------|---------------------|
| JS code generation | V8 JIT optimizes generated code better than interpreter loops | Not directly (MoonBit doesn't have `eval`). Use buffer-based processing instead. |
| Single-sample processing | Enables single-sample feedback (z⁻¹) | Yes. Some nodes need per-sample processing (oscillators with FM). |
| Flat node array + indices | Cache-friendly, no pointer chasing | Yes. `FixedArray[FlatNode]` in MoonBit. |
| Compile on main thread, run on audio thread | Compilation can be slow, audio thread has hard deadline | Yes. Exact same pattern. |
| AudioNode class with `update()` method | Each node type encapsulates its DSP + state | Yes. Use MoonBit structs with `process()` method. |
| Method chaining as DSL | Natural expression syntax, reduces parenthesis nesting | Possible in MoonBit with extension methods, but not the priority. |

### 5.3 kabelsalat Limitations That Salat Addresses

| Limitation | kabelsalat | Salat Engine |
|------------|-----------|--------------|
| Type safety | None (JS dynamic types) | MoonBit static types, enums, pattern matching |
| Pattern engine | External (Strudel) | Built-in (`salat-pattern`) |
| Incremental updates | Full recompilation on every change | `incr` memoizes unchanged subgraphs |
| Collaboration | Not supported | CRDT-based (future) |
| Native target | C codegen (experimental) | MoonBit C/LLVM backend (first-class) |
| Voice management | Struggled with this | ECS-based design (planned) |

### 5.4 froos's Learning Journey (from garten.salat.dev)

The 120-post development blog reveals a progression that directly maps to our phases:

| Blog posts | Topic | Our phase |
|------------|-------|-----------|
| 022-030 | AudioWorklet basics, first wasm audio | Phase 0 |
| 063-070 | Oscillators, waveforms, Fourier series | Phase 1 |
| 072-073 | Envelopes, sequences, triggers | Phase 1 |
| 076-078 | Graph computer, audio worklets | Phase 2 |
| 079-081 | Spawning audio graphs (voice management) | Phase 3 |
| 087-095 | "Hello Audio in C" series (DSP from scratch) | Phase 1 alt |
| 096 | "The Superdough Puzzle" (architecture reflection) | Design |
| 101 | kabelsalat to WAT compiler | Phase 2 alt |
| 104-105 | Worklet buffers, graph updates | Phase 2 |
| 110-120 | AST language design (evaluator, macros, lambdas) | Phase 4+ |

Key lesson: froos spent months on voice management (079-081) and described it as the hardest problem. Our ECS-based approach is explicitly designed to address this.

---

## 6. Node Type Reference

Minimum set needed for a useful synthesizer (Phase 1-2):

### Sources (no input)
| Node | Params | State | Description |
|------|--------|-------|-------------|
| `Num` | value | — | Constant number |
| `Sine` | freq | phase | Sine oscillator |
| `Saw` | freq | phase | Sawtooth oscillator |
| `Square` | freq, pw | phase | Square/pulse oscillator |
| `Tri` | freq | phase | Triangle oscillator |
| `Noise` | — | rng_state | White noise |

### Filters (1 input + params)
| Node | Params | State | Description |
|------|--------|-------|-------------|
| `LPF` | cutoff, Q | z1, z2 | Biquad low-pass |
| `HPF` | cutoff, Q | z1, z2 | Biquad high-pass |
| `BPF` | cutoff, Q | z1, z2 | Biquad band-pass |

### Envelopes (1 input + params)
| Node | Params | State | Description |
|------|--------|-------|-------------|
| `ADSR` | a, d, s, r | stage, level, gate | Attack-Decay-Sustain-Release |

### Arithmetic (2 inputs, stateless)
| Node | Description |
|------|-------------|
| `Add` | a + b |
| `Mul` | a * b |
| `Sub` | a - b |
| `Div` | a / b (with div-by-zero protection) |

### Effects
| Node | Params | State | Description |
|------|--------|-------|-------------|
| `Delay` | time, feedback | circular buffer | Echo/delay |
| `Gain` | amount | — | Volume control |
| `Pan` | position | — | Stereo panning |
| `Clip` | threshold | — | Hard clipping / distortion |

### Utility
| Node | Description |
|------|-------------|
| `Out` | Marks the final output node |
| `FeedbackRead` | Read from feedback register |
| `FeedbackWrite` | Write to feedback register |
| `Range` | Map [-1,1] to [min,max]: `(input + 1) / 2 * (max - min) + min` |

---

## 7. Glossary

| Term | Definition |
|------|-----------|
| **Render quantum** | 128 audio samples — the fixed block size of WebAudio's AudioWorkletProcessor |
| **Phase accumulator** | A counter that increments by `freq/sampleRate` each sample, wrapping at 1.0 |
| **Biquad** | A second-order IIR filter with 5 coefficients (b0, b1, b2, a1, a2) |
| **z⁻¹** | One-sample delay, the fundamental building block of digital filters |
| **Topological sort** | Ordering nodes so that every dependency is computed before the node that uses it |
| **PolyBLEP** | Polynomial correction applied near waveform discontinuities to reduce aliasing |
| **One-pole filter** | Simplest IIR filter: `y = target + coeff * (y_prev - target)`. Used for parameter smoothing. |
| **ADSR** | Attack-Decay-Sustain-Release envelope — shapes amplitude over time |
| **ControlMap** | A `Map[String, Double]` carrying event parameters from Pattern Engine to DSP Engine |
| **Finally Tagless** | A pattern where a DSL is defined as a trait. Each implementation is a different interpretation. |
| **Hylomorphism** | A recursion scheme combining an unfold (anamorphism) and a fold (catamorphism) |
| **`incr`** | MoonBit library for incremental computation (Signal/Memo). Salsa-inspired. |
| **CLAP** | Clever Audio Plugin format — modern alternative to VST3, designed for open-source |
