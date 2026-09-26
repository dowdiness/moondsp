# Browser facade and worklet ABI contract

The `dowdiness/moondsp/browser` package has two reviewed public surfaces:

- the MoonBit source facade generated in
  [`browser/pkg.generated.mbti`](../browser/pkg.generated.mbti); and
- the AudioWorklet export ABI listed under `link.js.exports` and
  `link.wasm-gc.exports` in [`browser/moon.pkg`](../browser/moon.pkg).

Use this guide when writing host code or reviewing browser API PRs. Keep
architecture rationale in ADRs, and keep graph runtime-control behavior in
[`technical-reference.md`](technical-reference.md).

For a new application, choose the public entry point rather than the raw ABI:

| Application | Entry point |
| --- | --- |
| JavaScript or TypeScript instrument | `@moondsp/browser`; see [local distribution](#standalone-synth-examples-and-local-distribution) |
| Realtime instrument with package-owned context | `@moondsp/browser/audio`; see [owned audio power](#owned-audio-power) |
| Repository-hosted browser integration | `web/graph-engine.js`; see [the external graph API](#external-graph-entry-point) |
| MoonBit code observing an existing JS engine | The separate [JS-host lifetime module](#moonbit-lifetime-observation-and-ownership-on-the-js-host) |
| Host-independent MoonBit rendering | Root-package `GraphEngine`; see [the engine contract](technical-reference.md#354-host-independent-graph-engine) |

## Contract summary

- `browser/pkg.generated.mbti` defines the supported MoonBit source facade.
- `browser/moon.pkg` defines the supported JS and wasm-gc worklet exports.
- The browser facade exposes operations and explicitly reviewed semantic value
  types. Mutable route types, pools, scheduler handles, and host state objects
  remain implementation details.
- `browser/internal/*` package paths are private, even when a symbol is `pub`
  for package wiring. Public value types are defined in the browser facade and
  projected from internal values without exposing their definition paths.
  The package is a `foreign_library`, usable by MoonBit consumers as well as
  through its configured JS/wasm-gc exports.
- `browser/browser_abi.baseline` records the reviewed facade/export shape.
  Update it only for an intentional public API or worklet ABI change.

Use the root, `engine`, `graph`, `scheduler`, `voice`, `mini`, and `song` packages
for general graph lifecycle/authoring, voice pools, scheduling, and Mini parsing. The
browser package is a low-level host ABI. Web applications can use the external
graph entry point below without calling its exports directly.

## External graph entry point

`web/graph-engine.js` exports `GraphEngine` and `GraphEngineError`.
`web/graph-example.html` is an independent consumer: it defines its graph and
imports only the public JS module, not the scheduler, demo exports, or private
worklet messages.

The implementation is MoonBit-first: `engine/` owns `GraphEngine`,
`MountedGraph`, and checked domain errors, re-exported from the root package.
Native MoonBit callers use `engine.mount(Array[DspNode])`, handle methods,
and `engine.process(AudioBuffer)` directly. See the checked example in
[`README.mbt.md`](../README.mbt.md) and the authoritative
[engine contract](technical-reference.md#354-host-independent-graph-engine).
JavaScript manages browser resources and asynchronous transport, not DSP
state or compilation.

```js
import { GraphEngine } from "./graph-engine.js";

// The application owns this context. Mount graphs before resuming it.
const context = new AudioContext();
await context.suspend();
const engine = await GraphEngine({ context });
const sound = await engine.mount({
  nodes: [
    { type: "oscillator", waveform: "triangle", frequency: 220 },
    { type: "gain", input: 0, gain: 0.1 },
    { type: "output", input: 1 },
  ],
});
engine.output.connect(context.destination);

// Run these operations from a user gesture, such as a Play button.
await context.resume();
await sound.play();
// Later:
await sound.pause();
await sound.unmount();
await engine.close();
await context.close(); // Only the application closes its context.
```

This example separates mounting from the later Play gesture. For a single
Power on gesture, call `context.resume()` before the first asynchronous wait
so loading cannot consume the user activation. After admission, suspend the
context again before creating the engine and mounting; start the graph, then
resume and connect output. The owned audio-power entry point implements that
sequence, including cancellation and cleanup. The root engine itself does not
perform browser admission.

### Description and mounting

- A description contains `nodes`, an array of 1–64 node objects. It may also
  contain `params`, a record of at most 256 exact string names mapped to finite
  numeric initial values. Array indices identify connections. The caller
  supplies the graph; it is not a demo preset.
- A scalar field may be a finite number or an exact reference
  `{ param: "name" }`. References are supported for oscillator `frequency`,
  gain `gain`, biquad `cutoff`/`q`, and ADSR `attackMs`/`decayMs`/`sustain`/
  `releaseMs`. Every declared name must be referenced by at least one supported
  scalar field, every reference must name a declared parameter, and malformed,
  unknown, unused, or orphan declarations reject mounting with
  `INVALID_GRAPH` (including `nodeIndex` when a node is known). References may
  intentionally fan out to multiple fields.
- `oscillator`: required `waveform` (`sine`, `saw`, `square`, or `triangle`)
  and finite numeric `frequency` in Hz.
- `gain`: required integer `input` referencing a node and finite numeric
  `gain` (linear multiplier, not dB).
- `adsr`: required `attackMs`, `decayMs`, `sustain`, and `releaseMs`. Times
  are milliseconds and sustain is a linear level. It starts with a closed gate.
- `biquad`: required integer `input`, `mode` (`lowpass`, `highpass`, or
  `bandpass`), `cutoff` in Hz, and `q`.
- `mul`: required integer `input0` and `input1`; multiply an audio source by an
  ADSR source to form a playable voice.
- `output`: required integer `input`. The existing compiler validates the
  output structure and graph semantics; exactly one mono output is required.
- The `params` values are initial values only. They do not form a current-value
  cache: raw controls and named updates can subsequently change the same
  runtime targets independently.
- The Worklet serializes the description as JSON. MoonBit decodes the browser
  node and parameter subset, then `GraphEngine::mount` uses the existing
  `AnalyzedGraph::analyze` and `Dsp::compile_result` path. There is
  no JS node validator, DSP implementation, or second compiler.
- The browser's 64-node description and 256-parameter limits are adapter
  constraints; the direct MoonBit API accepts canonical nodes supported by the
  mono compiler.
- At most 16 graph handles may be mounted in one engine. Slots can be reused
  before playback, but unmounted handle numbers never recur within an engine.
- Both engine creation and mounting require a suspended context. Mount all
  graphs before the first successful `play`. Mount admission remains closed
  after pausing or unmounting every graph; neither operation reopens admission.
  A new engine is required to mount additional graphs after playback.
- Do not concurrently resume the caller-owned context while creation or
  mounting is pending. Mounting allocates and compiles inside the AudioWorklet
  realm while the context remains suspended; it is not background-worker
  compilation and is not supported during playback.

### Rendering and lifecycle

- `engine.mount(description)` resolves to a `MountedGraph` handle with
  asynchronous `play()`, `pause()`, `unmount()`, `applyControls()`, and
  `setParams(values)` methods. `MountedGraph` is an exported TypeScript type,
  not a runtime constructor. `setParams` accepts a partial record of declared
  names and finite numeric values, and writes every target referring to each
  supplied name.
- Mounting creates independent DSP state and registers it with the engine's
  output, but does not start playback. The input description is reusable:
  mounting it twice creates two independent graphs.
- `play` starts or resumes processing; `pause` freezes oscillator phase.
  Repeated play/pause operations are allowed.
- `unmount()` permanently removes that graph. Concurrent and repeated calls
  share one completion promise. Once unmounting begins, play, pause, controls,
  and `setParams` reject with `GraphEngineError.code === "INVALID_HANDLE"`.
  Repeated unmount cannot affect another graph that reuses the underlying slot.
  An invalid command does not change another graph or close mount admission.
- All playing graphs sum into `engine.output`, a mono `AudioWorkletNode`.
  Connect it to any compatible Web Audio destination. There is no automatic
  master limiter; callers must choose gains appropriate for the sum.
- Rendering uses the actual context sample rate and currently supports
  128-frame render quanta. A different quantum produces a processor failure,
  rather than silently truncating audio.
- Graph commands take effect between render callbacks. This entry point does
  not provide timestamped scheduling or automation, live graph replacement, or
  polyphonic note allocation.
- `engine.close()` ends the engine and all remaining graphs. It is idempotent,
  including concurrent calls: all callers share one completion promise.
  Closing immediately rejects new requests. It disconnects output and closes
  the message port, but never suspends or closes the caller's context.
  Prefer closing the engine before closing its context. If the context closes
  first, its state-change notification rejects unacknowledged graph commands
  with `ENGINE_CLOSED` and releases local resources. An in-flight
  `engine.close()` then completes without requiring a worklet acknowledgement;
  repeated close calls still share completion. Already-acknowledged commands
  retain their result.
- Operations on remaining graph handles reject with `ENGINE_CLOSED`; a graph's
  already-issued unmount retains its shared result.
- The close acknowledgement has a deadline (`closeTimeoutMs`, default 5000ms;
  a positive finite number no greater than 2147483647). A missed deadline
  rejects close with `HOST_ERROR`, rejects pending commands, and attempts local
  processor retirement, output disconnection, and port closure. It does not
  close the context.
- `engine.wait({ signal }?)` observes one retained `EngineExit`:
  `{ type: "closed" }` or `{ type: "failed", error: GraphEngineError }`.
  It does not request shutdown. Multiple and late waiters receive the same result.
  Processor failure is published immediately, without waiting for another command
  or for cleanup. Normal close publishes `closed` after local cleanup; a cleanup
  error publishes `failed`. Caller context closure is normal termination unless
  a failure was already retained. Cleanup never replaces an earlier failure.
- The wait signal owns only that observer, not the engine or other observers.
  Cancellation rejects with `AbortError`, retains `signal.reason` as `cause`,
  and removes the observer and its abort listener. A signal already aborted at
  entry rejects even if an exit is cached. After registration, whichever settles
  the JS Promise first wins. Task cancellation at a MoonBit suspension boundary
  follows the async runtime's rules; the engine's retained result is unaffected.
  Pause, silence, unmounting a graph, and rejected controls do not end an engine.
- `GraphEngineError` carries `code`, `message`, and, for node decoding errors,
  `nodeIndex`. Invalid descriptions use `INVALID_GRAPH`; mounting after
  playback uses `MOUNT_CLOSED`, enforced by the MoonBit engine and exposed
  through JS. Capacity exhaustion uses `MOUNT_REJECTED`. Processor failures reject pending
  requests with `PROCESSOR_FAILED`.
- For new engine requests, `ENGINE_CLOSED` takes precedence over processor
  failure and mount admission when the engine is closing/closed or the context
  is closed. Otherwise, processor failure takes precedence over mount admission.
  A graph whose unmount has begun still rejects play/pause/controls with `INVALID_HANDLE`
  and returns its original promise for repeated unmount.
- Creation requires a suspended context (`INVALID_STATE`). An unsuccessful
  HTTP response uses `LOAD_FAILED`. Native failures during fetch, WASM
  compilation, worklet module loading, or node construction are wrapped in
  `GraphEngineError` with code `INITIALIZATION_FAILED` and the original exception
  in `cause`. Worklet initialization failures reported after node construction
  use `PROCESSOR_FAILED`. None of these failures closes the caller's context.
- `GraphEngine({ context, signal })` accepts an optional `AbortSignal`
  that owns **creation only**. An already-aborted signal prevents loading.
  Aborting during fetch, compilation, module loading, or worklet readiness
  rejects creation with `GraphEngineError.code === "ABORTED"` and preserves
  `signal.reason` as `cause`. The engine aborts its fetch, disconnects any node,
  retires its processor, closes its port, and removes its listeners. It never
  closes the caller's context.
- WASM compilation and worklet module loading cannot themselves be cancelled.
  Their late completion cannot resume abandoned initialization or publish an
  engine. A module already registered in the context is not unloaded.
  After successful creation the abort listener is removed: use `engine.close()`
  to end the returned engine, not the creation signal.
- Closing the context during creation also interrupts outstanding waits and
  rejects creation with `ENGINE_CLOSED`. When abort and context closure race,
  the first observed interruption settles creation. There is no built-in
  timeout or automatic retry; a caller can supply a deadline through its signal.

### MoonBit lifetime observation and ownership on the JS host

[`packages/browser/host`](../packages/browser/host/) is the separate MoonBit
source module `dowdiness/moondsp-browser-host`, with preferred target `js` and
`moonbitlang/async@0.21.3`. It is not imported by the DSP/Wasm module, and its
test driver is not shipped in the `@moondsp/browser` npm tarball.

Wrap the existing JavaScript engine handle in `EngineLifetime::EngineLifetime`.
This is a lifetime view, not another graph constructor or terminal-state owner:

```moonbit
pub async fn observe(native : @host.NativeEngine) -> @host.EngineExit {
  let lifetime = @host.EngineLifetime::EngineLifetime(native)
  lifetime.wait()
}
```

`wait()` uses `js_async.run_promise` to give each native wait its own cancellation
signal. `EngineExit::Failed(RuntimeFailure)` is a returned value, not a raised
task-group failure. `RuntimeFailure` exposes `code()`, `message()`, `node_index()`,
`cause()`, and `native()`. The native error and its arbitrary cause retain their
identity; absent, explicit `null`, and explicit `undefined` causes remain distinct.

`close()` returns `Result[Unit, RuntimeFailure]` and protects the bounded native
cleanup from task cancellation. It invokes native close when entered, without
deferring it through a JS `.then()`. The JS engine owns close idempotence and its
deadline. The binding does not promise bounded cleanup for arbitrary objects
masquerading as a `NativeEngine`, and it never closes the caller's context.

For a session task group, let the body wait for engine exit and run command
workers with `no_wait=true`. On exit, those workers are cancelled and joined
before group defers run. A defer may then close the engine. Do not make an
ordinary child wait for an engine whose close is performed only by that defer:
the group would wait for the child before it could close the engine.

### Owned audio power

`@moondsp/browser/audio` owns a realtime context and its engine. The root
`@moondsp/browser` entry point remains unchanged and caller-owned: use it for
adopted contexts, OfflineAudioContext, and custom destinations.

- Audio power (`AudioPower`) is an application-scoped owner of repeated cycles.
- Powered audio (`PoweredAudio<Value>`) is one generation's capability.
- Audio setup (`AudioSetup`) supplies the suspended context, engine, and power-off signal.
- Audio end (`AudioEnd`) distinguishes clean turn-off from failure.

The declarations below show the public shape. IDE-facing ownership and error
comments live in [`web/audio-power.d.ts`](../web/audio-power.d.ts); a complete
gesture-handler example is in the [package guide](../packages/browser/README.md#package-owned-realtime-audio).

```ts
import type { GraphEngine } from "./graph-engine.js";

export interface AudioPowerOptions {
  readonly contextOptions?: AudioContextOptions;
  readonly wasmUrl?: string | URL;
  readonly processorUrl?: string | URL;
  readonly closeTimeoutMs?: number;
}

export interface AudioSetup {
  readonly context: AudioContext;
  readonly engine: GraphEngine;
  readonly powerOff: AbortSignal;
}

export type AudioEnd =
  | { readonly reason: "turnedOff" }
  | { readonly reason: "failed"; readonly error: Error };

export interface PoweredAudio<Value> {
  readonly context: AudioContext;
  readonly ready: Promise<Value>;
  readonly ended: Promise<AudioEnd>;
  readonly resume: () => Promise<void>;
  readonly turnOff: () => Promise<void>;
}

export interface AudioPower {
  readonly turnOn: <Value>(
    setupAudio: (audio: AudioSetup) => Promise<Value>,
  ) => PoweredAudio<Value>;
}

export function AudioPower(
  options?: AudioPowerOptions,
): AudioPower;
```

#### Admission and readiness

`AudioPower()` stores options only. It creates no context, engine, or listener.
Keep the owner across power cycles. Owners are independent; one owner admits only
one generation that has not started retiring.

Call `turnOn()` directly from the user gesture, before any await. It validates
the callback and current slot before allocating a context:

- A non-callable callback throws `TypeError`.
- An occupied owner throws `InvalidStateError` without creating another context.
- A native context construction error is thrown synchronously.

Those failures return no handle, so a `ready.catch(...)` cannot handle them:
wrap `turnOn()` itself in `try`/`catch`. Once a context is acquired, the owner
attaches its listener and invokes native `resume()` in the same gesture stack,
before returning a frozen handle. Subsequent startup failures, including a
synchronous exception from that first native resume, reject `ready`, publish
failed `ended`, and trigger cleanup rather than escaping from `turnOn()`.

Setup order: await admission, suspend, await the captured cumulative retirement
tail, create GraphEngine, call setup while suspended, resume, connect destination,
then resolve `ready` with the exact setup value. Setup mounts/configures graphs
and calls `play()` itself; mount every graph before the first play. Context and
engine options are validated by AudioContext and GraphEngine, respectively.

#### Failure observation versus cleanup completion

| Observation | Settlement | What it does not imply |
|---|---|---|
| `ready` fulfills | Setup's exact return value, after final resume and connection | That the engine cannot fail later |
| `ready` rejects | Primary startup failure, or `AbortError` for clean retirement before readiness | That cleanup has finished |
| `ended` resolves with `failed` | Primary failure immediately; otherwise the first cleanup error after cleanup | That cleanup has finished when a primary failure was published |
| `ended` resolves with `turnedOff` | Clean retirement after package-owned cleanup | That arbitrary application setup work has stopped |
| `turnOff()` settles | All applicable package-owned cleanup steps have been attempted | That cleanup succeeded if the promise rejected |

Observe `ready` rejection even when `ended` is the single source of user-facing
failure reporting. An already-settled `ready` never changes: processor failure
after readiness is observed through `ended`. Multiple and late `ended` observers
receive the same frozen result; `ended` never rejects.

`turnOff()` synchronously retires its own generation, releases admission, and
aborts the setup signal. Concurrent and later calls return one retained cleanup
promise. Call and await it to join cleanup even after receiving failed `ended`;
doing so on an old handle cannot retire a replacement.

Cleanup bypasses arbitrary pending setup and attempts every applicable step:
disconnect output, close engine, close context, in that order. The first cleanup
error rejects `turnOff()`, but later steps are still attempted. A pending engine
acquisition is joined: any late acquired engine is closed exactly once.

Setup, admission, suspension, engine creation, final resume, connection, and
processor failures can supply the retained primary error. A later cleanup error
cannot replace it in `ended`. The two results therefore answer different questions:

- Primary failure, successful cleanup: `ended` is failed; `turnOff()` fulfills.
- Primary failure and cleanup failure: `ended` retains the primary error;
  `turnOff()` rejects with the first cleanup error.
- Cleanup failure only: failed `ended` and rejected `turnOff()` carry the same
  error. Avoid reporting it twice.
- No failure: `ended` is turnedOff; `turnOff()` fulfills.

Native `Error` and `DOMException` identity and cause survive the MoonBit boundary,
including errors from another realm such as an iframe. Non-Error throws are
normalized. Clean turn-off before readiness, including external context
closure, rejects `ready` with `AbortError`. The close-acknowledgement deadline
(`closeTimeoutMs`, default 5000ms) belongs to the engine; it does not bound setup,
the browser's `AudioContext.close()`, or total retirement time.

#### Borrowed resources and cooperative cancellation

The exposed context and setup engine are borrowed, not transferred to the
application. Observe context state and control graphs; use `PoweredAudio` for
resume and shutdown. Do not directly resume/suspend/close the owned context or
connect/close the engine during managed setup. `readonly` prevents replacing the
context property, not invoking native mutators. External context closure is
supported as clean retirement unless a failure was already retained, not as the
recommended shutdown API. Use the root GraphEngine for caller-owned lifecycles.

Retirement aborts `powerOff` and prevents late setup results from publishing
readiness. It cannot forcibly stop a JavaScript callback or undo application
side effects. Pass `powerOff` to cancellable operations such as
`fetch(url, { signal: powerOff })`; after an uncancellable await, check
`powerOff.throwIfAborted()` before further application work. Attach setup
listeners with `{ signal: powerOff }` to detach them on retirement. Application
timers, subscriptions, and other resources remain the caller's responsibility.

Replacement context admission starts in its new gesture, while replacement
engine creation waits for all earlier retirement barriers on that owner,
regardless of their cleanup result. Do not await predecessor cleanup before
calling `turnOn()` and lose activation. The package protects its resources from
stale completions; application callbacks must still check that their generation
is current before updating UI. It does not implement automatic retry.

#### Resuming a ready generation

Call `resume()` directly from a gesture, not after an await or through an
application command queue. It rejects `InvalidStateError` before readiness,
during/after retirement, or when observing a closed context. When already running
it resolves without calling native resume. Otherwise it invokes native resume
synchronously, including for interrupted contexts; concurrent calls during that
restore share one promise.

Clean retirement during restore rejects the pending restore with `AbortError`
without reviving the generation. A native resume failure rejects the restore,
publishes failed `ended`, and starts cleanup. Handle the method rejection for
the gesture's outcome; it is not a second independent engine failure.
Starting again after failure requires a new `turnOn()`, not `resume()`.

#### Host ownership state and arbitration

The production `audio_power` executable in the JS-host module owns lifecycle
policy. Its generated ESM ships privately in the npm package. Handwritten JS
only adapts Web APIs and frozen public objects; it contains no lifecycle races.
The existing EngineLifetime supplies processor observation and engine close.

The internal ownership interface is `Owner::turn_on(setup)` plus
`Generation::resume_audio()` and `turn_off()`, with `ready()`, `ended()`, and
the borrowed context for observation. The JS exports only translate handles and
results. They do not inspect lifecycle states, invoke native resume themselves,
or arrange task groups and predecessor cleanup. `resume_audio` is the internal
MoonBit name because `resume` is reserved; the public JS method remains `resume()`.

Startup and its supervisor are one implementation, not a callback-based
interface callers must coordinate. Ownership regressions exercise this same
interface using per-owner context and engine factories; they do not construct
partial generations or mutate lifecycle states. Production context creation
defaults to the browser's `AudioContext`, and the factory seam stays private.

Each generation variant carries only resources valid at that phase:
Admitting → Suspending → WaitingForEngineGate → CreatingEngine → SettingUp →
Resuming → Ready. Ready may enter Restoring for one retained resume task.
Any live state can enter Retiring, then Ended. No optional-resource bag sits
beside a phase enum. Ready resolves only at Resuming → Ready.

The owner holds an admission slot and a persistent list of typed cleanup
completions independently. Retirement vacates the slot and prepends its completion
before aborting the signal, so reentrant admission captures every pending
predecessor. Completed prefixes are discarded; no JS join task is needed.
Cleanup operations may overlap. New context admission is gesture-synchronous,
but new engine creation waits for every captured completion, even when predecessor
cleanup failed.

Retirement progresses through ResolvingEngineAcquisition, Disconnecting,
ClosingEngine, ClosingContext, and Complete, skipping unacquired resources.
Engine acquisition must yield a bounded ownership disposition before context
close: either cancellation proves no engine can publish, or a late engine is
closed and joined. Arbitrary setup completion is detached, not awaited by cleanup.

A generation supervisor owns setup, processor observation, and acquisition tasks
in one MoonBit task group. Retirement cancels and joins non-owning observers.
The acquisition child is protected until it publishes a typed ownership outcome;
only then does protected cleanup dispose any late engine and close the context.
Internal `Completion[T]` values retain outcomes for cancellable `CondVar` waiters,
without casting a JS deferred between user values and native result records.

All live-generation awaits use one post-await arbiter. It re-reads browser
liveness and commits the transition without another suspension. A closed context
retires cleanly; operation failures otherwise retain the first error. Duplicate
terminal signals return retained results; incompatible internal transitions use
catchable failure, never abort. Native outcomes and context disposition are
parsed once at the adapter boundary.

JS promises remain at public and browser-effect boundaries. `Promise::from_async`
starts only the generation supervisor and public resume operation; resume has its
own scoped retirement observer. Browser-operation observation uses
`js_async.run_promise` with an AbortSignal that actually detaches the observer,
without pretending to cancel the underlying effect. The retirement signal also
crosses this bridge: a bare JS callback broadcasting a MoonBit `CondVar` would
not restart the pinned async runtime's JS scheduler.

Normative transitions (public temporal misuse is rejected before dispatch):

| Current state | Input | Next state | Required effect |
|---|---|---|---|
| `Admitting` | admission succeeded while live | `Suspending` | suspend owned context |
| `Suspending` | suspension succeeded while live | `WaitingForEngineGate` | await the captured cumulative gate |
| `WaitingForEngineGate` | captured gate settled, regardless of predecessor cleanup result | `CreatingEngine` | start engine creation |
| `CreatingEngine` | engine succeeded while live | `SettingUp` | transfer engine ownership and invoke setup |
| `SettingUp` | setup succeeded while live | `Resuming` | retain setup value and start final resume |
| `Resuming` | final resume and connection succeeded while live | `Ready` | settle `ready` with the setup value |
| `Ready` | resume requested while playing | `Ready` | return an already-resolved promise |
| `Ready` | resume requested while temporarily unavailable | `Restoring` | invoke native resume synchronously and retain its promise |
| `Restoring` | resume succeeded while context remains live | `Ready` | settle the retained resume promise |
| `Ready` | resume requested while context is closed | `Retiring` | reject `InvalidStateError` and begin clean external-close retirement |
| `Restoring` | concurrent resume requested | `Restoring` | return the retained resume promise |
| any live operation state | native admission/suspend/engine/setup/resume/connect failure | `Retiring` | retain primary failure and begin cleanup |
| any live state except `CreatingEngine` | `TurnOff` | first applicable `RetirementStage` | abort setup, release current slot, start cleanup, join cleanup into retirement tail |
| `CreatingEngine` | `TurnOff` | `ResolvingEngineAcquisition` | abort creation, release current slot, register ownership disposition in retirement tail |
| `ResolvingEngineAcquisition` | no engine can publish | `ClosingContext` | continue context cleanup |
| `ResolvingEngineAcquisition` | late engine success | `ClosingEngine` | transfer engine to cleanup and close exactly once |
| any live state | context closed | `Retiring` | classify as clean external turn-off and begin cleanup |
| any engine-owning live state | processor failed | `Retiring` | retain processor failure and begin cleanup |
| any retirement stage | cleanup outcome | next retirement stage | preserve first failure |
| `Retiring` or `Ended` | duplicate turn-off/terminal signal | same state | return retained cleanup/end result |


### Live controls

`sound.applyControls(controls)` accepts an ordered batch of 1–64 controls:

- `{ type: "setParam", node, slot, value }` sets a finite numeric parameter.
  Slots are `value0`, `value1`, `value2`, `value3`, or `delaySamples`.
- `{ type: "gateOn", node }` and `{ type: "gateOff", node }` control an ADSR.

`sound.setParams(values)` accepts a partial record of names declared by the
graph. The object must be non-null, non-array, and contain only own enumerable
string keys whose values are finite numbers. Unknown names, malformed records,
and non-finite values reject atomically with `INVALID_CONTROL`; an empty record
is a successful no-op on a valid handle. `setParams` has no current-value cache,
and it does not make raw controls unavailable: applications may use named
updates for shared knobs and raw batches for controls such as notes.

`node` is the original authoring index, not the optimized execution index.
Named references and raw slots can coexist and can update the same target.
These operations take effect between render callbacks, not at sample timestamps.

MoonBit validates the whole batch before changing runtime state. A bad node,
slot, value, or gate target rejects the batch with `INVALID_CONTROL`;
preceding controls in the batch do not take effect. Named update errors use
`INVALID_CONTROL` for unknown names or invalid values. Lifecycle errors take
precedence. Gate-off starts the release tail; keep the graph playing until it
finishes. `pause()` freezes the envelope and is not a substitute for gate-off.
Control decoding and transactional validation are not an allocation-free
audio-thread contract; a real-time allocation/GC audit remains a separate gate.

The dedicated processor is `web/graph-processor.js`. It instantiates the same
browser WASM artifact as the existing browser paths, in its own WASM instance.
Its primitive ABI is `graph_host_init`, `graph_host_clear_input`,
`graph_host_push_char`, `graph_host_mount`, `graph_host_command`,
`graph_host_apply_controls`, `graph_host_set_params`, `graph_host_process`,
`graph_host_sample`, `graph_host_close`, `graph_host_error_length`, and
`graph_host_error_char`.
Input is JSON transmitted as Unicode scalar values; errors are MoonBit-generated
JSON envelopes containing `code`, `message`, and optional `nodeIndex`.
Integer handles exist only in this adapter; MoonBit callers receive typed,
engine-owned handles. `graph_host_close` delegates to the MoonBit engine.
Existing scheduler/demo behavior and exports are unchanged. The earlier
graph builder ABI is replaced, not retained as aliases; deploy the matching
Worklet and WASM together. Application code uses only the public JS methods.

### TypeScript and JavaScript editor support

Keep `web/graph-engine.d.ts` beside `graph-engine.js` when distributing the
module to TypeScript consumers. Imports retain the `.js` extension; TypeScript
resolves the adjacent declaration automatically. No runtime wrapper is required.
The declarations require TypeScript 5.4 or newer (`NoInfer` keeps references
from widening the names declared in `params`).

```ts
import { GraphEngine, type GraphDescription } from "./graph-engine.js";

const graph = {
  params: { volume: 0.1, cutoff: 2_000 },
  nodes: [
    { type: "oscillator", waveform: "triangle", frequency: 220 },
    { type: "biquad", input: 0, mode: "lowpass", cutoff: { param: "cutoff" }, q: 0.7 },
    { type: "gain", input: 1, gain: { param: "volume" } },
    { type: "output", input: 2 },
  ],
} as const satisfies GraphDescription<"volume" | "cutoff">;

const engine = await GraphEngine({ context });
const sound = await engine.mount(graph);
await sound.setParams({ volume: 0.2 }); // updates every volume target
```
The declaration exports `GraphDescription<Name>`, the discriminated
`GraphNode<Name>` union and its node variants, `ParamRef<Name>`, `GraphControl`,
`GraphEngineOptions`, `GraphEngineWaitOptions`, `EngineExit`, `GraphEngine`,
`MountedGraph<Name>`, and `GraphEngineErrorCode`. `Name` is inferred from
`params` keys when mounting; an explicit union such as
`GraphDescription<"volume" | "cutoff">` enables exact ref and update-key
checking. A no-parameter graph does not admit typed nonempty `setParams`
updates. Runtime validation remains authoritative for broadened dynamic data.

Readonly descriptions (including `as const` arrays) are accepted without
requiring a mutable copy. Returned handle properties are readonly, matching
their frozen runtime objects. Bounds, finite numbers, topology, and lifecycle
state remain runtime checks; the declarations do not claim to prove them.
Catch values still require narrowing with `instanceof GraphEngineError`;
`nodeIndex` is optional and `cause` is `unknown`, including arbitrary abort reasons.

JavaScript consumers can annotate descriptions with
`/** @type {import('./graph-engine.js').GraphDescription} */` and enable
`// @ts-check` for diagnostics as well as editor completion.

From the repository root, run `npm run typecheck:browser` to check positive
consumer examples and expected failures for invalid nodes and obsolete APIs.
This uses the existing TypeScript development dependency in `web/live`;
install that project's dependencies with `npm --prefix web/live ci` if needed.
The browser CI `live-smoke` job runs the same command after installing those
dependencies; type failures fail the job independently of browser runtime tests.

### Running the external example and acceptance tests

Install the root npm development dependencies and Chromium first:

```sh
npm ci
npx playwright install chromium
```

Then build and serve matching artifacts:

```sh
NEW_MOON_MOD=0 moon build --target wasm-gc --release
./playwright-serve.sh 8090
# Open http://127.0.0.1:8090/graph-example.html
# In a second terminal:
NEW_MOON_MOD=0 npx --no-install playwright test \
  playwright-tests/graph-engine.spec.js \
  playwright-tests/graph-engine-lifetime.spec.js --workers=1 --retries=0
```

The server script synchronizes WASM assets. Keep `graph-engine.js`,
`graph-processor.js`, and `moonbit_dsp.wasm` together, or supply `wasmUrl` and
`processorUrl` to `GraphEngine`. Serve them over HTTPS or localhost;
deployments must permit their fetch/worklet execution under their CSP.

The tests compare every rendered frame against analytic waveforms using a
real AudioWorklet in `OfflineAudioContext`, including release at a known
render boundary. They also exercise the visible controls using Chromium's
virtual audio output. This is automated PCM/lifecycle evidence, not a
hardware listening verdict or a hard-real-time allocation/GC audit.
`OfflineAudioContext` here is a verification host, not a file-rendering API.

### Standalone synth examples and local distribution

[`examples/basic-synth`](../examples/basic-synth/README.md) contains
framework-free TypeScript and Svelte adapters over one shared core. Both consume
only the package root `@moondsp/browser` and provide the same monophonic
keyboard, volume and filter controls, and single Power on / Power off button.
The vanilla adapter exposes the explicit DOM seam; the Svelte adapter renders
the same state and gestures declaratively. Both start without an `AudioContext`,
cancel partial initialization on Power off, close the full app-owned session,
observe processor failure immediately through `engine.wait()`, and retry with a
fresh session. Neither implements a Worklet nor reaches into the browser ABI.

`npm run pack:browser` builds release Wasm and packs
`packages/browser/moondsp-browser-0.6.0.tgz`. The tarball contains the matching
JS adapter, declarations, Worklet, Wasm, and Apache-2.0 license. This is a local
distribution artifact, not a claim that the package is published to npm.
Consumers install the tarball without MoonBit; only maintainers building the
tarball need the MoonBit toolchain.

Both Vite examples exclude the ESM package from development pre-bundling so
relative asset URLs remain attached to their module. Production builds emit
Wasm and Worklet files separately, with a relative base for subdirectory
deployment. No application-side asset copy script is required.

After rebuilding the tarball, reinstall it in `examples/basic-synth` and restart
the selected adapter's development server so it serves the new package. Do not
combine an old installed package with freshly built loose Worklet or Wasm files.
The [example guide](../examples/basic-synth/README.md#maintainer-setup) includes
installation commands and shared verification coverage for failure recovery,
cancellation, delayed activation, and release tails.

## Supported facade groups

The exact function names below are part of the facade/export contract. They are
grouped by host use case.

```text
demo oscillator:
  reset_phase, tick, tick_source

mono compiled graph:
  init_compiled_graph, process_compiled_block, compiled_output_sample

mono hot-swap graph:
  init_compiled_hot_swap_graph, queue_compiled_hot_swap,
  process_compiled_hot_swap_block, compiled_hot_swap_output_sample

mono topology-edit graph:
  init_compiled_topology_edit_graph, queue_compiled_topology_edit,
  queue_compiled_topology_delete_edit, set_compiled_topology_edit_gain,
  process_compiled_topology_edit_block, compiled_topology_edit_output_sample

stereo compiled graph:
  init_compiled_stereo_graph, process_compiled_stereo_block,
  compiled_stereo_left_sample, compiled_stereo_right_sample

stereo hot-swap graph:
  init_compiled_stereo_hot_swap_graph, queue_compiled_stereo_hot_swap,
  process_compiled_stereo_hot_swap_block, compiled_stereo_hot_swap_left_sample,
  compiled_stereo_hot_swap_right_sample

stereo topology-edit graph:
  init_compiled_stereo_topology_edit_graph,
  queue_compiled_stereo_topology_edit,
  set_compiled_stereo_topology_edit_level,
  process_compiled_stereo_topology_edit_block,
  compiled_stereo_topology_edit_left_sample,
  compiled_stereo_topology_edit_right_sample

exit-deliverable graph:
  init_exit_deliverable_graph, process_exit_deliverable_block,
  exit_deliverable_output_sample, set_exit_deliverable_lfo_rate,
  set_exit_deliverable_cutoff, set_exit_deliverable_gain

scheduler pattern/song playback:
  init_scheduler_graph, process_scheduler_block, scheduler_left_sample,
  scheduler_right_sample, scheduler_sample_position, scheduler_cycle_position,
  clear_playback_input,
  push_playback_char, player_update_input, player_restart_input,
  player_play, player_pause, player_state, player_mode, player_pending_count,
  player_skipped_count, player_seek_cycle, player_loop_cycles,
  player_seek_section, player_loop_section, player_whole_song,
  player_section_count, player_section_start, player_section_end,
  player_section_label_length, player_section_label_char,
  player_loop_begin, player_loop_end,
  get_playback_error, get_playback_error_length, get_playback_error_char,
  set_scheduler_bpm, scheduler_bpm, set_scheduler_gain

browser graph-error transport:
  get_browser_last_error, get_browser_error_code, get_browser_error_length,
  get_browser_error_char
```

Group meanings:

- Demo oscillator functions are the Phase-0 demo entry points. Resetting the
  demo also resets browser graph slots and scheduler state.
- Mono and stereo compiled graph groups run fixed demo graphs with live runtime
  controls.
- Hot-swap groups run fixed demo graphs and queue fixed replacement graphs.
- Topology-edit groups run fixed controller demos. The mono path inserts or
  deletes a demo gain node. The stereo path replaces a demo pan node.
- The exit-deliverable group runs the fixed tagless-composition demo graph with
  LFO, cutoff, and gain controls.
- The scheduler group is the browser live-coding host for Mini pattern and song
  text. Demo drum/synth pools and event routing stay internal.
- Parse-error transport exposes the last scheduler parse or routing error.
  Length/char accessors support JS/wasm hosts that cannot receive MoonBit
  strings directly.
- Browser graph-error transport exposes the last graph init, queue, or
  runtime-control error routed through the browser error store.

## Worklet lifecycle and threading

Each browser graph variant owns mutable global slot state. The supported call
sequence is:

1. Call the matching `init_*_graph(sample_rate, block_size)` before audio starts.
2. Call `process_*_block(...)` from the AudioWorklet render path.
3. Read samples with the matching `*_sample(index)` accessor after a successful
   process call and before the next process call.
4. Send `queue_*` and `set_*` calls from the control side between process calls.
   Use the host worklet-message protocol to serialize access.

The browser package does not provide synchronization. Concurrent calls that touch
the same graph variant are outside the contract. Re-initializing a graph with a
new rate or block size rebuilds that variant and must not overlap a process call.

Sample accessors return zero for out-of-range or uninitialized reads.

Compiled, hot-swap, and topology-edit graph exports that return `false` from
init, process, queue, or set calls store browser error details. The
exit-deliverable init/process path uses the same error store.

The `set_exit_deliverable_*` functions return `false` for invalid input without
updating that error store. Scheduler status returns also do not guarantee a
browser-error update.

## Pattern/song parse protocol

Fill the shared UTF-16 input buffer, then consume it with `player_update_input`
or `player_restart_input`. Both accept the same source grammar: optional
bindings and `bpm(number);`, followed by a Pattern or arrangement. Omitted tempo
is 60 BPM. Patterns repeat; finite arrangements end unless followed by `.repeat()`.
There are no public preparation tokens.

Commands return `0` for acceptance, `1` for invalid/unrepresentable input, and
`2` when a Playing/Paused layout change requires Restart. Acceptance is immediate,
including while Paused; it does not wait for a rendered block. Diagnostics use
the shared playback-error buffer. Rejection preserves Current song, transport,
voices, room, and pending material reservations.

Update replaces Current song without starting or rewinding. Changed material
enters at safe boundaries. Restart parses and preflights before resetting and
starting from zero. Play starts Ready/Ended Current song, resumes Paused, or
leaves Playing unchanged. Pause freezes musical state and outputs silence
without suspending the AudioContext. Play without a Current song rejects.

Repeated arrangements must span at least one audio block at the accepted tempo
and sample rate; this limits repetition splitting to two slices per block, not
arbitrary pattern/event density. Finite endpoints are checked on the proposed
clock before mutation. Ready/Ended updates check their future zero-anchored
clock, preserving the old performance and tails on rejection.

Section preview commands act on the **accepted** arrangement, not the unsent
editor draft. `player_seek_section(index)` starts at that occurrence's exact
cycle boundary; `player_loop_section(index)` repeats that occurrence.
`player_seek_cycle(millicycles)` starts once at a cycle offset, and
`player_loop_cycles(start_millicycles, end_millicycles)` repeats a half-open
range that may cross multiple sections. Indexes are zero-based in accepted
occurrence order. Numeric coordinates have 0.001-cycle precision; section
commands use the exact authored fractions instead. A loop must span at least
one render block at the current tempo. `player_whole_song()` clears the loop
and restarts at zero. These commands return `0` on acceptance and `1` on
rejection, without changing accepted material or transport on rejection.
All routes share one seek/loop boundary; original section offsets, overlapping
parts, and seeded note choices remain anchored to accepted song coordinates.
Seeking drops active notes and room tails; natural wrap allows existing release
and reverb tails to decay rather than cutting them. A new Restart clears the
preview loop; compatible live edits keep it.
Each loop wrap restores finite occurrences from the latest accepted score:
materials skipped by an edit behind the loop cursor can enter on the next pass.
Seeking, including after natural song end, restores eligible accepted material
at the requested position before playback resumes.

The worklet `player-receipt` carries accepted `sections` as
`{label,start,end}` and `loopRange` as `{begin,end}` or `null`.
`player-status` carries `loopRange`; the host retains the last accepted
section layout between receipts. Before playback initialization, loop bound
getters return `-1`; the accepted section getters return zero/empty on invalid
indices.

`set_scheduler_bpm` returns `0` after changing all routes, or `1` on rejection
with a playback diagnostic. Rejection preserves the current transport and tempo.
Range-valid numbers can still be unrepresentable at the current transport
position; hosts must consume the result rather than assume success.
`scheduler_bpm` returns the effective BPM rounded to 0.001, or zero before
scheduler initialization. Do not compare it to the requested double to infer
success: rounding is part of an accepted change.

See the technical reference's browser Player section for retained-material
timing and the complete state/receipt contract.

### Migrating prepared-playback clients

This is a breaking cutover for the scheduler/player facade, not a change to
`GraphEngine` or `AudioPower`. Remove token storage and split prepare/apply
transactions; the old symbols and wire aliases are not retained.

| Removed API/protocol | Replacement |
|---|---|
| `prepare_pattern_input()` / `prepare_song_input()` | Fill the same UTF-16 buffer, then call `player_update_input()` or `player_restart_input()`; the source grammar selects Pattern versus arrangement |
| `apply_prepared_playback(token, false)` | `player_update_input()` performs preparation and acceptance together |
| `apply_prepared_playback(token, true)` | `player_restart_input()` preflights, resets, and starts atomically |
| `discard_prepared_playback(token)` | Delete token bookkeeping. Cancel an unsent editor update locally; an accepted command is not a deferred preparation that can be discarded |
| `restart_playback()` | Fill the input buffer with the desired source and call `player_restart_input()`. To rewind Current song rather than the draft, retain and resubmit the last accepted text |
| `apply-score` with `policy: "continue"` / `"restart"` | `player-update` / `player-restart`, each with `{ id, input }`, where `input` is the immutable schema-1 wire string; omit the old `mode`, `policy`, and `revision` fields |
| `restart-playback` | `player-restart` with `{ id, input }` |
| `pattern-updated`, `song-updated`, `playback-restarted`, and their old error replies | Correlate immediate `player-receipt` messages by `id`; handle `accepted`, `restartRequired`, and `message` |
| `playback-superseded` / render-triggered `didRender()` acknowledgement | No replacement notification. Coalesce unsent edits in the host; accepted commands receive their own immediate receipts |
| `PlaybackController.setTempo(data)` | `PlaybackController.handle({ type: "set-scheduler-bpm", bpm, revision })` for the separate legacy demo control |

Request IDs are positive safe integers. A receipt's `samplePosition` is the
owner's next unrendered sample, not the removed `acceptedAtSample` or a promise
that every material is audible. `pendingCount` and `skippedCount` describe that
distinction. `player-play` starts Ready/Ended, resumes Paused, and leaves Playing
unchanged; it is not an unconditional replacement for the old rewind call.

MoonBit scheduler consumers must also migrate the removed tempo validators and
`active_*` / `has_pending_*` snapshot observations; the
[scheduler migration table](../scheduler/README.mbt.md#migrating-tempo-and-snapshot-observation)
lists each replacement.

## Scheduler status and introspection

The supported consumers are the live editor's transport display, its distinction
between Draft submission and score acceptance, and real-WASM protocol/debug
checks. These need state, accepted mode/tempo, musical position, and material
transition counts. Initialization is already covered by the Worklet `ready`
handshake. Route counts/kinds, drum codes, scheduler handles, and master-gain
introspection have no current consumer requirement and are not added.

The browser facade and both JS/wasm-gc export lists provide:

| Function | Value |
|---|---|
| `player_state()` | `0` Empty, `1` Ready, `2` Playing, `3` Paused, `4` Ended, `5` Fault |
| `player_mode()` | MoonBit: `PlaybackMode::{None, Pattern, Song}` for the latest accepted score. JS/wasm-gc: `0`, `1`, `2`, respectively. Song includes finite and repeating songs; Fault returns None |
| `scheduler_bpm()` | Accepted tempo, at 0.001-BPM precision |
| `scheduler_sample_position()` | Next unrendered sample, or retained terminal sample in Ended |
| `scheduler_cycle_position()` | Zero-based absolute musical cycles from the piecewise transport clock |
| `player_pending_count()` / `player_skipped_count()` | Pending/skipped musical materials, not routes, voices, or submissions |

`PlaybackMode` is a public value enum defined in `browser`. It carries
no mutable state or runtime handles. MoonBit callers use exhaustive matching;
the Worklet adapter owns the numeric ABI interpretation. Its payload-free
constructors use MoonBit's [constant-enum ABI](https://docs.moonbitlang.com/en/latest/language/ffi.html#types).
The constructor order and the `0`/`1`/`2` mapping are part of this export contract.

The cycle getter reads clock scalars without constructing a rational, allocating
an inspection object, or advancing the scheduler. It is zero before initialization
and in Empty, Ready, or Fault. Pause freezes position; accepted tempo changes
preserve it. Repeating songs continue counting absolute cycles rather than
wrapping the display. Ended retains the completed run's musical endpoint, not
the end of the render quantum or the duration of a subsequently accepted score.
Play from Ended and Restart reset position. Display rounding is presentation
only; clients must not reconstruct this clock from BPM and total samples.
The returned `Double` is a floating-point observation of the exact internal clock,
not an exact scheduling timestamp. Reusable scheduler callers can use
`PatternScheduler::cycle_position()` for the next unrendered position; unlike the
browser getter, that method has no Player session or finite-song endpoint policy.

These are render positions, not measured or estimated speaker positions.
Acceptance can occur while Paused or Ended and does not imply audible output.
Pending materials can still be using previous accepted versions. Route
projections share musical identities and transition boundaries, so one material
does not become six pending items because it has six output routes. New identities
and retired identities count separately: replacing anonymous materials can
produce both additions and removals, unlike editing named continuing materials.
Status reporting preserves those existing scheduler semantics.

## Live editor playback ownership

The live editor routes draft edits and Play/Pause/Restart through `Player` in
`web/live/src/playback.ts`. MoonBit owns Current song and musical state; the
TypeScript adapter owns session capabilities, command correlation, edit-version
diagnostics, debounce cancellation, and revealing audio after acceptance.
`main.ts` renders `PlaybackView` rather than handling worklet replies.

Tempo and Pattern/arrangement selection belong to source, not separate UI
fields. Tempo is accepted over 0.001–1000 BPM and rounded to 0.001 BPM.
`RequestId` admits positive safe integers and never wraps.

An accepted source remains Current song even if the draft later becomes invalid.
Play resumes that accepted song; Restart explicitly submits editor text.
A delayed rejection cannot annotate a newer draft. Connection epochs quarantine
retired replies and failures so they cannot mutate a subsequent run.

`PlaybackView` retains `draftVersion`, `acceptedVersion`, and `inFlightVersions`
separately. `draftStatus` is `unsubmitted`, `queued`, `submitting`, `accepted`,
`rejected`, or `invalid`. The current Draft's syntax/preparation error is
`invalid`; a correlated owner refusal is `rejected`. A valid edit first queues
for debounce and automatic backpressure, not acceptance. Only a successful
source receipt changes the accepted version; Play/Pause and periodic status do
not. Explicit untracked text inputs have a null accepted version and cannot
mark an equal-text Draft accepted. Close/failure clears accepted ownership.
Source acceptance ordering is independent of control-receipt ordering, and a
late acceptance cannot erase a newer refusal of the same Draft.

The UI leads with tempo/position and an actionable explanation of the current
edit: ready to play, sending, accepted, or needing correction. Pending parts
remain a separate sentence, so acceptance never implies immediate adoption.
Editor/accepted/in-flight versions and raw transition counts are available in
the keyboard-accessible Technical details disclosure, not the primary display.
Position refreshes are not live screen-reader announcements. The compiled demo
does not display scheduler status.

Numeric musical states are Empty, Ready, Playing, Paused, Ended, and Fault
(0 through 5). The UI displays Empty as Ready and adds Starting during opening.
Pause during initial Starting cancels that start locally with `AbortError`;
it does not send Pause to an Empty owner or fabricate an accepted receipt.
Startup Pause and `Player.close()` abort initialization, disconnect partial
resources, and await owned context cleanup. Concurrent closes share retirement,
and an immediate Play waits for that retirement before opening afresh.

`AudioEngine.openSession(deliver, signal?)` returns `OpenSessionResult`: an
opened scheduler or compiled session, a failure, or busy. Cancellation rejects
with `AbortError`. One five-second deadline covers all initialization stages,
including suspended-context resume and the WASM request; timeout is a failure,
not cancellation. Non-abortable native completions cannot activate a retired
graph. Native context-close completion is still required before retirement
finishes. The signal is detached after opening and cannot cancel an active
session. An opened session starts muted.
The adapter owns AudioContext, AudioWorklet, suspension, teardown, and output
gain; it does not expose nullable-node command methods.

Player sources are subject to the
[structural admission limits](technical-reference.md#browser-player-ownership-and-source-updates):
8,192 code units, bounded syntax/query-plan depth, 128-step Euclidean rhythms,
128 occurrences, 256 source/retained material entries per route, and conservative
event/work expansion bounds at 1000 BPM.
Admission checks future callback branches and full-cycle sequence queries,
not just a sample of the opening blocks. Rejection preserves Current song.
Material admission includes accumulated entries waiting for replacement/removal
and future occurrences, not just the latest source. It checks all route clocks
and proposed material states before installing any route. Waiting for removal
boundaries or explicitly restarting can recover retained capacity.
The low-level Mini library does not impose browser limits by default.

| Session method | Meaning | Completion |
|---|---|---|
| `update(id, input)` | Accept immutable `PlaybackInput` without rewinding | Immediate Player receipt |
| `restart(id, input)` | Accept immutable editor input, reset and start | Immediate Player receipt |
| `play(id)` / `pause(id)` | Submit musical transport intent | Immediate Player receipt |
| `fadeIn()` | Schedule an 80ms output fade-in | Does not acknowledge a score or confirm audible output |
| `close()` | Expire the session, then fade out and suspend its graph | Returns `Promise<CloseSessionResult>`; a healthy graph may be reused |

Only scheduler sessions expose the four musical commands. These commands and
`fadeIn` return `SessionCommandResult`: `issued` means posted or locally
scheduled, not that DSP accepted the command or produced audible output.
`session-expired` means nothing was issued. Obtain a new session with
`openSession` only after retirement completes.

Session commands share one ownership check. Once closing begins, every command
from that session is rejected as `session-expired`, including after a later run
reuses the healthy graph. `CloseSessionResult` is `closed` or `session-expired`;
an expired close cannot stop a new run.

Graph health and playback-run freshness are distinct. Graph-bound listeners
continue handling runtime/protocol failures during closing, suspension, and
resumption; failures dispose the graph and prevent its reuse. Player receipts
are delivered only to an active run. Async close/resume completions
check their operation identity before changing state, so a failure or immediate
Retry cannot be overwritten. The resuming state also owns completion of the
open request: it returns failure even if closing the faulty context leaves the
browser's native resume promise pending.

`decodeWorkletMessage` is the single live-editor wire decoder. It turns
`unknown` into complete typed events or an explicit protocol failure, which
tears down the graph and enables Retry. `player-receipt` includes the request
ID, operation, acceptance, submitted `draftVersion` (or null for untracked inputs
and Play/Pause), and full state projection: `state`, `mode`, `cyclePosition`,
`samplePosition`, `tempo`, `pendingCount`, and `skippedCount`. `PlaybackController`
converts the low-level ABI codes before publishing either kind of message:
`state` is `Empty`/`Ready`/`Playing`/`Paused`/`Ended`/`Fault`, and `mode` is
`none`/`pattern`/`song`. The live decoder validates those strings; it does not
interpret ABI codes. Numeric, missing, or unknown state/mode values and missing,
negative, or non-finite cycle position are protocol errors, not fallback values.
Rejections require a boolean
`restartRequired` and diagnostic `message`; clients do not infer recovery from
message wording. `player-status` refreshes the state projection between commands.
The legacy demo tempo command remains separate from the live editor protocol.

The compiled JS/wasm-gc mode export remains numeric and the existing export
names and state codes are unchanged. The MoonBit source return type of
`player_mode()` intentionally changes from `Int` to `PlaybackMode`; migrate
numeric comparisons to enum matching. The Worklet protocol is a coordinated
cutover: clients require string-valued `state` and `mode`, plus `cyclePosition`.
Deploy the UI, Worklet adapters, and WASM from the same build. Legacy numeric
messages are rejected rather than accepted alongside the new schema.

Controlled tests cover startup cancellation, cleanup barriers, receipt ordering,
retired sessions, and stale edit diagnostics. Browser and real-WASM tests cover
paused updates, invalid Restart preservation, Ended replay, source tempo, and
transport freezes.
`audio-lifecycle.spec.ts` exercises real Web Audio close/resume operations with
injected failures and stalled loading stages: Stop/suspended/resuming failures,
cancelled fetch/resume, late body completion, total initialization timeout,
immediate Retry, and obsolete capability commands.

## Browser graph-error protocol

Browser graph and runtime-control failures that route through the browser error
helpers store both a numeric code and a string message. The code names below are
documentation names for host code, not additional worklet exports.

| Documentation name | Code | Meaning |
| --- | --- | --- |
| `MOONDSP_BROWSER_GRAPH_ERROR_NONE` | `0` | no browser graph error |
| `MOONDSP_BROWSER_GRAPH_ERROR_NOT_INITIALIZED` | `1` | graph not initialized |
| `MOONDSP_BROWSER_GRAPH_ERROR_COMPILE_REJECTED` | `2` | compile or replacement graph rejected |
| `MOONDSP_BROWSER_GRAPH_ERROR_HOT_SWAP_QUEUE` | `3` | hot-swap queue failed |
| `MOONDSP_BROWSER_GRAPH_ERROR_TOPOLOGY_QUEUE` | `4` | topology queue failed |
| `MOONDSP_BROWSER_GRAPH_ERROR_RUNTIME_CONTROL` | `5` | runtime control failed |
| `MOONDSP_BROWSER_GRAPH_ERROR_INIT` | `6` | graph initialization failed |

The graph, queue, process, and runtime-control exports keep their boolean result
ABI. When a call returns `false` and routes through the browser error helpers,
`get_browser_error_code()` exposes one of the codes above. The scheduler text
protocol uses its own error buffer and does not update this graph-error code.

For JS and wasm-gc hosts, the supported graph-error message transport is
`get_browser_error_length()` with `get_browser_error_char(i)`. The accessors
return the message as UTF-16 code units, and out-of-range indices return `0`.
`get_browser_last_error()` remains a string-returning facade/worklet export for
compatibility; direct string crossing is not the canonical JS/wasm-gc transport.

## Worklet selection and ownership

| Entry point | Worklet module / registered processor | Purpose |
|---|---|---|
| Live editor, default or `?audioMode=scheduler` | `web/scheduler-processor.js` / `moondsp-scheduler` | Pattern/song playback |
| Live editor, `?audioMode=compiled` | `web/processor.js` / `moonbit-dsp` | Compiled demo graph; editor score updates are not submitted |
| Demos and probe modes implemented in `processor.js` | `web/processor.js` / `moonbit-dsp` | Graph controls, hot swaps, topology edits, and optional scheduler/probe modes selected through processor options |
| Dedicated scheduler probes (`playwright-tests/scheduler-probe.spec.js`) | `web/scheduler-probe-processor.js` / `moondsp-scheduler-probe` | Isolated scheduler-path rendering probes |
| Dedicated crackle probes (`playwright-tests/crackle-probe.spec.js`) | `web/crackle-probe-processor.js` / `moondsp-crackle-probe` | Isolated crackle-investigation rendering probes |

The live page selects compiled mode only for the exact `audioMode=compiled`
value; other values use scheduler mode. Its compiled session passes
`useScheduler: false` and `useProbeSine: false`. Do not infer the registered
processor's mode from its filename alone: `processor.js` also retains a
scheduler path selected through `useScheduler` and available WASM exports.

The dedicated probe tests load their own modules into `OfflineAudioContext`;
they do not select a live-editor mode. These two probe modules are separate
from the three JS assets copied into the live app (`playback-controller.js`,
`processor.js`, and `scheduler-processor.js`). Running the live suite does not
run these dedicated probe suites.

Message responsibilities:

- Both scheduler paths use `PlaybackController` in `web/playback-controller.js`
  for `player-update`, `player-restart`, `player-play`, `player-pause`, and the
  separate revisioned demo `set-scheduler-bpm`. It returns immediate owner
  receipts; it does not retain public tokens or wait for rendering.
- Each worklet owns WASM initialization, graph initialization, sample copying,
  readiness and runtime errors. The dedicated scheduler reports `ready` after
  graph initialization and refreshes Player status every 32 rendered quanta.
- `set-scheduler-gain` is handled by the worklets, not the shared controller.
- `processor.js` additionally handles demo controls such as `set-freq`,
  `set-gain`, `set-pan`, `set-delay-samples`, `set-cutoff`, and graph queue
  messages. These are not the dedicated live scheduler's protocol.

Keep demo/probe behavior out of the dedicated scheduler. This division does not
require removing the existing scheduler mode from the demo worklet or duplicating
the shared playback protocol.

## Building and verifying the actual worklet assets

Run the following from the repository root. Install live dependencies once per
checkout with `npm ci --prefix web/live`.

| Changed source | Preparation before testing |
|---|---|
| Live TypeScript, HTML, or CSS | `npm --prefix web/live run build` |
| Worklet JS or shared playback controller | `npm --prefix web/live run build` |
| MoonBit code or WASM export manifest | Build WASM and copy it first, then build the live app as below |

```bash
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
./playwright-sync-wasm.sh
npm --prefix web/live run build
```

The artifact chain is:
`_build/wasm-gc/release/build/browser/browser.wasm`
→ `web/moonbit_dsp.wasm`
→ `web/live/public/moonbit_dsp.wasm`
→ `web/live/dist/moonbit_dsp.wasm`.
`playwright-sync-wasm.sh` performs the first copy.
The live `prebuild`/`predev` hook runs `scripts/sync-assets.mjs`, copying the
WASM and all three worklet/controller JS modules from `web/` into `public/`.
Vite's production build copies those public assets into `dist/`.

`sync:assets` does not compile MoonBit, and `preview` does not rebuild anything.
Missing assets currently produce sync warnings rather than a failing exit;
read the output and do not treat an old public/dist copy as a successful build.
When using an already-running dev server after a worklet/WASM edit, rerun
`npm --prefix web/live run sync:assets` and reload the page to create a fresh
worklet. Playwright never reuses an existing preview server, because that could
silently test assets from another checkout. Override the default port when it is
already occupied:

```bash
MOONDSP_LIVE_PLAYWRIGHT_PORT=5191 \
  MOONDSP_VIRTUAL_AUDIO=1 npm --prefix web/live test -- --retries=0
```

The root graph suite similarly accepts `MOONDSP_PLAYWRIGHT_PORT`; the vanilla
and Svelte synth suites accept `MOONDSP_VANILLA_SYNTH_PLAYWRIGHT_PORT` and
`MOONDSP_SVELTE_SYNTH_PLAYWRIGHT_PORT`, respectively.

### Automated rendering without an audio device

The command above enables virtual audio output for the live suite.

The live Playwright configuration adds Chromium's `--disable-audio-output`
only when `MOONDSP_VIRTUAL_AUDIO=1`. Chromium supplies virtual output timing;
AudioContext, AudioWorklet, and WASM processing remain real. This avoids
depending on an OS audio sink, including a stalled WSLg/RDP output path.
It is not a mock of playback messages or DSP.

This suite covers UI behavior, score/tempo acceptance and rejection, Stop/Retry,
and expired-session commands. A focused iteration can use:

```bash
MOONDSP_VIRTUAL_AUDIO=1 npm --prefix web/live test -- tests/audio-lifecycle.spec.ts tests/bpm.spec.ts --retries=0
```

After facade/export changes, also run `scripts/check-browser-abi.sh` and the
MoonBit checks/tests; virtual output does not replace the ABI guard.

### Physical output and listening

```bash
npm --prefix web/live run dev -- --host 127.0.0.1
```

Open the printed URL in a normal browser connected to the intended output
device. Use the default URL for live scheduler playback and
`?audioMode=compiled` for the compiled demo. The environment switch above
affects only Playwright, not the application or the dev server.

Check sound onset, sustained playback, edits, Stop and Play again. Listen for
clicks, gaps, and distortion. Record browser/version, OS, output device,
selected mode, score, and any sample-rate/latency URL overrides. Report these
observations separately from automated test results: virtual-output success
does not prove physical sound quality or behavior in other browsers.
Likewise, an AudioContext whose clock stalls even without moondsp is output
environment evidence, not by itself evidence of a DSP regression.

## Source facade versus worklet exports

The MoonBit source facade and the worklet export ABI are reviewed together, but
they serve different hosts:

- The source facade is the public MoonBit package API. It includes MoonBit
  calling conventions such as labelled arguments on `tick` and `tick_source`.
- The worklet ABI is the exported function-name list for JS and wasm-gc hosts.
  Hosts call exported names with positional primitive values.
- A public MoonBit function is not a worklet export unless it appears in the
  target's `exports` list in `browser/moon.pkg`.
- A type or helper exposed by `browser/internal/*` is not part of either public
  contract, even if it is `pub` inside that internal package.

The JS and wasm-gc export lists should stay in lockstep unless a PR documents a
target-specific reason to diverge.

## Unsupported browser internals

The following packages and concepts are outside the public API:

- `dowdiness/moondsp/browser/internal/slot`
- `dowdiness/moondsp/browser/internal/demo_templates`
- `dowdiness/moondsp/browser/internal/playback_host`
- route selectors, scheduler routes, sound pools, demo template shapes, temporary
  output buffers, and scheduler-owned transport state

Issue #150 / PR #155 removed the legacy browser facade route shell types
`SoundPool`, `SchedulerRouteSelector`, and `SchedulerRoute`. Those names only
preserved an old leaked interface shape; they never defined the routing API.

Do not recreate them to expose scheduler internals. If browser status or
introspection becomes necessary, design it under issue #156 as a new explicit
API.

## Semver and review policy

Treat source facade changes and worklet export changes as public API changes:

- Removing or renaming a facade function is a breaking source API change.
- Changing a facade parameter or return type is a breaking source API change.
- Changing documented result-code semantics is breaking for source and worklet
  hosts.
- Removing or renaming an exported worklet function is a breaking worklet ABI
  change.
- Changing exported argument order or primitive representation is a breaking
  worklet ABI change.
- Adding a new facade function or export is additive, but it still requires ABI
  review so the baseline records the intentional surface growth.
- Moving implementation behind `browser/internal/*` is not breaking when
  `browser/pkg.generated.mbti` and the JS/wasm-gc export lists stay unchanged.

Document breaking changes in `CHANGELOG.md`. Choose the release version from the
stricter of the source API and worklet ABI impact. Do not tag or publish a
release as part of an unrelated browser API documentation or cleanup PR.

## ABI guard workflow

Run the guard before and after browser facade/export work:

```bash
scripts/check-browser-abi.sh
```

The script regenerates MoonBit interface files with `moon info --quiet`, then
compares three reviewed surfaces against
[`browser/browser_abi.baseline`](../browser/browser_abi.baseline):

1. `browser/pkg.generated.mbti`
2. `browser/moon.pkg` JS exports
3. `browser/moon.pkg` wasm-gc exports

Do not update the baseline for docs-only changes or accidental drift. If a
facade/export change is intentional:

1. inspect the failing diff from `scripts/check-browser-abi.sh`;
2. update this guide and `CHANGELOG.md` for the API/ABI impact;
3. confirm the semver impact and downstream compatibility story;
4. run `scripts/check-browser-abi.sh --update`; and
5. rerun `scripts/check-browser-abi.sh` so the PR shows a clean reviewed
   baseline.

The baseline is a review artifact. The source of truth remains the
`browser/pkg.generated.mbti` interface generated by `moon info` plus the
`browser/moon.pkg` export manifest.
