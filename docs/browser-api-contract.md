# Browser facade and worklet ABI contract

The `dowdiness/moondsp/browser` package has two reviewed public surfaces:

1. the MoonBit source-level facade, generated in
   [`browser/pkg.generated.mbti`](../browser/pkg.generated.mbti); and
2. the AudioWorklet export ABI, listed under `link.js.exports` and
   `link.wasm-gc.exports` in [`browser/moon.pkg`](../browser/moon.pkg).

This guide documents the supported contract for those surfaces. Use it as a
reference/development guide.

Architecture decisions stay in ADRs, and graph runtime-control behavior stays
in [`salat-engine-technical-reference.md`](salat-engine-technical-reference.md)
as the authoritative reference.

## What is public

The supported MoonBit source API is the `Values` section of
`browser/pkg.generated.mbti`. The browser facade intentionally exposes no public
browser-specific types or traits. Downstream code should not infer support from
source files, internal package `.mbti` files, or historical names.

The current facade groups are:

| Group | Supported functions | Contract |
| --- | --- | --- |
| Demo oscillator | `reset_phase`, `tick`, `tick_source` | Phase-0 style oscillator/demo entry points. `reset_phase` also resets all browser graph slots and scheduler state. |
| Mono compiled graph | `init_compiled_graph`, `process_compiled_block`, `compiled_output_sample` | Fixed mono `CompiledDsp` proof graph with runtime frequency/gain controls. |
| Mono hot-swap graph | `init_compiled_hot_swap_graph`, `queue_compiled_hot_swap`, `process_compiled_hot_swap_block`, `compiled_hot_swap_output_sample` | Fixed mono `CompiledDspHotSwap` proof graph and fixed replacement graph. |
| Mono topology edit graph | `init_compiled_topology_edit_graph`, `queue_compiled_topology_edit`, `queue_compiled_topology_delete_edit`, `set_compiled_topology_edit_gain`, `process_compiled_topology_edit_block`, `compiled_topology_edit_output_sample` | Fixed mono topology-controller proof graph. The queue calls insert/delete the demo gain node; `set_*_gain` updates the live demo control. |
| Stereo compiled graph | `init_compiled_stereo_graph`, `process_compiled_stereo_block`, `compiled_stereo_left_sample`, `compiled_stereo_right_sample` | Fixed stereo `CompiledStereoDsp` proof graph with frequency, gain, pan, delay, and cutoff controls. |
| Stereo hot-swap graph | `init_compiled_stereo_hot_swap_graph`, `queue_compiled_stereo_hot_swap`, `process_compiled_stereo_hot_swap_block`, `compiled_stereo_hot_swap_left_sample`, `compiled_stereo_hot_swap_right_sample` | Fixed stereo hot-swap proof graph and fixed replacement graph. |
| Stereo topology edit graph | `init_compiled_stereo_topology_edit_graph`, `queue_compiled_stereo_topology_edit`, `set_compiled_stereo_topology_edit_level`, `process_compiled_stereo_topology_edit_block`, `compiled_stereo_topology_edit_left_sample`, `compiled_stereo_topology_edit_right_sample` | Fixed stereo topology-controller proof graph. The queue call replaces the demo pan node; `set_*_level` updates the live demo control. |
| Exit deliverable graph | `init_exit_deliverable_graph`, `process_exit_deliverable_block`, `exit_deliverable_output_sample`, `set_exit_deliverable_lfo_rate`, `set_exit_deliverable_cutoff`, `set_exit_deliverable_gain` | Fixed tagless-composition demo graph with LFO, cutoff, and gain controls. |
| Scheduler pattern/song playback | `init_scheduler_graph`, `process_scheduler_block`, `scheduler_left_sample`, `scheduler_right_sample`, `parse_and_set_pattern`, `clear_pattern_input`, `push_pattern_char`, `eval_pattern_input`, `parse_and_set_song`, `clear_song_input`, `push_song_char`, `eval_song_input`, `set_scheduler_bpm`, `set_scheduler_gain` | Browser live-coding host for Mini pattern and song text. It owns the demo drum/synth pools and routes events internally. |
| Parse-error transport | `get_scheduler_parse_error`, `get_song_parse_error`, `get_pattern_error_length`, `get_pattern_error_char`, `get_song_error_length`, `get_song_error_char` | Accessors for the last scheduler parse/routing error. The length/char form exists for JS/wasm hosts that cannot consume MoonBit strings directly. |
| Browser error transport | `get_browser_last_error`, `get_browser_error_code`, `get_browser_error_length`, `get_browser_error_char` | Accessors for the last graph queue/control/init error from browser graph exports. |

For general graph construction, external DSL lowering, or scheduler extension,
use the root, `graph`, `scheduler`, `voice`, `mini`, and `song` packages. The
browser facade is a host/demo ABI, not the general library authoring API.

## Worklet lifecycle and threading

Each browser graph variant owns mutable global slot state. The supported call
sequence is:

1. Call the matching `init_*_graph(sample_rate, block_size)` before audio starts.
2. Call `process_*_block(...)` from the AudioWorklet render path.
3. Read samples with the matching `*_sample(index)` accessors after a successful
   process call and before the next process call.
4. Send `queue_*` and `set_*` calls from the control side only between process
   calls, using the host worklet-message protocol to serialize access.

The browser package does not provide synchronization. Concurrent calls that
touch the same graph variant are outside the contract. Re-initializing a graph
with a different rate or block size rebuilds that variant and must not overlap a
process call.

Sample accessors return zero for out-of-range or uninitialized reads.

Compiled, hot-swap, and topology-edit graph exports that return `false` from
init, process, queue, or set calls store browser error details. The
exit-deliverable init/process path uses the same error store.

The `set_exit_deliverable_*` functions return `false` for invalid input without
updating that error store. Scheduler status returns also do not guarantee a
browser-error update.

## Pattern/song parse protocol

The scheduler text protocol currently returns `Int` status codes:

- `0` means parse/routing succeeded and the parsed pattern or song became the
  active playback source.
- `1` means parse/routing failed; the previous active playback source is left in
  place and the error accessors expose the message.

`parse_and_set_pattern(text)` and `parse_and_set_song(text)` accept a whole
string. The `clear_*_input`, `push_*_char`, and `eval_*_input` functions provide
a character-buffer path for hosts that stream text into the worklet.

`get_scheduler_parse_error()` and `get_song_parse_error()` read the same last
scheduler error buffer. The `*_error_length` / `*_error_char(i)` accessors return
UTF-16 code units and return `0` for out-of-range indices.

Issue #158 tracks a future parse/control result-code and error-transport design.
Until that design is accepted, do not reinterpret the existing `0`/`1` parse
codes or browser error code values in this document.

## Browser graph error protocol

Browser graph failures that route through the browser error helpers store both
a numeric code and a string message. The current code values are:

| Code | Meaning |
| --- | --- |
| `0` | no browser graph error |
| `1` | graph not initialized |
| `2` | compile/replacement graph rejected |
| `3` | hot-swap queue failed |
| `4` | topology queue failed |
| `5` | runtime control failed |
| `6` | graph initialization failed |

`get_browser_last_error()` returns the message when the host can receive a
MoonBit string. `get_browser_error_length()` and `get_browser_error_char(i)`
return the same message as UTF-16 code units, with `0` for out-of-range indices.

## Source facade versus worklet exports

The MoonBit source facade and the worklet export ABI are reviewed together, but
they are not the same kind of contract:

- The source facade is the public MoonBit package API. It includes MoonBit
  calling conventions such as labelled arguments on `tick` and `tick_source`.
- The worklet ABI is the exported function-name list for JS and wasm-gc hosts.
  Hosts call exported names with positional primitive values.
- A public MoonBit function is not a worklet export unless it appears in the
  `exports` list for that target in `browser/moon.pkg`.
- A type or helper exposed by `browser/internal/*` is not part of either public
  contract, even if it is `pub` inside that internal package.

The JS and wasm-gc export lists are expected to stay in lockstep unless a PR
explicitly documents a target-specific reason to diverge.

## Unsupported browser internals

The following are intentionally outside the public API:

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

- Removing or renaming a facade function, changing a parameter or return type, or
  changing documented result-code semantics is a breaking source API change.
- Removing or renaming an exported worklet function, changing argument order,
  changing argument/return representation, or changing documented result-code
  semantics is a breaking worklet ABI change.
- Adding a new facade function or export is additive, but it still requires ABI
  review so the generated baseline records the intentional surface growth.
- Moving implementation behind `browser/internal/*` is not breaking when
  `browser/pkg.generated.mbti` and the JS/wasm-gc export lists stay unchanged.

Document breaking changes in `CHANGELOG.md` and choose the release version from
the stricter of the source API and worklet ABI impact. Do not tag or publish a
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
