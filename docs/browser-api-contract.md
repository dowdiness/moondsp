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
  scheduler_right_sample, parse_and_set_pattern, clear_pattern_input,
  push_pattern_char, eval_pattern_input, parse_and_set_song, clear_song_input,
  push_song_char, eval_song_input, set_scheduler_bpm, set_scheduler_gain

parse-error transport:
  get_scheduler_parse_error, get_song_parse_error, get_pattern_error_length,
  get_pattern_error_char, get_song_error_length, get_song_error_char

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

The scheduler text protocol returns stable `Int` result codes. The names below
are documentation names for host code, not additional worklet exports.

| Documentation name | Code | Meaning |
| --- | --- | --- |
| `MOONDSP_BROWSER_RESULT_OK` | `0` | Parse and routing succeeded. The parsed pattern or song became the active playback source, and the scheduler error buffer was cleared. |
| `MOONDSP_BROWSER_RESULT_ERROR` | `1` | Parse or routing failed. The previous active playback source stayed in place, and the scheduler error buffer was updated. |

No additional scheduler text result codes are reserved or emitted. Defensive
hosts may treat any unknown nonzero value as failure, but only `0` and `1` have
stable meanings.

`parse_and_set_pattern(text)` and `parse_and_set_song(text)` accept a whole
string and return the result code directly. The `clear_*_input`, `push_*_char`,
and `eval_*_input` functions provide the same protocol through a character-buffer
path for hosts that stream text into the worklet.

For JS and wasm-gc hosts, use the length/char transport:

- Pattern errors: `get_pattern_error_length()` with
  `get_pattern_error_char(i)`.
- Song errors: `get_song_error_length()` with `get_song_error_char(i)`.

These accessors return the last scheduler error message as UTF-16 code units.
Out-of-range indices return `0`. `get_scheduler_parse_error()` and
`get_song_parse_error()` read the same buffer and remain string-returning
facade/worklet exports for compatibility. Direct string crossing is not the
canonical JS/wasm-gc transport.

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
