# Browser host boundary

`browser` is the low-level MoonBit-to-AudioWorklet boundary. It exports
primitive functions for one WASM instance and keeps browser transport state
outside the reusable DSP, graph, engine, and scheduler packages.

Most applications should not call these exports directly. Use
[`web/graph-engine.js`](../web/graph-engine.js) for graph lifecycle from
JavaScript, or use the dedicated scheduler worklet protocol for live pattern
and song playback.

## Public surfaces

The package has two reviewed surfaces:

1. [`pkg.generated.mbti`](pkg.generated.mbti) is the MoonBit source facade.
2. [`moon.pkg`](moon.pkg) lists the JavaScript and wasm-gc exports available to
   an AudioWorklet.

Both are pinned by [`browser_abi.baseline`](browser_abi.baseline). Run
`scripts/check-browser-abi.sh` when reviewing changes. Update the baseline only
for an intentional compatibility change.

The facade exposes functions, not browser-specific route types, pools,
scheduler handles, or host state objects. `browser/internal/` is private even
when an internal symbol is public for package wiring.

## Application graph API

`web/graph-engine.js` wraps the primitive graph-host ABI with promises, typed
lifecycle objects, and browser resource ownership.

```js
import { GraphEngine } from "./graph-engine.js";

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
await context.resume(); // Perform from a user gesture.
await sound.play();

// Later:
await sound.pause();
await sound.unmount();
await engine.close();
await context.close(); // The application, not the engine, owns the context.
```

Creation and mounting require a suspended `AudioContext` or
`OfflineAudioContext`. Mount all graphs before the first successful `play`.
Playback permanently closes mount admission for that engine.

The supported browser description is deliberately narrow:

- 1–64 nodes;
- `oscillator` with `sine`, `saw`, `square`, or `triangle` and a finite
  frequency;
- `gain` with an input index and finite linear gain;
- one terminal `output` node.

MoonBit decodes this data and delegates to the canonical `GraphEngine` compile
path. JavaScript does not contain a second graph compiler or DSP
implementation.

See the [browser API contract](../docs/browser-api-contract.md) for lifecycle,
error precedence, cancellation, TypeScript declarations, and deployment.

## Primitive graph-host ABI

AudioWorklet glue uses these exports:

| Phase | Exports |
|---|---|
| Initialize | `graph_host_init` |
| Transfer JSON | `graph_host_clear_input`, `graph_host_push_char` |
| Mount | `graph_host_mount` |
| Control | `graph_host_command` |
| Render | `graph_host_process`, `graph_host_sample` |
| Diagnose | `graph_host_error_length`, `graph_host_error_char` |
| Close | `graph_host_close` |

`graph_host_push_char` accepts Unicode scalar values, not UTF-16 code units.
`graph_host_command` uses `0` for play, `1` for pause, and `2` for unmount. A
returned handle of `0` means mounting failed. The JavaScript wrapper owns these
integer transport details; native MoonBit callers should use typed
`MountedGraph` handles from `engine` instead.

```moonbit
///|
test "primitive graph host mounts and renders" {
  assert_true(@browser.graph_host_init(48000.0))
  @browser.graph_host_clear_input()
  let description = "{\"nodes\":[{\"type\":\"oscillator\",\"waveform\":\"sine\",\"frequency\":375},{\"type\":\"gain\",\"input\":0,\"gain\":0.1},{\"type\":\"output\",\"input\":1}]}"
  for i in 0..<description.length() {
    @browser.graph_host_push_char(description[i].to_int())
  }

  let handle = @browser.graph_host_mount()
  assert_true(handle > 0)
  assert_true(@browser.graph_host_command(handle, 0))
  assert_true(@browser.graph_host_process(128))
  assert_true((@browser.graph_host_sample(32) - 0.1).abs() < 0.000001)

  assert_true(@browser.graph_host_command(handle, 2))
  @browser.graph_host_close()
}
```

The graph host accepts only 128-frame render quanta. It returns structured JSON
errors through its error-character functions; `web/graph-engine.js` maps them
to `GraphEngineError` values.

## Scheduler playback ABI

The scheduler exports support Mini pattern and song text in an AudioWorklet:

1. Call `init_scheduler_graph(sample_rate, block_size)` before rendering.
2. Clear the text buffer, then send Unicode scalar values with
   `push_playback_char`.
3. Call `prepare_pattern_input` or `prepare_song_input`.
4. Apply the returned token with `apply_prepared_playback(token, restart)`.
5. Call `process_scheduler_block`, then read left and right samples.

Preparation parses and stages data without changing current playback. Applying
a token queues the accepted snapshot for the next render boundary. Prepared
tokens can be discarded. `restart_playback` returns the current accepted score
to its beginning.

`apply_prepared_playback` returns:

| Status | Meaning |
|---|---|
| `0` | Snapshot queued |
| `1` | Invalid or unrepresentable request |
| `2` | Starting or restarting is required |

Read diagnostics through `get_playback_error`, or through its length/character
pair when the host cannot consume MoonBit strings directly. Tempo changes use
`set_scheduler_bpm`; gain changes use `set_scheduler_gain`.

## Demo and compiled export families

The remaining public functions are explicit AudioWorklet ABI families used by
repository demos and integration probes:

- `tick`, `tick_source`, and `reset_phase` for the original oscillator demo;
- `init_compiled_*`, `process_compiled_*`, and sample readers for compiled mono
  and stereo demonstrations;
- `queue_compiled_*` and `set_compiled_*` for hot-swap and topology-edit demos;
- `init_exit_deliverable_graph` and its controls for the integrated graph;
- `get_browser_*` for numeric error codes and text diagnostics.

These are fixed demo templates, not a general graph-authoring interface.

```moonbit
///|
test "demo oscillator reset is deterministic" {
  @browser.reset_phase()
  let first = @browser.tick(freq_hz=440.0, sample_rate=48000.0)
  let second = @browser.tick(freq_hz=440.0, sample_rate=48000.0)
  assert_true(first == 0.0)
  assert_true(second != first)

  @browser.reset_phase()
  @debug.assert_eq(@browser.tick(freq_hz=440.0, sample_rate=48000.0), first)
}
```

## Threading and call order

Each WASM instance is single-threaded. Module-level state persists across host
calls and has no synchronization.

- Initialize before audio starts; initialization allocates graph state and
  buffers.
- Call `process_*` only from the AudioWorklet render callback.
- Deliver queue and control changes between render callbacks through
  `AudioWorkletNode.port` messages.
- Read samples only after a successful process call and before the next one.
- Never initialize, mutate, or render the same export family concurrently.

Reinitializing a family replaces its state and must not overlap rendering.
Successful render paths use preallocated buffers; browser resource creation,
message promises, and cancellation remain JavaScript responsibilities.

## Build and deployment

Build the browser package as wasm-gc:

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
```

Deploy the matching WASM, JavaScript module, and processor together. A stale
processor/export pair is an ABI mismatch. Serve worklet assets over HTTPS or
localhost and allow their fetch and execution in the deployment CSP.

For reusable APIs, start with [`engine/`](../engine/),
[`scheduler/`](../scheduler/), or the [root facade](../README.md), not this ABI
package.
