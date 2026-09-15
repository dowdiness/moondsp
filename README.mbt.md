# moondsp

A portable, live-codable DSP audio and pattern engine written in [MoonBit](https://www.moonbitlang.com/).

> **Patterns describe *what* plays *when*; DSP graphs describe *how* it sounds.**  
> moondsp combines a Strudel/TidalCycles-inspired pattern algebra with a compiled signal-processing graph and a polyphonic voice pool, targeting **browser (Web AudioWorklet via `wasm-gc`)**, **native DAWs (CLAP prototype via C ABI)**, and **host-independent MoonBit execution**.

---

## Target Platforms

`moondsp`'s core DSP, graph compilation, and pattern scheduling are completely platform-agnostic and free of browser or host globals. The engine compiles to multiple targets:

- **Browser (Web AudioWorklet)**: Compiled via `wasm-gc` for in-browser live coding and synthesis. Automated checks cover rendered PCM and resource lifecycle; they do not establish glitch-free playback on every device.
- **Native DAWs (CLAP Plugin Prototype)**: Native shared library via MoonBit's C ABI shim. It passes `clap-validator`; real host/DAW loading, stable bridge symbols, and an audio-thread allocation audit remain production gates.
- 🖥️ **Host-Independent MoonBit API**: Direct programmatic audio synthesis in pure MoonBit via `GraphEngine` — embeddable into games, tools, or custom runtimes.
- 💻 **CLI & Offline Rendering**: Headless command-line entry point for audio rendering, batch synthesis, and automated tests.

---

## Quick start

### Play the basic synth in a browser

[`examples/basic-synth`](examples/basic-synth/README.md) uses only the public
`@moondsp/browser` package: a C4–C5 keyboard, volume, low-pass cutoff, and
a single Power on / Power off control. It is monophonic, with last-held-note
priority, and contains no custom Worklet.

Audio starts off, without an `AudioContext`. Power on handles browser admission,
loading, and playback; Power off cancels loading or releases the entire session.
Processor failure is reported immediately, and the same Power on button retries.

To build a local distribution and run its consumer:

```sh
npm run pack:browser
cd examples/basic-synth
npm install ../../packages/browser/moondsp-browser-0.6.0.tgz
npm run dev
```

Building the tarball requires MoonBit. Consuming that tarball elsewhere does
not: it includes the matching Wasm, Worklet, JS API, and TypeScript declarations.
The package is not yet published to npm. See the example README for external
installation and production builds.

### Engine development

```bash
# Verify & test the core engine across targets
NEW_MOON_MOD=0 moon check --target all && NEW_MOON_MOD=0 moon test --target all

# Run CLI entry point
NEW_MOON_MOD=0 moon run cmd/main
```

*(Note: `NEW_MOON_MOD=0` preserves the repository's hand-maintained `moon.mod`)*

### 1. Run in Browser (Web AudioWorklet via `wasm-gc`)
```bash
NEW_MOON_MOD=0 moon build --target wasm-gc --release
./playwright-serve.sh 8000
# Open http://127.0.0.1:8000/ for the demo
# Open http://127.0.0.1:8000/graph-example.html for the public graph API
```

The server script copies the release Wasm into `web/` before serving it.
Use localhost for development and HTTPS for deployment; AudioWorklet requires
a secure context, not merely an HTTP origin. Rebuild and restart the script
after changing MoonBit sources to avoid serving stale Wasm.

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

Operations raise the checked `GraphEngineError` type. Mount compiles the graph
and prepares its buffers before `process()` renders it. This separation does
not establish an allocation-free contract for every backend or host operation;
see [Performance](#performance) for measured scope.

For browser use, `web/graph-engine.js` adapts this engine to AudioWorklet and
Promise-based methods. Its JSON subset accepts oscillator, gain, output, ADSR,
biquad, and multiply nodes; `applyControls` exposes atomic parameter and gate
updates. The MoonBit API accepts canonical graphs supported by the mono
compiler. See [the browser contract](docs/browser-api-contract.md).

Browser applications observe termination through `engine.wait({ signal })`;
cancelling a wait does not close the engine. `engine.close()` releases its graphs
and Worklet but leaves the caller-owned `AudioContext` open. The optional
JS-target MoonBit module at [`packages/browser/host`](packages/browser/host/)
adds cancellable lifetime observation and protected cleanup without importing
the async runtime into DSP/Wasm. See [host lifetime observation](docs/browser-api-contract.md#moonbit-lifetime-observation-on-the-js-host).

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
- **DSP layer**: Declarative signal graphs compile into flat topological execution plans with preallocated render buffers. At 48 kHz / 128 samples, the callback budget is 2.67 ms; meeting it is a measured deployment property, not a hard-real-time guarantee.
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

## Package Map & Architecture

moondsp is structured as a stack of decoupled, platform-independent core packages, complemented by platform-specific adapters and frontends:

```text
[ mini ] (text notation & document parsing)
   ↓
[ pattern / song ] (exact rational time, event queries, arrangement)
   ↓
[ scheduler ] (event-to-voice scheduling & block quantization)
   ↓
[ voice ] / [ engine ] (polyphonic pools & host-independent graph engine)
   ↓
[ graph ] (topology validation, DAG compilation, hot-swap)
   ↓
[ dsp ] (primitives: buffers, oscillators, filters, envelopes)
   ↑
[ identity ] (stable node IDs & monotonic revisions for live editing)
```

### Core Engine (Platform-Agnostic)

| Package | Role & Responsibility | Key Types / Entry Points |
|---|---|---|
| [`dsp/`](dsp/README.mbt.md) | Sample buffers, oscillators, envelopes, biquad filters, delay lines, gain, clip, pan, and tagless DSP traits | `DspContext`, `AudioBuffer`, `Oscillator`, `Adsr`, `Biquad`, `DelayLine`, `Pan`, `ArithSym`, `DspSym` |
| [`graph/`](graph/README.mbt.md) | DAG compilation, topological sorting, runtime controls, block-boundary hot-swap, and topology editing | `DspNode`, `CompiledTemplate`, `CompiledDsp`, `CompiledStereoDsp`, `GraphControl`, `CompiledDspHotSwap`, `GraphTemplateDoc` |
| [`engine/`](engine/README.mbt.md) | Host-independent graph lifecycle management, typed mount handles, and multi-graph mono buffer mixing | `GraphEngine`, `MountedGraph`, `GraphEngineError` |
| [`voice/`](voice/README.mbt.md) | Polyphonic voice pool with priority voice stealing, generation handles, ADSR lifecycle, and equal-power stereo panning | `VoicePool`, `BoundVoicePool`, `VoiceHandle`, `VoiceState`, `NoteGate` |
| [`identity/`](identity/README.mbt.md) | Type-safe stable node identifiers and monotonic revision tokens for structural live-editing trees | `GraphNodeId`, `PatternNodeId`, `SectionId`, `SectionLayerId`, `OccurrenceId`, `Revision` |
| [`pattern/`](pattern/README.mbt.md) | Queryable musical pattern algebra with exact `Rational` time, polyrhythmic combinators, and `ControlMap` events | `Pat[A]`, `Rational`, `TimeSpan`, `Event[A]`, `ControlMap`, `sequence`, `stack`, `merge_control`, `PatternDoc` |
| [`mini/`](mini/README.mbt.md) | Mini-notation parser turning concise live-coding text into `Pat[ControlMap]`, `Song[ControlMap]`, or incremental documents | `parse`, `parse_song`, `parse_song_with_bpm`, `parse_doc`, `parse_snapshot`, `MiniAuthoringPipeline` |
| [`song/`](song/README.mbt.md) | Macro-level musical structure arranging patterns into length-bounded sections, layers, parts, and local `TimeScope` | `Song[A]`, `Section[A]`, `SongPart[A]`, `TimeScope`, `SongDoc[A]`, `SongSnapshot[A]` |
| [`scheduler/`](scheduler/README.mbt.md) | Audio block quantization, tempo clock, note lifecycle tracking, and voice-scope reconciliation | `PatternScheduler`, `PlaybackSnapshot`, `BlockFrame`, `PatternVoiceScope`, `SongVoiceScope` |

### Platform Adapters & Native Scaffolding

| Package / Directory | Role & Responsibility | Key Files / Entry Points |
|---|---|---|
| [`browser/`](browser/README.md) | AudioWorklet export ABI and WASM-to-JS transport adapter (128-frame quantum, JSON decoding, named params) | `graph_host_*`, `scheduler_*`, `get_browser_*`, `browser_abi.baseline` |
| [`packages/browser/`](packages/browser/README.md) | Local distribution bundle for `@moondsp/browser` (TypeScript declarations, JS API wrapper, processor, release Wasm) | `GraphEngine`, `GraphDescription`, `GraphControl` |
| [`examples/basic-synth/`](examples/basic-synth/README.md) | Standalone monophonic synth demo consuming `@moondsp/browser` with keyboard priority and reactive UI | `SYNTH_GRAPH`, `noteOn`, `noteOff`, `startApplication` |
| [`clap_engine/`](clap_engine/README.mbt.md) | Polyphonic subtractive synth engine core tailored for CLAP plugins (preallocated voices, note ID / wildcard matching) | `ClapSynthEngine`, `CLAP_PARAM_*`, `default_synth_template` |
| [`clap_host/`](clap_host/README.mbt.md) | Flat primitive integer-handle C-ABI bridge exposing scalar getters/setters without object leaking | `engine_create`, `engine_destroy`, `engine_note_on`, `engine_process`, `engine_set_param` |
| [`clap_plugin/`](clap_plugin/README.md) | Native CLAP plugin payload, C ABI shim, build scripts, and `clap-validator` automation | `moondsp_clap.c`, `moondsp_clap_moonbit.h`, `clap_payload.mbt` |
| [`cmd/main/`](cmd/main/) | Headless CLI entry point for testing, batch rendering, and offline experiments | `cmd/main/main.mbt` |

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
│   ├── packages/browser/       Packaged JS/TS API, Worklet, and release Wasm
│   ├── packages/browser/host/  Separate JS-target MoonBit lifetime binding
│   ├── examples/basic-synth/   Standalone public-package consumer
│   ├── clap_engine/    Native CLAP synth engine core around graph + voice pool
│   ├── clap_host/      Primitive integer-handle bridge for C CLAP shims
│   ├── clap_plugin/    Native CLAP prototype payload and C ABI shim (passes clap-validator)
│   └── cmd/main/       CLI entry point and offline experiments
│
└── docs/               Architecture blueprint, technical reference, ADRs, performance snapshots
```

---

## Performance

The audio callback budget at 128 samples / 48 kHz is **2.67 ms per block**.
Graph compilation and buffer preparation happen before playback. Benchmark
results depend on the graph, target, toolchain, host, and measurement method;
dated records are under [`docs/performance/`](docs/performance/).

The [Wasm-GC sine allocation investigation](docs/performance/2026-09-14-wasm-gc-sine-allocation-fix.txt)
verified removal of the oscillator's scratch allocation and observed no GC in
the measured fixed AudioWorklet windows. It also recorded an output underrun:
these results do not prove zero allocation for the whole engine or glitch-free
playback. Browser control decoding and transactional validation allocate
outside the sample loop; a whole-audio-thread allocation/GC audit remains a
separate gate.

---

## Development

```bash
# Type-check all targets with warnings denied
NEW_MOON_MOD=0 moon check --target all --deny-warn

# Run the test suite on all targets
NEW_MOON_MOD=0 moon test --target all --deny-warn

# Test specific packages

[Showing lines 1-300 of 350. Use :301 to continue]