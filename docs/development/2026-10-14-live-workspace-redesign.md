# 2026-10-14 — Live workspace redesign: surface, audio start, and cross-engine tests

This record describes `web/live` as of 2026-10-17: what the workspace shows,
how audio starts, how the code is divided, how it is tested, and the evidence
and its limits. It claims no award, jury result, or usability outcome. No
audio-thread, worklet, or MoonBit code changed in this work.

## The workspace

- **Surface.** One masthead row holds the waveform mark and "moondsp."
  wordmark, the transport, and icon-only tools: Undo, Redo, and Controls, then
  Import, Download, Share, and Help. Each tool has an accessible name and a
  tooltip. Code is set at `clamp(15px, min(1.3vw, 2.6vh), 22px)`, and the
  line-number gutter reserves three digits so the code does not shift as a score
  grows. A single 30 px status line shows change status, save state, and cursor
  position. Light and dark palettes follow `prefers-color-scheme`; there is no
  theme toggle.
- **Signal horizon.** A full-width band under the masthead draws the measured
  output level as a scrolling history of rounded bars, with the live waveform
  behind them and cycle ticks along the bottom. Levels follow a soft peak
  tracker mapped over 30 dB with a short visual release. The pure level model is
  `web/live/src/level-history.ts`; `signal-horizon.ts` draws it. Both read the
  main-thread analyser. With reduced motion the horizon redraws every 250 ms,
  and the history still fills every slot between redraws.
- **Share.** `web/live/src/score-link.ts` copies a `#score=` link that carries
  the score in the URL fragment, compressed with `deflate-raw` and
  base64url-encoded, so nothing is uploaded. The click writes a pending
  `ClipboardItem`, which starts the write inside the gesture as Safari requires.
  If the clipboard refuses, or the page has no Clipboard API (plain HTTP), the
  message says the link was not copied and that Download keeps the score.
  Opening a link replaces the score as one undoable step, like Import.
- **Percussion matrix.** Pads are 30 × 26 px on fine pointers and 44 × 40 px on
  touch or narrow screens, with one pastel hue per sound in both themes.
- **Help.** Four icon-only cards start a sound and play it; text buttons load an
  example without playing it. Help draws both from one catalogue,
  `web/live/src/examples.ts`, which holds each entry's label, note, drawing, and
  score. Help's Playback details section holds the output scope, the playback
  position, and editor and engine versions.

## How audio starts

Browsers start an `AudioContext` only from a user gesture, and Safari only while
the click is still being handled. Three rules in `web/live/src/audio.ts` and
`playback.ts` follow from that:

- Play opens the audio session synchronously inside the click, and the engine
  asks for a running context as soon as it creates one, before loading the
  worklet and WASM.
- A session that is going away gives way rather than making Play wait for it.
  Play during Stop's fade-out resumes the same audio graph and cancels the fade;
  Play after a cancelled start replaces that start. `openSession` reports busy
  only for a running session or a start still in progress. Each start changes
  engine state only while it is current, so a replaced start cannot overwrite
  its replacement.
- One `AbortController` ends a start: the caller cancels it, five seconds pass,
  or the graph fails. A start that times out fails with "Press Play again",
  because a fresh click can start audio in every browser.

The live editor always plays through the scheduler worklet
(`scheduler-processor.js`).

## How the code is divided

The workspace follows functional core / imperative shell. The note grid and
structure strip each have a pure layout module that lays a phrase out in
viewBox units, describes its SVG, and decides what a pointer at a point hits
(`note-grid-layout.ts`, `structure-layout.ts`). Shells (`note-grid.ts`,
`structure-strip.ts`) measure, render, and run gestures, and `moving-score.ts`
composes them; an `InteractionLock` lets only one of them hold an interaction
at a time. `svg-patch.ts` applies a described SVG tree to the document while
keeping each keyed element, so a pointer or focus on an element survives a
re-render. The grid re-renders only when its measured width changes, not when
its own height changes.

Edits in `notation-structure.ts` return an `Edit` result: the edit, or the
reason the notation refuses it, such as a move outside the note's sequence.
Callers show the reason; a thrown error is always a bug and is never shown as a
refusal.

Every pattern control applies its source edit through `dispatchPatternEdit`
(`pattern-edit.ts`), which makes the edit one undo step and records the edited
source as the selection Redo restores. Views derive their selected step from the
pattern's selected node. In `main.ts`, the draft, player, playback observation,
and pattern controls are one `tools` value, present once score tools load.

## How it is tested

`web/live/playwright.config.ts` defines `chromium`, `firefox`, and `webkit`
projects; CI runs one job per engine. Every run builds `dist-e2e/` with
`npm run build:e2e` and serves it, so tests never see stale assets. That build
differs from production only in exposing `window.__moondspEngine`, which lets
tests drive the engine's lifecycle and inject worklet faults. Firefox and WebKit
need an audio device to start an `AudioContext`; WebKit reaches it through
GStreamer's PulseAudio sink, which CI, `.agents/setup`, and `.agents/resume`
provide. `.agents/setup` installs each browser from the location and URL that
`playwright install --dry-run` reports, extracting with system `unzip` because
Playwright's extractor can stall in an orb.

Shared helpers in `web/live/tests/editor-helpers.ts` make one test act the same
way in every engine:

- `platformKeys` returns the modifier CodeMirror expects; Playwright's WebKit
  reports a Mac, where shortcuts use Command.
- `insertText` types through the browser's insertText command, because Firefox
  delivers Playwright's `keyboard.insertText` as IME composition, which
  CodeMirror joins to the previous undo step.
- `leave` navigates away the way a link does, so Firefox runs the `pagehide`
  save.
- `boxOf` and `centerOf` measure an element once its box holds for a frame.

Some expectations depend on the engine. Share reads the clipboard back only in
Chromium, the one engine where automation can grant clipboard-read; elsewhere
the test opens the link that the shared encoder produces, and
`score-link.spec.ts` covers that encoder in every engine. Three touch tests
need Chromium's native touch input, and one mobile-emulation test cannot run
in Firefox; those are skipped elsewhere.

## Verification

Run on 2026-10-17 in an orb with
`MOONDSP_VIRTUAL_AUDIO=1 npx playwright test --project=<engine> --retries=0`:

| Engine | Passed | Skipped |
|---|---|---|
| Chromium | 198 | 0 |
| Firefox | 194 | 4 |
| WebKit | 195 | 3 |

- `npm run build` passed, with Vite's chunk-size advisory.
- "Play right after a cancelled start starts audio inside its own click"
  records whether every `AudioContext` construction and resume runs inside a
  click, with the WASM fetch delayed and context closing slowed so the race is
  deterministic. Without the give-way rule it failed in all three engines.
- The Help test clicks every example and checks that each loads its own score
  without playing. With two examples given the same score, it failed.
- The code's left edge stayed at the same position with 9, 10, and 100 lines in
  Chromium and WebKit (within 0.02 px), at 1440 px and 390 px wide.
- A browser install into an empty directory with the `.agents/setup` function
  launched both Chromium and WebKit.

Checked on 2026-10-14, before the audio-start and cross-engine work:

- Each level-history test caught a seeded mutant that changed the release, the
  dB range, freezing, grouped ticks, or slot interpolation.
- In WebKit without clipboard permission, Share copied the exact editor text
  both right after an edit and later, confirmed by pasting into a field.
- The note-grid drag tests in `note-manipulation.spec.ts` passed 150 of 150
  repeated runs.
- Headless Chromium captures at 320, 360, and 390 px show no horizontal
  overflow; captures at 1440 × 900 cover both themes and reduced motion.

## Limits

- Not yet run on GitHub Actions.
- No physical device and no Safari on macOS or iOS; WebKit here is Playwright's
  Linux build. The audio-start rules matter most on iOS and need a check there.
- `tsc` does not check `web/live/tests/`; the tests run, but type errors in them
  are not reported.
- No screen-reader session, human listening test, or first-use study.
- Playback highlights need a cross-origin-isolated top-level page, so they do
  not appear inside embedded previews.
