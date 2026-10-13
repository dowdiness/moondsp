# Live editor staged startup — 2026-10-09

## Scope and environment

Production builds of `web/live` using the installed Vite 5.4.21, via `npm run build` (TypeScript check followed by Vite). The dependency manifest declares a different Vite range; these measurements describe the installed version, not that declared range.

## Observed bundle sizes

Sizes below are Vite's decimal kB reports, excluding source maps.

| JavaScript | Before staged startup: minified kB | Before: gzip kB | After: minified kB | After: gzip kB |
|---|---:|---:|---:|---:|
| Application entry | 173.02 | 54.84 | 68.25 | 23.59 |
| CodeMirror/Lezer | 348.29 | 113.43 | 348.29 | 113.43 |
| Generated authoring | 318.41 | 80.35 | 318.41 | 80.35 |
| Authoring wrapper | — | — | 2.07 | 0.87 |
| Player | — | — | 9.23 | 2.52 |
| Pattern controls | — | — | 96.81 | 30.29 |

Before this change, the first three chunks were static startup dependencies. Afterward, only the application entry and editor are static startup dependencies; authoring, Player, pattern controls and their generated-code/CSS dependencies load through dynamic imports. All emitted JS chunks remain below the unchanged 500 kB warning threshold.

## Loading schedule and correctness evidence

`main.ts` mounts basic editing/history/save/help first. A `requestAnimationFrame` callback schedules a zero-delay timer task that starts the three dynamic imports concurrently. This gives the browser an opportunity to paint basic editing before score-tool loading; it does not wait for idle time or a Play gesture.

A real Chromium production-preview smoke intercepted `/assets/authoring-*.js` requests behind a promise barrier. While requests were held, the editor accepted replacement text and scheduler Play remained disabled. Releasing the barrier initialized the latest text, rendered F4/G4 notation and reached Playing with an advancing position. Aborting authoring requests instead produced a failed preparation state and reload advice while text remained editable.

`tests/authoring-startup.spec.ts` permanently covers held imports, editing and Undo during loading, history retention after readiness, latest-text playback, and continued editing after an aborted import. The complete live suite passed 167 tests; the two startup tests also passed in a separate final run. Browser screenshots confirmed the ready/playback and failed/editable surfaces.

## Controlled startup timing comparison

Measured on 2026-10-09 with headless Chrome 148.0.7778.215 and a 1365 × 768
viewport. Both builds used installed Vite 5.4.21 and the same generated authoring,
public assets, and manual-chunk configuration. The before build overlaid
`main.ts`, `authoring.ts`, `playback-protocol.ts`, and `playback.ts` from commit
`5f76b3c54fe8976a86d16bfeb52be11d2053d703`; the after build used current sources.
Builds were isolated under a temporary directory, without modifying the checkout.
The before build reproduced the previous emitted JS names and minified/gzip sizes.

A local HTTP server served precompressed gzip assets with `Cache-Control: no-store`
and the app's isolation headers. Chromium cache and origin storage were cleared
before every navigation. Each profile used 10 before/after pairs, alternating
which variant ran first: 40 measured navigations total.

Profiles:

- Local: no network or CPU throttling.
- Constrained: CDP network latency 150 ms, download 200,000 bytes/s (1.6 Mbps),
  upload 93,750 bytes/s (0.75 Mbps), and CPU slowdown rate 4.

Two startup markers were collected using a document MutationObserver and
`performance.now()` in the first animation-frame callback after:

- `editorFrame`: `.cm-content[contenteditable=true]` exists with nonzero height.
- `toolsFrame`: `.score-pattern` exists and scheduler Play is enabled.

These are frame-level availability proxies measured from navigation time origin,
not a physical input-to-screen measurement or proof that pixels were already
painted at the callback. The same probes ran on both variants. FCP was captured
as auxiliary data, but not used as the primary result: the HTML shell can paint
without a working editor, and some entries were unavailable at collection time.

### Median results

| Profile | Availability marker | Before ms | After ms | After − before ms | Change |
|---|---|---:|---:|---:|---:|
| Local | Basic editor | 221.3 | 138.8 | −82.5 | −37.3% |
| Local | Score tools and Play | 221.3 | 255.2 | +33.9 | +15.3% |
| Constrained | Basic editor | 2614.9 | 1780.2 | −834.7 | −31.9% |
| Constrained | Score tools and Play | 2614.9 | 3022.4 | +407.5 | +15.6% |

Basic editor sample ranges were 203.6–237.3 ms before / 131.1–176.1 ms after
locally, and 2579.0–2810.9 ms before / 1758.8–1914.2 ms after under constraints.
The measured tradeoff is earlier basic editing, but later full score-tool readiness.
Completed JS response bodies totaled 248,628 gzip bytes before and 251,050 after;
this is dependency scheduling, not a reduction in total downloaded functionality.

Raw samples, exact profile values, browser version, and computed medians are in
[2026-10-09-live-startup-samples.json](2026-10-09-live-startup-samples.json).

## Limitations

This controlled local comparison does not predict exact production/CDN timings,
real mobile-device performance, or warm-cache behavior. CPU slowdown is emulation
on this workstation. Ten samples per variant/profile quantify this run, not a
population confidence interval. AudioContext creation, WASM preparation, and
time to first sound were not measured; `toolsFrame` means Play is enabled, not
that audio is already prepared. Downloads still begin automatically after the
initial frame and may overlap immediately with basic editing. No faster full
startup or first-playback claim follows from these results.

## Perceived-readiness refinement

The timing and size comparison above records the original staged-startup change,
before this subsequent UI refinement. No additional speedup is claimed for the
final refinement.

- Short startup now keeps the Play label and omits loading text. If preparation
  lasts 500 ms, `Code is editable. Loading score tools…` appears in the footer
  and describes the code textbox. Controls retain their disabled/busy states.
  Failure immediately identifies score tools as unavailable while code stays editable.
- Initial note/chord selection is discovered through the existing MiniLive
  syntax parser without compiler projection. Readiness never changes selection.
- Installing controls includes CodeMirror's `scrollSnapshot()` effect. A
  long-document regression exposed automatic document-end following: the caret
  moved 404 px on desktop and 456 px on mobile when the notation widget expanded.
  The scroll-snapshot fix passed both regressions with a ≤2 px caret-position
  tolerance and unchanged selected text, focus, and scroll offset.
- Actual loading and ready screenshots were inspected at 1365 × 768 and
  390 × 844. Fresh-page initial selection stayed at line 5, column 4; neither
  state had horizontal document overflow. The ready state removes the loading
  message and enables real score tools, rather than showing an inert skeleton.
- The installed Vite remains 5.4.21. After quiet-startup feedback, application JS
  is 69.51 kB minified / 23.90 kB gzip; generated authoring and editor sizes are unchanged.

A production HTML `modulepreload`/low-fetch-priority candidate was built and
exercised, but not retained. Eight exploratory constrained navigations did not
establish a reliable full-readiness improvement and showed later basic-editor
availability. Concurrent test activity makes those samples unsuitable for a
controlled speedup claim or a definitive bandwidth-causality conclusion. The
final code retains post-frame dynamic fetching; no extra preload hints ship.

The six targeted startup and compiled/scheduler smoke tests passed against the
owned production preview. The repository test runner's preview-start path stalled
in this environment; a temporary config pointed the installed runner at the
explicitly launched, same-checkout preview instead. This changes the test launch,
not application behavior. Visual and deterministic interaction checks are not a
human usability study and do not prove subjective first-use perception.

Full-suite verification before quiet-startup feedback: 169 live tests passed with one worker against
the owned preview. A preceding two-worker run passed 168 and timed out on one
touch chord playback-highlight observation; that test passed in isolation
without a code change, then passed in the serial full suite. The intermittent
parallel observation is recorded rather than treating that run as fully green.

Quiet-startup feedback verification: seven startup and smoke tests passed,
including a clock-controlled short startup, held imports, desktop/mobile
selection and scroll retention, import failure, and the independent compiled demo.
The production build passed without a bundle-size warning. Actual browser
inspection confirmed normal startup without a notice and editing during held
imports with the delayed footer notice; readiness hid it and retained the edit.
No new load-time benchmark was performed.
