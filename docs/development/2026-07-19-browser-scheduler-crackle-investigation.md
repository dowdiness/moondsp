# Browser scheduler crackle investigation

Issue: #212

## Scope

This follow-up closes the largest evidence gap in the earlier Sine probe: the
Triangle/Sine comparison now runs through the production
Mini → `PatternScheduler` → `BoundVoicePool` → browser playback host path.
Production browser playback still selects Triangle. The production browser
export ABI, drum routes, ADSR, master gain, and voice policy are unchanged.

`browser/test_support` is the explicit test boundary. It is compiled into the
test WASM only and delegates to the same `browser/internal/demo_templates` and
`browser/internal/playback_host` packages used by production. The shared synth
template builder accepts a waveform, while the production wrapper continues to
pass Triangle.

The diagnostic branch is ported to main's prepared-playback API:
`clear_playback_input` / `push_playback_char` → `prepare_pattern_input` →
`apply_prepared_playback(token, true)`. It retains main's production transport,
snapshot-entry reconciliation, and shared-send rendering. On the ported branch,
all four scheduler/crackle Playwright scenarios pass in Linux headless Chromium;
this does not establish affected-Windows real-time playback quality.

## Automated matrix

The Playwright probe renders each pattern independently in two instances of the
same test WASM:

1. synchronously on the page thread;
2. from `OfflineAudioContext` through an `AudioWorkletProcessor`.

Both outputs are converted to Float32 before a sample-by-sample stereo PCM
comparison.

| Case | Pattern | Purpose |
| --- | --- | --- |
| Single note | `note("60")` | repeated onset, release, and slot reuse across multiple cycles |
| Triad sequence | `note("60 64 67")` | one-third-cycle events and non-aligned render blocks |
| Dense triad | `note("60,64,67").fast(8)` | dense overlapping note events |
| Voice pressure near event | `note("48,49,50,51,52,53,54,55,56,57,58,59,60").fast(8)` | repeated 13-note stacks against the 24-voice pool |
| Silence | `s("bd(0,8)")` | output-stage silence |

Telemetry records peak, `abs(sample) > 1`, non-finite samples, DSP sanitizer
count, page/worklet Float32 residual, active synth voices, and discontinuities
localized to onset, note-off, steady-state, and voice-pressure-near-event
intervals. The probe does not observe whether a note-on actually stole a voice;
it only combines pool pressure with proximity to a predicted event. Raw maximum
adjacent step remains diagnostic only and is not a pass/fail threshold.

## Local Chromium result

Command:

```bash
NEW_MOON_MOD=0 ./node_modules/.bin/playwright test \
  playwright-tests/scheduler-probe.spec.js --reporter=line
```

All production-path smoke cases and all ten waveform/pattern comparisons
passed:

- page-thread and AudioWorklet Float32 PCM matched exactly for every sample
  (`mismatchCount = 0`, `maxResidual = 0`);
- non-finite and sanitizer counts were zero;
- silence stayed exactly zero;
- single-note, sequence, and dense-triad cases stayed below unity;
- the 13-note repeated stack reached all 24 synth voices and produced
  clipping:
  - Triangle: peak `1.9344473`, 750 samples above unity;
  - Sine: peak `2.2354193`, 1,184 samples above unity.

The voice-pressure case also localized its largest discontinuities to
voice-pressure/onset blocks. This is expected diagnostic evidence, not a new
quality gate: the case intentionally exceeds the configured pool and gain
headroom.

## Interpretation

On the local headless Chromium environment, the AudioWorklet/wasm-gc boundary
does not alter scheduler PCM. If the same comparison mismatches on the affected
Windows/Chrome build, the failure is narrowly located at that boundary. If PCM
still matches there:

- onset/note-off or voice-pressure-only anomalies point to scheduler/voice
  lifecycle behavior;
- samples above unity point to gain staging/clipping;
- normal PCM with clicks only during real-time playback points beyond the WASM
  renderer, toward Chrome/Windows output buffering, device sample-rate
  conversion, or latency configuration.

The original report describes clicks across nearly all patterns, which was not
reproduced by the local offline AudioWorklet matrix. Therefore the production
Triangle fallback should remain until the affected Chrome 150 / Windows
environment completes the real-time A/B matrix.

## Windows real-time reproduction

Build and serve the repository:

```bash
NEW_MOON_MOD=0 moon build --target wasm-gc --release
./serve.sh
```

Open `/windows-crackle-harness.html` in Chrome 150.0.7871.115. The test-only
harness switches:

- scheduler versus direct oscillator route;
- Triangle versus Sine;
- master/output gain;
- requested 48 kHz versus device-native/default sample rate;
- `interactive` versus `playback` latency hint.

Run the five pattern presets for each relevant configuration and use **Save
JSON result** after every run. Record the audible outcome next to each saved
file, because a browser cannot objectively capture clicks introduced after the
AudioWorklet output buffer.

## Mitigation decision

No production DSP change is justified by the local result. Recommended
mitigation depends on the affected-machine evidence:

- clipping only: reduce gain or add an explicitly designed output limiter;
- voice-pressure-near-event discontinuities only: inspect voice reuse/release
  crossfades;
- real-time-only clicks improved by native sample rate or `playback`: select
  the stable AudioContext configuration on Windows;
- Windows-only PCM mismatch: isolate a Chrome 150/wasm-gc reproducer before
  changing oscillator or scheduler behavior.
