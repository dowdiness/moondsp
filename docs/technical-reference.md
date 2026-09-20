# moondsp Technical Reference

Companion to `blueprint.md` (historical bootstrap notes live in `archive/step0-instruction.md`).
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
// Pattern: Shared execution context — sample rate + block size only.
// Constructed once on the main thread, passed by value to every per-block
// process() call on the audio thread. Labelled args avoid argument-order
// confusion between the two Doubles a positional API would expose.
pub struct DspContext {
  sample_rate : Double
  block_size : Int

  fn new(sample_rate~ : Double, block_size~ : Int) -> DspContext
}

// Pattern: Pre-allocate buffers at initialization time, never in the hot path.
// In moondsp these live as AudioBuffer wrappers around FixedArray[Double];
// the audio thread only reads/writes existing slots.
let scratch : FixedArray[Double] = FixedArray::make(128, 0.0)

// Pattern: In-place buffer operations (no allocation)
fn apply_gain(buf : FixedArray[Double], gain : Double) -> Unit {
  for i in 0..<buf.length() {
    buf[i] = buf[i] * gain
  }
}

// Pattern: Mutable state in struct fields
struct Oscillator {
  mut phase : Double
}

// This function allocates NOTHING — only reads/writes mut fields and
// AudioBuffer slots. Labels name all call-site values whose position would
// otherwise be easy to swap.
pub fn Oscillator::process(
  self : Oscillator,
  context~ : DspContext,
  output~ : AudioBuffer,
  freq_hz~ : Double,
) -> Unit {
  let phase_inc = freq_hz / context.sample_rate()
  let two_pi = 6.283185307179586
  for i in 0..<output.length() {
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
- `block_size`: 128 samples (WebAudio render quantum)
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

Per-sample computation (times in **milliseconds**):
```
match stage:
  Attack:
    level += 1000.0 / (attack_ms * sample_rate)
    if level >= 1.0: level = 1.0, stage = Decay
  Decay:
    level -= (1.0 - sustain) * 1000.0 / (decay_ms * sample_rate)
    if level <= sustain: level = sustain, stage = Sustain
  Sustain:
    level = sustain  (no change)
  Release:
    level -= level_at_release * 1000.0 / (release_ms * sample_rate)
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

`DelayLine::reset` is a constant-time valid-range clear, not a physical
`buffer.fill(0.0)`. After reset (and after construction), reads from samples
that have not been written yet return silence. Physical buffer contents may
remain until overwritten. `StereoReverb` keeps its own hard zero-fill reset
because its comb/allpass read model is different.

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
// Gain (envelope): output[i] = input[i] * envelope[i] * gain_value
//   when input1 >= 0, Gain multiplies by a second buffer (e.g. ADSR output)
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

In the concrete library API, the pipeline is
`Array[DspNode] → AnalyzedGraph::analyze → AnalyzedGraph →
Dsp::compile → Dsp`. `AnalyzedGraph` is the single
runtime exchange type between authoring and compile. See ADR-0010 for
the boundary contract, `docs/external-dsl-lowering.md` for the external
DSL lowering contract, `docs/mini-graph-authoring-boundary.md` for Mini
`ControlMap` integration with graph templates, and
`docs/editor-audio-preview-handoff.md` for editor-facing preview ownership and
state transitions.

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

Current status note: the implementation now uses a self-register feedback model
in both compiled mono graphs and terminal-stereo graphs. `Dsp` and
`StereoDsp` detect back-edges and resolve them as zero-initialized
implicit `z^-1` reads during runtime using self-registers rather than
linked-list infrastructure. Stereo and mixed-shape feedback are now accepted.
Supported shapes include direct self-feedback, multiple simultaneous
back-edges, and loops that lift through `Pan` into a terminal stereo suffix.
Node-local recirculation on `Delay` and `StereoDelay` remains a separate
feature.

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
        for j = 0; j < ctx.block_size(); j = j + 1 {
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
        for j = 0; j < ctx.block_size(); j = j + 1 {
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

### 3.5.1 Compiled Graph & Runtime-Control Surface

This section is the authoritative description of the current compiled-graph
runtime-control surface. Update it first whenever runtime behavior changes;
keep `docs/blueprint.md` as a summary-level pointer back to this
section (the early Phase 0/1/2 status log lives at `docs/archive/RESULTS.md`
for historical context).

The current repository already implements:

- a compiled mono graph path: `DspNode` authoring graphs compile into an opaque
  `Dsp`, including explicit `Mono -> Stereo -> Mono` subgraphs through
  `Pan` and `StereoMixDown`, plus supported mono feedback cycles through
  automatic `z^-1` back-edge insertion
- a first stereo graph path: the same `DspNode` authoring language can compile
  into `StereoDsp` for `Mono -> Pan -> Stereo post-processing ->
  StereoOutput`, where the current stereo post-processing node set is
  `StereoGain`, `StereoClip`, `StereoBiquad`, and `StereoDelay`, and where the
  feedback uses a self-register model: stereo, mixed-shape, and mono `z^-1`
  feedback loops are accepted through `Pan` and in the stereo post-processing
  path
- input nodes may be declared in authoring order; the compiler topologically
  sorts reachable nodes from a single terminal output node
- `Dsp::compile(AnalyzedGraph, DspContext) -> Self?` remains the
  compatibility compile entry point; `Dsp::compile_result(...)` returns
  `Result[Dsp, GraphCompileError]` for callers that need a typed
  rejection reason, with node errors mapped back to original authoring indices
  when the analyzed template retains that mapping. `StereoDsp` has the
  same optional/result pair. `AnalyzedGraph::analyze(Array[DspNode])`
  produces the input. See ADR-0010 for the boundary contract and ADR-0014 for
  the equality/diagnostic policy.
- `AnalyzedGraph::analyze(...)` captures the authoring template, the
  optimizer's authoring-index map, and the optimized node array; both mono
  and stereo graphs compile from the same analyzed template via
  `Dsp::compile(...)` / `compile_result(...)` or
  `StereoDsp::compile(...)` / `compile_result(...)`, reusing the
  optimized nodes without running the graph optimizer a second time
- compile rejects:
  - unsupported feedback cycles
  - multiple outputs
  - missing outputs
  - unreachable nodes
  - invalid references
  - non-finite constants
  - invalid fixed `Biquad` parameters
  - fixed `Delay` / `StereoDelay` feedback outside the live supported range
- runtime processing fails closed to silence if the caller requests a block size
  larger than the graph was compiled for
- `Dsp::reset_runtime_state(...)` restores compile-time node
  parameters, clears compiled buffers, and resets stateful DSP primitives so a
  preallocated mono voice graph can be reused for a fresh voice without
  recompilation

Current graph node support:

- `Constant`
- `Oscillator`
- `Oscillator` in FM mode (`input0 >= 0`): reads frequency per-sample from input buffer
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
- `StereoDelay`
- `StereoMixDown`
- `Output`
- `StereoOutput`

Current runtime control support:

- `apply_control(GraphControl) -> Result[Unit, GraphControlError]` is the
  runtime-control entrypoint. Direct compiled mono/stereo graphs and their
  hot-swap/topology wrappers all return `Result[Unit, GraphControlError]` and
  report the specific rejection reason (`InvalidNodeIndex`, `OrphanNode`,
  `InvalidGateNode`, `InvalidSlotForNode`, `InvalidParamValue`,
  `MissingRuntimeState`) when a control is refused
- hot-swap and topology wrappers participate in the same `GraphControllable`
  trait surface; the trait returns `Result[Unit, GraphControlError]` so
  consumer code can be written generically over any controllable graph
- `apply_controls(Array[GraphControl]) -> Result[Unit, GraphControlError]`
  applies control batches transactionally in batch order while targeting nodes
  by authoring index. Preparation checks each intermediate value in preallocated
  per-node scratch, retaining final parameters and folded envelope gates.
  Adoption uses bound runtime targets without reinterpreting the raw batch.
- per-kind convenience methods on every wrapper:
  - `gate_on(node_index)` / `gate_off(node_index)` for `Adsr`
  - `set_param(node_index, slot, value)` for selected numeric params
    (`Gain`, `Clip`, `Biquad`, `Delay`, `Constant`, `Oscillator`, `Pan`,
    `StereoGain`, `StereoClip`, `StereoBiquad`, `StereoDelay`)
  - all return `Result[Unit, GraphControlError]` with the same rejection
    reasons as `apply_control(...)`
- `Delay` and `StereoDelay` now each expose a node-local feedback coefficient:
  `Value0 = feedback` and `DelaySamples = delay length`
- integration coverage now includes successful runtime `Biquad` retunes in
  compiled mono graphs for `LowPass`, `HighPass`, and `BandPass`
- the current graph tests also include directional runtime-retune assertions for
  `HighPass` and `BandPass`, not just output-difference checks
- accepted mono feedback graphs keep the existing supported runtime-control
  surface; coverage now includes direct `Gain` retunes and transactional
  `apply_controls(...)` batches inside a compiled `z^-1` loop, plus direct
  `Delay` and `Biquad` runtime-update equivalence checks against fixed feedback
  graph compiles
- stereo graph coverage now includes:
  - graph-unit checks for `Pan -> StereoOutput` shape enforcement
  - stereo post-processing through `StereoGain`, `StereoClip`, and
    `StereoBiquad`, plus `StereoDelay`
  - direct runtime updates for `Pan`, `StereoGain`, `StereoClip`, and
    `StereoBiquad`, plus `StereoDelay`
  - accepted mono `z^-1` feedback loops before `Pan`, including graph-unit
    gain-retune coverage and bounded block-persistence plus batched
    gain/pan-retune integration checks
  - end-to-end compiled stereo voice-path and batched-control integration tests
- mono graph coverage now includes explicit stereo fold-down through
  `StereoMixDown`, including stereo-filtered and stereo-delayed paths through
  `StereoBiquad` and `StereoDelay`
- mono graph coverage now also includes a bounded `z^-1` feedback recurrence in
  `Dsp`, direct self-feedback acceptance with zero-initialized state,
  a direct multi-back-edge fanout regression, runtime
  gain/delay/biquad/control-batch retunes on accepted loops, and rejection
  coverage for unsupported output/stereo cycles
- browser automation now also exercises the mono `Dsp` feedback path
  through the wasm-side stereo-init-failure fallback route, checking both the
  first-block `z^-1` recurrence preview and a live loop-gain retune in the
  AudioWorklet pipeline
- browser automation now also exercises the `StereoDsp` feedback path
  on the main browser wasm, checking the first-block center-pan recurrence of a
  mono `z^-1` loop before `Pan` plus live loop-gain retuning and directional
  pan behavior in the AudioWorklet pipeline

Current `set_param(node_index, slot, value)` support matrix:

| Node kind | Supported slots | Notes |
|-----------|-----------------|-------|
| `Constant` | `Value0` | Finite values only |
| `Oscillator` | `Value0` | Finite frequency values only |
| `Oscillator` (FM mode) | none | FM mode: frequency comes from input buffer, no runtime freq param |
| `Noise` | none | No runtime seed update yet |
| `Adsr` | `Value0`–`Value3` | Attack ms, decay ms, sustain level, release ms. Times must be finite and nonnegative; sustain is in `[0, 1]`. Parameter changes preserve stage and level; note-on applies settings before opening the gate. |
| `Biquad` | `Value0`, `Value1` | `Value0 = cutoff`, `Value1 = q`; validated against the compile-time sample rate |
| `Delay` | `Value0`, `DelaySamples` | `Value0 = feedback`; finite values in `[-0.99, 0.99]` only. `DelaySamples` requires exact integer values. Both are applied to the live `DelayLine` state |
| `Gain` | `Value0` | Finite gain only |
| `Mul` | none | No runtime params |
| `Mix` | none | No runtime params |
| `Clip` | `Value0` | Positive finite threshold only |
| `Pan` | `Value0` | Finite pan position only |
| `StereoGain` | `Value0` | Finite gain only |
| `StereoClip` | `Value0` | Positive finite threshold only |
| `StereoBiquad` | `Value0`, `Value1` | `Value0 = cutoff`, `Value1 = q`; validated against the compile-time sample rate |
| `StereoDelay` | `Value0`, `DelaySamples` | `Value0 = feedback`; finite values in `[-0.99, 0.99]` only. `DelaySamples` requires exact integer values. Both are applied to the live left/right `DelayLine` states |
| `StereoMixDown` | none | Fixed equal-weight fold-down: `0.5 * (left + right)` |
| `Output` | none | No runtime params |
| `StereoOutput` | none | No runtime params |

Current limits:

- stereo graph support is still narrow: terminal stereo remains
  `Pan -> stereo post-processing -> StereoOutput`, while mono graphs may now
  fold stereo back through `StereoMixDown`
- stereo post-processing remains intentionally small: the current effect slice
  is `StereoBiquad` plus `StereoDelay`, with no broader stereo mix/effect set
  yet
- feedback-edge insertion now uses a self-register model: stereo and
  mixed-shape feedback are accepted, and both `Dsp` and
  `StereoDsp` process feedback through a unified per-sample loop
  with self-registers rather than a separate linked-list infrastructure
- constant folding and dead-node elimination run exactly once inside
  `AnalyzedGraph::analyze(...)` via `optimize_graph()`; both optional and
  result-typed mono/stereo compile entry points receive the pre-optimized
  template and do not re-run the optimizer
- constant folding preserves runtime-control identity: an authoring control
  remains the same control kind when its dependencies are constant, so
  authoring-index controls and bindings continue to target their declared
  parameters. Barrier eligibility follows the canonical runtime-parameter
  policy rather than a separate list of control kinds. Pure arithmetic
  dependencies may still fold beneath retained controls, and ordinary
  dead-code elimination still removes genuinely unreachable nodes.
- separating authoring control identity from optimized sample execution remains
  an exploratory direction, not current behavior. See
  [`control-aware-partial-evaluation.md`](control-aware-partial-evaluation.md)
  for its invariants and evidence gates.
- `DspNode` and `AnalyzedGraph` equality are authoring/artifact equality,
  not DSP sample equality: `NaN` compares equal to `NaN`, `+0.0` compares equal
  to `-0.0`, and finite values otherwise compare structurally. This keeps
  invalid-but-unchanged authoring templates stable for future incr-backed
  last-good-template flows.
- `InsertChain` / `DeleteChain` topology edit variants support multi-node
  subgraph operations with stereo parity
- state preservation across topology edit recompilation is supported
- graph hot-swap is now narrow but no longer mono-only:
  `DspHotSwap` supports mono `Dsp` replacement and
  `StereoDspHotSwap` supports terminal-stereo `StereoDsp`
  replacement, both with block-boundary `queue_swap(...)` and optional
  equal-power crossfade
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
]).unwrap()
compiled.process(context, output)
```

`apply_controls(...)` returns `Result[Unit, GraphControlError]`; the
example uses `.unwrap()` for brevity, but real callers typically pattern
match on the specific rejection reason (`InvalidNodeIndex`,
`InvalidSlotForNode`, `InvalidParamValue`, etc.).

Current semantics:

- controls are evaluated in the array's batch order
- controls target nodes by original authoring index, not topo-sorted index
- `apply_controls(...)` is transactional:
  - if any control in the batch is invalid, none of them are applied
  - if the batch succeeds, all controls are committed before the next
    `process(...)` call
- `apply_control(...)` remains the single-message form of the same runtime API
- standalone control validation does not mutate audible graph state.
  Multi-voice effects instead use `BoundVoicePool::apply_voices_controls_result`:
  each selected handle and graph batch is prepared in selection order, then
  every target is adopted together. An earlier graph error takes precedence
  over a later stale handle, and any rejection leaves all voices unchanged.

This is enough for the current compiled mono and terminal-stereo graph paths to
support per-block parameter and gate updates from a host, UI, or future pattern
engine.

Current limits of the control-frame model:

- controls are still block-boundary updates, not sample-accurate events
- runtime-updatable slots are still limited to the support matrix above
- `GraphControl` still does not cover topology changes or stereo graph routing
  changes directly; hot-swap and the first topology-edit slice remain separate
  wrapper APIs in this phase

### 3.5.3 Pattern-to-DSP Control Binding

Pattern playback now has a bound voice-pool layer that keeps template validation
and control-key routing together. When Mini patterns drive externally authored
graph templates, `docs/mini-graph-authoring-boundary.md` defines the layer split:
Mini owns timing and `ControlMap` values, graph authoring owns topology and
control declarations, and the bridge selects a prepared template plus validated
bindings on the control side.

Current semantics:

- `VoicePool` is the low-level polyphonic mono-voice allocator and mixer
  with priority stealing, per-slot template snapshots, and per-voice pan gains
- `BoundVoicePool` owns both a `VoicePool` and the `ControlBindingMap` proven
  against that pool's current `AnalyzedGraph`
- `BoundVoicePool::new(...)` analyzes the template once, validates voice-pool
  requirements, and builds bindings against the same analyzed template
- `BoundVoicePool::set_template(...)` is transactional:
  - it analyzes and validates the replacement template first
  - it builds the replacement `ControlBindingMap` against that replacement
    template before mutating the live pool
  - if validation or binding fails, the previous template and bindings remain
    active
- `BoundVoicePool::note_on_controls(...)` accepts pattern/control-map values,
  resolves them through the current binding map, and delegates to the inner
  `VoicePool::note_on(...)`; hosts that already have a materialized
  graph-control batch may call `note_on_graph_controls(...)` to bypass the
  control-key map resolution layer. Stable-template hosts with a fixed four-
  parameter note-on layout may use `note_on_prevalidated_params4_id(...)` to
  reset a prepared graph, apply scalar parameters, set pan, and receive a packed
  primitive handle id without constructing graph-control batches.
- voice-control validation and application target already-sounding voices by
  active voice identifier; stale identifiers and invalid control changes are
  rejected without changing the voice-pool template or bindings
- result-returning voice mutators are the supported path for observing stale or
  invalid handle errors; allocation-conscious Bool predicates are available for
  host callback paths that have already validated their fixed control layout, and
  the old Bool wrappers remain only as deprecated compatibility shims that
  collapse any rejection to `false`
- `VoicePool` precompiles per-slot runtime graphs at construction time and
  `VoicePool::note_on(...)` resets/reuses a prepared graph when the selected
  slot still matches the current template generation; after `set_template(...)`,
  the generic graph-control note-on path can still lazily compile the replacement
  template on next reuse while already-sounding voices keep their prior compiled
  graph and ADSR snapshot. The prevalidated scalar note-on path instead requires
  a matching prepared slot and fails closed with a negative packed handle id if
  the slot is stale.
- `PatternScheduler` stores tempo, sample position, a `DspContext`, and active
  notes that pair each live `VoiceHandle` with a typed `VoiceOrigin`. Pattern
  origins carry a non-empty `PatternNodePath`; song origins always carry
  occurrence, section, and layer identity. Anonymous origins exist only for
  direct unsourced playback. The scheduler also owns optional active and pending
  `PlaybackSnapshot` values; it does not duplicate the pool's voice state or
  control bindings.
- `PatternScheduler::process_block(...)` takes a `BoundVoicePool`, expires old
  notes, queries the pattern for the current block arc, converts raw control
  maps through the scheduler's mapper, calls `note_on_controls(...)`, applies
  per-voice side effects such as pan and the single shared-send gain, then
  renders through the bound pool. The default mapper consumes `room` as a
  normalized `0..1` send; it is not a graph control and does not add reverb
  nodes to each voice.
- The browser note/chord template binds Mini `lpf` and `hpf` controls to each
  biquad's `Value0` cutoff slot. When `.lpf(hz, resonance)` or
  `.hpf(hz, resonance)` includes its optional second argument, the corresponding
  `lpf_resonance` or `hpf_resonance` control targets that filter's `Value1` Q
  slot. Omitting resonance preserves the template default Q of `0.707`; drum
  templates remain unbound and retain their authored filter shape.
- Quoted Mini notation lowers `~` to a silent sequence member: it emits no event
  but still occupies one equal subdivision of its containing layer. `Pat::gate`
  shortens each discrete event's `whole` and `part` spans to a rational
  `0..1` fraction while preserving onset and pattern period. Gate factors with
  a denominator above one billion are rounded to the nearest billionth before
  event arithmetic so later-cycle endpoints remain representable in the
  `Int64` rational timeline. The scheduler therefore closes the gate at that
  musical endpoint, and tempo edits retime the remaining deadline. An explicit
  `.hold(s)` remains a physical-duration envelope override and does not use the
  event-derived gate endpoint.
- Phase 6 incremental authoring adds a snapshot-swap layer over the same
  block-processing loop. `queue_pattern_snapshot` / `queue_song_snapshot`
  stage a lowered `PlaybackSnapshot` without changing playback immediately;
  `render_block` and `render_block_with_send` accept the latest queued snapshot
  at block start through one shared implementation. The former writes dry
  stereo; the latter also writes a post-pan, pre-master-gain stereo send using
  separate buffer arguments. Both advance the same transport once per successful
  block. Output buffers are overwritten without caller-side clearing and must
  have at least the configured block size and non-overlapping storage. If the
  next transport frame is unrepresentable, outputs are silenced and the queued
  snapshot remains staged; `last_transport_error()` reports the failure.
  Each changed material finishes its current source cycle before replacement;
  sounding voices retain deadlines. See [scheduler guide](../scheduler/README.mbt.md)
  for entry and identity rules. Multiple staged snapshots coalesce so the
  latest staged state wins.
- Reconciliation consumes already-lowered snapshots and classifies every
  material into an exclusive runtime state: current, waiting at a proven entry,
  changing at a proven entry, finishing current material with a skipped incoming
  occurrence, or skipped for this Play. Waiting/changing/finishing states always
  contain a concrete rational exit or entry boundary; absence of a boundary is
  not a pending transition and is never represented by a nullable due time.
- A newly added finite occurrence whose start is before the current transport
  position is skipped for the rest of that Play, even when one of its internal
  material-grid entries remains ahead. It never joins an occurrence midway.
  Resetting playback constructs fresh current states from the accepted snapshot.
- A later edit preserves a reserved boundary only while that boundary remains
  eligible for the replacement placement. Moving a waiting finite occurrence
  behind the transport reclassifies it as skipped. When current material must
  first reach its reserved exit, it finishes at that boundary while the moved
  incoming occurrence remains explicitly skipped; settlement cannot install it.
- `accepted_snapshot()` exposes the Pattern or Song selected at the most recent
  render-block boundary, while `queued_snapshot()` exposes the latest snapshot
  waiting for the next boundary. Both can be present simultaneously.
  `pending_material_change_count()` counts accepted changes waiting for a
  reserved entry; `skipped_material_change_count()` counts accepted finite
  changes that cannot enter during this Play. These facts do not imply transport
  activity or audio audibility.
- Sourced snapshot queries retain native pattern and song provenance through
  voice dispatch without converting records through a second wrapper array.
  Pattern and song selectors are separate types: `PatternVoiceScope` selects a
  pattern node, while `SongVoiceScope` selects an occurrence, section, or
  section-bounded layer.
- `ActiveVoiceEffect` makes active-note mutation explicit: `Release` gates off
  and detaches matching notes, `Kill` stops and detaches them immediately, and
  `Retune(VoiceControlBatch)` applies a statically non-empty control batch.
  Retune selects matching handles, then asks the bound pool to prepare all
  target updates before changing any voice.
  `queue_pattern_snapshot_effect_result(...)` and
  `queue_song_snapshot_effect_result(...)` stage replacement only after the
  selected effect succeeds, so invalid controls leave both voices and queued
  snapshot state unchanged. See `scheduler/README.mbt.md` for a checked
  end-to-end example.
- Effect calls return `ActiveVoiceEffectOutcome`. `retuned_voice_count` counts
  voices successfully controlled by Retune. `detached_note_count` counts note
  records removed from scheduler tracking by Release or Kill, not voices
  destroyed in the pool: a Release tail may still sound after detachment.
  Each effect leaves the other counter at zero.

This prevents a stale scheduler-owned binding map from being paired with a
voice pool after a template swap, and it removes the previous double
`optimize_graph(...)` pass from the voice-template path. The boundary type
makes single-optimize a static guarantee, not just a dynamic property —
`optimize_graph` is package-private and runs exactly once inside
`AnalyzedGraph::analyze`.

### 3.5.4 Host-independent graph engine

`engine/` owns the graph lifecycle API, re-exported by the root facade:
`GraphEngine`, `MountedGraph`, and the checked `GraphEngineError` type.
It depends on `graph/` and `dsp/`, not on browser APIs or global registries.

- Construct each engine with a `DspContext` and an optional positive capacity
  (default 16). Sample rate must be finite and positive; block size must be
  positive. Context and capacity failures raise `InvalidConfiguration`.
- `mount(Array[DspNode])` uses the canonical `AnalyzedGraph::analyze` /
  `Dsp::compile_result` crossing and returns a paused, typed handle.
  Compilation failure retains the underlying `GraphCompileError` in
  `GraphEngineError::InvalidGraph` and does not consume a slot.
- `MountedGraph::play` seals mount admission on its owning engine only.
  `pause` preserves DSP state; `unmount` detaches permanently and is idempotent.
  A retired handle cannot control a replacement that reuses its slot.
- `MountedGraph::apply_controls(Array[GraphControl])` applies the existing
  transactional compiled-graph control contract to that handle. Node indices
  are original authoring indices. A rejected batch leaves all controls
  unapplied and raises `GraphEngineError::ControlRejected` with the underlying
  `GraphControlError`. Handle lifecycle errors take precedence.
  Gate-off releases an ADSR envelope while processing continues; `pause` is
  not note-off because it freezes the release along with other DSP state.
- `process(output)` replaces the caller's buffer with the mono sum. Buffer
  length must match the context; mismatch is rejected before any state advance
  or buffer write. Successful processing reuses preallocated graph buffers.
- `close` drops compiled graphs and invalidates remaining handles with
  `EngineClosed`. Already-unmounted handles remain safely unmounted. There is
  no implicit relationship between the lifetimes of separate engines.
- Mounting, compilation, lifecycle mutation, and control batches occur outside
  processing. Calls are serialized by the caller; this is not a concurrent
  engine API. Live graph replacement, timestamped parameter automation, and
  scheduler integration are not added by this layer.

The browser adapter decodes its oscillator/gain/output/ADSR/biquad/multiply
JSON subset into canonical nodes in MoonBit, maps typed errors to a JSON error envelope, and
keeps integer handles only at the WASM boundary. JavaScript owns browser
resources, serialization, pending promises, and creation cancellation; it
does not compile graphs or decide the engine's mount/playing state.

### 3.6 Graph Hot-Swap

The current implementation provides narrow mono and terminal-stereo hot-swap
wrappers, plus a first mono topology-edit wrapper layered on top of mono
hot-swap:

Mono hot-swap example:

```moonbit
let old_template = AnalyzedGraph::analyze(old_nodes)
let new_template = AnalyzedGraph::analyze(new_nodes)
let active = Dsp::compile(old_template, context).unwrap()
let replacement = Dsp::compile(new_template, context).unwrap()
let hot_swap = DspHotSwap::from_graph(active, crossfade_samples=128)

hot_swap.queue_swap(replacement).unwrap()
hot_swap.process(context, output)
```

Stereo hot-swap example:

```moonbit
let old_template = AnalyzedGraph::analyze(old_nodes)
let new_template = AnalyzedGraph::analyze(new_nodes)
let active_stereo = StereoDsp::compile(old_template, context).unwrap()
let replacement_stereo = StereoDsp::compile(new_template, context).unwrap()
let hot_swap_stereo = StereoDspHotSwap::from_graph(
  active_stereo,
  crossfade_samples=128,
)

hot_swap_stereo.queue_swap(replacement_stereo).unwrap()
hot_swap_stereo.process(context, left_output, right_output)
```

```moonbit
let topology = DspTopologyController::from_nodes(
  old_nodes,
  context,
  crossfade_samples=128,
).unwrap()

topology
  .queue_topology_edit(
    GraphTopologyEdit::delete_node(
      gain_node,
      output_node,
      GraphTopologyInputSlot::Input0,
      gain_node,
    ),
  )
  .unwrap()
topology.process(context, output)
```

Current semantics:

- `DspHotSwap` owns one active mono `Dsp`
- `StereoDspHotSwap` owns one active terminal-stereo `StereoDsp`
- `DspTopologyController` owns authoring-order mono nodes plus an inner
  `DspHotSwap`
- `queue_swap(...) -> Result[Unit, HotSwapQueueError]` stages one replacement
  graph for the next `process(...)` call on direct mono/stereo hot-swap
  wrappers; reports `SampleRateMismatch` or `BlockCapacityMismatch` explicitly
- `queue_topology_edit(...) -> Result[Unit, GraphTopologyQueueError]` /
  `queue_topology_edits(...) -> Result[Unit, GraphTopologyQueueError]` apply
  an ordered `GraphTopologyEdit` batch to the stored authoring nodes,
  recompile a replacement graph, and stage that replacement through the inner
  hot-swap wrapper. The batch is transactional and reports `PendingSwap`,
  `InvalidEdit(index, reason)`, `RecompileRejected`, or a wrapped
  `HotSwapQueueError`
- `InvalidEdit(index, reason)` reports the zero-based edit position in the
  submitted batch and a stable `GraphTopologyEditError` reason such as invalid
  node/source indices, unsupported input slots, unsupported inserted node
  templates, invalid delete ranges, replacement sources inside a deleted chain,
  or delete shapes that are not unary/single-consumer chains
- topology-edit batches are transactional:
  - if any edit has an invalid authoring index, nothing is changed
  - if the edited node array fails recompilation, nothing is staged
  - `RewireInput` also rejects unsupported input slots for the targeted node
  - `InsertNode` also rejects unsupported unary template nodes
  - `DeleteNode` also rejects non-unary targets or delete shapes without a
    single deterministic downstream consumer
- replacement graphs must match the active graph's compile-time sample rate and
  block capacity
- `process(...)` runs only the active graph when no swap is pending
- when a swap is pending and `crossfade_samples > 0`, `process(...)` runs both
  graphs and mixes them with equal-power gains:
  - `old_gain = cos(t * π/2)`
  - `new_gain = sin(t * π/2)`
- when `crossfade_samples <= 0`, the swap is instantaneous on the next
  `process(...)` call
- the internal swap state is `Playing` or `Switching`; queueing constructs the
  completion state before rendering. Fade progress is mutable preallocated state,
  so completing either a cut or a crossfade does not allocate on the render path
- runtime `apply_control(...)` / `apply_controls(...)` target the active graph
  when no swap is pending
- during an in-flight crossfade, preparation checks the complete active batch,
  then the complete pending batch; adoption updates both graphs transactionally
  - if either graph rejects the control batch, nothing is applied
  - result-typed wrapper APIs return that rejection as `GraphControlError`
- topology controllers also mirror accepted runtime `set_param(...)` updates
  into their stored authoring-order nodes, so later `queue_topology_edit(...)`
  recompiles preserve the current parameter baseline instead of rebuilding from
  stale pre-control node values

Current limits:

- direct `queue_swap(...)` does not migrate history; it adopts the supplied
  replacement graph's existing state
- in-flight control mirroring requires both graphs to accept the same
  node-index / slot updates during the crossfade window
- topology edits support both single-node and multi-node operations:
  - `GraphTopologyEdit::replace_node(...)` swaps one authoring-order node
  - `GraphTopologyEdit::rewire_input(...)` retargets one existing input edge
  - `GraphTopologyEdit::insert_node(...)` appends one unary node and retargets
    one existing downstream input to it
  - `GraphTopologyEdit::delete_node(...)` removes one unary node and retargets
    one downstream input to a replacement upstream source
  - `GraphTopologyEdit::insert_chain(...)` inserts a chain of unary nodes
    between a source and a downstream input
  - `GraphTopologyEdit::delete_chain(...)` removes a contiguous chain of unary
    nodes and retargets the downstream input to a replacement source
  - all edit variants work for both mono and stereo topology controllers
  - non-deleting edit batches copy compatible state by authoring index and kind:
    oscillator phase, noise RNG, envelope progress, filter history, delay rings,
    and feedback registers. Old and replacement graphs own independent histories
  - destination envelope timing, filter configuration, and delay settings survive
    the copy. Delay history transfers only between equal-capacity buffers.
    Batches containing deletion retain the fresh-state policy
  - only one topology replacement may be staged at a time
- browser/AudioWorklet hot-swap proof is now narrow but present for both paths:
  the `browser/` wrapper exports dedicated mono `DspHotSwap` and
  terminal-stereo `StereoDspHotSwap` proof paths, and Playwright checks
  both the mixed crossfade block and the settled replacement block in the
  AudioWorklet pipeline
- browser queue/control paths route through the result-typed APIs and retain a
  last graph-error string/code for JavaScript callers:
  `get_browser_error_code()`, `get_browser_error_length()`, and
  `get_browser_error_char(i)`. The queue/process exports keep their boolean ABI
  and return `false` while the helper exports carry the specific
  `HotSwapQueueError`, `GraphTopologyQueueError`, or `GraphControlError`
  summary.
- browser/AudioWorklet topology-edit proof is now present for the mono slice:
  the `browser/` wrapper exports a dedicated `DspTopologyController`
  proof path, and Playwright checks an `InsertNode` / `DeleteNode` round-trip:
  - `queue_compiled_topology_edit()` explicitly queues the fixed unary insert
  - `queue_compiled_topology_delete_edit()` explicitly queues the matching
    unary delete back to the baseline graph
  - the first queued edit inserts one unary node with the expected mixed and
    settled rebuilt blocks, and the second queued edit deletes that node and
    returns the browser output to the original baseline shape
  - the browser proof also applies a live runtime gain control while the insert
    crossfade is already in flight, and Playwright checks that the mixed block
    reflects the mirrored control on both the active and pending rebuilt graphs
  - terminal-stereo parity now exists through a dedicated
    `StereoDspTopologyController` browser proof path, with Playwright
    checking the mixed and settled channel-shape transition from a queued
    stereo topology edit
  - the stereo browser proof also applies a live runtime level control while
    the queued pan-replacement crossfade is already in flight, and Playwright
    checks that the mixed left/right block reflects the mirrored control on
    both the active and pending stereo graphs

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

## 5. Node Type Reference

*(Historical architecture notes on prior art like kabelsalat are preserved under [`archive/prior-art-kabelsalat-analysis.md`](archive/prior-art-kabelsalat-analysis.md).)*

Minimum set needed for a useful synthesizer:

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
| `ADSR` | a_ms, d_ms, s, r_ms | stage, level, gate | Attack-Decay-Sustain-Release (times in ms) |

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
| `Gain` | amount | — | Volume control (with optional envelope buffer via input1) |
| `Pan` | position | — | Stereo panning |
| `Clip` | threshold | — | Hard clipping / distortion |

### Utility
| Node | Description |
|------|-------------|
| `Out` | Marks the final output node |
| `FeedbackRead` | Read from feedback register |
| `FeedbackWrite` | Write to feedback register |
| `Range` | Map [-1,1] to [min,max]: `(input + 1) / 2 * (max - min) + min` |
| `range()` | Composed `ArithSym` function — maps [-1,1] to [min,max] using arithmetic; no new enum variant |
| `lin_map()` | Composed `ArithSym` function — linear map from [in_min,in_max] to [out_min,out_max]; no new enum variant |

---

## 6. Glossary

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

### Browser Player ownership and source updates

The browser Player owns Current song, transport, routed material versions,
voices, output buffers, and the shared room. Clients submit source or transport
intent; they do not sequence public preparation tokens or mutate route state.
The resource owner still manages AudioContext creation and shutdown separately.

`clear_playback_input` / `push_playback_char` fill one UTF-16 input buffer.
Both `player_update_input()` and `player_restart_input()` consume it through the
same parser. A source may contain bindings, comments, an optional `bpm(number);`
declaration, and either a Pattern or `song(...)`. The source default is 60 BPM.
An arrangement may retain its embedded `bpm(...)` item, but declaring tempo
twice is an error. Patterns repeat; arrangements end unless followed by
`.repeat()`. `silence()` is an explicit silent Pattern.

Repeated arrangements must span at least one audio block at the accepted tempo
and sample rate. This bounds repetition splitting to at most two slices per
rendered block; shorter periods are rejected, not truncated or silently muted.
This is a bound on repetition overhead, not on arbitrary pattern/event density.
The same admission rule applies to source edits and the demo tempo control.

| Operation | Accepted behavior |
|---|---|
| Update | Replace Current song immediately, without rewinding. Changed materials enter at their safe boundaries. |
| Restart | Parse the submitted editor source first, then replace Current song, reset transport/voices/room, and start from zero. |
| Play | Start Ready or Ended Current song from zero; resume Paused from its frozen state; leave Playing unchanged. |
| Pause | Freeze transport, voices, effects, and material transitions while outputting silence. |

Update before the first Play produces Ready. Ended accepts a newer Current song
without starting or replacing the old release/effect tails; the next Play uses
the newer song. Play without a Current song fails. Invalid Update or Restart
leaves Current song, position, sounding state, and existing material reservations
unchanged. In particular, invalid editor text does not prevent Play from
resuming an already accepted song.

Operations return `0` for acceptance, `1` for an invalid/unrepresentable request,
and `2` when a Playing/Paused layout change requires Restart. The diagnostic is
available through `get_playback_error` and its length/character exports. Clients
use the status code, not diagnostic wording, to identify RestartRequired.
Owner acceptance completes during the command, including while Paused; it does
not wait for a rendered block.

Material transitions carry the retained source and a proven entry boundary.
Entering has no fictional current material. Later updates replace waiting
payloads without moving a still-valid reservation. Removing an unentered
addition cancels it immediately. Finite additions already underway or over are
Skipped, not Pending, and cannot join through a later material-grid entry.
Current song can therefore be newer than some sounding material versions.
Source identity and event origins remain attached to the actual retained
version. At a repetition boundary the latest song begins its next local cycle;
transport, voice releases, and the shared room are not reset.

Tempo parsing produces a validated `Tempo`. The owner calculates each proposed
clock and every musical note deadline once, before mutating any route. If any
route is unrepresentable, none changes. Applying the retained plans preserves
musical position; physical note deadlines stay fixed. Restart plans use a zero
anchor and clear voices after every route has accepted the plan.
The finite song endpoint is checked on the proposed clock before commit,
including Restart. Ready/Ended source updates check the future zero-anchored
clock without touching the old performance or tails.

Both worklets share `PlaybackController`. Commands are `player-update` and
`player-restart` with `{ id, text }`, or `player-play` and `player-pause` with
`{ id }`. IDs are positive safe integers. An immediate `player-receipt` reports
the ID, operation, acceptance, and complete owner projection: state,
`samplePosition`, `tempo`, `pendingCount`, and `skippedCount`. Rejections also
carry `message` and `restartRequired`. The dedicated scheduler worklet refreshes
the projection with `player-status` every 32 rendered quanta; the editor does
not poll it per sample. That worklet reports Ready only after graph initialization.

Numeric ABI states are 0 Empty, 1 Ready, 2 Playing, 3 Paused, 4 Ended, and 5
Fault. The live UI displays Empty as Ready and adds Starting only while opening
resources. Play/Pause and Restart are separate controls. Tempo belongs to the
source, not an independent UI input. Request receipts retain the submitted
source version so a delayed rejection cannot annotate newer editor text.
Pause during initial Starting cancels the pending start locally; no Pause command
is sent to an Empty Player and no accepted receipt is fabricated. Cancellation
uses `AbortError`, which the UI does not display as a playback failure.
Closing or failing the connection settles outstanding requests and retires
late replies. Startup Pause and `Player.close()` abort the opening capability:
fetch is cancelled, non-abortable native completions are observed but cannot
publish a graph, and owned partial resources are disconnected and closed.
Opening has one five-second deadline covering resume, fetch/body, compilation,
module loading, and readiness. Cancellation is `AbortError`; deadline expiry is
a visible initialization failure. Concurrent closes share retirement and a
subsequent Play waits for cleanup. Cleanup awaits the browser's native
`AudioContext.close()` promise; a browser that never settles that promise is
not given a false cleanup acknowledgement. The opening signal has no authority
over a session after successful activation.

`set_scheduler_bpm` remains a lower-level demo/probe control, returning 0 on
success and 1 on rejection. Its `set-scheduler-bpm` worklet message reports a
`tempo-updated` or `tempo-error` receipt with a request revision. It uses the same
all-route tempo plan, but is not part of the live Player command API.
`scheduler_bpm()` reports accepted tempo at the runtime's 0.001-BPM precision;
source updates replace a previous demo tempo, including the omission default.
Snapshots and preparation plans stay inside WASM.

The browser audio owner also owns exactly one stereo room reverb, outside all
routed voice pools. Each voice keeps one normalized send gain; every route
renders dry stereo plus a send pair, the host sums all sends, and the reverb is
processed once per block with fixed room settings. This is a dedicated shared
bus, not a generic effect graph: there are no per-part reverb instances,
multiple rooms, or event-controlled decay and damping. Its state is independent
of voice and authored-material identity, so tails survive note release, section
boundaries, and continuing live edits even when one contributing part is
replaced or stopped. Restart application clears the room state together with
transport and voices. Pause instead freezes the room without suspending the
AudioContext; Play resumes that same tail. Ended schedules no new finite-song
events while existing releases and room energy continue to render.
Parsing, lowering, and pattern queries still allocate in the audio owner.
The ownership contract does not promise glitch-free live editing or freedom
from underruns. Arbitrary seeks are outside this API.

Player admission bounds source construction and query expansion before accepting
a new performance. It evaluates the shared mini syntax and notation grammar,
including referenced bindings, future conditional transforms, scalar-control
cross-products, and the full-cycle child queries used by sequence. Arrangement
bounds account for overlap, minimum section length, and repeat-boundary splitting,
not the sum of every sequential section as though all played simultaneously.

| Admission resource | Limit |
|---|---|
| Source text | 8,192 UTF-16 code units |
| Expression AST | 512 nodes; nesting depth 32 |
| Lexical nesting / expanded query plan | 32 / 64 levels |
| Euclidean rhythm | 128 steps |
| Arrangement | 128 occurrences, including fills |
| Source and retained material entries | 256 per routed scheduler, including future occurrences and material awaiting replacement/removal |
| Candidate events | Conservative bound of 256 per source query window |
| Query work | 65,536 structural expansion/control-fold units |
| Composed exact-time factors | Numerator/denominator magnitude product at most 1,000,000,000 |

`PlaybackController` rejects oversized strings before its per-character WASM
transfer; MoonBit checks the same bound independently for direct callers.
Mini's whitespace parser and admission pre-scan share line/block comment scanning.
Unterminated block comments reject rather than accepting a valid source prefix;
bounded recursive descent also checks its own depth before descending.

The window comes from `Tempo::span_for_samples` at the actual sample rate and
block size, using the maximum supported tempo (1000 BPM). Demo tempo changes
therefore cannot bypass admission. The same canonical conversion checks repeat
periods without reconstructing millibpm in the browser host. Limits also apply
to intermediate expressions and can reject sources whose final transform would
reduce their cost. Direct Mini parsers remain unrestricted unless
`parse_play_source(..., max_query_span=Some(span))` is requested.

Source entry counts are checked even while Ready, before publication. For a live
Update, `accept_playback_all` prepares every route's proposed tempo, deadlines,
and reconciled material state before installing any of them. The 256-entry cap
covers the incoming snapshot as well as accumulated retained entries, not merely
the latest source or pending count. A rejected edit cannot partially retime an
earlier route. Capacity returns when retained entries reach their removal
boundaries; Restart checks the new source against an empty material state.
`PlaybackSnapshot::material_count` exposes the source count without consulting
the current play position. Lower-level unbounded scheduler APIs remain available.

Rejection retains the accepted source, voices, tempo, and position. The
[bounded-player measurements](performance/2026-09-16-player-bounds.json) record
the high-density reproduction, retained-state checks, and all 30 shipped source
examples. These limits bound supported workloads; they are not an AudioWorklet
deadline or allocation-free rendering guarantee.

The [2026-09-16 acceptance measurements](performance/2026-09-16-player-owner.json)
record page-local WASM Update and Restart p95 of 2.8 ms and 2.9 ms, respectively,
against a 2.667 ms audio quantum. They are not AudioWorklet deadline measurements.
The [62-group benchmark snapshot](performance/2026-09-16-player-owner-benchmarks.txt)
records the toolchain and shared-workstation conditions; neither run establishes
a speedup, regression, or glitch-free guarantee.

The [post-fix admission smoke](performance/2026-09-16-player-reliability.json)
checks rejected tiny repeats, rejected finite endpoints, and an exact one-block
repeat against release WASM. The
[post-fix benchmark snapshot](performance/2026-09-16-player-reliability-benchmarks.txt)
records the full suite separately; accepting a source still does not establish
a real-time deadline guarantee.

The [2026-09-17 review-fix measurements](performance/2026-09-17-player-review.json)
also run the actual scheduler AudioWorklet. With 40 alternating tempo edits of
the 12-section score, owner Update p95 was 11 ms against a 2.667 ms quantum.
Instrumented render p95 was 1 ms, but the worklet clock resolves only integer
milliseconds. Callback interarrival gaps reached 24 ms both with and without
edits because this headless configuration batches callbacks; those gaps do not
establish audible dropouts. The command timings still exceed one quantum: source
admission and retained-state bounds are not a hard-real-time guarantee.
The companion [62-group benchmark snapshot](performance/2026-09-17-player-review-benchmarks.txt)
records the full suite after the review fixes.

MoonBit async remains at the JS host lifetime boundary, not in the synchronous
AudioWorklet renderer. `packages/browser/host` already uses async 0.21.3:
`EngineLifetime.wait` bridges a cancellable Promise, while `close` uses
`protect_from_cancel` to finish cleanup. On 2026-09-16, an isolated async 0.22.1
task-group probe on moon 0.1.20260904 completed both children with the JS target;
the same program failed to build for wasm-gc with missing `run_async_main`.
The [upstream support table](https://github.com/moonbitlang/async#features)
also leaves wasm-gc unchecked. Compiler async syntax does not imply an available
embedding runtime. The runtime's
[cooperative scheduling model](https://github.com/moonbitlang/async#caveats)
does not move CPU work to another thread. Moving parse/lower work off the audio
thread requires a worker and an explicit transfer/commit boundary, not merely
marking the current methods async.
