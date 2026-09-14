# Browser facade and worklet ABI contract

The `dowdiness/moondsp/browser` package has two reviewed public surfaces:

- the MoonBit source facade generated in
  [`browser/pkg.generated.mbti`](../browser/pkg.generated.mbti); and
- the AudioWorklet export ABI listed under `link.js.exports` and
  `link.wasm-gc.exports` in [`browser/moon.pkg`](../browser/moon.pkg).

Use this guide when writing host code or reviewing browser API PRs. Keep
architecture rationale in ADRs, and keep graph runtime-control behavior in
[`salat-engine-technical-reference.md`](salat-engine-technical-reference.md).

## Contract summary

- `browser/pkg.generated.mbti` defines the supported MoonBit source facade.
- `browser/moon.pkg` defines the supported JS and wasm-gc worklet exports.
- The browser facade exposes functions only. It has no public browser-specific
  route types, pools, scheduler handles, traits, or host state objects.
- `browser/internal/*` packages are private implementation detail, even when an
  internal package marks a symbol `pub` for package-to-package wiring.
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
[engine contract](salat-engine-technical-reference.md#354-host-independent-graph-engine).
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

### Description and mounting

- A description contains `nodes`, an array of 1–64 node objects. Array indices
  identify connections. The caller supplies the graph; it is not a demo preset.
- `oscillator`: required `waveform` (`sine`, `saw`, `square`, or `triangle`)
  and finite numeric `frequency` in Hz.
- `gain`: required integer `input` referencing a node and finite numeric
  `gain` (linear multiplier, not dB).
- `adsr`: required `attackMs`, `decayMs`, `sustain`, and `releaseMs`. Times
  are milliseconds and sustain is a linear level. It starts with a closed gate.
- `biquad`: required integer `input`, `mode` (`lowpass`, `highpass`, or
  `bandpass`), `cutoff` in Hz, and `q`.
- `mul`: required integer `input0` and `input1`; multiply an audio source by
  an ADSR source to form a playable voice.
- `output`: required integer `input`. The existing compiler validates the
  output structure and graph semantics; exactly one mono output is required.
- The Worklet serializes the description as JSON. MoonBit decodes the browser
  node subset into `DspNode`, then `GraphEngine::mount` uses the existing
  `CompiledTemplate::analyze` and `CompiledDsp::compile_result` path.
  There is no JS node validator, DSP implementation, or second compiler.
  The browser's 64-node description limit is an adapter constraint; the
  direct MoonBit API accepts canonical nodes supported by the mono compiler.
- At most 16 graph handles may be mounted in one engine. Slots can be reused
  before playback, but unmounted handle numbers never recur within an engine.
- Both engine creation and mounting require a suspended context. Mount all
  graphs before the first successful `play`. Mount admission remains closed
  after pausing or unmounting every graph; neither operation reopens admission.
  A new engine is required to mount additional graphs after playback.
- Do not concurrently resume the caller-owned context while creation or
  mounting is pending. Mounting allocates and compiles inside the AudioWorklet
  realm while the caller keeps the context suspended; it is **not**
  background-worker compilation and is not supported during playback.

### Rendering and lifecycle

- `engine.mount(description)` resolves to a `MountedGraph` handle with
  asynchronous `play()`, `pause()`, `unmount()`, and `applyControls()` methods. `MountedGraph`
  is an exported TypeScript type, not a runtime constructor.
  Mounting creates independent DSP state and registers it with the engine's
  output, but does not start playback. The input description is reusable:
  mounting it twice creates two independent graphs.
- `play` starts or resumes processing; `pause` freezes oscillator phase.
  Repeated play/pause operations are allowed.
- `unmount()` permanently removes that graph. Concurrent and repeated calls
  share one completion promise. Once unmounting begins, play, pause, and controls reject
  with `GraphEngineError.code === "INVALID_HANDLE"`. Repeated unmount cannot
  affect another graph that reuses the underlying slot.
  An invalid command does not change another graph or close mount admission.
- All playing graphs sum into `engine.output`, a mono `AudioWorkletNode`.
  Connect it to any compatible Web Audio destination. There is no automatic
  master limiter; callers must choose gains appropriate for the sum.
- Rendering uses the actual context sample rate and currently supports
  128-frame render quanta. A different quantum produces a processor failure,
  rather than silently truncating audio.
- Graph commands take effect between render callbacks. This entry point
  does not provide timestamped scheduling or automation, live graph
  replacement, or polyphonic note allocation.
- `engine.close()` ends the engine and all remaining graphs. It is idempotent,
  including concurrent calls: all callers share one completion promise.
  Closing immediately rejects new requests. It disconnects output and closes
  the message port, but never suspends or closes the caller's context.
  Prefer closing the engine before closing its context. If the context closes
  first, its state-change notification rejects unacknowledged graph commands
  with `ENGINE_CLOSED` and releases local resources. An in-flight `engine.close()`
  then completes without requiring a worklet acknowledgement; repeated close
  calls still share completion. Already-acknowledged commands retain their result.
  Operations on remaining graph handles reject with `ENGINE_CLOSED`; a graph's
  already-issued unmount retains its shared result.
  The close acknowledgement has a deadline (`closeTimeoutMs`, default 5000ms;
  a positive finite number no greater than 2147483647). A missed deadline rejects
  close with `HOST_ERROR`, rejects pending commands, and attempts local processor
  retirement, output disconnection, and port closure. It does not close the context.
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

### MoonBit lifetime observation on the JS host

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

The executable [`browser_test/driver.mbt`](../packages/browser/host/browser_test/driver.mbt)
demonstrates this ownership and the JS export boundary. In `async 0.21.3`,
`Promise::from_async(abort_signal=...)` can leave an externally-cancelled,
otherwise idle Promise waiter queued without rescheduling the JS event loop.
The driver instead delivers abort through a cancellable Promise and completes
its owning task group from inside the async event loop. This requires no
polling, private scheduler API, or patched dependency. Its cancelled JS exports
reject with `AbortError` only after their tasks and cleanup finish.
Known host errors cross that export boundary as structured values, not raised
errors that `from_async` would stringify.

From the repository root, `npm run test:browser-host` runs the isolated MoonBit
tests and real Chromium/AudioWorklet lifetime tests. The Playwright suite builds
the test-only JS driver. `npm run typecheck:graph` checks the public TS surface.

### Live controls

`sound.applyControls(controls)` accepts an ordered batch of 1–64 controls:

- `{ type: "setParam", node, slot, value }` sets a finite numeric parameter.
  Slots are `value0`, `value1`, `value2`, `value3`, or `delaySamples`.
- `{ type: "gateOn", node }` and `{ type: "gateOff", node }` control an ADSR.

`node` is the original authoring index, not the optimized execution index.
For the synth example, oscillator frequency, biquad cutoff, and gain amount
each use `value0` on their respective nodes. See the runtime-control slot
matrix in the [technical reference](salat-engine-technical-reference.md).

MoonBit validates the whole batch before changing runtime state. A bad node,
slot, value, or gate target rejects the batch with `INVALID_CONTROL`; preceding
controls in the batch do not take effect. Lifecycle errors take precedence.
These are between-render-callback updates, not sample-timestamped events.
Gate-off starts the release tail; keep the graph playing until it finishes.
`pause()` freezes the envelope and is not a substitute for gate-off.
Control decoding and transactional validation are not an allocation-free
audio-thread contract; a real-time allocation/GC audit remains a separate gate.

The dedicated processor is `web/graph-processor.js`. It instantiates the same
browser WASM artifact as the existing browser paths, in its own WASM instance.
Its primitive ABI is `graph_host_init`, `graph_host_clear_input`,
`graph_host_push_char`, `graph_host_mount`, `graph_host_command`, `graph_host_apply_controls`,
`graph_host_process`, `graph_host_sample`, `graph_host_close`,
`graph_host_error_length`, and `graph_host_error_char`.
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

```ts
import { GraphEngine, type GraphDescription } from "./graph-engine.js";

const graph = {
  nodes: [
    { type: "oscillator", waveform: "triangle", frequency: 220 },
    { type: "gain", input: 0, gain: 0.1 },
    { type: "output", input: 1 },
  ],
} as const satisfies GraphDescription;

// context is a caller-owned, suspended AudioContext or OfflineAudioContext.
const engine = await GraphEngine({ context });
const sound = await engine.mount(graph);
```

The declaration exports `GraphDescription`, the discriminated `GraphNode` union
and its `OscillatorNode`, `AdsrNode`, `BiquadNode`, `MulNode`, `GainNode`, and
`OutputNode` variants, `Waveform`, `BiquadMode`, `GraphControl`,
`GraphEngineOptions`, `GraphEngine`, `MountedGraph`, and `GraphEngineErrorCode`.
These node types describe authoring data, not Web Audio nodes. Only
`GraphEngine` and `GraphEngineError` are runtime exports. `GraphEngine` is also
the returned engine's TypeScript type; import the remaining names with `import type`.

Readonly descriptions (including `as const` arrays) are accepted without
requiring a mutable copy. Returned handle properties are readonly, matching
their frozen runtime objects. Bounds, finite numbers, topology, and lifecycle
state remain runtime checks; the declarations do not claim to prove them.
Catch values still require narrowing with `instanceof GraphEngineError`;
`nodeIndex` is optional and `cause` is `unknown`, including arbitrary abort reasons.

JavaScript consumers can annotate descriptions with
`/** @type {import('./graph-engine.js').GraphDescription} */` and enable
`// @ts-check` for diagnostics as well as editor completion.

From the repository root, run `npm run typecheck:graph` to check positive
consumer examples and expected failures for invalid nodes and obsolete APIs.
This uses the existing TypeScript development dependency in `web/live`;
install that project's dependencies with `npm --prefix web/live ci` if needed.
The browser CI `live-smoke` job runs the same command after installing those
dependencies; type failures fail the job independently of browser runtime tests.

### Running the external example and acceptance tests

```sh
NEW_MOON_MOD=0 moon build --target wasm-gc --release
./playwright-serve.sh 8090
# Open http://127.0.0.1:8090/graph-example.html
# In a second terminal:
NEW_MOON_MOD=0 npx --no-install playwright test \
  playwright-tests/graph-engine.spec.js --workers=1 --retries=0
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

### Standalone basic synth and local distribution

[`examples/basic-synth`](../examples/basic-synth/README.md) consumes the package
root `@moondsp/browser` only. It provides a monophonic keyboard, volume and
filter controls, and explicit audio/resource lifecycle actions; it does not
implement a Worklet or reach into the browser ABI.

`npm run pack:browser` builds release Wasm and packs
`packages/browser/moondsp-browser-0.6.0.tgz`. The tarball contains the matching
JS adapter, declarations, Worklet, Wasm, and Apache-2.0 license. This is a local
distribution artifact, not a claim that the package is published to npm.
Consumers install the tarball without MoonBit; only maintainers building the
tarball need the MoonBit toolchain.

The Vite example excludes the ESM package from development pre-bundling so
relative asset URLs remain attached to their module. Production builds emit
Wasm and Worklet files separately, with a relative base for subdirectory
deployment. No application-side asset copy script is required.

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
  scheduler_right_sample, scheduler_sample_position, clear_playback_input,
  push_playback_char, prepare_pattern_input, prepare_song_input,
  apply_prepared_playback, discard_prepared_playback, restart_playback,
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

Preparation returns a positive token on success and zero on failure.
Application returns `0` when accepted for the next block, `1` for an invalid
token or unrepresentable change, and `2` when starting/restarting is required
because there is no active score or its mode/layout differs. Restart returns
`0` on acceptance and `1` on rejection. Acceptance is not an application
receipt. Errors update the shared playback diagnostic buffer while retaining
applied and pending playback.
`discard_prepared_playback` returns whether the supplied token was released.

Preparation and application are separate. Fill the shared input buffer and call
`prepare_pattern_input` or `prepare_song_input` to obtain an opaque positive
token. Zero means failure; the unified playback-error accessors expose the
message. Preparation never resets or replaces the active score.

`apply_prepared_playback(token, restart)` consumes a valid token on success
and queues one operation at the next audio block. `restart=false` preserves
transport and voices; `restart=true` replaces and resets atomically.
`discard_prepared_playback(token)` releases an unused prepared result.
`restart_playback()` restarts the applied snapshot without parsing text and
cancels pending replacements. Preparation results are audio-owner objects and
are not transferable snapshots. Only one prepared token is retained at a time.

`set_scheduler_bpm` returns `0` after changing all routes, or `1` on rejection
with a playback diagnostic. Rejection preserves the current transport and tempo.
Range-valid numbers can still be unrepresentable at the current transport
position; hosts must consume the result rather than assume success.
`scheduler_bpm` returns the effective BPM rounded to 0.001, or zero before
scheduler initialization. Do not compare it to the requested double to infer
success: rounding is part of an accepted change.

See the technical reference's browser playback section for admission rules,
error preservation, block receipts and the shared worklet protocol.

## Live editor playback ownership

The live editor sends draft edits, mode selection, example selection, tempo
changes, and Play/Stop intent through `LivePlayback` in
`web/live/src/playback.ts`. The module owns submission revisions, accepted-score
deduplication, debounce cancellation, and the decision to reveal audio after a
successful receipt. `main.ts` renders its `PlaybackView`; it does not handle
worklet replies or reset playback bookkeeping.

`Tempo` parses manual input once: the complete decimal must be finite and at
most 1000 BPM, with values below the manual minimum clamped to 1. Incoming
runtime tempo is decoded separately over its full 0.001–1000 range; a valid
song tempo below the manual minimum must not be clamped. `ScoreSource` parses
empty versus nonempty drafts, not score syntax. `RequestId` admits only
positive safe integers and does not wrap. These values have private constructors.

The BPM field explicitly separates editing text from the committed UI value.
Enter or blur commits and normalizes it; empty or invalid input restores the
committed value, with invalid input reported. Same-value receipts preserve
unfinished text. Correlated tempo acknowledgements supply the runtime's
effective value, including after rejection or rounding. Score receipts carry
effective tempo after render and the most recently processed tempo revision;
an older acknowledgement cannot overwrite a newer tempo commit.
The field variants are `editing` and `displaying`. Displaying the committed UI
value does not claim that the runtime has acknowledged it.

Playback acceptance and diagnostic freshness are separate. A successful
submission can reveal audio even after the draft has changed, but its reply
must not repaint diagnostics for a different draft. Stop and audio failure
invalidate outstanding submissions without reusing their revision numbers, so
late replies cannot reveal a subsequent Play or affect its diagnostics. Retry
submits the latest draft, including edits made while audio was unavailable.

The playback lifecycle is a closed union: stopped, opening,
awaiting-acceptance, playing, compiled, closing, or failed. Only scheduler
states own pending score requests and a scheduler session; playing also owns
an accepted score. `PlaybackView` is a projection, not another mutable state
store. Intent methods return named outcomes instead of validate-and-no-op.

`AudioEngine.openSession` returns `OpenSessionResult`: an opened scheduler or
compiled session, a failure, or busy. An opened session starts muted.
The adapter owns AudioContext, AudioWorklet, suspension, teardown, and output
gain; it does not expose nullable-node command methods.

| Session method | Meaning | Completion |
|---|---|---|
| `submitScore(request)` | Submit a score to the scheduler worklet | A playback receipt reports acceptance or rejection |
| `requestTempoChange(tempo, id)` | Request a scheduler tempo change | A tempo receipt reports the result and effective BPM |
| `fadeIn()` | Schedule an 80ms output fade-in | Does not acknowledge a score or confirm audible output |
| `close()` | Expire the session, then fade out and suspend its graph | Returns `Promise<CloseSessionResult>`; a healthy graph may be reused |

Only scheduler sessions expose `submitScore` and `requestTempoChange`.
The first three methods return `SessionCommandResult`: `issued` means the
command was posted to the worklet or scheduled locally, **not** that the DSP
accepted or finished it. `session-expired` means nothing was issued because the
session is no longer active. Obtain a new session with `openSession` after
closing completes or a fault permits Retry.

Session commands share one ownership check. Once closing begins, every command
from that session is rejected as `session-expired`, including after a later run
reuses the healthy graph. `CloseSessionResult` is `closed` or `session-expired`;
an expired close cannot stop a new run.

Graph health and playback-run freshness are distinct. Graph-bound listeners
continue handling runtime/protocol failures during closing, suspension, and
resumption; failures dispose the graph and prevent its reuse. Score/tempo
receipts are delivered only to an active run. Async close/resume completions
check their operation identity before changing state, so a failure or immediate
Retry cannot be overwritten. The resuming state also owns completion of the
open request: it returns failure even if closing the faulty context leaves the
browser's native resume promise pending.

`decodeWorkletMessage` is the single live-editor wire decoder. It turns
`unknown` into complete typed events or an explicit protocol failure, which
tears down the graph and enables Retry. Rejections require an explicit
`recovery: "edit" | "restart"` field. The shared worklet controller derives it
from native admission status before posting the diagnostic; neither the
controller nor the editor interprets diagnostic wording as a recovery code.
The controller still owns prepared-token transport and render receipts;
next-entry timing is unchanged. Tempo commands require a revision and report
`tempo-updated` or `tempo-error`; score receipts include `tempo` and `tempoRevision`.

Controlled tests cover receipt ordering, retired sessions, and stale tempo
acknowledgements through the same interface as the editor. Real-browser tests
cover startup, parse recovery, Play/Stop, Retry, tempo drafts, protocol failure,
song tempo below the manual minimum, and contextual tempo rejection. The
real-WASM controller tests also distinguish accepted rounding from rejection.
`audio-lifecycle.spec.ts` exercises real Web Audio close/resume operations with
injected failure notifications, including failure during Stop, failure while
suspended/resuming, immediate Retry, and obsolete capability commands.

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
  for `apply-score`, `restart-playback`, and revisioned `set-scheduler-bpm`.
  It owns prepared-token submission, supersession, effective-tempo replies, and
  score receipts after rendering. See the playback protocol above for fields.
- Each worklet owns WASM initialization, graph initialization, sample copying,
  readiness and runtime errors. The dedicated scheduler queues initial restart
  and tempo requests until its first render initializes the graph. `ready`
  announces WASM readiness, not completion of an initial score render.
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
worklet. For production-preview verification, stop an older preview server
on port 5181 before testing, so Playwright cannot reuse a different checkout.

### Automated rendering without an audio device

```bash
MOONDSP_VIRTUAL_AUDIO=1 npm --prefix web/live test -- --retries=0
```

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
