# DESIGN.md — moondsp musical workspace

A text-first music editor in the browser. The source document is the editable score; pads operate on that text, while the transport reports what the audio engine is actually playing.

## Form

Graphic score workshop, grounded direction 3, seed `c93d7327`. No external reference image or approved visual comp; the direction is an own-world notation sheet, not a physical imitation.

## What is primary

- **Text editing is the musical source of truth.** CodeMirror holds the draft. Text, GUI controls, starters, and file imports change that document through transactions. The engine separately retains the last accepted score and sounding material.
- **Hierarchy over decoration.** A full-height text score dominates the viewport. Transport is persistent in the masthead. A selection-scoped pattern ribbon appears only under the focused phrase. Help is on demand.
- **No alternative GUI truth.** There is no separate sequencer state, project file, or hidden model that can disagree with the source. What you see in the pads is what the source says at your cursor.

## Typography

- **Body:** Manrope (regular 400, bold 700), self-hosted from `/fonts/` under the SIL Open Font License.
- **Code and notation:** JetBrains Mono (regular 400), self-hosted under the SIL Open Font License.
- **Scale:** body 14 px / 1.55 on desktop; score content 15 px / 1.95 (16 px at ≥1600 px, 14 px at ≤1100 px, 13 px at ≤760 px). Brand 25 px, score title 16 px, transport status 12 px, footer 10 px.
- **Measurements:** tabular numerals in transport; letter-spacing -0.035 em on the brand; -0.02 em on headings.

## Color

Light and dark palettes are defined as CSS custom properties in [`web/live/src/workspace.css`](web/live/src/workspace.css).

- **Light:** ink `#252c3c` on paper `#fbfcfe` over a `#eef1f5` ground; accent indigo `#3e50a8`.
- **Dark:** ink `#e1e6ef` on `#202733` over `#171d27`; accent `#a6b5f5`.
- **Part colors:** clay drum `#995337` (dark `#ecb09a`), blue note `#425eb0` (dark `#b0c1f7`). Pattern ribbons also carry text labels. Syntax colors identify language tokens, not sounding voices.
- **Semantic colors:** ok `#3b684a`, error `#a13535`, warning `#937019`, info `#386889`; dark variants in the dark palette.
- **Forced colors:** selected step buttons and pressed toggles use a 2 px `Highlight` border under `forced-colors: active`.

## Interaction patterns

- **Play / Pause / Restart** are always visible in the masthead; `Ctrl/⌘+Enter` plays, `Ctrl/⌘+Shift+Enter` restarts.
- **Undo / Redo** appear only in the score toolbar, never inside pitch/drum controls: their scope is the entire score. Standard `Ctrl/⌘+Z` / `Ctrl/⌘+Shift+Z` also work from the sound controls. GUI edits and text edits share the same CodeMirror history.
- **Pattern controls** appear under the phrase at the cursor. Each numbered step shows its source pitch or drum name; selecting it auditions without editing. One inline chromatic keyboard edits the selected note, while named buttons edit a drum sound. No dropdowns, separate cards, or duplicate musical state.
- **Pitch editing:** keys run from low to high. Octave −/+ only browses the visible range; choosing a key writes the source atom, within MIDI 0–127. Numeric and flat spellings are preserved; pressing the current key does not rewrite it. A code-cursor move selects the corresponding step. Rest sits immediately to the right of the Octave −/+ controls, above the keyboard. Drum sounds and Rest form six equal choices in a three-column grid. Rest writes `~`, stops the preview, and shared Undo restores the exact token.
- **Listening:** numbered step buttons preview about 0.7 seconds using a separate instance of the existing scheduler Player and DSP; there is no separate Listen button. Sound edits and history shortcuts while focus is inside the controls preview the selected step when the main score is stopped or paused. Toolbar history returns focus to the code without starting a preview; press the numbered step to hear a restored sound. During main playback, edits retain normal entry-boundary behavior.
- **Preview boundaries:** the selected chain retains its own modifiers and the score's declarations, with its string replaced by the selected source step. Other voices, enclosing-group modifiers, downstream references, and original multi-step timing are not reproduced. Main Play remains the in-context reference. Preview does not enter undo history, alter the accepted score, or move the main transport.
- **Pattern keyboard focus:** steps, pitch keys, and drum choices including Rest each use a roving Tab stop. Melodic Rest has its own Tab stop beside the octave controls, before the keys. Left/Right and Home/End move within steps, keys, or drum choices without editing; Space/Enter activates. Step Up/Down changes pitch, with Shift for an octave. Escape returns to the mapped code selection. History and transport shortcuts remain shared. Preview is cancelled on source/target changes, hidden controls, main transport actions, and page hiding.
- **Inline knobs** edit gain and filter values for note and chord voices; drums are not affected.
- **File actions:** Open (`.mini`, `.txt`, `text/plain`), Download, Show help. Imports are bounded at 1 MiB and decoded by the browser's `File.text()`; they need not be valid MiniLive to remain editable.
- **Starters** in Help replace the score; Undo restores the previous one.
- **Examples** in Help replace the score and are individually labelled with duration and what to listen for.

## One immutable text score

- **Draft code, accepted code, and sounding material are distinct.** An invalid edit never replaces the accepted score; the footer reports the actual state.
- **Edits take effect at each material's next entry boundary.** Pending changes wait while the current phrase finishes; accepted edits switch per part, not all at once.
- **Restore** returns to the last accepted score via a regular undoable CodeMirror transaction.
- **Session persistence** uses `localStorage` under `moondsp.live.score.v1`, debounced at 350 ms. Pending edits are flushed synchronously on `pagehide`; an untouched tab does not rewrite its loaded score. The stored text is compared with the session's last saved text; an observed conflict leaves the shared score untouched, reports **Not saved**, and retains the draft for recovery or Download. This check is not a cross-tab transaction: overlapping saves can still replace the shared score.
- **Recovery copies** prevent that overlap from destroying either edit. Before publishing an edited score, each save writes `{ source, savedAt }` to a fresh `moondsp.live.draft.v1.<UUID>` key. Only after that succeeds may the tab remove its own previous checkpoint and attempt the shared write. It never removes another session's copy automatically. A checkpoint failure blocks the shared write and asks the user to Download. This is local browser storage, not protection against storage eviction, quota exhaustion, or a process killed before pending edits flush.
- **Saved drafts** below the score toolbar lists checkpoints from other sessions, newest first, with source previews. Restore inserts the complete text through the shared undo history; confirmed Delete removes only that immutable key, so deleting an older displayed snapshot cannot remove a newer checkpoint. An open list stays stable while other tabs save and refreshes when reopened. Copies from closed sessions remain until explicitly deleted; an active session normally retains one latest checkpoint.

## Help

All explanatory prose — first-sound story, syntax reference, what controls can and cannot edit, example listening notes, capability limits — lives in the Help drawer. The working surface carries layout, controls, and concise state feedback instead of tutorials.

## Responsive layout

- **Desktop (≥1100 px):** three-column masthead (brand / transport / file actions); workspace grid `1fr 344px` with Help as a right column.
- **Narrow (≤1100 px):** masthead reflows; workspace grid `1fr 288px`.
- **Mobile (≤760 px):** single column; transport spans the second row; Help becomes a native modal dialog up to `min(380px, 100%)`. It contains focus, closes on Escape, and restores the trigger. Choosing a score closes Help and focuses the editor.
- **Compact (≤360 px):** file actions move below transport so the masthead does not overflow.
- **≥1600 px:** score font grows to 16 px; editor minimum height increases.
- An open Help dialog switches between modal and non-modal behavior when crossing the 760 px breakpoint.

## Motion

- Transitions run only under `prefers-reduced-motion: no-preference` and are limited to 120 ms background/border easing on buttons.
- The cycle progress bar is the only continuous motion; it is `aria-hidden="true"`.
- No decorative animation interrupts the score or transport.

## Accessibility

- Skip link to `#editor`.
- `lang="en"`; `theme-color` matches the active palette.
- Transport status is `aria-live="polite"`; change status is `aria-live="polite" aria-atomic="true"`.
- Numbered play buttons have accessible sound/step names; preview feedback has `role="status"`. Starters use `aria-pressed`; Help toggle uses `aria-controls` and `aria-expanded`.
- Focus is a 2 px accent outline at 3 px offset on interactive elements.
- Transport Play is 46 px high. Steps have a 30 px minimum height; drum choices 36 px and octave controls including Rest 28 px. The keyboard scales with the code font, with a 23 em width constrained to the editor. At the observed 390 px viewport, accidental keys were 30.75 px wide. This is not a claim of universal 44 px touch targets.
- Forced-colors mode adds `Highlight` borders to selected steps, pressed keys, drum choices, Rest, and toggles.
- Screen-reader, novice-user, and physical-device perception studies have not been conducted; these are structural provisions, not validated outcomes.

## Architecture boundaries

- **Browser only.** The workspace is a Vite + TypeScript + CodeMirror 6 application backed by the MoonBit browser audio engine compiled to `wasm-gc`. No server, account, or external AI service is involved.
- **DSP safety remains an engine boundary.** This change does not modify MoonBit, Worklet processing, graph compilation, or render buffers. It does not establish a new audio-thread allocation audit.
- **External AI service integration, accounts, publishing, and paid services are out of scope.**
- **English is the only UI language.** Japanese localization is not in confirmed scope, although Japanese scores import correctly as UTF-8.

## Evidence on hand

- Observed browser scenarios (headless Chromium, not physical devices): fresh Play starts an `AudioContext`; typing a pitch changes both source and measured waveform frequency; GUI pad edits update source and pad `aria-pressed` state; invalid edits during playback retain playing state and surface a diagnostic; Restore replaces the source via a normal undoable transaction; Undo restores an invalid draft without interrupting audio; file chooser imports a 65-byte UTF-8 Japanese-comment score and reloads it exactly.
- Frequency measurements come from an analyser attached to the actual audio output; they are not subjective audio-quality evidence.
- No first-time user study, screen-reader session, or human audio perception study has been conducted.

## What this is not

- Not a full DAW. There is no mixer, multitrack timeline, audio file import, or plugin host in the workspace.
- Not an integrated AI service. Scores are plain text; nothing is sent to an external model.
- Not an award submission. The direction aspires to the craft of Awwwards, Webby Awards, FWA, and UX Design Awards examples documented in [`docs/development/2026-10-02-musical-workspace.md`](docs/development/2026-10-02-musical-workspace.md), without claiming any award or usability evidence.
