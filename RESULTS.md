# Phase 0 Results / Phase 1 Status / Phase 2 Progress

This file records the outcome of the Phase 0 MoonBit `wasm-gc` AudioWorklet
experiment, the completion status of the Phase 1 DSP primitive set, and the
current Phase 2 graph-compiler checkpoint.

## Current Status

- Phase 0 is complete.
- Phase 1 is complete.
- Phase 2 is complete.
- The browser demo now serves the dedicated `browser/` wrapper package wasm so
  the external browser ABI stays stable as `tick`, `tick_source`, and
  `reset_phase`.
- `web/index.html` and `web/processor.js` now provide the current Phase 2
  browser proof: the AudioWorklet runs a fixed MoonBit `CompiledStereoDsp`
  graph once per render quantum and reads its left/right output blocks back for
  playback, metering, exact feedback-recurrence checks, loop-gain retuning,
  and pan verification. That fixed graph now proves the accepted mono-valued
  `z^-1` feedback slice before `Pan` while still exercising `StereoDelay` and
  `StereoBiquad` on the main browser wasm path.
- `serve.sh` copies the browser wrapper `.wasm` into `web/` and starts a local
  server.
- Browser validation is complete for the current prototype.
- `CompiledDspHotSwap` now provides a first mono-only graph replacement path
  for already-compiled graphs, with block-boundary `queue_swap(...)` and an
  optional equal-power crossfade.
- The browser wrapper now also exports a dedicated mono hot-swap proof path,
  and browser automation confirms the AudioWorklet runs both the mixed
  crossfade block and the settled replacement block.
- `CompiledStereoDspHotSwap` now brings the same hot-swap model to
  terminal-stereo graphs, and the browser wrapper exports a dedicated stereo
  hot-swap proof path as well.
- `CompiledDspTopologyController` now adds a first narrow topology-edit layer
  above mono `CompiledDspHotSwap`, with ordered transactional
  `ReplaceNode` / `RewireInput` frames that recompile and stage a replacement
  graph.
- The mono topology-edit slice now also supports an append-only
  `InsertNode` frame for unary nodes, keeping existing authoring indices stable
  while still changing graph length.
- The mono topology-edit slice now also supports `DeleteNode` as the inverse of
  that unary insert model, collapsing the graph back to a shorter shape through
  the same staged crossfade path.
- The browser wrapper now also exports a dedicated mono topology-edit proof
  path, and browser automation now confirms the full length-changing round-trip:
  `queue_compiled_topology_edit()` yields the expected mixed and settled unary
  insert rebuild, and `queue_compiled_topology_delete_edit()` returns that path
  to the original baseline shape.
- `CompiledStereoDspTopologyController` now brings the same narrow
  topology-edit model to terminal-stereo graphs, and the browser wrapper
  exports a dedicated stereo topology-edit proof path as well.

## Confirmed Outcome

Confirmed on 2026-03-10:

- The page loads in the browser and the `Start Audio` button successfully
  unlocks `AudioContext`.
- `processor.js` loads and `moonbit_dsp.wasm` instantiates inside
  `AudioWorkletProcessor`.
- The exported MoonBit functions are visible in the browser:
  `tick`, `reset_phase`, and `_start`.
- The page reports `Audio running`.
- The live signal meter shows non-zero output while the app is running.
- Audible sound is confirmed manually from the current app.
- The frequency slider updates pitch while the demo is running.

This means the core Phase 0 viability question has a positive answer for the
current setup: MoonBit `wasm-gc` can generate audible audio in a browser
`AudioWorklet`.

Confirmed on 2026-03-13:

- The browser wrapper exports `init_compiled_graph`,
  `process_compiled_block`, and `compiled_output_sample` in addition to the
  legacy Phase 0/1 compatibility exports.
- The browser wrapper also exports `init_compiled_stereo_graph`,
  `process_compiled_stereo_block`, `compiled_stereo_left_sample`, and
  `compiled_stereo_right_sample`.
- The served page reports `CompiledStereoDsp block runtime` after `Start
  Audio`.
- `processor.js` now prefers the `CompiledStereoDsp` path once per render
  quantum instead of calling `tick(...)` for each individual sample.
- Browser automation confirms the live page enters the compiled-stereo mode and
  that the `StereoBiquad` cutoff control measurably changes output level before
  pan changes are applied.
- Browser automation also confirms the left/right meters respond to `pan`
  changes in the expected direction.

This means the browser prototype now exercises the actual Phase 2 compiled
stereo graph runtime, not just the earlier per-sample wrapper ABI.

Confirmed on 2026-03-14:

- The fixed browser `CompiledStereoDsp` graph now includes `StereoDelay` ahead
  of the live `StereoBiquad` stage.
- Browser automation compares the first rendered block with
  `delaySamples=0` versus `delaySamples=24` and confirms the delayed path starts
  with the expected silent offset.
- The dedicated `browser_test/` wasm now drives the stereo-init-failure route
  with a deterministic mono feedback `CompiledDsp` graph instead of a generic
  acyclic fallback.
- Browser automation confirms that fallback route renders the expected first
  `z^-1` recurrence samples and that a live loop-gain retune changes the next
  block while staying finite.

Confirmed on 2026-03-15:

- The main browser `CompiledStereoDsp` proof graph now runs a deterministic
  mono `z^-1` feedback loop before `Pan` instead of the earlier acyclic
  delay/filter chain.
- Browser automation confirms the first rendered stereo block matches the
  expected center-pan recurrence from that feedback graph.
- Browser automation also confirms `StereoDelay` startup offset, live
  `StereoBiquad` cutoff retuning, bounded loop-gain retuning, and hard-left /
  center / hard-right pan behavior on the same stereo feedback path.

## Phase 1 Completion

Confirmed on 2026-03-11:

- Source primitives are implemented: `Oscillator` with sine/saw/square/triangle
  and `Noise`.
- Runtime/data-path primitives are implemented: `AudioBuffer`,
  `DspContext`, and `ParamSmoother`.
- Processing primitives are implemented: `Gain`, `Mix`, `Clip`, and `Pan`.
- Stateful control/effect primitives are implemented: `Adsr`, `Biquad`, and
  `DelayLine`.
- Integration coverage exists for mono voice chains, mixed source chains, and
  stereo pan chains.
- The browser prototype has been upgraded to exercise the Phase 1 surface,
  including source selection and stereo pan.

This means the project can treat Phase 1 as complete and move into Phase 2
graph compilation work.

## Phase 2 Progress

Confirmed on 2026-03-11:

- A compiled mono graph exists via `DspNode` -> `CompiledDsp`.
- Compiled mono graphs now support explicit `Mono -> Stereo -> Mono` round-trips
  through `Pan` and `StereoMixDown`.
- A first narrow terminal-stereo graph slice also exists via
  `CompiledStereoDsp` for `Mono -> Pan -> Stereo post-processing ->
  StereoOutput`, including `StereoGain`, `StereoClip`, `StereoBiquad`, and
  `StereoDelay`.
- Phase 2 graph compilation and runtime control are working in the current
  graph implementation.
- Integration coverage exists for compiled graph voice paths and runtime
  retuning.
- Stereo graph coverage now includes compiled stereo voice-path integration plus
  runtime and batched updates for `Pan`, `StereoGain`, `StereoClip`, and
  `StereoBiquad`.

Confirmed on 2026-03-14:

- The current terminal-stereo slice now also includes `StereoDelay`.
- Stereo graph coverage now includes `StereoDelay` runtime updates plus
  mono-mixdown equivalence, stereo-delay retune integration checks, and
  local `StereoDelay` feedback updates.
- `Delay` and `StereoDelay` now support internal recirculating feedback
  coefficients. This is node-local delay feedback only; general graph-cycle
  feedback insertion is still pending.
- `CompiledDsp` now supports a first real graph-cycle slice for mono-only
  back-edges by inserting implicit `z^-1` feedback reads during compile.
- Coverage now includes a bounded mono feedback recurrence, direct
  self-feedback acceptance, runtime control retunes inside an accepted loop,
  and rejection of unsupported output/stereo feedback cycles.

Confirmed on 2026-03-15:

- `CompiledStereoDsp` now accepts the same narrow mono `z^-1` feedback slice
  before `Pan`, so terminal-stereo graphs can carry supported mono feedback
  loops into the stereo post-processing path.
- Coverage now also includes bounded terminal-stereo feedback persistence plus
  graph/integration runtime retunes on accepted mono feedback loops before the
  stereo lift.
- `CompiledDspHotSwap` now adds a first graph replacement layer above mono
  `CompiledDsp`, supporting either instantaneous swap or fixed equal-power
  crossfade between compatible compiled graphs.
- Coverage now pins exact equal-power crossfade samples plus bounded
  block-to-block hot-swap behavior for that wrapper.
- The browser wrapper now also exports a dedicated `CompiledDspHotSwap` proof
  path, and browser automation confirms a queued swap yields one mixed
  crossfade block followed by the settled replacement block in the
  AudioWorklet.
- `CompiledStereoDspHotSwap` now adds stereo hot-swap parity for
  `CompiledStereoDsp`, including mirrored runtime controls during crossfade and
  browser proof of the mixed and settled stereo swap blocks.
- `CompiledDspTopologyController` now adds the first topology-edit wrapper
  beyond whole-graph swap for mono graphs, with transactional
  `GraphTopologyEdit::replace_node(...)`, `GraphTopologyEdit::rewire_input(...)`,
  append-only `GraphTopologyEdit::insert_node(...)`, and mono-only
  `GraphTopologyEdit::delete_node(...)` batches compiled and staged through the
  mono hot-swap path.
- Coverage now includes exact crossfade expectations for a rebuilt mono graph,
  transactional rejection of invalid edit batches, and runtime-control mirroring
  into a queued topology-edited replacement.
- The browser wrapper now also exports a dedicated
  `CompiledDspTopologyController` proof path, and browser automation confirms
  the queued topology edit runs through the AudioWorklet with the expected
  mixed crossfade block and settled rebuilt block, now including an
  `DeleteNode` proof on the mono path.
- `CompiledStereoDspTopologyController` now adds stereo topology-edit parity for
  terminal-stereo graphs, with queued `ReplaceNode` / `RewireInput`
  recompilation staged through `CompiledStereoDspHotSwap`.
- The browser wrapper now also exports a dedicated
  `CompiledStereoDspTopologyController` proof path, and browser automation
  confirms the queued stereo topology edit yields the expected mixed and
  settled channel-shape transition in the AudioWorklet.

Confirmed on 2026-03-19:

- Two-layer Finally Tagless architecture implemented: `ArithSym`, `DspSym`,
  `FilterSym`, `DelaySym`, `StereoSym`, `StereoFilterSym`, `StereoDelaySym`
  trait hierarchy with diamond super-trait bounds resolved by MoonBit
- `GraphBuilder` interpretation type bridges tagless traits to `DspNode` graph
  construction with array merging for source nodes
- `replay()` function enables tagless round-trip through any interpretation
- Composed operations `range()` and `lin_map()` as generic `ArithSym` functions
  — no new enum variants needed
- Oscillator FM mode: `DspNode::oscillator_from()` reads frequency per-sample
  from input buffer
- `NodeSpanning`, `NodeFoldable`, `NodeStateful`, `NodeEditable` capability
  traits for compiler passes
- `optimize_graph()`: constant folding + dead-node elimination, integrated into
  `CompiledDsp::compile()` and `CompiledStereoDsp::compile()`
- Self-register feedback model replaces linked-list infrastructure: stereo and
  mixed-shape feedback now accepted
- `InsertChain` / `DeleteChain` topology edit variants for multi-node subgraph
  operations with stereo parity
- State preservation across topology edit recompilation
- `ChannelSpec` trait with `Mono` / `Stereo` types
- Exit deliverable `sine(2).range(200,400).sine().lpf(800,1).out()` compiles
  and produces audible FM synthesis output

Authoritative detailed Phase 2 graph status now lives in
`docs/salat-engine-technical-reference.md`, including:
- current node coverage
- current `set_param(node_index, slot, value)` support matrix
- current graph limits and remaining Phase 2 work

## How To Run

1. `moon build browser --target wasm-gc --release`
2. `./serve.sh`
3. Open the URL printed by `serve.sh` (for example `http://127.0.0.1:8080` or
   the next free port if `8080` is occupied)
4. Click `Start Audio`
5. Move the frequency, cutoff, delay, gain, and pan controls
6. Watch the signal meter if you need visual confirmation that samples are
   flowing

## Verified Checks

- The page loads without blocking initialization errors
- The processor reports `ready`
- `tick`, `tick_source`, and `reset_phase` appear in the browser wrapper wasm
  exports
- `init_compiled_graph`, `process_compiled_block`, and `compiled_output_sample`
  appear in the browser wrapper wasm exports
- `init_compiled_stereo_graph`, `process_compiled_stereo_block`,
  `compiled_stereo_left_sample`, and `compiled_stereo_right_sample` appear in
  the browser wrapper wasm exports
- The page reports `CompiledStereoDsp block runtime`
- Audible output is confirmed manually
- The frequency, cutoff, delay, gain, and pan controls update the running demo
- The signal meter shows non-zero output while running
- The first rendered block changes as expected when the page starts with
  different `delaySamples` query values
- The stereo-init-failure route reports `CompiledDsp block runtime` and now
  renders the expected mono feedback recurrence preview
- The cutoff control changes the running stereo-filtered output
- The left/right meters shift in the expected direction when pan changes

## Remaining Checks

- Run a dedicated 30-second glitch test and record whether playback stays clean
- Inspect browser performance tooling for any GC-related spikes during playback
- Test one or two additional browsers after the Chrome-path prototype is stable

## Open Questions

- Does the generated `wasm-gc` module continue to instantiate in other target
  browsers without additional imports beyond the current stubs?
- Does the browser show any GC-related glitches during extended sustained
  playback?
- Is the current `wasm-gc` path viable enough to keep as the default browser
  backend, or should the project prefer the `js` backend for AudioWorklet?
