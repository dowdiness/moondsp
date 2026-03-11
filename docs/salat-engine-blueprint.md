# Salat Engine — Project Blueprint

**A live-codable DSP audio engine in MoonBit, targeting browser and native.**

Version: 0.1 (draft)
Date: 2026-03-10

---

## 1. Vision

Build an audio engine where:

- **Patterns** describe *what* plays *when* (temporal structure, à la Strudel/TidalCycles)
- **DSP graphs** describe *how* it sounds (signal processing, à la kabelsalat/noisecraft)
- **Everything is incrementally recomputable** (via the `incr` library)
- **One codebase** targets browser (WebAudio/AudioWorklet), native (CLAP), and offline rendering

The unifying design principle is the **Incremental Hylomorphism Pipeline**: every system boundary follows the shape `external₁ ←(ana)→ internal ←(cata)→ external₂`, and `incr` memoizes each boundary crossing.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Interface                           │
│   Node-graph editor / Text REPL / Projectional editor           │
│   (DOM as rendering engine, React or plain HTML)                │
└───────────┬─────────────────────────────────┬───────────────────┘
            │ edit operations                  │ visualization data
            ▼                                  ▲
┌───────────────────────────────────────────────────────────────┐
│                    Pattern Engine                              │
│                                                               │
│   PatternSym trait (Finally Tagless)                          │
│   ┌──────────────┐    ┌──────────┐    ┌──────────────────┐   │
│   │ Pattern Graph │───▶│ replay() │───▶│ Pat (queryable)  │   │
│   │ (Source of    │cata│          │    │                  │   │
│   │  Truth)       │    └──────────┘    └────────┬─────────┘   │
│   └──────────────┘                              │ queryArc    │
│                                                 ▼             │
│                                     Array[Event[ControlMap]]  │
└─────────────────────────────────────────┬─────────────────────┘
                                          │
                            ControlMap = the contract
                                          │
                                          ▼
┌───────────────────────────────────────────────────────────────┐
│                      DSP Engine                               │
│                                                               │
│   DspSym trait (Finally Tagless)                              │
│   ┌──────────────┐    ┌────────────┐    ┌─────────────────┐  │
│   │ DspNode enum │───▶│ compile()  │───▶│ CompiledDsp     │  │
│   │ (declarative │    │ topo-sort  │    │ (process() per  │  │
│   │  graph)      │    │ + flatten  │    │  128 samples)   │  │
│   └──────────────┘    └────────────┘    └────────┬────────┘  │
│                                                  │           │
│   event_to_dsp: ControlMap → DspNode mutations   │           │
│                                                  ▼           │
│                                         Audio Samples        │
└─────────────────────────────────────────┬────────────────────┘
                                          │
                                          ▼
┌───────────────────────────────────────────────────────────────┐
│                   Platform Layer                              │
│                                                               │
│   ┌─────────────────┐  ┌──────────────┐  ┌───────────────┐  │
│   │ Web Audio       │  │ CLAP/VST3    │  │ Offline       │  │
│   │ AudioWorklet    │  │ (native)     │  │ Render        │  │
│   │ + wasm-gc/JS    │  │ + C backend  │  │               │  │
│   └─────────────────┘  └──────────────┘  └───────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

### Key Separation

| Concern | Engine | Rate | Update trigger |
|---------|--------|------|----------------|
| What plays when | Pattern Engine | User-edit time | Graph change |
| How it sounds | DSP Engine | Audio rate (~2.9ms) | Every render quantum |
| Where it runs | Platform Layer | Varies | Backend-specific |

The Pattern Engine operates at "human time" (user edits a pattern → re-query).
The DSP Engine operates at "audio time" (128 samples per callback at 48kHz).
These never share a hot path.

---

## 3. Design Principles

### 3.1 Incremental Hylomorphism Pipeline

Every transformation in the system is a hylomorphism: unfold input into an internal structure, then fold it into output. When the input changes, `incr` (Salsa-style memoization) ensures only the affected portion is recomputed.

```
Pattern Graph ──(cata: replay)──▶ Pat ──(query)──▶ Events
                                   │
                              incr Memo: only re-replay changed subtree
```

### 3.2 Finally Tagless / Two-Layer Architecture

- **Layer 1 (Abstract)**: Traits (`PatternSym`, `DspSym`) define the algebra. Each backend provides a different interpretation.
- **Layer 2 (Concrete)**: Enums (`PatternNode`, `DspNode`) provide a concrete AST for pattern matching, serialization, optimization.
- **`replay()`** bridges Layer 2 → Layer 1: walks the concrete AST and calls trait methods.

This gives open extensibility (new interpretations without modifying existing code) while retaining closed analysis (pattern matching on the enum for optimization).

### 3.3 No Allocation in the Audio Thread

The DSP hot path (called 48000/128 ≈ 375 times per second) must not:
- Allocate heap objects (triggers GC)
- Lock mutexes (blocks)
- Perform I/O
- Use unbounded algorithms

All DSP state is pre-allocated. Parameter changes arrive via `postMessage` or `SharedArrayBuffer` and are smoothed with one-pole filters.

### 3.4 Compile the Graph, Don't Interpret It

Lesson from kabelsalat/noisecraft: compiling the DSP graph into a flat sequence of operations (topologically sorted, with arithmetic inlined) is dramatically faster than interpreting a tree. The compiled form is JIT-friendly (V8) or AOT-friendly (native).

Start with an interpreter for prototyping, migrate to code generation when performance matters.

### 3.5 Small Trait-Only Packages

MoonBit's ecosystem is young. Avoid large foundation libraries. Each library (`incr`, `loom`, `seam`, `ecs`) defines its own traits. Shared traits (e.g., `JoinSemilattice`) are extracted only when cross-library interop is actually needed.

---

## 4. Core Libraries

| Library | Role | Status |
|---------|------|--------|
| `incr` | Signal/Memo incremental computation | Active development |
| `loom` | Parser framework | Active (6 defects identified) |
| `seam` | Language-agnostic CST / green-red tree | Active |
| `ecs` | Entity-Component-System | Phase 1 ready |
| **`salat-dsp`** | **DSP engine (this project)** | **Phase 1 complete, Phase 2 in progress** |
| **`salat-pattern`** | **Pattern engine** | **Design phase** |

---

## 5. Roadmap

### Phase 0 — Platform Proof (1-2 days)

**Question**: Can MoonBit wasm-gc generate audio in a browser AudioWorklet?

- Single sine oscillator, frequency controlled by slider
- MoonBit → wasm-gc → AudioWorkletProcessor → sound
- Record findings: GC behavior, export mechanics, import requirements
- Fallback path: MoonBit → JS backend if wasm-gc is problematic

**Deliverable**: `RESULTS.md` documenting platform viability + a working sine tone.

### Phase 1 — DSP Primitives (1-2 weeks)

**Question**: Can we build a minimal but useful set of DSP building blocks?

```
salat-dsp/
├── buffer.mbt       AudioBuffer (FixedArray[Double] wrapper)
├── context.mbt      DspContext (sample rate + block size)
├── osc.mbt          Sine, Saw, Square, Triangle (phase accumulator)
├── noise.mbt        Seeded white-noise source
├── filter.mbt       Biquad (LPF, HPF, BPF) — Bristow-Johnson cookbook
├── env.mbt          ADSR envelope
├── delay.mbt        Delay line (circular buffer, FixedArray)
├── gain.mbt         Scalar gain processor
├── mix.mbt          In-place mono buffer mixing
├── clip.mbt         Hard clipping / explicit range limiting
├── pan.mbt          Equal-power mono-to-stereo pan
├── smooth.mbt       One-pole parameter smoother
└── integration_test.mbt  End-to-end DSP chain coverage
```

The current implementation uses small, explicit structs and `process(...)`
methods instead of a shared `Processor` trait. All state lives in `mut` fields
or preallocated `FixedArray[Double]` buffers — no heap allocation during
processing.

**Deliverable**: Individual DSP blocks that pass unit tests (input buffer → expected output buffer).

### Phase 2 — Graph Compiler (1-2 weeks)

**Question**: Can we dynamically compose DSP blocks into a signal graph and hot-swap it?

```
DspNode enum  ──(flatten)──▶  Array[FlatNode]
              ──(topo-sort)──▶  sorted execution order
              ──(compile)──▶   CompiledDsp (process() function)
```

Current implemented surface:
- Declarative mono `DspNode` graph compiled into opaque `CompiledDsp`
- First terminal-stereo graph slice via `CompiledStereoDsp` for
  `Mono -> Pan -> StereoOutput`
- Topological sorting, graph validation, and runtime control for the current
  graph paths
- Integration coverage for compiled mono voice paths and runtime retuning
- See `docs/salat-engine-technical-reference.md` for the current node set,
  `set_param(...)` slot matrix, and exact runtime-control surface

Still planned in Phase 2:
- Single-sample feedback handling (cycles → insert z⁻¹ delay)
- Constant folding and dead node elimination
- Stereo post-processing after `Pan`
- Full multichannel graph semantics
- Graph hot-swap and crossfade on the audio thread

**Current deliverable**: compiled mono graph execution plus the first
terminal-stereo graph slice, both with runtime control and integration
coverage.

**Phase 2 exit deliverable**: `sine(2).range(200,400).sine().lpf(800,1).out()`
produces sound with graph hot-swap and feedback handling.

### Phase 3 — Voice Management (1-2 weeks)

**Question**: How do we handle polyphonic events where each voice has independent parameters?

This is the hardest unsolved problem (kabelsalat also struggled here).
Two candidate approaches:

- **A) Voice pool**: Pre-allocate N voice slots, each a compiled DSP graph instance. Events are assigned to free slots. ADSR release frees the slot.
- **B) ECS-based**: Each voice is an Entity. Components hold DSP state. Systems run the graph per-entity. Integrates naturally with the `ecs` library.

Evaluate both; choose based on prototype results.

**Deliverable**: Polyphonic synth — multiple overlapping notes with independent filter/envelope per voice.

### Phase 4 — Pattern Engine (2-3 weeks)

**Question**: Can we implement Strudel's pattern algebra in MoonBit?

```
salat-pattern/
├── time.mbt         Rational time (fraction-based, exact arithmetic)
├── arc.mbt          Time span [begin, end)
├── event.mbt        Event[A] = { arc, value }
├── pattern.mbt      Pat[A] = (Arc) -> Array[Event[A]] (query function)
├── combinators.mbt  sequence, stack, fast, slow, every, rev, ...
└── control_map.mbt  Map[String, Double] — the contract with DSP
```

The core insight from Strudel: `Pattern a = State → [Event a]`. A pattern *is* a function. Combinators wrap functions in functions. This is Church encoding / Finally Tagless.

**Deliverable**: `sequence(["c3","e3","g3"]).fast(2)` queries correctly over a time arc.

### Phase 5 — Pattern × DSP Integration (1-2 weeks)

Connect the two engines:

```
Pattern Engine                          DSP Engine
  Pat.queryArc(currentArc)
     │
     ▼
  Array[Event[ControlMap]]
     │
     ├─ { note: 60, cutoff: 800, ... }
     ├─ { note: 64, cutoff: 1200, ... }
     │
     ▼
  event_to_dsp()  ←── ControlMap catamorphism
     │                  (same shape as Serialize driving SerializerSym)
     ▼
  Voice allocation + DspNode construction
     │
     ▼
  CompiledDsp.process() → audio
```

**Deliverable**: Text pattern → audible polyphonic output in browser.

### Phase 6 — incr Integration (1-2 weeks)

Make pattern and DSP graph changes incremental:

- Pattern graph edit → `incr` Memo invalidates only changed subtree → re-replay → re-query
- DSP parameter change → `incr` Signal → smoother → audio thread
- Version tracking via `incr` Signals for ECS integration (Option C from `ecs` design)

**Deliverable**: Editing a pattern while audio plays — only changed voices re-trigger.

### Phase 7 — UI & Visualization (2-4 weeks)

- REPL with CodeMirror (text input → eval → pattern/DSP graph)
- Scope/waveform visualization (AudioWorklet → SharedArrayBuffer → Canvas)
- Pattern visualization (events on a timeline, Strudel-style)
- Optional: Node-graph editor (DOM as rendering engine, `incr` for dependency tracking)

### Phase 8 — Native Backend (2-4 weeks)

- MoonBit C/LLVM backend → CLAP plugin
- Same DSP code, different platform layer
- clap-wrapper / CPLUG for multi-format distribution (VST3, AU via wrapper)
- VOICEVOX Core integration for vocal synthesis (stretch goal)

### Phase 9 — Collaboration (future)

- `event-graph-walker` (FugueMax CRDT) for collaborative pattern editing
- Pattern graph CRDT (simpler than text CRDT — node/edge operations)
- Live coding sessions with multiple participants

---

## 6. Technology Choices

### Language & Targets

| Target | MoonBit Backend | Use |
|--------|----------------|-----|
| Browser DSP | wasm-gc (preferred) or JS | AudioWorkletProcessor |
| Browser UI | wasm-gc or JS | DOM manipulation |
| Native plugin | C or LLVM | CLAP/VST3 |
| Offline render | Any | File output |

### MoonBit-Specific Constraints

- **No HKT**: Use Finally Tagless with explicit generics, not `Functor`/`Monad`
- **No associated types**: Explicit generic type parameters on traits
- **No macros**: Manual `children()`/`map_children()` for tree traversals
- **No TypeId/downcast**: Dictionary passing, defunctionalization, closure-based workarounds
- **Trait objects (`&Trait`)**: Available for vtable dispatch where needed
- **Monomorphization**: Confirmed for trait-constrained generics — good for DSP inlining
- **`FixedArray`**: Pre-allocated, fixed-length — ideal for audio buffers
- **`ReadOnlyArray`**: Statically initialized on C/LLVM/Wasmlinear — good for lookup tables (wavetables, coefficient tables)
- **`#cfg(target=...)`**: Backend-specific code for FFI differences

### Audio-Specific Constraints

| Constraint | Solution |
|------------|----------|
| No GC in audio thread | `FixedArray`, primitive types, pre-allocation |
| No allocation in `process()` | Buffer pool, pre-compiled graph |
| Parameter smoothing | One-pole filter: `current += (target - current) * coeff` |
| Main ↔ Audio communication | `postMessage` (simple), `SharedArrayBuffer` + `Atomics` (low-latency) |
| Graph hot-swap | Compile on main thread, `postMessage` serialized graph, rebuild on audio thread |
| Sample rate | 48000 Hz (WebAudio standard) |
| Buffer size | 128 samples (WebAudio render quantum, ~2.67ms) |

### Key References

| Topic | Reference |
|-------|-----------|
| Build systems theory | Build Systems à la Carte (Mokhov et al.) |
| Incremental computation | Salsa framework, Adapton, Jane Street Incremental |
| Pattern algebra | Strudel (strudel.cc), TidalCycles, "The Art of the Fugue" (Weidner) |
| DSP graph compilation | noisecraft (Maxime Chevalier-Boisvert), kabelsalat (Felix Roos) |
| Audio DSL foundations | λmmm (lambda calculus for audio), FAUST, mimium-rs |
| Web audio architecture | Chrome AudioWorklet design patterns, WAM 2.0 spec |
| Green tree / CST | rowan / rust-analyzer architecture |
| CRDT | FugueMax / eg-walker (Gentle & Kleppmann) |
| Plugin format | CLAP, clap-wrapper, CPLUG |

---

## 7. Relationship to Other Projects

```
                        ┌─── incr (Signal/Memo) ───┐
                        │                           │
                        ▼                           ▼
    loom + seam ──── text DSL parsing      salat-pattern (query memoization)
    (parser infra)   (future: text REPL)   salat-dsp (parameter tracking)
                                                    │
                        ┌───────────────────────────┘
                        ▼
                   ecs (voice management, entity-per-voice)
                        │
                        ▼
               event-graph-walker (collaborative editing, future)
```

Each library is independently useful. The audio engine is the first project that integrates multiple libraries from the ecosystem. It serves as a proving ground for the `incr` + ECS + Finally Tagless combination.

---

## 8. Open Questions

Ranked by impact × uncertainty:

1. **wasm-gc in AudioWorklet**: Does it work without GC pauses? (Phase 0 answers this)
2. **Voice allocation strategy**: Pool vs ECS? (Phase 3 evaluates both)
3. **Graph hot-swap latency**: Can we recompile and crossfade within one render quantum? (Phase 2)
4. **Feedback resolution**: How to detect cycles and insert z⁻¹ automatically? (Phase 2)
5. **ControlMap type safety**: String-keyed map vs typed record vs enum? (Phase 5)
6. **`incr` integration granularity**: Per-node memoization vs per-subtree? (Phase 6)
7. **Multichannel expansion**: Full SuperCollider semantics or simplified subset? (Phase 2)
8. **`fast` query semantics**: Exact time dilation logic for arc transformation (Phase 4)
9. **CRDT for node graphs**: What operations need to be conflict-free? (Phase 9)
10. **CLAP integration**: MoonBit C backend maturity for real-time native code (Phase 8)

---

## 9. Success Metrics

| Milestone | Metric |
|-----------|--------|
| Phase 0 | Sine wave plays in browser from MoonBit code |
| Phase 1 | Core DSP primitives and integration tests pass on wasm-gc and js |
| Phase 2 | 50+ node DSP graph runs without dropout at 48kHz |
| Phase 3 | 16-voice polyphony without GC pauses |
| Phase 5 | `s("bd sd hh sd").fast(2)` plays a beat |
| Phase 7 | Usable as a live coding instrument at a performance |
| Phase 8 | Same patch runs as CLAP plugin in a DAW |

---

## Appendix A: Naming

Working title: **Salat Engine** (a nod to kabelsalat / "cable salad" / tangled wires).

Packages:
- `salat-dsp` — DSP engine
- `salat-pattern` — Pattern engine  
- `salat-web` — Browser platform layer
- `salat-native` — Native platform layer (CLAP)

---

## Appendix B: Prior Art Comparison

| System | Language | Graph Compilation | Pattern Engine | Incremental | Collab |
|--------|----------|-------------------|---------------|-------------|--------|
| kabelsalat | JS | JS codegen / C codegen | — (separate: Strudel) | No | No |
| noisecraft | JS | JS codegen (JIT-optimized) | — | No | No |
| Strudel | JS/TS | Web Audio nodes / supradough | Yes (Tidal port) | No | No |
| FAUST | Custom DSL | FIR → C/LLVM/Wasm | — | No (full recompile) | No |
| Cmajor | Custom DSL | LLVM JIT | — | Hot reload | No |
| Elementary Audio | JS | Graph diff/reconcile | — | Yes (React-style) | No |
| **Salat Engine** | **MoonBit** | **Topo-sort + compile** | **Yes (built-in)** | **Yes (incr)** | **Yes (CRDT, future)** |

The unique combination is: **type-safe MoonBit + integrated pattern engine + incremental computation + CRDT collaboration**, all from a single codebase targeting both browser and native.
