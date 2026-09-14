# moondsp

A portable, live-codable DSP audio and pattern engine written in [MoonBit](https://www.moonbitlang.com/).

> **Patterns describe *what* plays *when*; DSP graphs describe *how* it sounds.**  
> moondsp combines a Strudel/TidalCycles-inspired pattern algebra with a compiled, zero-allocation signal-processing graph and a polyphonic voice pool — designed to target **browser (Web AudioWorklet via `wasm-gc`)**, **native DAWs (CLAP via C ABI)**, and **headless CLI / host-independent embedded execution** from a single unified codebase.

---

## Target Platforms

`moondsp`'s core DSP, graph compilation, and pattern scheduling are completely platform-agnostic and free of browser or host globals. The engine compiles to multiple targets:

- 🌐 **Browser (Web AudioWorklet)**: Compiled via `wasm-gc` for high-performance, glitch-free in-browser live coding and synthesis.
- 🎛️ **Native DAWs (CLAP Plugin Prototype)**: Native shared library via MoonBit's C ABI shim, compatible with modern DAWs (passes `clap-validator`).
- 🖥️ **Host-Independent MoonBit API**: Direct programmatic audio synthesis in pure MoonBit via `GraphEngine` — embeddable into games, tools, or custom runtimes.
- 💻 **CLI & Offline Rendering**: Headless command-line entry point for audio rendering, batch synthesis, and automated tests.

---

## Quick start

```bash
# Verify & test the core engine across targets
NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test

# Run CLI entry point
NEW_MOON_MOD=0 moon run cmd/main
```

*(Note: `NEW_MOON_MOD=0` preserves the repository's hand-maintained `moon.mod`)*

### 1. Run in Browser (Web AudioWorklet via `wasm-gc`)
```bash
NEW_MOON_MOD=0 moon build --target wasm-gc
# Start any local HTTP server (AudioWorklet requires an HTTP origin)
python3 -m http.server 8000
# Open http://localhost:8000/web/ in your browser
```

### 2. Build Native CLAP Plugin Prototype
```bash
scripts/build-clap-prototype.sh     # Build Linux CLAP prototype shared object
scripts/smoke-clap-prototype.sh     # dlopen / process smoke test
scripts/validate-clap-prototype.sh  # Run clap-validator against the build
```

---

## Host-Independent MoonBit API

`GraphEngine` is a platform-independent MoonBit API, requiring no JavaScript wrappers, JSON serialization, or browser globals. Each engine instance manages its mounted graphs and render context directly using canonical `DspNode` values:

```mbt check
///|
test {
  let context = @moondsp.DspContext::DspContext(
    sample_rate=48000.0,
    block_size=128,
  )
  let engine = @moondsp.GraphEngine::GraphEngine(context)
  let sound = engine.mount([
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 375.0),
    @moondsp.DspNode::gain(0, 0.1),
    @moondsp.DspNode::output(1),
  ])
  let output = context.make_buffer()
  sound.play()
  engine.process(output)
  assert_true((output.get(32) - 0.1).abs() < 0.000001)
  sound.pause()
  sound.unmount()
  engine.close()
}
```

Operations raise the checked `GraphEngineError` type. Compilation happens ahead of time during mount, guaranteeing **zero allocation** during `process()`.

For browser integration, `web/graph-engine.js` adapts this engine to AudioWorklet and Promise-based JavaScript APIs. See [the browser contract](docs/browser-api-contract.md).

---

## How it works

The engine bridges high-level musical structure to low-level audio signals through an exact rational-time control bridge:

```text
Pattern Engine (Human Time)           DSP Engine (Audio Time)
  Pat.query(arc)                        CompiledDsp.process(ctx, buf)
       |                                      |
       v                                      v
  Array[Event[ControlMap]]             BoundVoicePool.process(ctx, L, R)
       |                                      ^
       +-- { note: 60, cutoff: 800 } ---------+
           PatternScheduler.process_block (48 kHz / 128 samples per block)
```

- **Pattern layer**: Operates in musical cycles using exact fractions (`Rational`) — zero floating-point timing drift. Combinators like `fast`, `slow`, `rev`, `sequence`, `stack`, and `every` compose complex polyrhythms.
- **DSP layer**: Declarative signal graphs compile into flat topological execution plans. Hard real-time: **zero allocations** in the audio thread (2.67 ms budget per block at 48 kHz / 128 samples).
- **Bridge**: `scheduler/` queries pattern events per audio block and dispatches note lifecycles and parameter updates to the voice pool through validated template bindings.

---

## Features & Code Examples

### 1. Mini-notation Parser (`mini/`)
Write expressive polyrhythmic patterns in a concise DSL ([Syntax Reference](docs/mini-notation.md)):

```moonbit nocheck
// Mini-notation with Euclidean rhythms, polyphonic layers ($:), and method chains
let pat = parse_mini!(r#"
  $: s("bd(3,8) [~ sd] [hh*2] sd").fast(2).gain(0.8)
  $: note("c3 e3 g3 b3").cutoff(1200)
"#)
```

Supports sub-groups (`[a b]`), step replication/stretching (`*n`, `/n`), Euclidean rhythms (`bd(3,8)`), and chained modifiers (`.fast()`, `.slow()`, `.rev()`, `.degradeBy()`, `.cutoff()`, `.gain()`, `.pan()`, `.every()`, `.jux()`).

### 2. Finally Tagless DSP Algebra (`dsp/`, `graph/`)
The DSP graph definition functions both as an extensible trait-driven algebra and as an optimizable concrete AST:

```moonbit nocheck
///|
/// FM Synthesis patch: LFO sweeps carrier frequency through a low-pass filter
fn[T : FilterSym] fm_synth() -> T {
  let lfo = DspSym::oscillator(ArithSym::constant(2.0), Waveform::Sine)
  let freq = range(lfo, 200.0, 400.0)
  let carrier = DspSym::oscillator(freq, Waveform::Sine)
  let filtered = T::biquad(carrier, BiquadMode::LowPass, 800.0, 1.0)
  DspSym::output(DspSym::gain(filtered, 0.3))
}
```

- **DSP Primitives**: Sine/saw/square/triangle oscillators, white noise, ADSR envelopes, biquad filters (LPF/HPF/BPF), delay lines with feedback, gain, mix, hard clip, and equal-power pan.
- **Runtime Graph Hot-Swap & Topology Editing**: Equal-power crossfades between different graphs on the fly; insert, replace, and remove nodes without audio dropouts.

### 3. Polyphonic Voice Pool (`voice/`)
- 32+ simultaneous voices with deterministic priority stealing (`idle` > `oldest releasing` > `oldest active`).
- Generation-tagged handles prevent stale note control across voice reuse.
- Two-stage silence detection (ADSR idle AND output buffer silent).
- Per-voice equal-power stereo panning.

---

## Repository layout

The codebase strictly decouples platform-agnostic core engines from platform-specific host adapters:

```text
├── dowdiness/moondsp   Library public API facade (re-exports dsp, graph, engine, voice, identity)
│
├── Core Engine (Platform-Agnostic)
│   ├── dsp/            DSP primitives, filters, oscillators, Finally Tagless algebra
│   ├── graph/          Compiled graph runtime, topology editing, hot-swap, control binding
│   ├── engine/         Host-independent graph lifecycle, typed handles, mono mixing
│   ├── voice/          Polyphonic voice pool with priority stealing and stereo mixdown
│   ├── identity/       Stable ID wrappers and revision tokens for incremental editing
│   ├── pattern/        Pattern engine: rational time, combinators, and control maps (zero DSP dep)
│   ├── mini/           Mini-notation parser: text expressions to Pat[ControlMap]
│   ├── song/           Long-form section scaffolding with identity TimeScope
│   └── scheduler/      Bridges pattern events to voice pool and DSP parameter binding
│
├── Platform Adapters & Frontends
│   ├── browser/        AudioWorklet export wrapper and multi-pool routing (wasm-gc)
│   ├── web/            Browser demo UI and AudioWorklet processor
│   ├── browser_test/   Browser integration test wrapper (Playwright)
│   ├── clap_engine/    Native CLAP synth engine core around graph + voice pool
│   ├── clap_host/      Primitive integer-handle bridge for C CLAP shims
│   ├── clap_plugin/    Native CLAP prototype payload and C ABI shim (passes clap-validator)
│   └── cmd/main/       CLI entry point and offline experiments
│
└── docs/               Architecture blueprint, technical reference, ADRs, performance snapshots
```

---

## Performance

The audio callback budget at 128 samples / 48 kHz is **2.67 ms per block**. `moondsp` is engineered around strict real-time constraints:
- A single compiled voice (oscillator + filter + delay + ADSR) processes in the **low-microsecond range**.
- 32 simultaneous FM voices process comfortably within a fraction of the block budget.
- Graph compilation and hot-swap crossfades are microsecond-scale, enabling glitch-free live graph reconfiguration.

Historical and current benchmark records are preserved under [`docs/performance/`](docs/performance/).

---

## Development

```bash
# Type-check all targets with warnings denied
NEW_MOON_MOD=0 moon check --target all --deny-warn

# Run the test suite on all targets
NEW_MOON_MOD=0 moon test --target all --deny-warn

# Test specific packages
NEW_MOON_MOD=0 moon test -p dowdiness/moondsp
NEW_MOON_MOD=0 moon test -p pattern

# Format code and regenerate interfaces
NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt

# Run microbenchmarks
NEW_MOON_MOD=0 moon bench --release -p dowdiness/moondsp/graph -f graph_benchmark.mbt

# Run Playwright browser integration tests (builds wasm-gc first)
npm run test:browser
```

The project follows an incremental edit discipline: run `NEW_MOON_MOD=0 moon check` after edits and resolve errors before proceeding.

---

## Documentation

Start at the **[docs index](docs/README.md)**, which categorizes materials by role:

- **[Technical reference](docs/technical-reference.md)** — Node types, parameter slots, runtime control surface (authoritative for graph runtime-control behavior)
- **[Mini-notation guide](docs/mini-notation.md)** — Pattern syntax, grouping, and method chaining
- **[Blueprint](docs/blueprint.md)** — Complete architectural vision, design principles, and multi-target roadmap
- **[Architecture decisions (ADRs)](docs/decisions/)** — Short records explaining why key architectural choices were made
- **[Next actions](docs/next-actions.md)** — Active handoff list for upcoming priorities
- **[`CLAUDE.md`](CLAUDE.md)** — Project conventions and contributor cheat sheet

---

## Project status

| Phase | Status | Summary |
|:---|:---|:---|
| **0 — Platform proof** | Complete | MoonBit `wasm-gc` runs in browser AudioWorklet |
| **1 — DSP primitives** | Complete | Oscillators, filters, envelopes, delay, pan, clip |
| **2 — Graph compiler** | Complete | Compiled graphs, hot-swap, topology editing, stereo |
| **3 — Voice management** | Complete | 32+ voice pool with priority stealing & stereo mix |
| **4 — Pattern engine** | Complete | Rational time, combinators, ControlMap |
| **5 — Pattern × DSP** | Complete | `scheduler/` + `mini/` wire pattern events to voice allocation |
| **6 — incr integration**| In progress | Stable identity plus initial pattern/song authoring groundwork |
| **7+ — Native & Frontends**| Prototype | Browser live UI & CLAP plugin prototype available; DAW production gates underway |

---

## Acknowledgments & Prior Art

`moondsp` builds upon concepts pioneered by several remarkable open-source projects in computer music, live coding, and audio synthesis:

- **[kabelsalat](https://codeberg.org/froos/kabelsalat)** by Felix Roos (`froos`) — Demonstrated high-performance DSP graph compilation and real-time execution in Web AudioWorklet. The project's early working title *Salat Engine* was a nod to this work.
- **[Noisecraft](https://noisecraft.app/)** by Maxime Chevalier-Boisvert — Pioneer in topological DSP graph flattening and in-browser visual synthesis.
- **[Strudel](https://strudel.cc/)** & **[TidalCycles](https://tidalcycles.org/)** by Alex McLean, Felix Roos, and the live coding community — Foundational models for rational-time queryable pattern algebra, cyclic arcs, and mini-notation.
- **[FAUST](https://faust.grame.fr/)** & **[mimium](https://mimium.org/)** — Inspiration for functional audio signal processing and tagless DSP algebra.
- **[CLAP](https://cleveraudio.org/)** (Clever Audio Plug-in) — The modern, open native audio plugin standard enabling DAW integration beyond the browser.

---

## License

[Apache-2.0](LICENSE)
