# 2026-10-02 — Musical workspace direction and evidence

Independent worktree `.worktrees/musical-workspace`, branch `feat/musical-workspace`. Goal: a text-first, approachable, programmable music-making surface in the browser, informed by Daniel Jackson's *Essence of Software* concepts and musical experiences recognized by several award organizations.

## Goal and decisions

- **Text editing primary, GUI supplementary.** CodeMirror holds the draft; pads change that same text. Transport reports the engine's accepted and sounding state, which may differ from an unfinished draft.
- **Sound before syntax.** A ready-to-play starter pattern and a visible Play control let a visitor hear music before writing code.
- **One score, two entry points.** GUI edits and code edits go through the same CodeMirror transactions and share one undo history.
- **Explanations off the working surface.** Tutorials, syntax reference, example listening notes, and capability limits live in the Help drawer; the working surface carries layout, controls, and state feedback.
- **Own-world notation.** Direction seed `c93d7327`, grounded direction 3. No supplied or approved external visual comp; source-derived notation is the material, not a physical imitation.
- **No award self-certification.** The direction aspires to the craft of the cited examples; it does not claim to have won or been judged by any of them.
- **Direction checkpoint confirmed.** After receiving the working preview and verification record, the user chose to retain the current cursor-linked supplementary GUI rather than an explicit-open-only workflow. This confirms that interaction direction, not novice usability or award readiness.

## Primary-source research

The citations below are the first-party records inspected. The applied lessons are design deductions, not evidence that this workspace has achieved the cited products' quality.

### Essence of Software — Daniel Jackson

Jackson's [criteria](https://essenceofsoftware.com/tutorials/concept-basics/criteria/), [purpose](https://essenceofsoftware.com/tutorials/concept-basics/purpose/), [operational principle](https://essenceofsoftware.com/tutorials/concept-basics/principle/), [state](https://essenceofsoftware.com/tutorials/concept-basics/state/), and [synchronization](https://essenceofsoftware.com/tutorials/concept-basics/sync/) tutorials distinguish a user's concept from a widget or implementation class.

| Concept | Purpose and operational principle | Remembered state |
|---|---|---|
| Score | Express musical intent. Editing text or a supported pad changes the same draft. | Plain MiniLive text |
| Playback | Hear accepted music. Play resumes it; Restart starts the current valid score from the beginning. Invalid edits leave accepted playback intact. | Transport position, accepted score, pending and sounding material |
| History | Try changes without losing the previous score. Undo reverses text, pad, starter, restoration, and import edits. | CodeMirror transaction history |
| Score file | Carry music between sessions or tools. Download serializes the draft; Open inserts decoded text as an undoable edit. | Plain-text file, separate from local autosave |

Synchronization connects these purposes without merging their state: an edit changes the draft, compilation submits a version, and a runtime receipt updates acceptance. A source-derived pad is not a second score; an accepted edit is not necessarily audible before the next material boundary. These are workspace design decisions, not claims made by Jackson.

### Awwwards — Super Looper, Site of the Day, 15 Sep 2014

- **Official record:** [awwwards.com/sites/super-looper](https://www.awwwards.com/sites/super-looper).
- **Status as listed:** Site of the Day, 15 Sep 2014. Awwwards score 8.05/10 with a separate usability component; that is a rating, not usability evidence.
- **Launch URL** (`superlooper.universlabs.co.uk`) did not respond to the research tool; observations are limited to the official entry description.
- **Lesson:** let a novice capture a sound in a visible part, hear it immediately, and build by layering.

### The Webby Awards — Weezer's Human Record Player, People's Voice Winner, 2023, Music category

- **Official record:** [Webby Music gallery](https://winners.webbyawards.com/winners/websites-and-mobile-sites/general-desktop-mobile-sites/music?years=3); [live experience](https://humanrecordplayer.com/).
- **Status as listed:** People's Voice Winner, 2023, Music. Do not infer a Webby jury winner from People's Voice.
- **Lesson:** a single, legible instruction and a familiar physical action can replace musical terminology for the first interaction.

### FWA — Stanley the Interactive Player Piano, FWA of the Day, 9 Sep 2012

- **Official record:** [thefwa.com/cases/stanley-the-interactive-player-piano](https://thefwa.com/cases/stanley-the-interactive-player-piano).
- **Status as listed:** FWA of the Day, dated 9 Sep 2012 in the FWA daily case search record.
- **Lesson:** make user input consequential to a real instrument; present-day availability of the original experience is unverified.

### FWA — Tonecraft (Google Experiments)

- **Official record:** [thefwa.com/cases/tonecraft](https://thefwa.com/cases/tonecraft); [Google Experiments archive](https://experiments.withgoogle.com/tonecraft) (Aug 2011); [Dinahmoe's current Tonecraft page](https://dinahmoelabs.com/tonecraft).
- **Status as listed:** FWA case; listed as an FWA of the Day entry, but the specific FWA award date was not visible in the accessible first-party rendering. Google's 2011 date is the original experiment listing, not proof of the FWA award year.
- **Lesson:** explicit spatial mapping of pitch / time / instrument / layer is unusually teachable; musical dimensions can become a manipulable landscape alongside text.

### UX Design Awards — Opus Studio: Accessible music-making for children, Autumn 2026 winners archive, New Talent

- **Official record:** [ux-design-awards.com/winners/2026-2-opus-studio-accessible-music-making-for-children](https://ux-design-awards.com/winners/2026-2-opus-studio-accessible-music-making-for-children); [designer's project page](https://www.markvedberg.com).
- **Status as listed:** winners archive, Autumn 2026, category New Talent. The visible entry does not state a more specific prize tier; treat as a winners-archive New Talent entry, not Gold or Best of the Year.
- **Lesson:** open-ended rules that guide creativity without limiting it; progression that grows with the player; low-tech physical controls and collaborative play.

## Comparative takeaways applied

1. Let people make sound before they learn code.
2. Use visible musical metaphors, but keep them semantically honest: pads edit source steps, not a transformed playback timeline.
3. Keep the complete language available while exposing a small set of direct manipulations at the cursor.
4. Support click, tap, keyboard, focus visibility, screen-reader labels, reduced motion, non-color cues, and a visible Pause control.
5. Clear primary surface and direct action; motion explains state transitions, not decorative.

## Verified browser scenarios

Observed in headless Chromium at `http://localhost:5194`, not on physical devices and not with novice users or screen readers.

- Fresh **Play** starts an `AudioContext`; temporary `AudioNode` analyser reports peak 0.78194, RMS 0.160866, samplePosition 38912.
- Changing the GUI pitch from C4 to G4 updates the source and produces a measured waveform frequency of 391.9367 Hz.
- Typing A4 updates the source, GUI, and measured waveform to 439.9185 Hz; a D4 check measures 293.6528 Hz.
- An invalid edit while playing retains the playing state and produces a position 5 diagnostic; the accepted score is unchanged.
- **Restore accepted score** replaces the source via a regular undoable CodeMirror transaction.
- **Undo** restores an invalid draft without interrupting audio.
- GUI rest toggle updates the source, pad `aria-pressed`, and retains native control focus.
- Keyboard **Undo** works.
- Local draft reload is exact.
- Real file chooser imports a 65-byte UTF-8 Japanese-comment score and reloads it exactly.
- Chromium downloads the imported score as 65 bytes; `cmp` confirms byte-for-byte equality with the original file.
- Mobile Help opens as a native modal with focus on Close help. Reverse Tab remains in the dialog; Escape closes it and restores Show help. Choosing Offbeat closes Help, focuses the editor, and changes the score to BPM 112. Resizing an open Help to desktop releases the editor while retaining the sidebar.

Frequency measurements come from an analyser attached to actual audio output, not from calculating the expected pitch. They are not subjective audio-quality evidence.

## Production captures

The built bundle was served with Vite Preview on port 5196 for a separate smoke run. Fresh Play reached `Playing`, an accepted draft, and sample position 10112; Pause worked. Both self-hosted font families loaded, and the browser reported no page errors.

- [Desktop, 1440 px viewport](musical-workspace/desktop.webp)
- [Dark mode with reduced motion](musical-workspace/dark.webp)
- [Mobile, 390 px viewport](musical-workspace/mobile.webp)
- [Mobile Help](musical-workspace/help.webp)

## Evidence and limits

- **Build.** `npm run build` passed, including TypeScript checking and asset synchronization. Vite still reports its >500 kB chunk advisory: the main bundle is 700.59 kB minified, 207.85 kB gzip. This record makes no cold-load performance claim.
- **Tests.** `MOONDSP_VIRTUAL_AUDIO=1 MOONDSP_LIVE_PLAYWRIGHT_PORT=5195 npm test -- --retries=0`: **66 passed**, no retries, in 2.5 minutes. This includes existing playback/protocol/lifecycle coverage plus multiline pad edits and undo, unsupported notation preservation, responsive Help focus, exact UTF-8 import/export, empty-draft persistence, import-versus-typing races, and storage-denied export.
- **Typing regression caught during refinement.** Adding method-name highlight spans caused native caret drift while error decorations changed. Input tracing observed `.lp` turn into `.lfp`. The final theme retains the established default token coverage and changes its palette instead; fast live typing of `.lpf(` now produces `.lpf()`, and the existing invalid-draft/knob/recovery regression passes without weakening its source assertion.
- **Independent visual review.** Initial disposition: `fix`, for mobile Help focus leaking into the covered editor. After the native-dialog correction and browser verification, the verdict was `ship`, with no remaining material findings. This means the reviewed direction is ready for a user checkpoint, not that award quality or beginner usability has been established.
- **MoonBit runtime.** No MoonBit runtime code changed in this workspace. Browser `wasm-gc` built and synced successfully for the browser probe.
- **Static boundary review.** An independent reviewer found no high-confidence defect in pattern ranges, history, import races, persistence, or retained playback. This is not runtime proof.
- **Design detector.** One run reported an advisory about 12 em-dashes in inherited Help examples, with no mechanical failures. Examples were retained rather than rewritten to improve a detector score.
- **Not studied.** No first-time user study, no screen-reader session, no human audio perception study, no physical-device testing.
- **Not awarded.** No submission, jury, or rating has been sought or obtained from Awwwards, the Webby Awards, FWA, or the UX Design Awards for this workspace.

## Compact-control refinement

Following the direction checkpoint, the user requested smaller controls matching the editor text and removal of labels such as Melody and 8 steps. The control panel is now a wrapping row of numbered on/off buttons and source-token selectors. Voice names remain in accessible labels, not visible headings. The card background, duplicate sound labels, and count caption were removed.

The real browser measured the default eight-step row at 36 px high on desktop (15 px code and selector text) and about 59 px high across two rows at a 390 px viewport (13 px code and selector text). Neither viewport had page-level horizontal overflow. Pitch selection changed C4 to G4 in the source and retained selector focus; keyboard Undo restored C4. Step toggling and toolbar Undo worked, playback reached Playing, and no page errors were reported. The production build passed; its existing large-chunk advisory remains.

These development-server captures supersede the control geometry in the earlier production screenshots:

- [Compact desktop controls](musical-workspace/compact-desktop.webp)
- [Compact mobile controls](musical-workspace/compact-mobile.webp)
- [Compact note controls in dark mode](musical-workspace/compact-dark.webp)

The existing `tests/workspace.spec.ts` suite passed all five tests with retries disabled. The first invocation exceeded its 120-second command deadline during startup; a diagnostic invocation showed a loopback availability probe timing out before the preview server started, then completed the tests successfully. The final build, including the revised Help wording, passed.

## Code–GUI keyboard round-trip repair

Browser investigation found two failures: ArrowDown in a pitch selector moved the
editor selection instead of changing the pitch, and Escape after a GUI edit could
leave focus in the selector. Both new round-trip regressions failed against the
pre-fix production build.

The pattern widget had explicitly passed keydown events to CodeMirror. Its editor
keymap could handle them before the custom focus/history handler. The widget now
uses CodeMirror's default event isolation, with local handling for explicitly
shared commands and Escape, following the existing inline-knob pattern. Playback
bindings explicitly include the pattern-control scope so isolation does not
remove Play/Pause/Restart shortcuts. This changes no pitch vocabulary, rest-toggle
semantics, audio engine, or visual layout.

Observed verification:

- Native ArrowDown changed `C4` to `C#4` while retaining a selection on a later
  `E4`; its source offsets mapped across the added character. Undo/Redo retained
  that selection. Escape restored both editor focus and the browser's text
  selection; typing `F4` replaced only `E4`.
- Directly choosing `F#4` for the second note while `C4` was selected no longer
  prevented focus return or inserted subsequent typing outside the quoted pattern.
- Space activated a numbered step without inserting source text. Undo restored
  the note. Tab/Shift+Tab moved between the native controls rather than changing
  the source selection.
- The final production bundle, served separately on port 5202, retained Play/Pause
  from a focused pitch selector and Restart from a focused numbered button.
  A real native dropdown click, arrow choice, Enter, and Escape also returned to
  the editor without changing unrelated text.
- At a 390 px viewport, changing the first pitch preserved selection of the eighth
  pitch `C5`; Escape followed by typing `D5` replaced that eighth pitch. Desktop
  verification used a 1440 px viewport. No browser page errors were observed.
- During the repaired-widget development-server smoke, an analyser on the real
  output measured FFT peaks of 263.67 Hz (`C4`), 275.39 Hz after the GUI ArrowDown
  edit (`C#4`), and 392.58 Hz after returning to code and typing `G4`. These are
  8192-point FFT bins at 48 kHz, not exact-frequency or subjective listening claims.

The regression suite covers keyboard pitch choice, mapped source selection,
focus return, shared history, native step activation, and transport shortcuts.
One initial test invocation spelled the shifted redo key with lowercase `z`,
which generates a different synthetic key event; it was corrected to
`Control+Shift+Z`, matching existing keyboard tests and the real shifted key.
Native-browser smoke also exercised Ctrl+Y and Ctrl+Shift+Z redo.

Final verification: `npm run build` passed TypeScript checking and the production
build; the existing Vite >500 kB chunk advisory remains.
`MOONDSP_VIRTUAL_AUDIO=1 MOONDSP_LIVE_PLAYWRIGHT_PORT=5201 npm test -- --retries=0`
passed **all 69 tests**, including the three new regressions, with no retries.

These checks establish the tested keyboard behavior, not novice comprehension,
physical touchscreen operation, or screen-reader compatibility. The full
interaction remains subject to the user-study limits above.

## Change, listen, and undo

The next pass replaces the ambiguous numbered on/off buttons with numbered play
buttons. They audition without editing. Menus still write source tokens, with an
explicit Rest choice. The selected source step has adjacent Lower, Higher, Listen,
Undo, and Redo actions. Pitch changes are semitone-based; Shift changes an octave.
An editor cursor move identifies the step these actions will change. No piano
keyboard or second sequencer document was introduced.

Control changes and history commands inside the controls automatically audition
while the main score is stopped or paused. While it is playing, normal source
updates retain the existing musical-entry timing; explicit Listen provides a
separate preview. Undo is the editor history, not an independent note cache:
replacing `D5` with `~` and undoing restores `D5`, not a default `C4`.

Audition reuses `Player`, `AudioEngine`, and `PlaybackInput.text` in a separate
scheduler session. It does not synthesize a substitute tone, mutate the main
Draft, or submit preview text to the main Player. Existing Player cancellation,
retirement, and receipt validation are reused rather than implementing another
audio protocol. The preview ends about 700 ms after acceptance and suspends its
owned context; newer requests supersede older ones. Source/target changes,
Escape, hiding controls, transport actions, and page hiding cancel preview.
Status has reserved line height so normal preview feedback does not shift
subsequent code lines.

### Observed evidence

- Final production build served on port 5205; desktop 1440×1000 and narrow
  390×844 Chromium viewports exercised. The narrow document's scroll width was
  380 px, with no horizontal overflow. Happy-path browser probes recorded no
  page errors.
- Fresh starter: pressing the first numbered drum button produced real output
  while main transport remained Ready and source remained unchanged.
- An analyser connected to the actual preview output measured FFT peaks of
  **263.78 Hz → 274.55 Hz → 263.78 Hz** for `C4 → C#4 → Undo`.
  These are 8192-point FFT bins at the native 44.1 kHz context rate, not exact
  pitch or subjective listening measurements. The managed browser's inherited
  `AudioContext.sampleRate` getter reported 48 kHz despite the native
  `BaseAudioContext` getter reporting 44.1 kHz; initial frequency calculations
  using the inherited value were discarded.
- A paused main score stayed at **0.18666666666666668 cycles** throughout a
  separate preview. At completion the preview context was suspended; the main
  context and paused transport remained independently owned.
- A binding containing `note("C4 E4 G4").gain(0.15).lpf(1200)` previewed its
  selected `G4` at a 392.98 Hz FFT peak without replacing the binding or source.
- Narrow-screen editing retained an eighth-note `C5` selection while changing
  the first pitch; Escape and typing replaced only that selected note with `D5`.
  In the production build, `D5 → Rest → Undo` restored the exact source and
  produced a 586.78 Hz preview peak.
- Blocking the preview WASM fetch displayed an explicit preview error without
  altering source or starting the score. Retrying after removing the block
  produced a real C4 output peak while main transport remained Ready.
- `npm run build` passed TypeScript and production compilation. The existing
  >500 kB Vite chunk advisory remains (707.64 kB minified JS).
  `MOONDSP_VIRTUAL_AUDIO=1 MOONDSP_LIVE_PLAYWRIGHT_PORT=5204 npm test -- --retries=0`
  passed **83 tests**, no retries. An earlier run passed 82 and failed a test's
  incidental exact close-call count; the obsolete count assertion was removed,
  retaining checks that only the latest source plays and obsolete requests never
  report playing. The late-open closure and auto-stop regressions remain.
- A final CSS-only correction aligned feedback line-height with its reserved
  height. After rebuilding, the following source line stayed at **315.359375 px**
  before, during, and after preview. The final production browser pass also
  confirmed the dark color scheme, narrow-screen Rest/Undo, and no page errors.
  The 83-test run preceded this last line-height-only correction.

### Limits

Preview constructs one source-step phrase with the selected chain's direct
modifiers and original declarations. It excludes other performers and modifiers
on enclosing groups or later references; its duration is not the original step's
duration. Full-score Play is necessary to judge that musical context and long
effect tails. The controls still support simple source sequences, not arbitrary
mini notation or a full piano roll. GUI action labels and Help were updated, but
no novice-user, physical-touchscreen, or screen-reader study was conducted.

## Direct pitch and drum choices — 2026-10-03

This supersedes the menu-based editing described in earlier iterations above.
Numbered steps now include the note or drum name. Selecting a step auditions it;
one compact keyboard below the phrase exposes pitch relationships spatially,
instead of requiring a search through a dropdown. Drum phrases use named sound
buttons rather than an unrelated pitched keyboard.

Octave −/+ browses without changing source. A key press commits the chosen pitch;
the existing parser and transposition helper preserve numeric and flat spelling.
Rest, Listen, Undo, and Redo sit together below the keys. Roving keyboard focus
keeps each group to one Tab stop; Left/Right changes focus without editing,
Space/Enter activates, and Escape retains the code-selection round trip.

Production Chromium observations:

- C4 → C#4 → Undo yielded FFT peaks of **263.78 → 274.55 → 263.78 Hz**.
  Browsing an octave left source unchanged; choosing G5 and Rest/Undo yielded
  **785.96 Hz** before and after restoration.
- At 390 px, eighth-step D5 → Rest → Undo restored the exact score and a
  **586.78 Hz** peak. The keyboard was 299 px wide, with 30.73 px accidental
  keys and no page overflow in the inspected layout. The first layout split
  Redo onto its own row; the final layout groups all four edit/history actions.
- Eb4 → Ab4 retained flat spelling and produced a **414.51 Hz** peak.
  MIDI `60` → D4 remained numeric `62`; keys above G9 were disabled, and the
  lowest octave disabled further downward browsing.
- Selecting Clap wrote `cp`; an output analyser measured a transient peak of
  **0.01835** (−34.73 dBFS). A 250 ms delayed FFT missed this short transient,
  so the successful measurement captured the waveform throughout preview.
- Main transport stayed Ready at cycle 0 throughout these isolated previews.
  Light/mobile and dark/desktop surfaces were inspected; no page errors were
  reported. Audio measurements use the native 44.1 kHz rate and are FFT-bin
  estimates, not subjective listening or usability evidence.
- A mixed keyboard/pointer check found that re-clicking the current pitch left
  Tab on another key, and a focused natural key covered part of an accidental's
  hit area. Focus now owns the group's Tab stop without requiring a source edit;
  focus outlines no longer raise natural keys above accidentals. The same browser
  scenario then tabbed directly to Rest and clicked the formerly covered C#4
  area, producing the expected code and a **274.55 Hz** peak. A regression covers
  both operations. Forced-colors emulation confirmed a 2 px selected-key border.

`npm run build` passed; the existing Vite >500 kB chunk advisory remains.
After the layout and focus fixes,
`MOONDSP_VIRTUAL_AUDIO=1 MOONDSP_LIVE_PLAYWRIGHT_PORT=5208 npm test -- --retries=0`
passed **all 84 tests**, including the new pointer/keyboard regression, with no
retries. No engine/render-path changes were made. Physical-device, novice-user,
and screen-reader studies remain unperformed; a keyboard is not claimed to be
universally optimal.

## Score-wide history placement — 2026-10-03

User feedback identified the wrong scope implied by Undo/Redo beside a selected
note. Those duplicate buttons were removed; history controls now appear only
in the score toolbar. Keyboard shortcuts still address the same history from
the editor or sound controls. No note-local history was added.

This supersedes the inline history placement in the preceding iteration.
Rest and Listen remain below the keyboard because they target the selected step.
Toolbar Undo/Redo retains its existing behavior: restore source and return to
the code, without automatically auditioning a potentially unrelated step.
Listen explicitly auditions the restored source.

Production browser checks traversed edits across two distinct notes:
`C#4 F4 G4` → Undo → `C#4 E4 G4` → Undo → `C4 E4 G4` → Redo →
`C#4 E4 G4`. Explicit Listen then produced a 274.55 Hz peak. Desktop and 390 px
layouts showed one toolbar pair and no inline history buttons; mobile Rest/Undo
restored the exact source without moving the Ready transport from cycle 0.
A stale Rest announcement exposed by toolbar restoration was also cleared on
source/target changes. No page errors or horizontal overflow were observed.

Final verification: `npm run build` passed. The affected workspace suite,
`MOONDSP_VIRTUAL_AUDIO=1 MOONDSP_LIVE_PLAYWRIGHT_PORT=5210 npm test -- tests/workspace.spec.ts --retries=0`,
passed **12 tests** with no retries, including shared history, source-selection
return, Rest restoration, and explicit listening after toolbar Undo. The final
mobile browser pass confirmed that restored notes and changing the selected step
clear the obsolete Rest feedback.

## Sound and silence as peer choices — 2026-10-03

Removed the separate Listen button and its action row. Numbered steps already
select and audition without editing; a second action obscured that purpose.
Rest now belongs to the pitch keyboard or the drum choices, writes `~`, and
stops the preview. It participates in the same arrow/Home/End navigation,
roving Tab stop, and pressed-state feedback as the sounds. Undo/Redo remain
score-wide toolbar actions.

The drum choices use a three-column grid: on a narrow display, Rest no longer
wraps alone beneath the sounds and resembles a separate action. The pitch
keyboard reserves enough width for the Rest label. A 320 px check also exposed
masthead overflow; file actions now move below transport at widths up to 360 px.

Observed browser evidence:

- Numbered C4 audition produced an FFT peak near **263.78 Hz**. Rest wrote `~`,
  reported idle, and the preview audio context stopped running. Choosing C#4
  produced **274.55 Hz**; toolbar Undo restored Rest, then the original C4.
- Drum keyboard navigation traversed Kick → Rest → Snare and changed the source.
  Rest shares the second grid row with Open hat and Clap.
- At 390 px, D5 → Rest → toolbar Undo → numbered step restored D5 and produced
  **586.78 Hz**. The main transport remained Ready at cycle 0.
- Final production checks at 320 and 390 px showed no horizontal page overflow.
  The Rest label fit, Tab left the choice group, dark desktop controls rendered,
  and restored C4 still produced **263.78 Hz**. No page errors were recorded.

`MOONDSP_VIRTUAL_AUDIO=1 MOONDSP_LIVE_PLAYWRIGHT_PORT=5211 npm test -- --retries=0`
passed **all 85 tests**, including the new pitch/drum Rest navigation and shared
history regression. The final layout and accessibility-description refinements
followed that run; `npm run build` and the production browser checks above passed
after those refinements. The existing Vite >500 kB chunk advisory remains.
Audio peaks are analyser measurements, not subjective listening evidence.
Novice-user, physical-touchscreen, and screen-reader studies remain unperformed.

## Files

- Design record: [`../../DESIGN.md`](../../DESIGN.md).
- Product context: [`../../PRODUCT.md`](../../PRODUCT.md).
- Implementation: `web/live/index.html`, `web/live/src/workspace.css`, `web/live/src/main.ts`, `web/live/src/pattern-controls.ts`, `web/live/src/pattern-audition.ts`, `web/live/src/audition.ts`, `web/live/src/score-session.ts`.
