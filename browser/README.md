# Browser host boundary

`browser` is the low-level MoonBit-to-AudioWorklet boundary. It exports
primitive functions for one WASM instance and keeps browser transport state
outside the reusable DSP, graph, engine, and scheduler packages.

Most applications should not call these exports directly. Use
[`web/graph-engine.js`](../web/graph-engine.js) for graph lifecycle from
JavaScript, or use the dedicated scheduler worklet protocol for live pattern
and song playback.

## Architecture context

In moondsp's layered design, `browser` acts as the low-level WASM/Wasm-GC and
AudioWorklet transport adapter:

```text
[ Web Page / UI / Web Audio API ] (AudioContext, AudioWorkletNode)
   ↓ MessagePort / Typed JS API
[ @moondsp/browser / web/graph-engine.js ] (JS lifecycle wrapper)
   ↓ primitive C/WASM export ABI
[ browser ] ← (flat exports: graph_host_*, scheduler_*, demo families)
   ↓ MoonBit memory & engine objects
[ engine ] / [ scheduler ]
   ↓
[ voice ] / [ graph ]
   ↓
[ dsp ]
```

- **Upstream consumers**: `web/graph-engine.js`, `web/graph-processor.js`,
  `web/live/`, and the `@moondsp/browser` package.
- **Downstream dependencies**: Delegates graph compilation and mounting to
  [`engine/`](../engine/) (`GraphEngine`); delegates pattern/song playback to
  [`scheduler/`](../scheduler/) via `browser/internal/playback_host`; uses
  [`dsp/`](../dsp/) and [`graph/`](../graph/) for demo and probe templates.

## API quick reference

| ABI family | Key exports | Purpose |
|---|---|---|
| **Graph Host (Lifecycle)** | `graph_host_init`, `graph_host_mount`, `graph_host_command`, `graph_host_close` | Initialize engine (128-frame quantum), mount JSON graph description, transport play/pause/unmount, close engine |
| **Graph Host (Input & Controls)** | `graph_host_clear_input`, `graph_host_push_char`, `graph_host_apply_controls`, `graph_host_set_params` | Push Unicode scalar JSON, apply raw transactional `GraphControl` batches, or atomically update named parameter sets |
| **Graph Host (Render & Errors)** | `graph_host_process`, `graph_host_sample`, `graph_host_error_length`, `graph_host_error_char` | Render 128-sample block, retrieve output samples, read structured JSON error envelopes |
| **Scheduler Playback** | `init_scheduler_graph`, `clear_playback_input`, `push_playback_char`, `player_update_input`, `player_restart_input`, `player_play`, `player_pause`, `player_state`, `player_pending_count`, `player_skipped_count`, `process_scheduler_block`, `scheduler_left_sample`, `scheduler_right_sample` | Owning Player with unified source parsing, immediate acceptance, material-boundary updates, frozen Pause, and stereo rendering |
| **Diagnostics & Error Inspection** | `get_browser_last_error`, `get_browser_error_code`, `get_browser_error_length`, `get_browser_error_char`, `get_playback_error` | Numeric error codes (`BROWSER_ERROR_*`) and diagnostic messages for host inspection |
| **Compiled & Demo Probes** | `init_compiled_*`, `process_compiled_*`, `queue_compiled_*`, `init_exit_deliverable_graph`, `tick`, `tick_source`, `reset_phase` | Deterministic integration probes and fixed demo graph verification |

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
  frequency (or parameter reference);
- `adsr` with `attackMs`, `decayMs`, `sustain`, `releaseMs` (or parameter references);
- `biquad` with `input`, `mode` (`lowpass`, `highpass`, `bandpass`), `cutoff`, `q` (or parameter references);
- `mul` with `input0` and `input1`;
- `gain` with an input index and finite linear gain (or parameter reference);
- one terminal `output` node with an input index;
- optional `params` mapping declaring up to 256 named parameters with finite initial values, referenced by nodes via `{ "param": "name" }`.

MoonBit decodes this data and delegates to the canonical `GraphEngine` compile
path. JavaScript does not contain a second graph compiler or DSP
implementation.

### Live parameter updates

Once mounted, applications can control graphs in two ways:

1. **Named parameter updates (`sound.setParams({ cutoff: 1200, volume: 0.2 })`)**:
   Updates parameters declared in `params` across all referencing nodes. The update
   is validated atomically before applying; unknown names or non-finite values reject
   with `INVALID_CONTROL`. Uses `graph_host_set_params`.
2. **Raw control batches (`sound.applyControls(controls)`)**:
   Sends an ordered batch of 1–64 raw `{ type: "setParam", node, slot, value }`,
   `{ type: "gateOn", node }`, or `{ type: "gateOff", node }` operations targeting
   original authoring node indices. Uses `graph_host_apply_controls`.

See the [browser API contract](../docs/browser-api-contract.md) for lifecycle,
error precedence, cancellation, TypeScript declarations, and deployment.

## Primitive graph-host ABI

AudioWorklet glue uses these exports:

| Phase | Exports |
|---|---|
| Initialize | `graph_host_init` |
| Transfer JSON | `graph_host_clear_input`, `graph_host_push_char` |
| Mount | `graph_host_mount` |
| Control | `graph_host_command`, `graph_host_apply_controls`, `graph_host_set_params` |
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

The Player accepts immutable `@mini.PlaybackInput` envelopes for Pattern and
arranged Song source. Raw source strings are no longer accepted by this ABI:

1. Call `init_scheduler_graph(sample_rate, block_size)`.
2. Call `clear_playback_input`, then send the UTF-16 code units of
   `PlaybackInput::encode_wire()` with `push_playback_char`.
3. Call `player_update_input()` to accept Current song without rewinding, or
   `player_restart_input()` to validate and start the submitted input from zero.
4. Use `player_play()` to start/resume Current song and `player_pause()` to freeze it.
5. Call `process_scheduler_block`, then read left and right samples.

Owner acceptance is immediate, not tied to a render boundary. Changed materials
may remain Pending until their next entry. Invalid source leaves accepted music
unchanged. A paused render emits silence without advancing voices, effects, or
transport; the worklet remains active. Finite songs reach Ended and retain their
tails. Updating Ended changes the song that the next Play starts.

`web/live` keeps one main-thread `Draft` across AudioContext lifetimes. Every
CodeMirror transaction is applied in order, including same-text replacement;
`prepare()` freezes source and exact witnesses together. The scheduler preserves
those origins through pending material boundaries, but does not yet emit source
highlighting observations.

At the MessagePort boundary, Update/Restart use `{ type, id, input }`, where
`input` is the schema-1 JSON string. Explicit untracked callers construct
`{ schema: 1, kind: "text", text }`; tracked callers use Draft preparation rather
than hand-building witnesses. Play/Pause contain no input. Every receipt has
`draftVersion: [epoch, revision]` for tracked submissions, otherwise `null`.
Malformed tracked witnesses are rejected, never retried as plain text.

Source is limited to 8192 UTF-16 code units; the complete wire envelope is limited
to 2097152. The receiver validates integer IDs, UTF-16 ranges, complete atom and
binding coverage, and resolved targets before the existing workload admission.
Rejection preserves accepted source, clocks, voices, and pending material.
Automatic editor updates allow one in-flight request plus the latest unsent
input. Manual Update/Restart discard older unsent automatic work without waiting
for that request.

| Result | Meaning |
|---|---|
| `0` | Operation accepted |
| `1` | Invalid source, unavailable song, or unrepresentable request |
| `2` | Playing/Paused layout change requires Restart |

Read errors through `get_playback_error` or its length/character pair.
`player_state` reports 0 Empty, 1 Ready, 2 Playing, 3 Paused, 4 Ended, or 5 Fault.
`player_pending_count` and `player_skipped_count` distinguish waiting material
changes from finite additions that cannot enter during the current occurrence.

Author `bpm(90);` in source; omission means 60 BPM. Patterns repeat, arrangements
are finite unless suffixed with `.repeat()`. Repetition preserves release and
effect tails. Restart clears them only after the new source has been accepted.
`set_scheduler_bpm` and `set_scheduler_gain` remain lower-level demo/probe controls.

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
