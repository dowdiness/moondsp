# Browser facade and worklet ABI contract

The `dowdiness/moondsp/browser` package has two reviewed public surfaces:

- the MoonBit source facade, generated in
  [`browser/pkg.generated.mbti`](../browser/pkg.generated.mbti); and
- the AudioWorklet export ABI, listed under `link.js.exports` and
  `link.wasm-gc.exports` in [`browser/moon.pkg`](../browser/moon.pkg).

Use this guide as the browser API reference for host code and PR review.
Architecture decisions stay in ADRs. Graph runtime-control behavior stays in
[`salat-engine-technical-reference.md`](salat-engine-technical-reference.md).

## Contract summary

- The supported MoonBit source API is the `Values` section of
  `browser/pkg.generated.mbti`.
- The supported worklet ABI is the JS and wasm-gc export lists in
  `browser/moon.pkg`.
- The browser facade exposes no public browser-specific types, traits, route
  objects, pools, or scheduler handles.
- `browser/internal/*` packages are implementation details, even when an
  internal package uses `pub` for package-to-package wiring.
- `browser/browser_abi.baseline` records the reviewed facade/export shape. Update
  it only for an intentional public API or worklet ABI change.

For general graph construction, external DSL lowering, voice pools, scheduler
extension, or Mini parsing, use the root, `graph`, `scheduler`, `voice`, `mini`,
and `song` packages. The browser package is a host/demo ABI, not the general
library authoring API.

## Supported facade groups

The groups below are the supported browser facade. Function names are listed in
plain text so host code can compare them directly with the export manifest.

### Demo oscillator

```text
reset_phase
tick
tick_source
```

These are the Phase-0 oscillator and demo entry points. `reset_phase` also
resets the browser graph slots and scheduler state.

### Mono compiled graph

```text
init_compiled_graph
process_compiled_block
compiled_output_sample
```

This group runs a fixed mono `CompiledDsp` demo graph. The process call accepts
the live frequency and gain controls.

### Mono hot-swap graph

```text
init_compiled_hot_swap_graph
queue_compiled_hot_swap
process_compiled_hot_swap_block
compiled_hot_swap_output_sample
```

This group runs a fixed mono `CompiledDspHotSwap` demo graph. The queue call
stages the fixed replacement graph.

### Mono topology-edit graph

```text
init_compiled_topology_edit_graph
queue_compiled_topology_edit
queue_compiled_topology_delete_edit
set_compiled_topology_edit_gain
process_compiled_topology_edit_block
compiled_topology_edit_output_sample
```

This group runs a fixed mono topology-controller demo graph. The queue calls
insert or delete the demo gain node. The setter updates the live gain control
used by the process call.

### Stereo compiled graph

```text
init_compiled_stereo_graph
process_compiled_stereo_block
compiled_stereo_left_sample
compiled_stereo_right_sample
```

This group runs a fixed stereo `CompiledStereoDsp` demo graph. The process call
accepts frequency, gain, pan, delay, and cutoff controls.

### Stereo hot-swap graph

```text
init_compiled_stereo_hot_swap_graph
queue_compiled_stereo_hot_swap
process_compiled_stereo_hot_swap_block
compiled_stereo_hot_swap_left_sample
compiled_stereo_hot_swap_right_sample
```

This group runs a fixed stereo hot-swap demo graph. The queue call stages the
fixed replacement graph.

### Stereo topology-edit graph

```text
init_compiled_stereo_topology_edit_graph
queue_compiled_stereo_topology_edit
set_compiled_stereo_topology_edit_level
process_compiled_stereo_topology_edit_block
compiled_stereo_topology_edit_left_sample
compiled_stereo_topology_edit_right_sample
```

This group runs a fixed stereo topology-controller demo graph. The queue call
replaces the demo pan node. The setter updates the live level control used by
the process call.

### Exit-deliverable graph

```text
init_exit_deliverable_graph
process_exit_deliverable_block
exit_deliverable_output_sample
set_exit_deliverable_lfo_rate
set_exit_deliverable_cutoff
set_exit_deliverable_gain
```

This group runs the fixed tagless-composition demo graph. The setters update the
LFO rate, cutoff, and gain values used by the process call.

### Scheduler pattern/song playback

```text
init_scheduler_graph
process_scheduler_block
scheduler_left_sample
scheduler_right_sample
parse_and_set_pattern
clear_pattern_input
push_pattern_char
eval_pattern_input
parse_and_set_song
clear_song_input
push_song_char
eval_song_input
set_scheduler_bpm
set_scheduler_gain
```

This group is the browser live-coding host for Mini pattern and song text. It
owns the demo drum and synth pools. Event routing stays internal to the browser
host.

### Parse-error transport

```text
get_scheduler_parse_error
get_song_parse_error
get_pattern_error_length
get_pattern_error_char
get_song_error_length
get_song_error_char
```

These functions expose the last scheduler parse or routing error. The length and
char accessors exist for JS/wasm hosts that cannot receive MoonBit strings
directly.

### Browser graph-error transport

```text
get_browser_last_error
get_browser_error_code
get_browser_error_length
get_browser_error_char
```

These functions expose the last graph init, queue, or runtime-control error that
was routed through the browser error store.

## Worklet lifecycle and threading

Each browser graph variant owns mutable global slot state. The supported call
sequence is:

1. Call the matching `init_*_graph(sample_rate, block_size)` before audio starts.
2. Call `process_*_block(...)` from the AudioWorklet render path.
3. Read samples with the matching `*_sample(index)` accessors after a successful
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

The scheduler text protocol returns `Int` status codes:

- `0` means parse or routing succeeded. The parsed pattern or song became the
  active playback source.
- `1` means parse or routing failed. The previous active playback source stays in
  place, and the error accessors expose the message.

`parse_and_set_pattern(text)` and `parse_and_set_song(text)` accept a whole
string. The `clear_*_input`, `push_*_char`, and `eval_*_input` functions provide
a character-buffer path for hosts that stream text into the worklet.

`get_scheduler_parse_error()` and `get_song_parse_error()` read the same last
scheduler error buffer, while `*_error_length` and `*_error_char(i)` expose that
message as UTF-16 code units. Out-of-range indices return `0`.

Issue #158 tracks a future parse/control result-code and error-transport design.
Until that design is accepted, do not reinterpret the existing `0`/`1` parse
codes or browser error code values in this document.

## Browser graph-error protocol

Browser graph failures that route through the browser error helpers store both a
numeric code and a string message. The current code values are:

| Code | Meaning |
| --- | --- |
| `0` | no browser graph error |
| `1` | graph not initialized |
| `2` | compile or replacement graph rejected |
| `3` | hot-swap queue failed |
| `4` | topology queue failed |
| `5` | runtime control failed |
| `6` | graph initialization failed |

`get_browser_last_error()` returns the message when the host can receive a
MoonBit string. `get_browser_error_length()` and `get_browser_error_char(i)`
return the same message as UTF-16 code units. Out-of-range indices return `0`.

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
