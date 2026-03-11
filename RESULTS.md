# Phase 0 Results / Phase 1 Status / Phase 2 Progress

This file records the outcome of the Phase 0 MoonBit `wasm-gc` AudioWorklet
experiment, the completion status of the Phase 1 DSP primitive set, and the
current Phase 2 graph-compiler checkpoint.

## Current Status

- Phase 0 is complete.
- Phase 1 is complete.
- Phase 2 is in progress.
- The browser demo now serves the dedicated `browser/` wrapper package wasm so
  the external browser ABI stays stable as `tick`, `tick_source`, and
  `reset_phase`.
- `web/index.html` and `web/processor.js` provide the current Phase 1 browser
  demo with waveform/noise source selection, gain, pan, and the signal meter.
- `serve.sh` copies the browser wrapper `.wasm` into `web/` and starts a local
  server.
- Browser validation is complete for the current prototype.

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
- Topological sorting, graph validation, and runtime control are implemented.
- Integration coverage exists for compiled graph voice paths that use both gate
  events and runtime parameter updates, including successful runtime `Biquad`
  retunes in compiled mono graphs.

Authoritative detailed Phase 2 graph status now lives in
`docs/salat-engine-technical-reference.md`, including:
- current node coverage
- current `set_param(node_index, slot, value)` support matrix
- current graph limits and remaining Phase 2 work

Current Phase 2 limits:

- mono graph only
- no stereo graph semantics or `Pan` node in the compiled graph
- no feedback-edge insertion yet
- no graph hot-swap/crossfade path yet
- runtime parameter updates are partial, not universal across node kinds

## How To Run

1. `moon build browser --target wasm-gc --release`
2. `./serve.sh`
3. Open the URL printed by `serve.sh` (for example `http://127.0.0.1:8080` or
   the next free port if `8080` is occupied)
4. Click `Start Audio`
5. Choose a source and move the frequency, gain, and pan controls
6. Watch the signal meter if you need visual confirmation that samples are
   flowing

## Verified Checks

- The page loads without blocking initialization errors
- The processor reports `ready`
- `tick`, `tick_source`, and `reset_phase` appear in the browser wrapper wasm
  exports
- Audible output is confirmed manually
- The frequency, gain, and pan controls update the running demo
- The signal meter shows non-zero output while running

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
