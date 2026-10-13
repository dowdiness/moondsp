# moondsp — Engine Architecture & Technical Details

This document covers the internal design, runtime contracts, package organization, and development workflows for the `moondsp` audio engine.

For user-focused application concepts, creative goals, and workspace usage, see the [main README](../README.md).

---

## Target Platforms

`moondsp`'s core DSP, graph compilation, and pattern scheduling are completely platform-agnostic and free of browser or host globals:

- **Browser (Web AudioWorklet via `wasm-gc`)**: Compiled via `wasm-gc` for in-browser live coding and real-time synthesis. Automated tests cover rendered PCM, resource lifecycle, and atomic control updates.
- **Native DAWs (CLAP Plugin Prototype)**: Native shared library via MoonBit's C ABI shim. It passes `clap-validator`; real host/DAW loading, stable bridge symbols, and an audio-thread allocation audit remain production gates.
- **Host-Independent MoonBit API**: Direct programmatic audio synthesis in pure MoonBit via `GraphEngine` — embeddable into games, tools, or custom runtimes without JavaScript or WebAudio.
- **CLI & Offline Rendering**: Headless command-line entry point for audio rendering, batch synthesis, and automated tests.

---

## How It Works

The engine bridges high-level musical structure to low-level audio signals through an exact rational-time control bridge:

```text
Pattern Engine (Human Time)           DSP Engine (Audio Time)
  Pat.query(arc)                        Dsp.process(ctx, buf)
       |                                      |
       v                                      v
  Array[Event[ControlMap]]             BoundVoicePool.process(ctx, L, R)
       |                                      ^
       +-- { note: 60, lpf: 1800, hpf: 80 } --+
           PatternScheduler.process_block (48 kHz / 128 samples per block)
```

1. **Pattern Layer (`pattern/`)**:
   - Operates in musical cycles using exact fractions (`Rational`) — zero floating-point timing drift.
   - Combinators like `fast`, `slow`, `rev`, `sequence`, `stack`, and `every` compose complex polyrhythms.
2. **DSP Layer (`dsp/`, `graph/`)**:
   - Declarative signal graphs compile into flat topological execution plans with preallocated render buffers.
   - At 48 kHz / 128 samples, the callback budget is 2.67 ms.
3. **Bridge (`scheduler/`)**:
   - Queries pattern events per audio block and dispatches note lifecycles and parameter updates to the voice pool through validated template bindings.

---

## Host-Independent MoonBit API

`GraphEngine` is a platform-independent MoonBit API, requiring no JavaScript wrappers, JSON serialization, or browser globals. Each engine instance manages its mounted graphs and render context directly using canonical `DspNode` values:

```moonbit
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
sound.pause()
sound.unmount()
engine.close()
```

Operations raise the checked `GraphEngineError` type. Mount compiles the graph and prepares its buffers before `process()` renders it.

For browser use, `web/graph-engine.js` adapts this engine to AudioWorklet and Promise-based methods. Its JSON subset accepts oscillator, gain, output, ADSR, biquad, and multiply nodes; `applyControls` exposes atomic parameter and gate updates. See [the browser contract](browser-api-contract.md).

---

## Core Engine Features

### 1. Mini-notation Parser (`mini/`)
Converts concise string notation into queryable pattern streams ([Syntax Reference](mini-notation.md)):

```moonbit
let pat = parse_mini!(r#"
  $: s("bd(3,8) [~ sd] [hh*2] sd").fast(2).gain(0.8)
  $: note("c3 e3 g3 b3").gain(0.6).lpf(1800, 2).hpf(80)
"#)
```

Supports sub-groups (`[a b]`), step replication/stretching (`*n`, `/n`), Euclidean rhythms (`bd(3,8)`), and chained modifiers (`.fast()`, `.slow()`, `.rev()`, `.degradeBy()`, `.lpf(hz, resonance?)`, `.hpf(hz, resonance?)`, `.gain()`, `.pan()`, `.every()`, `.jux()`).

### 2. Tagless DSP Algebra (`dsp/`, `graph/`)
The DSP graph definition functions both as an extensible trait-driven algebra and as an optimizable concrete AST:

```moonbit
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

## Package Map & Architecture

```text
Musical authoring and playback:
[ mini ] → [ pattern / song ] → [ scheduler ] → [ voice ] → [ graph ] → [ dsp ]

Host-controlled graph playback:
[ browser / custom host ] → [ engine ] → [ graph ] → [ dsp ]

Shared authoring identity:
[ identity ] → [ pattern ]
             → [ song ]
             → [ graph ]
```

### Core Engine (Platform-Agnostic)

| Package | Role & Responsibility | Key Types / Entry Points |
|---|---|---|
| [`dsp/`](../dsp/README.mbt.md) | Sample buffers, oscillators, envelopes, biquad filters, delay lines, gain, clip, pan, and tagless DSP traits | `DspContext`, `AudioBuffer`, `Oscillator`, `Adsr`, `Biquad`, `DelayLine`, `Pan`, `ArithSym`, `DspSym` |
| [`graph/`](../graph/README.mbt.md) | DAG compilation, topological sorting, runtime controls, block-boundary hot-swap, and topology editing | `DspNode`, `AnalyzedGraph`, `Dsp`, `StereoDsp`, `GraphControl`, `DspHotSwap`, `GraphDocument` |
| [`engine/`](../engine/README.mbt.md) | Host-independent graph lifecycle management, typed mount handles, and multi-graph mono buffer mixing | `GraphEngine`, `MountedGraph`, `GraphEngineError` |
| [`voice/`](../voice/README.mbt.md) | Polyphonic voice pool with priority voice stealing, generation handles, ADSR lifecycle, and equal-power stereo panning | `VoicePool`, `BoundVoicePool`, `VoiceHandle`, `VoiceState`, `NoteGate` |
| [`identity/`](../identity/README.mbt.md) | Type-safe stable node identifiers and monotonic revision tokens for structural live-editing trees | `GraphNodeId`, `PatternNodeId`, `SectionId`, `SectionLayerId`, `OccurrenceId`, `Revision` |
| [`pattern/`](../pattern/README.mbt.md) | Queryable musical pattern algebra with exact `Rational` time, polyrhythmic combinators, and `ControlMap` events | `Pat[A]`, `Rational`, `TimeSpan`, `Event[A]`, `ControlMap`, `sequence`, `stack`, `merge_control`, `PatternDoc` |
| [`mini/`](../mini/README.mbt.md) | Mini-notation parsing, causal draft editing, and frozen playback inputs with exact pattern origins | `parse`, `parse_song`, `parse_song_with_bpm`, `parse_doc`, `parse_snapshot`, `Draft`, `PlaybackInput` |
| [`song/`](../song/README.mbt.md) | Macro-level musical structure arranging patterns into length-bounded sections, layers, parts, and local `TimeScope` | `Song[A]`, `Section[A]`, `SongPart[A]`, `TimeScope`, `SongDoc[A]`, `SongSnapshot[A]` |
| [`scheduler/`](../scheduler/README.mbt.md) | Audio block quantization, tempo clock, note lifecycle tracking, and voice-scope reconciliation | `PatternScheduler`, `PlaybackSnapshot`, `BlockFrame`, `PatternVoiceScope`, `SongVoiceScope` |

### Platform Adapters & Native Scaffolding

| Package / Directory | Role & Responsibility | Key Files / Entry Points |
|---|---|---|
| [`browser/`](../browser/README.md) | AudioWorklet export ABI and WASM-to-JS transport adapter (128-frame quantum, JSON decoding, named params) | `graph_host_*`, `scheduler_*`, `get_browser_*`, `browser_abi.baseline` |
| [`packages/browser/`](../packages/browser/README.md) | Local distribution bundle for `@moondsp/browser` (TypeScript declarations, JS API wrapper, processor, release Wasm) | `GraphEngine`, `GraphDescription`, `GraphControl` |
| [`examples/basic-synth/`](../examples/basic-synth/README.md) | Shared synth core with framework-free TypeScript and Svelte 5 UI adapters | `AudioView`, `AudioActions`, `App.svelte`, `startApplication` |
| [`clap_engine/`](../clap_engine/README.mbt.md) | Polyphonic subtractive synth engine core tailored for CLAP plugins (preallocated voices, note ID / wildcard matching) | `ClapSynthEngine`, `CLAP_PARAM_*`, `default_synth_template` |
| [`clap_host/`](../clap_host/README.mbt.md) | Flat primitive integer-handle C-ABI bridge exposing scalar getters/setters without object leaking | `engine_create`, `engine_destroy`, `engine_note_on`, `engine_process`, `engine_set_param` |
| [`clap_plugin/`](../clap_plugin/README.md) | Native CLAP plugin payload, C ABI shim, build scripts, and `clap-validator` automation | `moondsp_clap.c`, `moondsp_clap_moonbit.h`, `clap_payload.mbt` |
| [`cmd/main/`](../cmd/main/) | Headless CLI entry point for testing, batch rendering, and offline experiments | `cmd/main/main.mbt` |

---

## Repository Layout

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
│   ├── packages/browser/       Packaged JS/TS API, Worklet, and release Wasm
│   ├── packages/browser/host/  Separate JS-target MoonBit lifetime binding
│   ├── examples/basic-synth/   Shared core with vanilla and Svelte adapters
│   ├── clap_engine/    Native CLAP synth engine core around graph + voice pool
│   ├── clap_host/      Primitive integer-handle bridge for C CLAP shims
│   ├── clap_plugin/    Native CLAP prototype payload and C ABI shim (passes clap-validator)
│   └── cmd/main/       CLI entry point and offline experiments
│
└── docs/               Architecture blueprint, technical reference, ADRs, performance findings
```

---

## Performance & Audio-Thread Contract

The audio callback budget at 128 samples / 48 kHz is **2.67 ms per block**.
Graph compilation and buffer preparation happen before playback.

Benchmark results depend on the graph, target, toolchain, host, and measurement method; measured findings and limits are summarized under [`docs/performance/`](performance/README.md).

- **Design requirement**: Audio rendering is designed around pre-allocated buffers without allocation in the hot sample path.
- **Measured scope**: The [Wasm-GC sine allocation investigation](performance/2026-09-20-dsp-and-authoring-summary.md#sine-allocation) verified removal of the oscillator's scratch allocation and observed zero GC in measured fixed AudioWorklet windows. It also recorded an output underrun: these results do not prove zero allocation for the whole engine or glitch-free playback.
- **Control path**: Browser control decoding and transactional validation allocate outside the sample loop; a whole-audio-thread allocation and GC audit remains a separate gate.

---

## Engine Development Workflows

### Prerequisites
- [MoonBit toolchain](https://www.moonbitlang.com/): pinned to `0.10.14+7d59c7ec9` across GitHub Actions, Copilot setup, and `scripts/cloudflare-build.sh`.
- Node.js 22.12+ (22.x LTS) and npm 11.19.0+

Prefix direct Moon commands with `NEW_MOON_MOD=0` to preserve the repository's hand-maintained manifests.

### Core Engine Verification
```bash
# Check types and compilation across all targets
NEW_MOON_MOD=0 moon check --target all --deny-warn

# Run the test suite on all targets
NEW_MOON_MOD=0 moon test --target all --deny-warn

# Test specific packages
NEW_MOON_MOD=0 moon test .
NEW_MOON_MOD=0 moon test pattern

# Format code and update interfaces
NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt

# Run CLI entry point
NEW_MOON_MOD=0 moon run cmd/main
```

### Live Application Development (`web/live`)

This builds and runs the text-first interactive editor shown in the main demo:

```bash
# Build browser Wasm artifact and sync to web runtime
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
./playwright-sync-wasm.sh

# Install dependencies and start Vite dev server
npm --prefix web/live ci
npm --prefix web/live run dev
# Open http://localhost:5173/
```

To create a production bundle:
```bash
npm --prefix web/live run build
npm --prefix web/live run preview
```

### Standalone Engine Demo & Package Distribution

```bash
# Serve the low-level standalone engine proof (web/)
NEW_MOON_MOD=0 moon build --target wasm-gc --release
./playwright-serve.sh 8000
# Open http://127.0.0.1:8000/

# Pack and test the @moondsp/browser distribution
npm run pack:browser
npm run typecheck:browser
NEW_MOON_MOD=0 npm run test:browser
```

### Native CLAP Plugin Prototype
```bash
scripts/build-clap-prototype.sh     # Build Linux CLAP prototype shared object
scripts/smoke-clap-prototype.sh     # dlopen / process smoke test
scripts/validate-clap-prototype.sh  # Run clap-validator against the build
```

---

## Project Status

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
