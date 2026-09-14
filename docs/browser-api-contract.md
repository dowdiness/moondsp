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

Use the root, `graph`, `scheduler`, `voice`, `mini`, and `song` packages for
general graph authoring, voice pools, scheduler extension, and Mini parsing. The
browser package is a host/demo ABI, not the general library authoring API.

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
