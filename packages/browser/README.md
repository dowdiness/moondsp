# @moondsp/browser

`@moondsp/browser` is the npm package distributing moondsp's AudioWorklet DSP graph engine for JavaScript and TypeScript applications. It packages prebuilt WebAssembly (Wasm-GC), an AudioWorklet processor, TypeScript declarations, and a typed Promise-based host API wrapper.

Applications using this package do not need the MoonBit toolchain or moondsp source tree.

## Architecture context

In moondsp's web integration architecture, `@moondsp/browser` acts as the primary package distribution layer between web applications and MoonBit AudioWorklets:

```text
[ Web Application / UI ] (React, Svelte, Vanilla JS/TS)
   ↓ imports "@moondsp/browser" (ES module & TypeScript declarations)
[ GraphEngine ] (`dist/graph-engine.js` host wrapper)
   ↓ creates AudioWorkletNode & posts JSON / control messages
[ AudioWorklet Processor ] (`dist/graph-processor.js`)
   ↓ loads and runs Wasm-GC instance (`dist/moonbit_dsp.wasm`)
[ browser ] (flat MoonBit export ABI: `graph_host_*`)
   ↓
[ engine ] (`GraphEngine` mono mixing & mount handles)
   ↓
[ graph ] / [ dsp ] (topological graph execution & DSP primitives)
```

- **Upstream applications**: Web synthesizers, interactive music tools, or live-coding playgrounds (e.g. [`examples/basic-synth/`](../../examples/basic-synth/README.md)).
- **Host wrapper (`dist/graph-engine.js`)**: Validates and observes the caller-owned `AudioContext`, registers the AudioWorklet module, posts asynchronous messages, tracks promise-based admissions, translates typed errors (`GraphEngineError`), and handles cancellation.
- **AudioWorklet (`dist/graph-processor.js`)**: Executes the audio render loop on the browser's dedicated high-priority audio thread.
- **WebAssembly payload (`dist/moonbit_dsp.wasm`)**: Standalone `wasm-gc` binary compiled from `browser/`, containing the full DSP and graph engine.
- **MoonBit host bindings**: A companion MoonBit JS-target lifetime binding is available in [`packages/browser/host/`](host/) (`dowdiness/moondsp-browser-host`) for MoonBit applications observing a JavaScript engine.

## Package contents

When built or installed from the tarball, the package exposes:

| File | Purpose |
|---|---|
| `dist/graph-engine.js` | Main ESM entry point exporting `GraphEngine`, `GraphEngineError` |
| `dist/graph-engine.d.ts` | TypeScript declarations (supports TS 5.4+ with `NoInfer` parameter inference) |
| `dist/graph-processor.js` | AudioWorklet processor script registered by `GraphEngine` |
| `dist/moonbit_dsp.wasm` | Precompiled release Wasm-GC binary |
| `dist/LICENSE` | Apache-2.0 license file |

## Quick start

### 1. Installation

From the moondsp repository root, build and pack the distribution tarball:

```bash
npm run pack:browser
```

Install the generated tarball in your web application:

```bash
npm install /path/to/moondsp/packages/browser/moondsp-browser-0.6.0.tgz
```

### 2. TypeScript / JavaScript usage

```ts
import { GraphEngine, type GraphDescription } from "@moondsp/browser";

// 1. Author a declarative graph description
const synthGraph = {
  params: {
    frequency: 220,
    cutoff: 1200,
    volume: 0.2,
  },
  nodes: [
    { type: "oscillator", waveform: "saw", frequency: { param: "frequency" } },
    { type: "biquad", input: 0, mode: "lowpass", cutoff: { param: "cutoff" }, q: 1.0 },
    { type: "gain", input: 1, gain: { param: "volume" } },
    { type: "output", input: 2 },
  ],
} as const satisfies GraphDescription<"frequency" | "cutoff" | "volume">;

// 2. The host application owns the AudioContext
const context = new AudioContext();

// AudioContext must be suspended during engine creation and graph mounting
await context.suspend();

// 3. Initialize GraphEngine
const engine = await GraphEngine({ context });
engine.output.connect(context.destination);

// 4. Mount the graph (starts paused)
const sound = await engine.mount(synthGraph);

// 5. Start playback within a user gesture (e.g. Start button)
const startButton = document.querySelector<HTMLButtonElement>("#start")!;
startButton.addEventListener("click", async () => {
  if (context.state === "suspended") {
    await context.resume();
  }
  await sound.play();
  // Parameters can be updated dynamically at block boundaries:
  await sound.setParams({ cutoff: 3500, volume: 0.15 });
});

// 6. Stop playback and clean up resources when finished (e.g. Stop button)
const stopButton = document.querySelector<HTMLButtonElement>("#stop")!;
stopButton.addEventListener("click", async () => {
  await sound.pause();
  await sound.unmount();
  await engine.close();
  await context.close(); // Only the application closes its context
});
```

## API summary

### `GraphEngine(options: GraphEngineOptions): Promise<GraphEngine>`

Creates the audio engine instance within an existing, suspended `AudioContext` or `OfflineAudioContext`.

- `options.context`: The caller-owned `AudioContext` (must be suspended).
- `options.wasmUrl` *(optional)*: Override URL for `moonbit_dsp.wasm`.
- `options.processorUrl` *(optional)*: Override URL for `graph-processor.js`.
- `options.signal` *(optional)*: `AbortSignal` owning engine creation only (aborts fetch/compilation if cancelled).
- `options.closeTimeoutMs` *(optional)*: Deadline for processor close acknowledgment (defaults to 5000 ms).

### `MountedGraph<Name>`

Returned by `engine.mount(graph)`. Represents a paused, mounted graph instance:

- `sound.play(): Promise<void>`: Starts or resumes playback of this graph.
- `sound.pause(): Promise<void>`: Freezes processing and oscillator phases.
- `sound.setParams(values): Promise<void>`: Atomically updates declared named parameters between render blocks.
- `sound.applyControls(controls): Promise<void>`: Applies an ordered batch of raw `setParam`, `gateOn`, or `gateOff` controls.
- `sound.unmount(): Promise<void>`: Permanently detaches and releases the graph from the engine.

### `engine.wait(options?: GraphEngineWaitOptions): Promise<EngineExit>`

Monitors engine lifetime and reports unexpected AudioWorklet failures without polling:

```ts
const exit = await engine.wait();
if (exit.type === "failed") {
  console.error("AudioWorklet crashed:", exit.error);
}
```

## Node types

| Node type | Fields | Description |
|---|---|---|
| `oscillator` | `waveform` (`"sine"`, `"saw"`, `"square"`, `"triangle"`), `frequency` | Audio-rate waveform generator |
| `adsr` | `attackMs`, `decayMs`, `sustain`, `releaseMs` | Linear attack/decay/release envelope with sustain level (0.0–1.0) |
| `biquad` | `input`, `mode` (`"lowpass"`, `"highpass"`, `"bandpass"`), `cutoff`, `q` | 2-pole resonant filter |
| `gain` | `input`, `gain` | Linear gain multiplier |
| `mul` | `input0`, `input1` | Audio-rate multiplication of two input signals (e.g. VCA / ring modulation) |
| `output` | `input` | Terminal output node directing signal to the engine's mono bus |

*Note: Scalar fields (`frequency`, `cutoff`, `q`, `gain`, ADSR timings) accept either finite numbers or `{ param: "paramName" }` references.*

## Requirements & Environment

- **Browser**: A modern browser supporting WebAssembly Garbage Collection (**Wasm-GC**) and **AudioWorklet** (Chrome/Chromium 119+, Firefox 120+, Safari 18.2+).
- **Context**: Must be served in a secure context (`https://` or `http://localhost`). `file://` execution is not supported.
- **CSP**: Content Security Policy must allow WebAssembly compilation (`'wasm-unsafe-eval'` or `'unsafe-eval'`).

## References

- [Browser API Contract](../../docs/browser-api-contract.md) — Exhaustive contract on admission, error codes, and thread protocols.
- [Technical Reference](../../docs/technical-reference.md) — Node definitions, slot mappings, and DSP constraints.
- [Basic Synth Example](../../examples/basic-synth/README.md) — Complete Vite + TypeScript instrument implementation.
- [Host Lifetime Module](host/) — Companion MoonBit `js` target module for engine lifetime tracking.
