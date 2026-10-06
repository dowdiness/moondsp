# The moving score — experience and verification

This record follows successive changes to the text-first music editor. Earlier
passes added phrase previews, comparisons, and generators; the user subsequently
rejected that complexity. The current surface is documented under
[Essential edit-listen loop](#essential-edit-listen-loop). Earlier screenshots,
recordings, and feature descriptions are historical, not the current contract.

## Concept and operating principle

1. Choose a starting sound and hear it immediately, without typing.
2. Pause, place the code cursor in a note phrase, and draw its inline contour.
   Release writes the source as one undoable edit and previews the plain phrase.
3. Keep a shape, turn or redraw it, and hear both versions. A dashed contour is
   comparison data, not another playing track or a saved score.
4. Make an answer: append reversed notes over six cycles. A four-cycle starter
   and six-cycle answer meet at different points. Both remain ordinary source.
5. Continue editing text or source-bound note/drum controls, play the full score,
   and download or restore the same text.

This follows the concept-design principle of exposing purpose, state, and the
operating principle together. The earlier
[Essence of Software and interaction research](2026-10-02-musical-workspace.md)
records the primary research. The objective is not a decorative visualization of
an editor: the contour is an editing operation, and its consequence is readable
in the source.

## Deliberate boundaries

- The drawing accepts simple single-note sequences, including rests and relative
  `@1`–`@16` lengths, up to 32 steps and 256 units. Nested/chord notation remains
  editable in code; it is not flattened.
- Drawing snaps to C minor pentatonic. Merely clicking an existing chromatic note
  does not rewrite it. A drag starting on a note is still a drawing gesture.
- Preview melody uses one finite four-cycle song at 90 BPM, without arbitrary
  source effects or timing transformations. Context loops, added in the
  composition pass below, retain the supported score's accompaniment and timing.
  Their rings follow the preview player's position, not a guessed main onset.
- During full playback, the drawing represents the written phrase. Existing
  accepted/sounding-material timing remains authoritative. Invalid drafts do not
  replace the accepted score.
- Shape comparison follows its source phrase until the phrase is removed or
  replaced, or the page reloads. Local score persistence and recoverable drafts
  are separate. Appending a phrase is limited to empty or `$:` stack programs;
  the UI explains other program shapes.
- The waveform observes actual post-master transport or preview output. A live
  waveform does not establish listener-device audibility or source provenance.
- The initial experience passes did not change MoonBit. The composition pass
  below adds relative-duration notation and pattern lowering, without changing
  Worklet DSP or native/CLAP code. No new audio-thread allocation audit is claimed.

## Public review criteria

The five-part internal rubric is informed by, not equivalent to:

- [Awwwards evaluation](https://www.awwwards.com/about-evaluation/): design,
  usability, creativity, and content.
- [Webby judging criteria](https://www.webbyawards.com/judging-criteria/): content,
  navigation, visual design, functionality, interactivity, innovation, and overall
  experience.
- [FWA](https://thefwa.com/about/about-fwa) and
  [its live judging](https://thefwa.com/live-judging): creative interactive work
  assessed through its own jury process.

The user-approved internal gate requires three independent AI reviewers to score
originality, music-making fun, interaction clarity, visual/audio unity, and finish
at least 4/5 each, and explicitly recommend the work as an award candidate.
This is not an award-body decision, an award prediction, or a novice usability
study. Maximum ten reviewed improvement rounds were authorized.

## Review rounds

Scores below follow the five-category order above.

| Round | Reviewer | Scores | Recommendation |
|---|---|---|---|
| 1 | ExperienceReviewA | 3 / 3 / 4 / 4 / 4 | No |
| 1 | ExperienceReviewB | 4 / 3 / 3 / 3 / 3 | No |
| 1 | ExperienceReviewC | 4 / 3 / 4 / 3 / 4 | No |
| 2 | RoundTwoExperience | 4 / 3 / 4 / 4 / 4 | No |
| 2 | RoundTwoUsability | 5 / 4 / 4 / 4 / 4 | Yes |
| 2 | RoundTwoVisual | 4 / 4 / 4 / 4 / 4 | Yes |
| 3 | RoundTwoExperience | 4 / 3 / 4 / 4 / 4 | No |
| 3 | RoundTwoUsability | 5 / 3 / 4 / 3 / 4 | No |
| 3 | RoundTwoVisual | 4 / 4 / 4 / 4 / 4 | Yes |

Round 1 rejected the gate. The recurring weaknesses were limited musical
exploration after the first drawing, a missing compare/discovery loop, and weak
inspectable correspondence between a phrase and heard output. Round 2 therefore
added complete previews with real position feedback, shape comparison, reversed
answers, and an audio-bearing browser recording. Review remains independent;
passing tests does not substitute for the experience verdict.

Round 2 did not meet the gate. Two reviewers recommended candidacy based on
musical agency, source/gesture correspondence, and presentation. The experience
reviewer withheld recommendation because it could not hear the supplied audio
or observe first-time users' musical response; its music-making-fun score stayed
at 3. All three explicitly limited their subjective listening claims. Changing
reviewers or treating two recommendations as a pass would not meet the agreed
criterion.

A subsequent craft pass removed an inherited SVG stroke that outlined pitch
labels, corrected their dark-scheme contrast, renamed isolated listening to
Preview melody / Preview kept, and made the comparison sequence and distinction
from full-score Play visible before activation.

Round 3 used the same reviewers, not replacements selected for agreement.
The experience reviewer retained No. The usability reviewer also withheld
recommendation after distinguishing observable interaction from subjective
hearing. Both explicitly said another UI-only iteration cannot resolve their
remaining evidence gap. Minimum missing evidence: independent human listening
to isolated preview and full playback, plus brief first-time-user observation
of musical reward, confusion, and willingness to explore again. The visual
reviewer retained Yes with the same listening limitation. **The agreed gate is
not met; the work is not declared award-ready.**

## Executed verification before inline integration

- `npm run build`: TypeScript and Vite production build passed. The large
  JavaScript chunk advisory remained; that bundle was 733.31 kB,
  218.82 kB gzip. It was not hidden or declared resolved.
- Existing `npm test` entry, with a temporary Playwright configuration selecting
  the existing test directory and the running production server on port 5195:
  **95 passed in 37.7 seconds** on the final build. No tests were skipped. The wrapper avoids the
  existing preview-server probe issue and uses virtual Chromium audio output.
- Real desktop browser: draw → complete preview → Turn → hear retained shape →
  append answer → full playback beyond seven cycles. Two source phrases were
  present, real waveform peak was 0.37052, and there were no page errors.
- The complete preview reached step 7 and the actual output reported Live.
- Real mobile Chromium emulation, width 390: touch drawing wrote source, reload
  restored exact text, a typed `Eb5` → `G5` change updated the diagram to `G5`,
  local storage matched exactly, and Play/Pause succeeded. No horizontal overflow
  or page errors was observed.
- Invalid-source scenario on that desktop build: playback remained
  Playing, Restore recovered exact accepted source, Undo restored the invalid
  draft, and a second Restore recovered exact source again.
- Dark scheme and reduced-motion preference were exercised visually. This does
  not claim an exhaustive accessibility audit.
- A new regression protects chromatic note clicks and drag-from-note Undo.
  Existing recovery coverage exposed a queued disclosure event replacing a
  focused draft control; preserving the focused list made the suite pass.

## Artifacts before inline integration

- [Round-3 desktop](musical-workspace/experience-desktop.webp)
- [Round-3 mobile](musical-workspace/experience-mobile.webp)
- [Round-3 dark scheme](musical-workspace/experience-dark.webp)
- [Round-2 creation/comparison recording with real audio](musical-workspace/experience-demo.webm)

The recording predates the final Preview labels and SVG text-contrast fix, not
the musical behavior. These screenshots precede the inline-editor integration.

To serve the built app from the worktree's `web/live` directory:

```sh
npm run preview -- --host 127.0.0.1 --port 5199 --strictPort
```

For the missing listening/first-use evidence, let a first-time visitor choose a
sound, pause, draw, Preview melody, Keep/Turn/Preview kept, Make an answer, and
Play the full score. Observe where they hesitate, ask what each action changed,
and ask which result they want to keep and whether they want to make another.
Record actual responses rather than inferring delight from task completion.

## Audio evidence and limits

The second-round demonstration recorded actual Web Audio from the browser's
output routes, not generated soundtrack audio. The original stereo Opus capture
was 33.96 seconds; `ffmpeg` measured mean -30.1 dB and maximum -1.5 dB. Screen
recording and audio were captured separately and muxed, so their alignment is
approximate rather than sample-accurate synchronization evidence.

No human listening study, first-time-user study, screen-reader session, physical
mobile-device study, or cross-browser study has been conducted. Reviewers must
state when their modality cannot hear the supplied audio; numerical signal
measurements do not establish that the composition sounds satisfying.

## Inline editor integration

The user deferred subjective listening judgment and asked to combine Draw a
melody with the code editor. This is not another award-review round.

- Removed the separate drawing workspace and phrase selector. The selected
  `note("…")` owns a CodeMirror block widget immediately below its source line.
- The drawing and existing step/pitch controls share the selected note. Clicking
  the drawing moves the source caret without moving keyboard focus; Escape
  returns to that note for typing. Pad edits retain existing text selections.
- Drawing, keyboard contours, Turn, Shift, and text edits share history.
  Hiding Controls cancels uncommitted gestures without writing the document.
- A kept shape belongs to its phrase's mapped source position, not a global
  currently selected phrase. Cursor moves, preceding edits, and hiding Controls
  preserve it; deletion, replacement, and reload clear it.
- Compare & answer is a disclosure inside the same widget. Add melody lives
  in the score toolbar. Adding a phrase selects its new source, including when
  starting from a chord-only stack. Neither action converts song programs into
  stack programs.
- Desktop and mobile use the same editor-local structure. The drawing is
  compact; SVG pitch shapes compensate for its changing aspect ratio.

### Inline integration verification

- `npm run build` passed TypeScript checking and the Vite production build.
  JavaScript: 732.76 kB, 218.81 kB gzip. The existing large-chunk advisory remains.
- Desktop Chromium: a pointer contour updated only the note phrase, one Undo
  restored the exact original source, and Redo restored the exact drawing.
  Local storage matched the edited document. The drawing was inside
  `.cm-content`, not an adjacent application panel.
- Mobile Chromium touch emulation at 390 px: a CDP touch contour changed the
  notes; reloading restored exact source. Typing `D4` over the selected `C4`
  updated the drawing to `D4`. Play/Pause and saving the typed change succeeded.
  Document scroll width was 380 px, below the 390 px viewport.
- An isolated inline preview reported its playing state and actual sounding-step
  ring. This is functional feedback evidence, not a subjective listening verdict.
- Native Download completed a 151-byte `.mini` export.
- Desktop, mobile, and dark/reduced-motion surfaces were inspected visually.
  No page errors were reported in the observed desktop/mobile sessions.

Fresh automation browsers hit an environment-level native Canvas stall:
`clearRect(0, 0, 300, 150)` on a standalone canvas, without application code,
prevented page load from completing. Both the bundled Chromium 147 and installed
Chrome 148 reproduced it; disabling GPU/accelerated 2D rendering did not resolve
it. An attachment to the already-running owned Chrome 148 process completed the
same minimal canvas scenario. Regression verification therefore uses that real
browser through CDP, with separate test contexts, rather than changing or
stubbing application rendering. The temporary runner selects the production
server on port 5199.

The existing `npm test` entry passed **all 99 tests in 1.5 minutes**, with no
skips or retries. Four added regressions cover shared drawing/pitch/text
selection and history, phrase-local comparisons across edits and hidden
controls, cancellation on hide, and safe melody insertion into chord-only
stacks rather than song programs. Existing file-import/export, recovery,
playback, and literal-control tests also passed.

Executed command:

```sh
NODE_OPTIONS=--require=./.inline-browser.cjs npm test -- \
  --config=.inline-verification.config.ts --retries=0 --workers=1
```

The temporary preload attached Chromium through `connectOverCDP`; it did not
mock application behavior or change test assertions. The single worker
separated keyboard interaction on the shared browser process. Temporary
diagnostic scripts, preload, and configuration were removed afterward.
All 30 local links in the changed Markdown documents resolved.

### Inline integration screenshots

- [Desktop inline editor](musical-workspace/inline-desktop.webp)
- [Mobile inline editor](musical-workspace/inline-mobile.webp)
- [Dark inline editor](musical-workspace/inline-dark.webp)

## Editor-native refinement

The user found that the embedded version still felt like a separate interface.
Moving the old panel into CodeMirror had preserved its oversized stage, repeated
note labels and pads, and always-visible keyboard. The refinement makes those
controls subordinate to reading and editing the source:

- Neutral background, a single accent, a thin source-aligned guide, and four
  octave guides instead of a colored stage with dense grid lines.
- Desktop plot height 200 → 124 px, with a 760 px width cap. The full idle note
  widget measured 216 px high. On a 390 px touch viewport the plot is 156 px,
  toolbar/disclosure targets are 44 px, and content width is 390 px.
- Numbered notes, chromatic keys, octaves, and Rest now open under Pitch
  controls. Opening is one extra action in exchange for a quieter default.
  The disclosure follows the phrase in-session. Closing stops the step preview
  but preserves source, selection, and Undo history.
- Selected notes keep a filled marker and accent label; other notes use outlines.
  Pitch labels keep an 11 px rendered size across aspect ratios. Dense phrases
  retain the selected label without overlapping every neighboring label.
- No opening animation delays keyboard work. Drawing, text, and keyboard
  editing still share source and history.

Observed in the real browser: keyboard disclosure activation, exact F#4 editing,
closing a playing preview, Undo while collapsed, cancelling a keyboard contour,
touch drawing, exact saved-source recovery after reload, and full-score
Play/Pause. Desktop, mobile, and dark/reduced-motion views were inspected.
No page errors were reported. Token-based label contrast is 5.54:1 in light
mode and 7.14:1 in dark mode; selected-label contrast is 6.74:1 and 7.44:1.
This is not a screen-reader audit or proof of an optimal design.

`npm run build` passed; the final JavaScript bundle is 733.05 kB, 218.91 kB gzip.
The existing chunk-size advisory remains. No MoonBit behavior changed.

- [Compact desktop editor](musical-workspace/compact-editor-desktop.webp)
- [Compact mobile editor](musical-workspace/compact-editor-mobile.webp)
- [Compact dark editor](musical-workspace/compact-editor-dark.webp)

The complete existing test entry passed **100 tests in 1.3 minutes**, with
no retries or skips. The new regression covers keyboard disclosure activation,
preview cancellation on close, Undo while collapsed, and retained open state
after hiding/showing Controls. Existing pitch-editing tests now explicitly open
the disclosure before using its controls; their behavioral assertions remain.

```sh
NODE_OPTIONS=--require=./.compact-browser.cjs npm test -- \
  --config=.compact-verification.config.ts --retries=0 --workers=1
```

As above, the temporary runner used the owned working Chrome process and
production preview, with isolated real contexts. Both temporary files were
removed afterward. All 33 local Markdown links resolved.

## Help-centered interface — 2026-10-04

The user requested less explanatory text in the working interface, with needed
instructions collected in Help. The default surface now keeps the musical
actions and state rather than a second introduction above the editor:

- Replaced the introductory headline and starter descriptions with compact
  named starters and their tempos. The score title identifies the selected
  starter without repeating a separate heading.
- Kept a stable Help button with an expanded-state treatment, instead of
  switching its label between Show/Hide help.
- Moved files/recovery and playback/update explanations into Help, alongside
  drawing, pitch controls, preview boundaries, and keyboard instructions.
- Shortened idle/preview guidance and tooltips. Kept actionable errors,
  unsupported-notation feedback, and playback/save states at the operation.

The production build passed TypeScript checking and Vite bundling. The main
JavaScript bundle is 732.26 kB (218.47 kB gzip); the existing chunk-size advisory
remains. This refinement changes no MoonBit behavior.

Real-browser checks on the production preview:

- Desktop, 1440 px: opened files/recovery and playback guidance, closed Help
  with Escape without changing source, played a starter, paused it, and restored
  the exact original score with Undo. No horizontal document overflow.
- Touch viewport, 390 px: Help opened modally with focus on Close; Escape
  returned focus to Help. Selected D4 through pitch controls, observed the saved
  source, reloaded to the matching D4 drawing, and played/paused the score.
  Document width was 390 px. Neither browser context reported page errors.

This host again stalled while initializing the default native Canvas.
Verification requested `willReadFrequently: true` for the real 2D context through
a temporary browser init script; native CPU Canvas rendered the application.
No draw call was stubbed and no application rendering code was changed.
This is software-rendering evidence, not a successful default-GPU run or a
subjective listening/first-use study.

- [Help-centered desktop](musical-workspace/help-centered-desktop.webp)
- [Help-centered mobile](musical-workspace/help-centered-mobile.webp)

Current production preview: `http://localhost:5201/`.

The complete existing test entry passed **100 tests in 1.2 minutes**, with no
retries or skips:

```sh
NODE_OPTIONS=--require=./.help-browser.cjs npm test -- \
  --config=.help-verification.config.ts --retries=0 --workers=1 --max-failures=1
```

The temporary runner attached to the owned Chrome 148 process and created
isolated contexts with the same CPU Canvas hint. Its config selected this
worktree's production preview on port 5201. Both temporary files were removed
after verification. All 35 local Markdown links resolved.

## Full-viewport editor — 2026-10-04

The user requested an editor that uses the whole screen without surrounding
frames or unnecessary prose. Removed the outer card, page gutters, width cap,
separate score toolbar, and decorative footer line. The viewport now contains
a compact shared toolbar, the flexible code surface, and a bottom status strip.
CodeMirror scrolls long documents; the page itself stays within the viewport.

Starting sounds moved into Help, with separate Play and Load groups preserving
their existing behavior. Choosing either on mobile closes Help and returns to
the editor. Audio output opens under Playback details. Saved drafts moved to
the bottom strip; expanded recovery and playback inspection share a bounded
scrolling footer so they cannot consume the whole editing surface.

Observed in the production browser:

- At widths 320, 390, 768, 1440, and 2560 px, document width matched viewport
  width and document height remained 900 px. The editor spanned the full width.
- At 1440 × 900 and 2560 × 900, the toolbar was 52 px and the editor 816 px high.
  At 320 px, the toolbar stayed at two rows (98 px), including during playback.
- A 101-line score scrolled within CodeMirror to its final note; the page stayed
  900 px high and Undo remained available in the toolbar.
- Help opened and closed on desktop. On touch, Help was modal and selecting a
  playable starter closed it. Pitch changes, Undo, and Controls remained usable.
- Playback details opened the real waveform, reported Live, and the analyser
  returned a measured peak of 0.2175. Playback then paused normally.
- At 390 × 400 with Saved drafts expanded, the footer stayed at 160 px and left
  139 px of usable editor height. Desktop light and mobile dark were inspected;
  the final browser context reported no page errors.

The final build passed TypeScript checking and Vite bundling: JavaScript
732.27 kB (218.48 kB gzip). The existing chunk-size advisory remains.
The mechanical design detector reported no findings. No MoonBit behavior or
audio-thread implementation changed.

Browser verification used the same temporary native CPU Canvas hint described
above, not stubbed drawing or audio. Physical mobile keyboards, screen readers,
subjective listening, and default-GPU rendering were not verified.

- [Full-viewport desktop](musical-workspace/edge-editor-desktop.webp)
- [Full-viewport mobile, dark](musical-workspace/edge-editor-mobile-dark.webp)

Regression evidence:

- The full existing suite passed **100 tests in 2.4 minutes** after the main
  viewport cutover.
- After the last recovery-footer and 320 px toolbar adjustments, a full rerun
  reached the workspace portion but hit the shell's 240-second deadline before
  producing a completion summary. This was not counted as a full-suite pass.
- The final affected workspace suite then passed **18 tests in 1.4 minutes**,
  with no retries or skips, covering editing/history, Help, import/export,
  saved drafts, concurrent saves, and storage failure.

```sh
NODE_OPTIONS=--require=./.edge-browser.cjs npm test -- \
  --config=.edge-verification.config.ts tests/workspace.spec.ts \
  --retries=0 --workers=1 --max-failures=1
```

The temporary runner selected the owned browser and current production preview,
with isolated contexts and the CPU Canvas hint. Both temporary runner files were
removed after verification. All 37 local documentation links resolved.

## Melody composition — 2026-10-04

The inline editor now exposes rhythm, contextual comparison, and auditioned
variations without creating a separate editable project model.

- Timing & ideas edits relative `@N` lengths, transfers time across an onset with
  Earlier/Later, preserves duration when replacing a note with Rest, and inserts
  a rest before the selection. GUI operations enforce the notation limits:
  1–16 per step, 256 total units, and 32 graphical steps.
- Try a note auditions nearby C minor pentatonic pitches. Repeat opening and
  Change ending retain rhythmic weights. Proposals do not modify source until
  Use change; Cancel, typing, or selecting another step discards them.
- Loop with score and Loop kept with score retain tempo, effects, and accompaniment
  for direct patterns and stacks with supported timing. Switching versions
  leaves the working document and main transport untouched. Loops start at the
  score's beginning and stop on edits, main transport actions, or Stop preview.
  Named-reference use, songs, reversal, and unsupported timing forms use main
  Play instead. Proposals fall back to the labelled isolated 90 BPM preview.
- Comparison captures pitches and rhythm before the first graphical edit.
  Keep this shape replaces the reference; Restore kept is undoable. This
  comparison remains session-only; the authored weighted notation persists.

Observed in production Chromium:

- Changing `C4` to `C4@2`, transferring one unit to the following note, replacing
  a note with a rest, and undoing each operation preserved surrounding code.
- A weighted context loop produced Live output and reached its final source
  step. Stop preview returned output to Silent. Weighted candidates also
  produced Live output; Use adopted them and Undo restored the exact source.
- Current/kept switching produced Live output for each version without editing
  the document. Repeating the opening and restoring the reference were undoable.
- Main Play accepted the weighted score and produced Live output. Reload
  preserved `C4@2  Eb4 F4 G4` with its original spacing.
- At 390 px in dark scheme, length changes, inserted rests, ending proposals,
  Use/Cancel, and Undo remained operable. Document width stayed 390 px.
  Use/Cancel returned keyboard focus to Timing & ideas rather than a hidden
  proposal button.

Engine and build verification:

- `NEW_MOON_MOD=0 moon check` passed.
- `NEW_MOON_MOD=0 moon test`: **1,278 passed, zero failed**. The first integration
  exposed truncated weighted groups; regression coverage now checks complete
  child timing, full event parts, partial queries, weighted rests, repetition,
  Draft preparation, and source origins.
- `NEW_MOON_MOD=0 moon info` and `NEW_MOON_MOD=0 moon fmt` completed. The interface
  diff adds only the weighted pattern/document constructors and their error.
- Rebuilt browser WASM with
  `NEW_MOON_MOD=0 moon build browser --target wasm-gc --release`, then ran
  `./playwright-sync-wasm.sh` and `npm --prefix web/live run build`.
  The Vite prebuild regenerates authoring JS but copies the existing web WASM,
  so rebuilding only Vite is insufficient after notation-engine changes.
- TypeScript and Vite passed: JavaScript **749.52 kB**, **223.55 kB gzip**.
  The existing large-chunk advisory remains.

These checks used real DSP/WASM and native CPU Canvas rendering via a temporary
`willReadFrequently` hint. No audio or drawing output was stubbed. Physical
devices, default-GPU rendering, and subjective musical quality were not verified.
This is not another award-review round and does not resolve the human-study gate.

- [Composition desktop](musical-workspace/composition-desktop.webp)
- [Composition mobile, dark](musical-workspace/composition-mobile-dark.webp)

Final browser regression run: **109 passed in 3.9 minutes**, with zero retries
and no skips, using the existing `npm test` entry and a temporary configuration:

```sh
NODE_OPTIONS=--require=./.composition-browser.cjs npm test -- \
  --config=.composition-verification.config.ts \
  --retries=0 --workers=1 --max-failures=1
```

The bridge attached to the owned Chromium process, created isolated contexts
with the native CPU Canvas hint, and selected the current production preview
on port 5201. Both temporary runner files were removed after verification.
All 30 local links in the changed Markdown documents resolved. The updated
composition Help section was also exercised in the mobile modal.

## Essential edit-listen loop

2026-10-04. The user asked for the interface to express the natural cycle of
editing, hearing the score, and refining it—not an accumulating collection of
composition tools.

The inline drawing now has no action toolbar. Its selected-step row contains
the pitch, Length, and Rest; one optional Pitch controls disclosure provides
exact chromatic editing. Code remains the score. Main Play/Pause/Restart is the
only audio path, and Undo/Redo is the only mechanism for reversing an experiment.

Removed, rather than hidden: pitch proposals and adoption state, motif variations,
phrase transforms, kept comparisons and restore state, answer generation,
isolated previews, context loops, their Player/AudioEngine, and their modules.
Relative `@N` rhythm remains part of the language and selected-step editing.
File exchange, local persistence/recovery, unsupported-source editing, and
normal material-entry update semantics remain available.

Observed production behavior:

- Desktop: select a note without rewriting it; change its length; replace it
  with a rest while keeping the weight; Undo both edits to the original source.
  These edits did not start playback.
- From the drawing, Ctrl+Enter started main Play and the real post-master samples
  became nonzero. ArrowUp changed the selected pitch during playback; Ctrl+Z
  restored the source without stopping playback. Ctrl+Enter paused, with focus
  still on the drawing. No separate listening mode was involved.
- Mobile Chromium, 390 × 844, dark: native touch events drew a contour, and one
  Undo restored the phrase. Length and Rest edits persisted across reload.
  Pitch selection and toolbar Undo/Redo worked; touch Play produced real output
  and touch Pause stopped the transport.
- Core Length and Rest controls measured 44 px high. Document width remained
  390 px. The browser reported no application page errors.

`npm run build` passed TypeScript checking and Vite bundling: JavaScript
**730.94 kB**, **217.80 kB gzip**; CSS **21.15 kB**. The existing large-chunk
advisory remains. No MoonBit source or audio-thread implementation changed in
this reduction; the previously verified relative-duration engine is retained.

The first regression run overlapped manual keyboard interaction in the same
owned Chromium process and failed one existing knob Redo assertion. After
closing the manually controlled tab, that exact test passed in 6.8 seconds
without changing the knob implementation or its test. Concurrent input
interference is a hypothesis, not an established application defect; final
regression verification runs without other browser input.

Browser evidence uses native CPU Canvas with the temporary `willReadFrequently`
hint and real DSP/WASM, not stubbed audio or graphics. It does not establish
physical-device, default-GPU, screen-reader, or subjective listening outcomes.
The earlier award-review/human-study gate remains unresolved.

- [Essential desktop editor](musical-workspace/essential-editor-desktop.webp)
- [Essential mobile editor, dark](musical-workspace/essential-editor-mobile-dark.webp)

Final full regression run passed **95 tests in 3.3 minutes**, with no retries or
skips, using the existing `npm test` entry and the temporary owned-browser bridge:

```sh
NODE_OPTIONS=--require=./.essential-browser.cjs npm test -- \
  --config=.essential-verification.config.ts \
  --retries=0 --workers=1 --max-failures=1
```

The no-autoplay regression counts real AudioContext construction across drawing,
pitch edits, main playback, and Undo: only main Play creates a context. A final
native-field browser check also confirmed that Ctrl+Z edits only the unfinished
Length value, Enter commits, Escape discards unfinished input, and score Undo
restores the prior length.

One obsolete Rest-placement test was then deleted instead of fixing the layout
in a test. Its source/Undo behavior is covered independently; the current suite
contains 94 cases. All 27 local links in the changed Markdown documents resolved.
After that deletion, all **17 remaining workspace tests passed in 1.9 minutes**,
again with no retries or skips. Both temporary browser-runner files were removed.

## Structural notation editing — 2026-10-04

The inline editor now operates on source atoms and groups rather than a
space-split approximation of the notation:

- The production MoonBit notation parser captures recursive source ranges and
  postfix spans. The main-thread authoring bridge queries compiled snapshots
  and joins exact event origins to source atoms. TypeScript does not introduce
  another notation grammar.
- Split preserves an atom's outer postfixes. Repeat edits an atom/group's
  existing repetition. Boundary drag and Share conserve the other sibling
  boundaries, including rescaling saturated integer weights.
- Source groups highlight all descendant occurrences. A repeated note remains
  one editable source atom, not a flattened series of independent notes.
  Dense event labels are omitted instead of overlapping; code, selection
  properties, and accessible source names remain available.
- Timing separates relative weight, phrase stretch, and gate. Direct decimal
  `.fast(1.5)` and `.slow(0.5)` preserve rational timing; callback factors remain
  integer-only. Outer code transformations and arrangements are preserved, not
  folded into the local notation drawing.
- There is still one transport and one source history. No auxiliary audio,
  comparison state, generators, or pitch proposals were added.

Observed production smoke:

- Desktop boundary drag left the text unchanged until pointer release, then
  changed `C4  D4 E4` to `C4@3  D4 E4@2`. One Undo restored exact whitespace.
  Escape cancelled a second drag without writing. A Unicode comment and outer
  `.fast(1.5).gain(.2)` survived. Main Play produced real post-master samples
  with peak **0.0116863**; Pause stopped the transport.
- Group selection highlighted all four events of `[C4 Eb4]*2`. Keyboard focus
  on a source atom had a visible accent stroke, rather than an invisible
  transparent hit region.
- Mobile Chromium at **390 × 844**, dark: native touch selected the group,
  repetition changed `*2` to `*3`, and touching the rest then Split wrote
  `[~ ~]`. One Undo restored the rest without reverting group repetition.
  Reload restored the exact edited source. Touch Play produced real output
  with peak **0.0309628**, and touch Pause stopped it.
- Native touch boundary drag also committed only on release and produced
  `C4@3  D4 E4@2`; one Undo restored the source. Group, atom, boundary, and
  Split targets measured **44 px high**. Document width stayed **390 px**.
  No application page errors were reported.

Integration fixes exercised by the regressions:

- Zero-aligned, whole-cycle projection uses the existing query-work estimator
  with known alignment. Arbitrary-arc playback admission had incorrectly
  rejected the valid 256-weight authoring boundary. Runtime admission itself
  is unchanged; projection still has bounded work and emitted events.
- Contour interpolation samples displayed event centers, handles vertical
  note drags, and accounts for device-pixel rounding at an ending note.
- Saturated sibling weights are reduced by their common divisor before
  choosing a representable boundary. No-op field commits add no history.

Evidence:

- [Desktop source/group editor](musical-workspace/structure-editor-desktop.webp)
- [Mobile source/group editor, dark](musical-workspace/structure-editor-mobile-dark.webp)

Verification uses the same owned Chromium and native CPU Canvas hint as the
preceding record, with real DSP/WASM and isolated test contexts. It does not
establish physical-device, default-GPU, screen-reader, or subjective listening
outcomes. The earlier human-review gate remains unresolved.

Final checks:

- `NEW_MOON_MOD=0 moon check --deny-warn` passed without warnings.
- `NEW_MOON_MOD=0 moon test`: **1,284 passed**, no failures.
- `moon info` and `moon fmt` ran with `NEW_MOON_MOD=0`. Generated interface
  inspection showed only the intended `mini.project_notation_nodes` and
  `browser_authoring.project_notation` additions.
- The release `browser` wasm-gc build and asset synchronization passed.
- `npm run build` passed TypeScript and Vite: JavaScript **768.17 kB**,
  **228.07 kB gzip**; CSS **23.60 kB**. Vite's existing large-chunk advisory
  remains.
- Final complete browser suite: **102 passed in 1.3 minutes**, no retries or
  skips. The final run includes the source/group interactions, fractional
  timing with real audio, existing history/lifecycle tests, and recovery.

```sh
NODE_OPTIONS=--require=./.structure-browser.cjs npm test -- \
  --config=.structure-verification.config.ts \
  --retries=0 --workers=1 --max-failures=1
```

The temporary owned-browser adapter and verification configuration were removed
afterward; no application test seam or alternate audio path remains.

## Actual-onset linkage — 2026-10-04

Actual successful scheduler note-ons now drive code and inline notation pulses.
This is not a JavaScript cycle counter: active material snapshots retain source
atom, complete reference path, and literal-local occurrence coordinates through
Pattern and Song playback. The source frame is root metadata, not another
musical graph node. Source IDs do not change material keys or voice scopes.

Code locations follow persistent identity across offset changes and invalid
drafts. Deletion/reinsertion, including Undo reinsertion, cannot inherit an old
atom's onsets. Literal content edits retire diagram coordinates independently:
surviving atoms can still pulse in code without falsely lighting edited notation.
Negative numeric notes remain distinct from unpitched drums.

Observed production surface:

- Desktop, **1365 × 950**: `note("[C4 E4]*2")` produced all four distinct local
  occurrences (`60:0`, `64:0.25`, `60:0.5`, `64:0.75`), with no code/diagram
  mismatch. Real post-master peak was **0.0570244**; Pause cleared all pulses.
- Mobile viewport, **390 × 844**: a named `motif` inside a repeating Song
  produced the same four occurrences plus the exact traversed `motif` reference.
  The inline drawing followed the selected source line; document width stayed
  390 px. Switching an already accepted Pattern to Song still required Restart,
  preserving the existing layout-change contract.
- A real tab switch cleared all highlights while audio continued dispatching
  at least eight more notes. Returning changed observation generation from
  **5 to 7** and displayed one current sequential occurrence, not a backlog.
- The six focused browser regressions passed: Pattern/Song repeated occurrence
  mapping with real audio; source insertion, persistence, and mobile reload;
  invalid drafts and retired Undo identities; selection/focus/scroll/history
  preservation; bounded-ring overflow and generation retirement.

Visual evidence:

- [Desktop actual-onset linkage](musical-workspace/onsets-desktop.webp)
- [Mobile Song and reference linkage](musical-workspace/onsets-mobile-song.webp)

Transport and allocation evidence:

- A single Player-owned 256-row buffer serves all routes. The Worklet writes
  primitive fields to a 256-slot shared ring. Atomic ownership prevents torn
  Float64 reads and never waits for the reader. Paths longer than 32 bindings
  are discarded whole; the boundary regression checks complete 32-binding
  serialization and unchanged storage after rejection.
- The final concurrent worker smoke attempted **320,000** observations:
  **319,631 written**, **313,506 overwritten**, **369 reader-busy drops**,
  **6,125 received**, **zero torn rows**, and **zero replayed identities**.
  This deliberately saturated the transport; it is not an audio benchmark.
- Release wasm-gc WAT inspection found **zero `array.new`/`struct.new`
  instructions** in `OnsetBuffer.record`, `field`, `clear`, and `enable`,
  `EventOrigin.write_binding_serials`, and the source-frame query callbacks.
  Their epoch comparison also had no allocations. Frame capture reuses the
  child query's array and already-owned payloads. Cold construction allocates;
  existing pattern queries still allocate. This is not a whole-engine
  audio-thread-allocation certification.
- Local production preview reported `crossOriginIsolated: true`. Vite and the
  Cloudflare static `_headers` file declare COOP/COEP; no remote deployment was
  performed. Without isolation, audio remains usable and pulses are disabled.

Paired observer measurement used the same nested-reference Pattern and the same
40 tracked first-note edits, ten warm-up updates, 128-frame blocks at 48 kHz,
and six cycles after the last update. Both orders used a fresh headless Chromium
process, muted output, and the actual AudioWorklet/WASM path. Main-thread
observation draining ran every 16 ms.

| Order | Observer | Edited blocks | Mean render ms | p95 ms | Max ms | Drained |
|---|---|---:|---:|---:|---:|---:|
| Off → on | Off | 2625 | 0.2385 | 1 | 7 | 0 |
| Off → on | On | 2581 | 0.1635 | 1 | 2 | 67 |
| On → off | On | 2598 | 0.2983 | 1 | 7 | 69 |
| On → off | Off | 2603 | 0.1909 | 1 | 3 | 0 |

Every arm remained Playing, drained pending material changes to zero, and
observed at least six post-update cycles. Enabled arms reported no engine,
overwrite, or reader-busy drops. Timing differences changed sign with order.
`Date.now()` cannot resolve sub-millisecond callback costs; callback interarrival
gaps reached 38 ms and some render maxima exceeded the 2.667-ms quantum even
with observation off. These measurements establish execution and bounded
transport behavior, not a speedup, glitch-free output, GC-pause measurement,
underrun count, or physical-device synchronization.

```sh
node scripts/measure-playback-api.cjs http://127.0.0.1:5202/ --onset-observation --order=AB
node scripts/measure-playback-api.cjs http://127.0.0.1:5202/ --onset-observation --order=BA
```

The MoonBit suite passed **1,294 tests**; `moon check --deny-warn`, `moon info`,
and `moon fmt` completed with `NEW_MOON_MOD=0`. The browser ABI and public graph
boundary checks passed. Generated interfaces were inspected for the new source
frame, exact Song snapshot, scalar observer, and authoring lookup APIs.

Browser smoke is automated Chromium evidence, including a mobile viewport,
not physical-device testing or human listening. The earlier independent
listening/first-use gate remains unresolved.

Final browser regression run: **108 passed in 6.2 minutes**, no retries or
skips. The ordinary runner first hit navigation/input deadlines; a captured
autocomplete failure contained the expected completions in its later snapshot.
The 8-CPU host reported load **24.52**, approximately **7.3 GiB swapped**, and
**24% I/O wait**. The final run reused owned Chromium with native CPU Canvas,
a temporary 60-second test budget, and a 20-second assertion budget. No test
assertions, application clocks, audio output, or drawing behavior were replaced.
This pass does not establish responsiveness under the default runner deadlines.

```sh
NODE_OPTIONS=--require=./.onset-browser.cjs MOONDSP_VIRTUAL_AUDIO=1 npm test -- \
  --config=.onset-verification.config.ts --workers=1 --retries=0 \
  --max-failures=1 --trace=retain-on-failure
```

The temporary browser adapter, verification profile, and concurrent-ring smoke
script were removed after use. All **77 local links** across the eight changed
Markdown documents resolved, and fenced blocks were balanced.

Final production rebuild exited successfully: TypeScript and Vite passed;
JavaScript was **786.86 kB / 232.96 kB gzip**, CSS **24.79 kB**. The existing
large-chunk advisory remains. The updated Playback & updates Help text was
opened and visually checked in the 390-px modal.

A separate plain HTTP server exercised the same production assets without
COOP/COEP: `crossOriginIsolated` was false, `SharedArrayBuffer` was undefined,
observer statistics were null, and no pulse was displayed. Real playback still
produced a post-master peak of **0.0619702**. Pause worked and no application
page errors were reported. That temporary server was stopped after the smoke.

## Hold until the next onset — 2026-10-04

At the user's request, highlights now retain the latest dispatched onset group
until the next onset across the score. This supersedes the brief-pulse lifetime
recorded above; it does not change audio scheduling or origin identity.
Simultaneous notes share their audio timestamp and remain lit together. Rests
retain the preceding group. Late batches jump to their newest due group rather
than replaying intermediate notes, and unresolved new origins cannot leave the
previous note falsely highlighted. The existing 256-observation bound remains.

Verification:

- Production TypeScript/Vite build passed.
- Eight affected Playwright tests passed in 2.5 minutes with the standard
  configuration, virtual audio, one worker, and no retries. Coverage includes
  Pattern/Song repeated occurrences, mobile edit/save/reload, source retirement
  and Undo, selection/scroll stability, ring generations, and new held-note and
  held-chord regressions across rests.
- Actual desktop and mobile browser playback of `chord("C ~ Dm ~")` showed
  complete C and Dm triads switching together, with no blank frames between
  observed groups. With `.slow(4)` at 120 BPM, completed mobile groups stayed
  highlighted for 966–983 ms. The desktop post-master waveform peak was
  0.1159465; this is rendered-signal evidence, not a listening assessment.
- Pause cleared all code and note highlights. A synthetic `visibilitychange`
  handler smoke also cleared four decorations and advanced generation 6 to 7.
  Native tab activation in this managed headless browser did not change
  `document.hidden`, so this run does not add real hidden-tab evidence to the
  prior integration smoke.

The changes are confined to frontend presentation, browser regressions, Help,
and documentation. No MoonBit or audio-render path changed; the full engine and
browser suites were not rerun for this presentation-only follow-up.

The final rebuild including revised Help passed; the existing large-chunk
advisory remains. Playback & updates was opened and visually checked at
390 px. All 52 local link paths across the six changed Markdown documents
resolved, and fenced blocks were balanced.

## Readable notation grid — 2026-10-04

The user rejected pitch-connecting lines and thin note marks as hard to read.
The inline notation now uses labelled chromatic rows, rectangular note blocks,
and a cycle ruler. It remains a projection of the quoted source, not a second
sequencer or a view of voice sustain/release. This replaces the earlier
contour/lozenge visual design described in this record.

### References and decisions

- [Sonic Pi's official interface inventory](https://github.com/sonic-pi-net/sonic-pi/blob/dev/etc/doc/tutorial/01.2-Exploring-the-Interface.md)
  separates code, play controls, Help, logs, and scopes. Its standard interface
  is not a piano-roll editor. Adopt the role separation, not a fictitious Sonic
  Pi notation widget.
- [Ableton Learning Music's pitch-pattern lesson](https://learningmusic.ableton.com/notes-and-scales/make-patterns-with-pitch.html)
  and [official screenshot](https://cdn-resources.ableton.com/resources/uploads/zinnia/NL_Learning_Collage_800x400.jpg)
  show named pitch rows, grid-aligned blocks and clear gaps. Adopt that familiar
  visual vocabulary, without importing independent note creation/deletion,
  a second playback clock, or DAW-style duration editing.
- Block position/width represents the compiled literal's start/interval.
  Outer transformations, Song placement, gate and envelope release remain in
  code. The ruler uses cycles rather than inventing a bar meter.
- An ink outline means selected source; a solid accent fill means the latest
  dispatched onset. Held highlights no longer blink. Chord blocks show their
  individual pitch names; the source strip retains the chord's authored name.
- Source slots are labelled, including rests. Invisible hit targets no longer
  inherit SVG strokes. Rests stay as grid gaps, not a misleading pitch lane.
- Rows remain 20 px high; wide pitch ranges scroll vertically while the ruler
  stays visible. Drag and grid-arrow pitches are chromatic, matching the visible
  rows rather than an undisclosed pentatonic quantizer. Repeats still edit one
  source atom, and a drawing is still one Undo operation.

### Observed browser evidence

- [Desktop, selected repeated E4 and playing C4](musical-workspace/note-grid-desktop.webp):
  dragging E4 onto F♯4 changed only `[E4 G4]*2` to `[F#4 G4]*2`, selected both
  linked occurrences, and left playback Ready. Undo restored the source; main
  Play then highlighted the actual C4 independently of the selected E4.
- [390 px dark mobile chord playback](musical-workspace/note-grid-mobile-dark.webp):
  all three C or Dm pitches lit together. Completed sampled groups stayed lit
  for approximately 950 and 1067 ms with no blank frames; the post-master peak
  was 0.1159465. No horizontal page overflow was observed.
- A separate 390 × 844 Chromium input smoke dispatched native CDP touch events:
  dragging C♯4 to F♯4 produced `note("F#4 D4 Eb4 F4").gain(.2)`, with no
  horizontal overflow. This is automated touch-input evidence, not a physical
  touchscreen or user study.
- Production TypeScript/Vite build passed. The mechanical UI detector returned
  no findings. The existing large-chunk advisory remains.
- The visual reviewer found that a playing source step overrode its selection
  outline. A combined selected/playing rule now retains the 2 px ink outline.
  Actual playback confirmed distinct stroke/fill in both
  [desktop light](musical-workspace/note-grid-selected-playing-desktop.webp)
  and [390 px dark](musical-workspace/note-grid-selected-playing-mobile.webp).
  The final production rebuild passed after this correction.
- The default full browser run passed 104 tests before a 15-second timeout in
  the conflicting-tab download test (`download.createReadStream: canceled`).
  This was a timeout, not an observed assertion mismatch; the run stopped there.
- The complete workspace file then passed **17/17 tests in 2.7 minutes**, with
  retries disabled and a 60-second per-test deadline. This includes the
  timed-out download scenario and the cases skipped when the full run stopped.
  Application code and assertions were unchanged for that run. The original
  15-second full run is not reported as green.
- The visual re-score marked the selection fix resolved, found no remaining
  issues in that scope, and returned **ship**. The independent interaction-code
  reviewer could not run because its configured model was unavailable; no
  substitute model or successful code-review claim was made.
- After the verification runtime restarted, dependencies and the production
  build were restored. JavaScript/CSS asset hashes matched the prior final
  build. The restored preview again rendered C4/E4/G4 highlights with a
  post-master peak of 0.1159465, no page overflow, and no reported browser
  errors. The preview is served at `http://localhost:5202/`.
- All 35 local link paths in PRODUCT, DESIGN, CHANGELOG, and this record
  resolved; fenced blocks were balanced.

Audio rendering, notation compilation, source identities, and observation
transport were not changed. These checks do not establish subjective listening
quality, screen-reader usability, or award qualification.

## Rest entry and percussion steps — 2026-10-05

The user requested direct note creation in rests and a separate editing surface
for percussion. Both edit the existing score, use shared Undo, and leave the
single transport and material-entry playback contract unchanged.

- Note rests now expose dashed pitch cells. Pointer/touch entry previews until
  release; Escape cancels. Source-selected rests also support keyboard pitch
  preview and Add note/Add chord, including entirely silent phrases.
- Only the chosen atom's core changes. Weights, repeats, whitespace, surrounding
  transformations, and linked occurrences survive. Drawing over existing notes
  still preserves intermediate bends without filling crossed rests; silence
  from degradation does not select a neighboring note.
- `s("…")` uses a dedicated matrix with Kick, Snare, Hi-hat, Open hat, and Clap
  rows. One column represents one authored atom, not an equal-time playback
  slice. Empty cells set/replace a sound; filled cells clear it. Headers select
  without editing. Nested/repeated source stays intact; simultaneous layers
  remain code-authored. This does not add sample-file import.
- Note-rest timing comes from a same-width `~` → `0` compiler probe, not another
  timing interpreter. The probe reuses production query-work admission before
  querying. Events plus rest occurrences are capped at 256. There are no
  scheduler, Worklet, DSP-render, or observation-transport changes.

### Observed verification

- [Desktop rest intervals](musical-workspace/rest-entry-desktop.webp):
  `note("C4 ~@2*2 G4").slow(2).gain(0.2)` previewed A4 before release, then
  changed only `~` to `A4`. Both repeated blocks updated. Undo restored `~`;
  Redo restored A4. Playback produced a post-master peak of 0.037962 and an
  actual-onset note highlight.
- [Desktop percussion](musical-workspace/percussion-steps-desktop.webp):
  setting and clearing Snare preserved `@2`, Undo restored it, and reload
  recovered the source. Playing Kick was marked in its sound row; the measured
  post-master peak was 0.123471.
- [390 px dark rest entry](musical-workspace/rest-entry-mobile-dark.webp):
  native CDP touch input changed `note("~@2 ~")` to `note("E4@2 ~")`. Undo
  restored both rests; Redo and Play produced a 0.034193 peak and the E4
  highlight. Reload recovered the edited source in Ready state without
  starting audio.
- [390 px dark percussion](musical-workspace/percussion-steps-mobile-dark.webp):
  a 560 px matrix scrolled within a 348 px viewport. A touch on source step 10
  inserted Snare; Undo restored the rest. Cells remained 48 × 48 px, and the
  page stayed 390 px wide. A final mobile percussion playback check produced a
  0.157535 peak with the Kick cell highlighted and no reported browser errors.
- The updated mobile Help opened the Percussion steps instructions and closed
  with Escape. No horizontal page overflow was observed in these scenarios.
- `NEW_MOON_MOD=0 moon check`, the full MoonBit suite (**1,297/1,297**), `moon info`,
  and `moon fmt` passed. The public `.mbti` hash was unchanged. Projection tests
  cover weighted/nested rests, all-rest phrases, original events, combined
  occurrence bounds, and oversized probe rejection.
- Production TypeScript/Vite build passed. The affected browser files passed
  **37/37**; the final full suite passed **121/121** with one worker, no retries,
  and a 60-second per-test deadline. The existing large-chunk advisory remains.
- Integration checks caught and fixed occupied percussion buttons inheriting
  SVG-only `pointer-events: none`, and a rest-hit change that blocked starting
  an existing contour above its old pitch. The behavioral regressions passed
  after fixing the implementation, without weakening their assertions.
- The final mechanical UI detector reported no findings on the changed
  controls, styles, and Help.

These are Chromium desktop/mobile-emulation, touch-input, and rendered-signal
checks. They do not establish physical-device usability, screen-reader
experience, subjective listening quality, or award qualification.

## Flexible note manipulation — 2026-10-05

The user rejected prominent rest cells and pitch-only dragging. Rests now
remain blank, while their source intervals still accept note entry. Note bodies
support diagonal pitch/source-order movement; note edges resize adjacent
durations. This is source-preserving editing, not arbitrary-time placement:
occupied steps rotate, whole tokens retain their postfixes, and moves do not
cross the source sequence boundary. Repeated occurrences remain linked.
Shift-drag and drawing from blank grid space retain contour editing.

Grid shortcuts are Alt+Left/Right for source-order movement,
Shift+Left/Right for the right boundary, and Delete/Backspace for rest conversion.
Ordinary arrows retain step selection and semitone editing. Help documents
these operations and the source-order constraint.

### Observed browser evidence

Screens: [movement preview](musical-workspace/flexible-notes-move-preview-desktop.webp),
[resize preview](musical-workspace/flexible-notes-resize-preview-desktop.webp),
[playback](musical-workspace/flexible-notes-playing-desktop.webp), and
[390 px dark touch editing](musical-workspace/flexible-notes-mobile-dark.webp).

- Desktop diagonal drag previewed F4 without changing the source, then changed
  `C4@2 ~ E4 ~ G4 ~` to `~ F4@2 E4 ~ G4 ~` on release. Undo restored the original;
  Redo selected F4 at its new position. Up then changed that note to F#4, not
  the old source position.
- Dragging F#4's right edge previewed without committing and produced
  `~@2 F#4@5 E4 ~@2 G4@2 ~@2`, preserving `.slow(2).gain(.2)`.
  Playback produced a post-master peak of 0.037856 and an F♯4 onset highlight.
  Reload recovered the edited score in Ready state without starting audio.
- At 390 px, native CDP touch input moved `C4 ~ E4 G4` to `~ D4 E4 G4`.
  A touch edge drag produced `~@2 D4@3 E4 G4@2`; Undo and Redo restored the
  corresponding sources. No horizontal page overflow was observed.
- Mobile playback produced a 0.037049 peak and the D4 highlight. Updated Help
  contained the movement constraint and keyboard controls and closed with
  Escape. The browser reported no errors in this scenario.
- Integration found that CodeMirror history maps the original selection on
  Redo unless a subsequent selection is recorded. Source edits now commit the
  destination caret, then select its core, preserving one document Undo step.
- Native vertical touch dragging initially triggered `pointercancel` and
  scrolling. Event tracing showed that selection redraw detached the original
  hit group before `touchstart`; canvas listeners never received that event.
  Listening on the hit groups preserved editing without disabling gutter
  scrolling. The rebuilt application changed F4 to D4 with native touch input,
  then restored both sources through Undo/Redo.
- A gutter swipe in `note("C2 G6")` changed the grid's scroll offset from
  938 to 853 without editing the source. A subsequent touch in the blank rest
  of `C4 ~ E4 G4` entered F4, and Undo restored the rest.
- Production TypeScript/Vite build passed. The focused manipulation file passed
  **11/11**, and the final full browser suite passed **135/135** with virtual
  audio, one worker, no retries, and a 60-second per-test deadline. Coverage
  includes occupied/rest rotation, repeated groups, cross-parent rejection,
  both resize edges, preview/commit geometry, cancellation, shared history,
  identical-token selection, native vertical touch editing, and gutter scrolling.
  The existing large-bundle advisory remains.
- The mechanical UI detector reported no findings on the changed interaction
  surfaces. Five Markdown documents passed code-fence and local-link validation
  (**59 links**, including the four screenshots above).

The audio engine, notation compiler, and onset transport were not changed in
this iteration. Browser signal and emulated-touch checks do not establish
subjective listening quality, physical-device usability, or award qualification.

## Phrase-centered editing — 2026-10-05

The user approved four improvements: multi-note editing, contextual structure
controls, clearer local rhythmic guidance, and feedback beside edited phrases.
All four remain inside the existing source editor and main transport.

- Select enables pointer/touch ranges and keyboard extension/shrinking. The
  range is a CodeMirror source selection, not a second musical document.
  Complete sibling tokens move as a block; transposition preserves rests,
  postfixes, and numeric/flat spelling. Nested source groups remain intact.
- Duplicate inserts an independent literal copy after the range. Unlike Repeat,
  edits to the copy do not change the original. Adding source steps redistributes
  the existing notation span; it does not invent a longer arrangement.
- Structure opens the source strip and Split/Repeat/Share controls on demand.
  Pitch-only controls are unavailable for a multi-note selection rather than
  silently editing just one selected note.
- The ruler labels local cycles. Optional four-division guides do not claim a
  time signature or incorporate outer speed, gate, or song placement. Compiled
  movement previews also show displaced neighboring notes.
- Phrase-local notices distinguish queued/sending source from accepted code
  with score-wide pending material. Source edits made while controls are hidden
  remain tracked. Only current-version settlement clears pending feedback.

### Observed browser evidence

Screens: [repeated-group editing](musical-workspace/phrase-range-group-desktop.webp),
[pending source update](musical-workspace/phrase-pending-desktop.webp), and
[390 px playback and range selection](musical-workspace/phrase-range-playing-mobile.webp).

- Desktop selection changed `C4@2  Eb4` to `C#4@2  E4`, then moved that range
  after G4 without overwriting notes. Undo/Redo retained both destination notes.
  Duplicate inserted a separately selected `C#4@2 E4` copy.
- Selecting only the `4` in `C4` disabled Duplicate and prevented ArrowUp from
  widening the edit. Selecting the complete inner `C4 E4` in `[C4 E4]*2` selected
  four performed occurrences and transposed the two authored notes together.
  Moving the whole repeated group produced `G4 [C#4 F4]*2`; Rest produced
  `G4 [~ ~]*2`, and Undo restored the group.
- Native Chromium touch input at 390 px selected C4/E4 without rewriting them.
  Drag preview retained the old source and showed two selected-note ghosts plus
  one displaced neighbor. Release changed `C4 E4 G4 A4` to `G4 C4 E4 A4`.
- Mobile Duplicate, Undo, Redo, and Play preserved the selected range. Actual
  onset highlighting marked G4 and post-master samples reached a peak of
  0.0376537. No horizontal page overflow was observed.
- During playback, editing showed `Queued · waiting to send`, then
  `Accepted · score still updating`. Closing Controls, replacing the source,
  and reopening restored the score-wide pending notice. It disappeared after
  material settlement while playback continued.
- Reload recovered `bpm(96); note("D4 F4 A4 C5").slow(8).gain(.2)` in Ready state.
  The final smoke browser reported no runtime errors.

Integration caught missing playback-status/highlight hooks, incomplete nested
range handling, and loss of pending feedback for edits made with controls hidden.
Those paths were repaired and exercised in the browser. The audio engine,
notation compiler, and onset transport were not changed. These checks do not
establish subjective listening quality, physical-device usability, novice-user
comprehension, or award qualification.

Final verification: production TypeScript/Vite build passed; the complete
browser suite passed **145/145**, with virtual audio, one worker, no retries,
and a 60-second per-test deadline. The touch regression now waits for and captures
a nonempty bounding box in one check, rather than reading geometry separately
after a visibility assertion and widget redraw. Five Markdown files passed code-fence
and local-link validation (**62 links**). The mechanical UI detector reported
no findings on the changed surfaces. The existing large-bundle advisory remains.

## Chord editing — 2026-10-05

Chord phrases now offer source-linked Root and Type controls beside their
numbered chord steps. Selecting any constituent pitch selects its written
chord. The controls replace only that atom's core; weights, repeated groups,
octave suffixes, surrounding formatting, and the shared Undo history survive.
Choosing a root or type can also fill a selected rest, seeded from a neighboring
chord or C. Group and partial source selections do not expose chord controls.
Tone names come from the production compiler. Individual-tone manipulation,
inversions, and slash-bass editing are not offered.

### Observed browser evidence

- Screens: [desktop harmony editing](musical-workspace/chord-editing-desktop.webp),
  [weighted rest entry on mobile](musical-workspace/chord-rest-entry-mobile-dark.webp),
  [suspended chord playback on mobile](musical-workspace/chord-suspended-playing-mobile.webp).
- Desktop Root/Type edits changed `Am` to `Bbmaj7`, displaying
  `Bb4 · D5 · F5 · A5` and selecting MIDI pitches `[70, 74, 77, 81]`.
  Undo/Redo retained the second chord as the next edit target.
- Main playback of the edited `Fmaj7` produced a post-master peak of
  **0.102317** and onset pitches `[65, 69, 72, 76]`. Changing its type during
  playback to minor seventh subsequently produced `[65, 68, 72, 75]`.
- At 390 px with native touch emulation, selecting a weighted rest and changing
  Root/Type yielded `chord("C Dm7@2 G7")`, preserving `.slow(2).gain(.2)`.
  Its onset pitches were `[62, 65, 69, 72]`, with a **0.094042** peak.
- ArrowDown in the focused root selector changed `Am` to `A#m`; Ctrl+Z restored
  `Am`. An invalid `Ffoo` draft hid chord controls and left the previous accepted
  score playing. Undo restored the valid score.
- After synchronized JS and WebAssembly builds, `Dbsus4` played pitches
  `[61, 66, 68]` with a **0.114487** peak. Reload restored the edited progression
  in Ready state. The browser reported no runtime errors or horizontal page
  overflow in these scenarios. Help exposed the new chord instructions and limits.

### Grammar and integration checks

The existing chord parser consumed the `s` in a suspended quality as an
additional accidental, rejecting `Dbsus4` and `C#sus4`. It now checks for a
quality after each of at most two same-direction accidentals. The second grammar
change permits a single leading zero on an octave suffix: `C07` means a major
triad rooted at C7, while `C7` retains its dominant-seventh meaning. This lets a
quality edit preserve register without inventing independent voicing state.

Both new MoonBit regression cases failed before the parser change. Afterwards,
`NEW_MOON_MOD=0 moon check`, the complete `moon test` suite (**1,299/1,299**),
`moon info`, and `moon fmt` passed. Generated pattern-interface inspection
showed the existing weighted-pattern/origin additions, with no new chord exports.
A throwaway compiler check exercised all **340** offered root/type combinations
and matched their pitches against transposed natural-root chords.

An early browser run exposed mismatched artifacts: the updated JS authoring
parser accepted suspended chords but the old WebAssembly parser rejected their
source map. Rebuilding `browser --target wasm-gc --release`, running
`playwright-sync-wasm.sh`, and rebuilding the Web app resolved that mismatch.
The audio render path and onset protocol were not changed. These checks establish
rendered signals and emulated-browser behavior, not subjective listening quality
or physical-device usability.

Final verification: the synchronized WebAssembly and TypeScript/Vite builds
passed, followed by **151/151 browser tests**, with virtual audio, one worker,
no retries, and a 60-second per-test deadline. The touch chord regression now
plays `Dbsus4`, covering both authoring and worklet parsers before testing saved
reload. The existing drawing regression also captures nonzero note geometry
atomically before its pointer gesture, without weakening its source/audio checks.
Six Markdown files passed code-fence and local-link validation (**70 links**,
including directory targets). The mechanical UI detector reported no findings
on the chord controls and Help surfaces. The existing large-bundle advisory remains.

## Direct chord choices — 2026-10-05

The chord widget now leads with source-step selection and harmonic choices,
followed by the pitch grid. Its selected chord name and compiler-derived tones
sit together. Six common types show their target chord symbols directly rather
than requiring a menu interaction for every change. The complete native selector
remains under All chord types. Selected aliases match their canonical button
without being rewritten on activation; rests have no falsely selected type.
The code remains the only editable score and Play remains the only transport.

- [Desktop chord palette](musical-workspace/chord-palette-desktop.webp)
- [Mobile dark chord palette](musical-workspace/chord-palette-mobile-dark.webp)

Browser verification exercised Root changes, direct choices, a five-tone
`Dbmaj9` through the disclosed selector, and keyboard Undo back to `Dbm7`.
At 390 px, native touch entered `Cmaj7` into `~@2` without losing its weight;
all six choices measured **108 × 58 px**. Main playback produced onset pitches
`[60, 64, 67, 71]` and a post-master peak of **0.106435**. Saved reload restored
the exact edited score in Ready state. The updated Help was reachable.
The 768 px and 390 px checks found no horizontal page overflow; the smoke tab
reported no runtime errors. Desktop light and mobile dark layouts were inspected.

`npm run build` and the complete browser suite passed (**151/151**, virtual audio,
one worker, no retries). After the final typography, spacing, and Help changes,
the production build and all six chord regressions passed again. Existing
regressions now exercise direct choices, touch entry, keyboard activation,
alias preservation, shared history, and the complete selector's projection limit.
The mechanical UI detector reported no findings. No MoonBit or audio-engine
implementation changed in this refinement; the existing bundle-size warning remains.

## Contextual chord editing — 2026-10-05

The six-choice bank above was not established as easier to use. It repeated the
selected harmony across too many surfaces and pushed the diagram down on mobile.
This revision removes that bank and the separate selected-chord heading.
The source progression leads, with Root/Type, tone names, and Rest directly below
it. The selected step keeps an outline; actual-onset playback fills the sounding
step independently. This feedback remains visible with the tone diagram closed.

View chord tones now opens an optional inspection diagram. Its hint and pointer
cursor distinguish whole-chord selection from individual-tone dragging, which
is still unavailable. The disclosure stays open across source edits during the
session. Structure and Timing do not require opening the diagram.

- [Compact desktop editor](musical-workspace/chord-context-desktop.webp)
- [Compact mobile editor](musical-workspace/chord-context-mobile.png)
- [Mobile dark playback](musical-workspace/chord-context-playing-mobile-dark.png)
- [Optional tone inspection](musical-workspace/chord-context-tone-inspection.webp)

Browser observations:

- Root/Type changed `Am` to `Dbsus4`; closed-diagram playback highlighted its
  source step and produced a post-master peak of **0.120623**.
- Native-touch Rest cleared a chord; choosing Minor 7 filled that rest with
  `Cm7`. Playback highlighted the filled step in the dark mobile surface.
- Keyboard Undo from the type selector restored `Dbsus4` without losing selector
  focus. Redo and a subsequent root edit produced `Fm7`.
- Code entry of `Gmaj9` refreshed the controls and displayed
  `G4 · B4 · D5 · F#5 · A5`. Replacing it with invalid `Foo` hid chord controls
  while accepted playback continued; Undo restored the valid source.
- Opening the diagram and selecting an F tone selected the whole F chord without
  changing source. Editing with the diagram open retained its open state.
- Saved reload restored the edited source in Ready state. Updated chord Help was
  reachable. The smoke tab reported no runtime errors.
- At **390 × 844**, Root/Type and Rest aligned on one row, with the progression,
  tone names, and all three disclosures visible. The example's collapsed widget
  measured **303 px** tall. Desktop light and mobile dark surfaces were inspected;
  **390 px** and **768 px** checks found no horizontal page overflow.

Verification: production TypeScript/Vite build and **151/151 browser tests**
passed with virtual audio, one worker, no retries, and a 60-second per-test
deadline. Chord regressions cover alias preservation, weighted/repeated source,
the projection limit, shared history, closed-diagram onset feedback, disclosure
persistence during editing, and saved reload. The mechanical UI detector reported
no findings. No MoonBit or audio-engine implementation changed; the existing
large-bundle advisory remains.

This establishes working interactions, not beginner comprehension. Major/minor
and extended-chord terminology still requires musical understanding; replacing
the bank with a compact selector does not remove that learning requirement.
No first-time-user study or subjective listening evaluation was performed.

## Direct chord-tone editing — 2026-10-06

The selected chord now opens editable tone rows rather than leading with
Root/Type fields. Drag one tone vertically, drag Move chord to transpose the
whole voicing, tap an empty row to add a tone, or remove the selected tone.
Lower/Raise and Add tone also support keyboard-only editing. Name-based choices
remain behind Choose by chord name; the older whole-progression diagram remains
an optional inspection surface.

The code is still the score. Exact supported voicings use chord names; arbitrary
combinations and inversions use ascending explicit MIDI sets such as
`chord("{60,63,68}")`. The compiler treats each set as one authored atom whose
voices share its source origin. Weights, linked repeats, groups, outer effects,
and the main transport are retained. Duplicate or out-of-range tones are rejected
rather than merged. Removing the last tone writes a rest.

Observed in headless Chromium:

- Dragging E4 down one semitone left the source unchanged during the preview and
  changed `C` to `Cm` on release. Raising G4 then wrote `{60,63,68}` exactly.
- Native CDP touch gestures at **390 × 844** produced the same custom voicing
  while retaining `@2`, the following F chord, and `.gain(.2)`.
- Real browser audio produced a waveform peak of approximately **0.065** and
  actual onset pitches **60, 63, 68**. Saved reload restored the exact source,
  matching tone rows, and Ready state.
- Keyboard whole-chord transposition produced `{61,64,69}`; Ctrl+Z restored
  `{60,63,68}` through shared history.
- Invalid `{60,60}` hid the chord controls and reported an error while accepted
  playback continued. Undo restored the valid draft.
- An extreme `{0,127}` voicing scrolled through its pitch-name gutter by native
  touch without modifying source. Horizontal page overflow was absent at
  **390 px** and **768 px**. Desktop light and mobile dark surfaces were inspected.
- Updated chord Help was reachable; the smoke tab reported no runtime errors.

Integration caught an omitted document-parser path in the first explicit-atom
implementation. The shared chord-token reader now covers ordinary compilation,
query-work assessment, and source-origin document lowering. A touch smoke also
caught SVG child `touch-action` failing to prevent browser scroll cancellation:
the SVG now owns drag handling and a separate HTML gutter preserves native
vertical scrolling. Inherited icon strokes on pitch labels were removed.

Evidence: [desktop](musical-workspace/chord-direct-tones-desktop.webp),
[mobile](musical-workspace/chord-direct-tones-mobile.webp), and
[mobile dark](musical-workspace/chord-direct-tones-dark.webp).

`moon check`, all **1,305 MoonBit tests**, `moon info`, `moon fmt`, and the
browser WebAssembly build passed. No DSP render path or audio-thread buffer
implementation changed. These checks establish working direct manipulation and
rendered audio signals, not subjective listening quality, physical-device
usability, or first-time-user comprehension.

Final verification: the production TypeScript/Vite build and **165/165 browser
tests** passed with virtual audio, one worker, no retries, and a 60-second
per-test deadline. Regression coverage includes exact named/custom spelling,
gesture cancellation, one-step history, linked source timing, keyboard rest
entry, MIDI boundaries, native touch, actual onset feedback, and saved reload.
Six Markdown files passed fence and local-link validation (**79 links**); the
mechanical UI detector reported no findings. The existing bundle-size advisory
remains. No beginner-comprehension or award-quality claim follows from these
results.
