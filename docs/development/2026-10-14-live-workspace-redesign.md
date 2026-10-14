# 2026-10-14 — Live workspace redesign: measured horizon, Share, and a quiet surface

Goal: raise the craft of `web/live` without changing the text-first editing
model. This record describes the final state, the path to it, and the evidence.
It claims no award, jury result, or usability outcome.

## Final state

- **Quiet surface.** One masthead row holds the original waveform mark and
  "moondsp." wordmark, the transport, and icon-only tools. The icons are Undo,
  Redo, and Controls, then Import, Download, Share, and Help; each has an
  accessible name and a tooltip. Code is set larger:
  `clamp(15px, min(1.3vw, 2.6vh), 22px)`. A single 30 px status line shows change
  status, save state, and cursor position. The established light and dark palettes
  follow `prefers-color-scheme`, and there is no theme toggle.
- **Signal horizon.** The horizon is a scrolling RMS level history of rounded
  bars, using a soft peak tracker, a 30 dB mapping, and a short visual release.
  The live waveform sways behind the bars as a teal-to-lavender gradient. Cycle
  ticks run along the bottom edge. The level model is the pure module
  `web/live/src/level-history.ts`; drawing is in `signal-horizon.ts`. Both read
  the existing main-thread analyser. No audio-thread, worklet, or render-buffer
  code changed.
- **Share.** `web/live/src/score-link.ts` copies a `#score=` link with the score
  `deflate-raw` compressed and base64url-encoded. The click writes a pending
  `ClipboardItem`, so the write starts inside the gesture; if the clipboard
  refuses, the message says so. There are no fallback paths.
  Opening a link is one undoable replacement, the same as Import.
- **Percussion.** The matrix is compact, with one pastel hue per sound in both
  themes and a deeper edge on the light panel. Pads are 30 × 26 px on fine
  pointers and 44 × 40 px on touch or narrow screens.
- **Help.** There are four icon-only starting-sound cards, including the layered
  **Moonrise**. Playback details (audio output and versions) moved into Help.
- **Removed:** Add melody, the load-only starter buttons, and the score title in
  the status line.
- **Robustness.** The moving score no longer re-renders when a `ResizeObserver`
  reports only its own height change.

## Path

Four independent critique rounds rescored captures. Each used a fresh agent
prompted as a strict Awwwards/FWA jury member, so these are model reviews, not
human juries:

| Round | Design | Usability | Creativity | Content |
|---|---|---|---|---|
| 1 | 6 | 6 | 7 | 5.5 |
| 4 | 7.5 | 7 | 8 | 6 |

Those captures showed an intermediate design that the user then rejected:
Night/Day palettes, a phase-tracking masthead moon, a Stage view, and a serif
display face. The scores do not describe the final state. The user then directed
the changes listed above one at a time.

## Verification

- `npm run build` passed. The existing Vite chunk-size advisory remains.
- `MOONDSP_VIRTUAL_AUDIO=1 npx playwright test --retries=0` passed. New tests:
  - a Share round trip with UTF-8 text and Undo, including the prepared-link path;
  - three level-history tests.
- Each level-history test caught a seeded mutant. The mutants changed the
  release, the dB range, freezing, grouped ticks, and slot interpolation.
- Share was checked in Playwright WebKit 26.4 with no clipboard permission
  granted. Both the prepared path and the just-edited path copied the exact
  editor text, confirmed by pasting into a field.
- The intermittent `note-manipulation.spec.ts` detach that the redesign
  introduced passed 150/150 after the resize fix. The unchanged baseline also
  passed 150/150.
- Headless Chromium captures at 320, 360, and 390 px show no horizontal
  overflow. Captures were also taken at 1440 × 900 in both themes and with
  reduced motion.

Limits: no physical devices or real Safari, no screen-reader session, and no
human listening or first-use study. Playback highlights require a
cross-origin-isolated top-level page; they are absent inside embedded previews,
as before this work.
