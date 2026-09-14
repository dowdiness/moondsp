# Prior Art Analysis: kabelsalat / noisecraft

*Historical research note extracted from the early design phases of `moondsp`.*

This analysis covers key architecture lessons distilled from Felix Roos's [kabelsalat](https://codeberg.org/froos/kabelsalat) and Maxime Chevalier-Boisvert's [noisecraft](https://noisecraft.app/).

---

## 1. What kabelsalat Does

1. **DSL**: JavaScript with method chaining. `sine(200).mul(0.5).out()`
2. **Graph**: `Node` objects form a tree. Each node has `type` and `ins[]`.
3. **Compiler**: Flatten → topo sort → generate JS code string.
4. **Runtime**: Generated code runs in AudioWorkletProcessor via `new Function()`.
5. **Stateful nodes**: Each `AudioNode` (e.g., Sine) keeps its own state (phase, etc.). Stored in a `nodes[]` array, indexed by compiler-assigned ID.

---

## 2. Key Design Decisions and Their Rationale

| Decision | Rationale | Applicable to moondsp? |
|----------|-----------|------------------------|
| JS code generation | V8 JIT optimizes generated code better than interpreter loops | Not directly (MoonBit compiles ahead-of-time to Wasm/C). Use buffer-based processing. |
| Single-sample processing | Enables single-sample feedback (z⁻¹) | Yes. Some nodes need per-sample processing (oscillators with FM). |
| Flat node array + indices | Cache-friendly, no pointer chasing | Yes. Preallocated arrays in MoonBit. |
| Compile on main thread, run on audio thread | Compilation can be slow, audio thread has hard deadline | Yes. Exact same pattern. |
| AudioNode class with `update()` method | Each node type encapsulates its DSP + state | Yes. Use MoonBit structs with `process()` method. |
| Method chaining as DSL | Natural expression syntax, reduces parenthesis nesting | Tagless Final traits and method chains on Pattern / Mini. |

---

## 3. kabelsalat Limitations That moondsp Addresses

| Limitation | kabelsalat | moondsp |
|------------|-----------|---------|
| Type safety | None (JS dynamic types) | MoonBit static types, enums, pattern matching |
| Pattern engine | External (Strudel) | Built-in (`pattern/`) |
| Incremental updates | Full recompilation on every change | `incr` memoizes unchanged subgraphs |
| Collaboration | Not supported | CRDT-based (future roadmap) |
| Native target | C codegen (experimental) | MoonBit C/LLVM backend (first-class CLAP) |
| Voice management | Ad-hoc / difficult | Explicit polyphonic voice pool with priority stealing |

---

## 4. froos's Learning Journey (from garten.salat.dev)

The 120-post development blog reveals a progression that directly inspired the early phases of `moondsp`:

| Blog posts | Topic | moondsp phase |
|------------|-------|---------------|
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

**Key takeaway:** froos spent months on voice management (079-081) and described it as the hardest problem. `moondsp`'s dedicated `voice/` pool with priority stealing was explicitly architected to solve this deterministically without audio-thread allocation.
