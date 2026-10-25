# @moondsp/browser

`@moondsp/browser` is the npm package distributing moondsp's AudioWorklet DSP graph engine for JavaScript and TypeScript applications. It packages prebuilt WebAssembly (Wasm-GC), an AudioWorklet processor, TypeScript declarations, and a typed Promise-based host API wrapper.

Applications using this package do not need the MoonBit toolchain or moondsp source tree.

## Choose an API

| Use case | Recommended API | Resource owner |
|---|---|---|
| Realtime instrument with Power on/off | [`AudioPower`](#package-owned-realtime-audio) from `@moondsp/browser/audio` | Package owns the context, engine, output connection, and cleanup |
| Existing context, custom routing, or an OfflineAudioContext | [`GraphEngine`](#2-caller-owned-context-example) from `@moondsp/browser` | Application owns the context and output routing; close the engine before the context |
| Graph creation without connection indices | `Graph(params, build)` | One synchronous builder owns all node references |
| Volume, cutoff, note-on/off, or a parameter-and-gate transaction | [`sound.update()`](#updating-sound-prefer-named-parameters) | Application supplies named parameters and ordered gates; each update is atomic |

Start with `AudioPower` unless you need to own the context. It handles browser
gesture admission, cancellation, and repeated power cycles. Do not implement a
Worklet or call `graph_host_*` exports in ordinary application code.

Both entry points use the same mono graph engine. Mount **all** session graphs
before the first `play()`; pausing or unmounting does not reopen mounting.
Neither provides timestamped automation, live topology replacement, or
polyphonic note allocation. Pattern/song playback in the live editor is a
separate integration, not a feature of this graph wrapper.

For a complete application with failure recovery and keyboard handling, use the
[basic synth examples](../../examples/basic-synth/README.md). For host-independent
MoonBit rendering, use the [engine examples](../../engine/README.mbt.md).

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

- **Upstream applications**: Web synthesizers, interactive music tools, or live-coding playgrounds (e.g. the [`basic-synth`](../../examples/basic-synth/README.md) core with Svelte and vanilla adapters).
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
| `dist/audio-power.js`, `dist/audio-power.d.ts` | Owned realtime lifecycle via the opt-in `@moondsp/browser/audio` subpath |
| `dist/audio-power-core.js` | Private generated MoonBit JS-host owner, included transitively |
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

This is a local distribution workflow, not a claim of npm-registry publication.
Keep the packaged JS, Worklet, and Wasm from the same build. Vite users should
follow the [example configuration](../../examples/basic-synth/vanilla/vite.config.ts)
to preserve package-relative asset URLs during development.

After installation, most realtime apps should start with the
[package-owned example](#package-owned-realtime-audio) below. The following
example is for applications that deliberately manage their own context.

### 2. Caller-owned context example

This illustrates setup followed by a separate Start gesture and terminal Stop.
It is not a reusable Power on/off controller: after Stop, create a fresh session.
Production hosts must also observe `engine.wait()`, handle command rejections,
and clean up partially initialized resources; `AudioPower` handles the owned
lifecycle for the common case.

```ts
import { GraphEngine, type Graph } from "@moondsp/browser";

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
} as const satisfies Graph<"frequency" | "cutoff" | "volume">;

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
  await sound.update({ params: { cutoff: 3500, volume: 0.15 } });
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

## Updating sound: prefer named parameters

Prefer `Graph` to author connections without numeric indices. Declare
parameter defaults up front; return the output signal and named ADSR gates.
Parameter and gate names are inferred through construction, mounting, and updates:

```ts
import { Graph } from "@moondsp/browser";

const instrument = Graph({ frequency: 220, volume: 0.1 }, g => {
  const oscillator = g.oscillator("sine", g.param("frequency"));
  const amp = g.adsr({ attackMs: 10, decayMs: 80, sustain: 0.7, releaseMs: 180 });
  return { output: g.gain(g.mul(oscillator, amp), g.param("volume")), gates: { amp } };
});

// During setup, before any graph plays:
const sound = await engine.mount(instrument);
await sound.play();
// Later, set pitch and trigger the envelope in a single transaction:
await sound.update({
  params: { frequency: 440 },
  gates: [{ target: "amp", action: "on" }],
});
await sound.update({ gates: [{ target: "amp", action: "off" }] });
```

The same description can be mounted inside `AudioPower` setup; return the
mounted graph and obtain it through `audio.ready`. Retain its named type
(`MountedGraph<"frequency" | "volume", "amp">`) when storing the handle.
Handle rejected updates in your application action, including retirement while
an update is pending.

- `Graph(params, build)` is called without `new`; it returns a frozen, reusable
  `Graph<Name, Gate>` value, not a running graph. The function and type share
  one name; no wrapper class or compatibility alias is needed.
  Its callback is synchronous; foreign node references and use of the builder
  after it returns are rejected. Shared references do not duplicate nodes.
  Numeric descriptions remain the serialization format; MoonBit still validates
  topology and parameter ranges at mount. The builder adds no DSP implementation.
- `params` holds initial values, not a readable current-value store. Keep UI
  values in application state and distinguish requested from accepted updates.
- A named update is validated as one transaction: an invalid entry rejects the
  whole batch. Names may intentionally update multiple node fields.
- Parameters are prepared first, then up to 64 gate actions in array order.
  Use `off` then `on` to retrigger; `on` then `off` finishes released. No audio
  renders between actions. Empty updates are valid no-ops on a live handle.
  Runtime controls use declared names; there is no raw numeric control method.
- Gate `off` allows an ADSR release to render; `pause()` freezes DSP state and
  is not note-off. Keep the graph playing for release tails.
- Updates apply between render callbacks, not at a requested sample timestamp.
  `update()` is not an `AudioParam` ramp or a smoothing guarantee.

**Breaking migration:** replace `sound.setParams(values)` with
`sound.update({ params: values })`. Replace numeric `applyControls()` calls by
declaring named parameters/gates and calling `update()`; neither `applyControls`
nor the `GraphControl` TypeScript export remains. There are no compatibility
aliases. Deploy the matching package/Worklet/Wasm together; the ABI now uses
`graph_host_update`.

## Package-owned realtime audio

Use `@moondsp/browser/audio` when the package should own both the realtime
`AudioContext` and engine. Keep the root `GraphEngine` entry point for
caller-provided contexts, offline rendering, or custom output destinations.
Each `AudioPower` is independent; construction allocates no audio resources.

Keep one owner across power cycles. The example below assumes buttons with IDs
`on`, `off`, and `resume`; attach these handlers after the buttons exist.
`ended` reports primary failures, while `turnOff()` reports cleanup failures.
The readiness handler consumes cancellation/failure without logging the same
startup error a second time.

```ts
import { AudioPower, type PoweredAudio } from "@moondsp/browser/audio";
import type { MountedGraph } from "@moondsp/browser";

const power = AudioPower();
let current: PoweredAudio<MountedGraph> | undefined;
const on = document.querySelector<HTMLButtonElement>("#on")!;
const off = document.querySelector<HTMLButtonElement>("#off")!;
const resume = document.querySelector<HTMLButtonElement>("#resume")!;

on.onclick = () => {
  if (current) return;
  // Call directly in the gesture; do not await loading before turnOn().
  let audio: PoweredAudio<MountedGraph>;
  try {
    audio = power.turnOn(async ({ engine, powerOff }) => {
      powerOff.throwIfAborted();
      const graph = await engine.mount({ nodes: [
        { type: "oscillator", waveform: "sine", frequency: 220 },
        { type: "gain", input: 0, gain: 0.1 },
        { type: "output", input: 1 },
      ] });
      powerOff.throwIfAborted();
      await graph.play();
      powerOff.throwIfAborted();
      return graph;
    });
  } catch (error) {
    // No handle exists: callback/admission validation or context construction failed.
    console.error("Could not start audio", error);
    return;
  }
  current = audio;
  void audio.ready.then(
    graph => {
      if (current === audio) console.log("Ready", graph);
    },
    () => { /* Early turn-off is normal; ended reports startup failures. */ },
  );
  void audio.ended.then(async end => {
    if (current === audio) current = undefined;
    if (end.reason === "failed") console.error("Audio failed", end.error);
    // Failed ended may arrive BEFORE cleanup finishes. Join it separately.
    try {
      await audio.turnOff();
    } catch (error) {
      // Cleanup-only failure is already in ended; don't report it twice.
      if (end.reason !== "failed" || error !== end.error) {
        console.error("Audio cleanup failed", error);
      }
    }
  });
};
off.onclick = () => {
  const audio = current;
  current = undefined; // Allow replacement admission in the next user gesture.
  // The terminal observer above also joins this same retained cleanup promise.
  void audio?.turnOff().catch(() => { /* Reported by the terminal observer. */ });
};
resume.onclick = () => {
  // Direct gesture call; rejects if setup is not ready or the generation retired.
  void current?.resume().catch(error => console.error("Resume did not complete", error));
};
```

### Which completion should I observe?

| Signal | Meaning | Caller action |
|---|---|---|
| `turnOn()` throws | No handle was returned: invalid callback, owner already occupied, or native context construction failure | Catch at the gesture handler |
| `audio.ready` | Setup value is usable after final resume and destination connection | Handle rejection, including normal early `AbortError`; later failures do not change an already-resolved promise |
| `audio.ended` | Retained clean end or failure; never rejects | Report failure and update UI only if this is still the current generation |
| `audio.turnOff()` | Package-owned cleanup has settled | Await it when cleanup completion matters; catch the first cleanup error |
| `audio.resume()` | This ready generation's restore attempt has settled | Call in the gesture and handle rejection; a native restore failure also appears in `ended` |

**`ended` is not a cleanup barrier.** A setup or processor failure is published
immediately; clean turn-off is published after cleanup. A later cleanup error
cannot replace an earlier failure in `ended`. If cleanup is the only failure,
the same error appears in `ended` and the rejecting `turnOff()` promise.
`closeTimeoutMs` bounds the engine close acknowledgement, not total cleanup or
the browser's `AudioContext.close()`.

`resume()` works only after readiness and before retirement. It handles
`suspended` or `interrupted` contexts, does nothing when already running, and
shares a pending restore promise. It does not retry a failed power cycle;
use a new gesture and `power.turnOn()` for that.

### Ownership and cancellation

- Treat `context` and setup's `engine` as **borrowed**. Observe context state and
  control graphs, but let `PoweredAudio` resume/close the context and connect/close
  the engine. TypeScript `readonly` does not prevent native mutator calls.
  External context closure is handled as normal turn-off unless failure was
  already retained. Use `GraphEngine` directly if you need lifecycle control.
- Setup runs while suspended. Mount all graphs before calling `play()`, then
  return the value you want from `ready`; do not resume or connect output yourself.
- `turnOff()` immediately aborts `powerOff` and retires only its own generation.
  It does not wait for arbitrary pending setup. A late result cannot publish
  readiness, but JavaScript cannot forcibly stop your callback or undo its effects.
  Pass `powerOff` to cancellable work such as `fetch(url, { signal: powerOff })`,
  and check `powerOff.throwIfAborted()` after uncancellable awaits before performing
  further application work. Application-created resources still need your cleanup.
- Attach setup listeners with `{ signal: powerOff }` so retirement removes them.
  The library owns its context and engine, not your timers, subscriptions, or UI.
- A replacement context is admitted in the new gesture, but its engine creation
  waits for all earlier retirements on that owner, even failed ones. Do not await
  predecessor cleanup before calling `turnOn()` and lose the new gesture.
  Old handles cannot stop the replacement; old application callbacks must still
  check which generation is current before updating UI.

See the [owned audio contract](../../docs/browser-api-contract.md#owned-audio-power)
for failure precedence and the internal lifecycle transitions.

## API summary

### `GraphEngine(options: GraphEngineOptions): Promise<GraphEngine>`

Creates the audio engine instance within an existing, suspended `AudioContext` or `OfflineAudioContext`.

- `options.context`: The caller-owned `AudioContext` (must be suspended).
- `options.wasmUrl` *(optional)*: Override URL for `moonbit_dsp.wasm`.
- `options.processorUrl` *(optional)*: Override URL for `graph-processor.js`.
- `options.signal` *(optional)*: `AbortSignal` owning engine creation only (aborts fetch/compilation if cancelled).
- `options.closeTimeoutMs` *(optional)*: Deadline for processor close acknowledgment (defaults to 5000 ms).

### `MountedGraph<Name, Gate>`

Returned by `engine.mount(graph)`. Represents a paused, mounted graph instance:

- `sound.play(): Promise<void>`: Starts or resumes playback of this graph.
- `sound.pause(): Promise<void>`: Freezes processing and oscillator phases.
- `sound.update({ params?, gates? }): Promise<void>`: Atomically updates named parameters and ordered gate actions between render blocks.
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
- [Basic Synth Example](../../examples/basic-synth/README.md) — Shared lifecycle core with Svelte 5 and framework-free TypeScript adapters.
- [Host Lifetime Module](host/) — Companion MoonBit `js` target module for engine lifetime tracking.
