# DESIGN.md — moondsp musical workspace

A text-first music editor in the browser. The source document is the editable score; pads operate on that text, while the transport reports what the audio engine is actually playing.

## Form

A source-bound note grid sits directly beneath its editable phrase. Labelled pitch rows, subtle accidental-key shading, a cycle ruler, and rectangular notes replace pitch-connecting curves and eye-shaped marks. Deep green ink and the existing cobalt accent remain part of the code-first workspace. Sonic Pi informs role separation; Ableton Learning Music informs the note-grid vocabulary, not an independent DAW model.

## What is primary

- **Text editing is the musical source of truth.** CodeMirror holds the draft. Text, GUI controls, starters, and file imports change that document through transactions. The engine separately retains the last accepted score and sounding material.
- **One editor, multiple ways to edit.** Starting sounds play directly. The focused phrase opens a 760 px maximum-width grid below its source. Pitch rows are 20 px high and fit the phrase's range, with at least one octave. Wide ranges scroll vertically inside a 304 px desktop / 264 px mobile viewport; the 24 px cycle ruler stays outside that scrolling area. Notes contain pitch names when space permits; narrow notes retain pitch-row context and accessible names. Source labels remain editor-sized, and touch toolbar actions retain 44 px targets.
- **No alternative GUI truth.** There is no separate sequencer state, project file, or hidden model that can disagree with the source. What you see in the pads is what the source says at your cursor.
- **The editor fills the viewport.** No outer card, centered width cap, or page gutters. A compact toolbar and status strip bound an independently scrolling code surface. Starting sounds live in Help; the waveform opens under Playback details. Errors, save failures, and recovery actions remain available.

## Typography

- **Body:** Manrope (regular 400, bold 700), self-hosted from `/fonts/` under the SIL Open Font License.
- **Code and notation:** JetBrains Mono (regular 400), self-hosted under the SIL Open Font License.
- **Scale:** body 14 px / 1.55 on desktop; score content 14 px / 1.95 (15 px at ≥1600 px, 13 px at ≤760 px). Brand 16 px, transport status 12 px, document status 11 px. Pitch labels suppress inherited SVG strokes; dark-scheme pastel marks use dark text.
- **Measurements:** tabular numerals in transport; letter-spacing -0.035 em on the brand; -0.02 em on headings.

## Color

Light and dark palettes are defined as CSS custom properties in [`web/live/src/workspace.css`](web/live/src/workspace.css).

- **Light:** ink `#153e39` on `#f9fbf8` over `#e9efeb`, with cobalt `#354acb`. The grid uses the editor panel and border colors rather than a separate colored stage.
- **Dark:** ink `#e2eee5` on `#1e3631` over `#162c28`, with accent `#b8c1ff`; the grid inherits those same tokens.
- **Notes:** neutral pitch rows, subtle accidental-key bands, soft accent blocks, ink selection outlines, and solid accent playback fills. Pitch names and position carry meaning rather than a decorative pitch-color palette.
- **Semantic colors:** successful, invalid, pending, and accepted playback states remain separate from note selection and onset indication.
- **Forced colors:** selected controls retain `Highlight` borders; note selection uses a 3 px `Highlight` stroke, and playing blocks use `Highlight` / `HighlightText`.

## Interaction patterns

- **Play / Pause / Restart** are always visible in the masthead; `Ctrl/⌘+Enter` plays, `Ctrl/⌘+Shift+Enter` restarts.
- **Undo / Redo** appear in the shared top toolbar, never inside pitch/drum controls: their scope is the entire score. Standard `Ctrl/⌘+Z` / `Ctrl/⌘+Shift+Z` also work from the sound controls. GUI edits and text edits share the same CodeMirror history.
- **Edit / listen / refine:** the score is the only editable musical state and the main transport is the only listening path. Selecting, drawing, changing a pitch or length, and Undo never start audio. While playing, those edits use the existing material-entry acceptance path. `Ctrl/⌘+Enter` works from the drawing and controls without returning focus to the toolbar.
- **Direct manipulation:** clicking an existing note selects its exact source atom without changing pitch. Body drag changes chromatic pitch and reorders whole source tokens within their sequence; occupied slots rotate rather than overwrite, with separators and postfixes preserved. Horizontal movement is source-order editing, not arbitrary-time placement. Note-edge drag trades adjacent weights while holding unrelated boundaries fixed. Compiled dashed previews precede one document change and one Undo step; Redo retains the destination selection. Shift-drag and blank-grid drawing retain contour editing. Repeated appearances stay linked.
- **Source structure:** the closed-by-default Structure disclosure contains a labelled, normalized strip for atoms, rests, and nested groups, with contextual Split, Repeat, and Share controls. Its proportions describe authored weights, not a second performance timeline. Split replaces one atom's core with `[atom atom]`, leaving its postfixes outside. Repeat edits the selected atom/group's `*n`. Boundary drag and Share trade weight with the next sibling while preserving the other sibling boundaries; integer weights are rescaled when necessary. Ambiguous operations remain code-only.
- **Note meaning and rest entry:** horizontal position and block width show the quoted notation's onset and interval, excluding outer transforms, gate, release, and song placement. Rests remain ordinary blank space, without a dashed-cell lattice or extra accent. Explicit source-rest intervals retain transparent hit areas; a click/tap previews and commits one rest atom on release. Escape cancels. Source-selected rests also support Enter, semitone preview, and Enter to commit, plus Add note/Add chord with neighboring-value or C4/C fallback. Silent gaps produced by other operators do not select a neighboring event. Ambiguous overlapping rests use source selection. A chord source selects all its pitch blocks.
- **Selection and playback:** selection is an ink outline; the latest dispatched onset group uses a solid accent fill with contrasting text, without blinking or connecting lines. The existing exact-identity observer holds it until the next onset. Playback never scrolls the grid; only source selection and keyboard editing can reveal an offscreen pitch.
- **Phrase selection:** Select enables pointer/touch range selection and keyboard extension within one source sequence. Code and GUI share that complete source range. Drag and Up/Down transpose all selected notes; horizontal movement rotates the block through siblings. Duplicate inserts literal independent source, unlike linked Repeat; it adds steps within the existing notation span. Rest clears selected sounded atoms without removing postfixes. One source change is one Undo; Redo restores the entire destination selection.
- **Rhythmic guidance:** the ruler explicitly measures local notation cycles. Optional four-division guides label cycle/division positions, not bars or global beats. Move previews show selected notes and displaced neighbors from the compiled candidate; outer speed, gate, and song placement are not folded into that preview.
- **Pending edits:** compact status beside edited phrases distinguishes queued/sending drafts from accepted code with score-wide pending material. No phrase-specific sounding claim is inferred from a score-wide receipt. Mapped edited spans survive hiding controls; the notice clears only for current-version acceptance without pending material, or stopped states.
- **Timing:** the optional disclosure separates relative Weight (`@1`–`@16`, total at most 256) from Phrase stretch (`.slow(n)`) and Phrase gate (`.gate(n)`). Weight can move subsequent onsets; gate cannot. Existing whitespace, comments, postfix order, and surrounding transforms survive local edits. Invalid input restores the previous field value with feedback.
- **Pitch controls:** the optional disclosure contains numbered selection buttons, octave browsing, and the chromatic keyboard. Its open state follows the source phrase for the session. Numeric and flat spellings are preserved; selecting the current pitch does not rewrite it.
- **Chords:** numbered source steps select a chord without changing playback. Editable tone rows sit beneath them: drag a tone vertically, drag Move chord to transpose all tones, tap an empty row or use Add tone, and remove the selected tone. Lower/Raise and keyboard arrows provide discrete edits. Pointer movement previews only; release writes one shared Undo step, while Escape, cancellation, or a changed source discards the gesture. Exact compiler-derived voicings retain chord names; other combinations, including inversions, use sorted explicit MIDI sets such as `{64,67,72}`. Collisions and out-of-range tones are rejected rather than merged or clamped. The last removed tone becomes a rest. Choose by chord name discloses the optional Root/Type selectors for named chords; custom sets are edited directly. View chord tones remains an optional whole-progression inspection diagram, not another editing state. Actual-onset highlights mark source steps and the selected chord's tones independently of selection. Weights, groups, linked repetitions, and surrounding transforms survive.
- **Percussion:** a dedicated matrix has Kick, Snare, Hi-hat, Open hat, and Clap rows. Columns are source atoms, not a performance ruler. A filled cell clears to `~`; an empty cell sets/replaces that atom's sound. Headers select without editing. Postfixes, grouping, and linked repeats stay intact; parallel layers remain code-authored. Sticky sound labels and internal horizontal scrolling keep 48 px cells usable on narrow screens. Only occupied cells receive actual-onset highlights.
- **Shared history, not a second comparison model:** no kept versions, candidate proposals, motif generators, answers, or auxiliary audition Player. Use Undo/Redo to try and reverse source edits.
- **Add melody:** the toolbar appends an editable phrase to an empty or stack score, including chord-only stacks, and moves the source cursor to it. It does not convert an arranged song into a stack.
- **Audio output:** under Playback details, a post-master analyser displays the main transport's samples. It does not claim note provenance or that a pending source edit is already sounding.
- **Keyboard focus:** steps and pitch keys use roving Tab stops; percussion arrows move between sound rows and source columns, with Space/Enter toggling the focused cell. Source atoms, groups, and boundary sliders are keyboard reachable; boundary arrows adjust adjacent weights. Grid Up/Down changes pitch by a semitone, Alt+Left/Right reorders a note, Shift+Left/Right resizes its right boundary, and Delete/Backspace clears it. Numbered-note-step Up/Down changes pitch, with Shift for an octave. Escape cancels a pending gesture and returns to code. Numeric fields retain native text undo; Enter commits and Escape discards unfinished input.
- **Inline knobs** edit gain and filter values for note and chord voices; drums are not affected.
- **File actions:** Open (`.mini`, `.txt`, `text/plain`), Download, Help. Imports are bounded at 1 MiB and decoded by the browser's `File.text()`; they need not be valid MiniLive to remain editable.
- **Starting sounds** in Help start playback; **Load a score** only replaces the text. Both support Undo. On mobile, either choice closes Help and focuses the editor.
- **Examples** in Help replace the score and are individually labelled with duration and what to listen for.

## One immutable text score

- **Draft code, accepted code, and sounding material are distinct.** An invalid edit never replaces the accepted score; the footer reports the actual state.
- **Edits take effect at each material's next entry boundary.** Pending changes wait while the current phrase finishes; accepted edits switch per part, not all at once.
- **Restore** returns to the last accepted score via a regular undoable CodeMirror transaction.
- **Session persistence** uses `localStorage` under `moondsp.live.score.v1`, debounced at 350 ms. Pending edits are flushed synchronously on `pagehide`; an untouched tab does not rewrite its loaded score. The stored text is compared with the session's last saved text; an observed conflict leaves the shared score untouched, reports **Not saved**, and retains the draft for recovery or Download. This check is not a cross-tab transaction: overlapping saves can still replace the shared score.
- **Recovery copies** prevent that overlap from destroying either edit. Before publishing an edited score, each save writes `{ source, savedAt }` to a fresh `moondsp.live.draft.v1.<UUID>` key. Only after that succeeds may the tab remove its own previous checkpoint and attempt the shared write. It never removes another session's copy automatically. A checkpoint failure blocks the shared write and asks the user to Download. This is local browser storage, not protection against storage eviction, quota exhaustion, or a process killed before pending edits flush.
- **Saved drafts** in the bottom status strip lists checkpoints from other sessions, newest first, with source previews. Expanding it uses the bounded, scrollable footer rather than covering the editor. Restore inserts the complete text through the shared undo history; confirmed Delete removes only that immutable key, so deleting an older displayed snapshot cannot remove a newer checkpoint. An open list stays stable while other tabs save and refreshes when reopened. Copies from closed sessions remain until explicitly deleted; an active session normally retains one latest checkpoint.

## Help

All explanatory prose — first-sound story, syntax reference, what controls can and cannot edit, example listening notes, capability limits — lives in the Help drawer. The working surface carries layout, controls, and concise state feedback instead of tutorials.

## Responsive layout

- **Viewport:** `100dvh` shell, no maximum width or outside padding. The editor fills the remaining height between toolbar and footer; CodeMirror owns long-document scrolling. Expanded playback details and error messages can use up to 40% of viewport height before the footer scrolls.
- **Desktop (>1100 px):** one wrapping toolbar for brand, transport, score tools, and file actions. Optional Help occupies a 344 px right column with its own scrolling.
- **Narrow (≤1100 px):** brand yields space to controls; optional Help narrows to 288 px.
- **Mobile (≤760 px):** transport and files occupy the first row, score tools the second. Help becomes a native modal up to `min(380px, 100%)`, contains focus, closes on Escape, and restores the trigger.
- **Compact (≤380 px):** playback control widths and file-button padding contract; the editor remains edge-to-edge.
- **≥1600 px:** score font grows to 15 px without adding a minimum editor height.
- An open Help dialog switches between modal and non-modal behavior when crossing the 760 px breakpoint.

## Motion

- Transitions run only under `prefers-reduced-motion: no-preference` and are limited to 120 ms background/border easing on buttons.
- The cycle progress bar is the only continuous motion; it is `aria-hidden="true"`.
- No decorative animation interrupts the score or transport.

## Accessibility

- Skip link to `#editor`.
- `lang="en"`; `theme-color` matches the active palette.
- Transport status is `aria-live="polite"`; change status is `aria-live="polite" aria-atomic="true"`.
- Numbered selection buttons have accessible sound/step names; validation feedback has `role="status"`. Starters use `aria-pressed`; Help uses `aria-controls` and `aria-expanded`.
- Focus is a 2 px accent outline at 3 px offset on interactive elements.
- Transport Play is 40 px high on desktop and 44 px on mobile. Structural number fields, Split, and melodic Rest are 32 px on desktop and 44 px on touch/small screens. Source selection and boundary hit regions expand for touch. Optional pitch steps and octave controls also reach 44 px there. The keyboard scales with the code font, with a 23 em width constrained to the editor. This is not a claim of universal 44 px targets.
- Forced-colors mode adds `Highlight` borders to selected steps, pressed keys, occupied percussion cells, Rest, and toggles; note-rest cells retain dashed outlines.
- Screen-reader, novice-user, and physical-device perception studies have not been conducted; these are structural provisions, not validated outcomes.

## Architecture boundaries

- **Browser only.** The workspace is a Vite + TypeScript + CodeMirror 6 application backed by the MoonBit browser audio engine compiled to `wasm-gc`. No server, account, or external AI service is involved.
- **DSP safety remains an engine boundary.** Relative-duration authoring extends MoonBit notation and pattern lowering, not the render graph, Worklet processing, or render buffers. It does not establish a new audio-thread allocation audit.
- **One notation grammar.** The production MoonBit parser supplies UTF-16 source ranges, recursive nodes, and postfix spans. The main-thread authoring bridge joins compiled event origins to those atoms; TypeScript only projects and edits that structure. Input, depth, nodes, query work, and emitted events are bounded. Oversized/invalid notation stays editable as code. No audio-thread or render-buffer work was added.
- **External AI service integration, accounts, publishing, and paid services are out of scope.**
- **English is the only UI language.** Japanese localization is not in confirmed scope, although Japanese scores import correctly as UTF-8.

## Evidence on hand

- Observed browser scenarios (headless Chromium, not physical devices): fresh Play starts an `AudioContext`; typing a pitch changes both source and measured waveform frequency; GUI pad edits update source and pad `aria-pressed` state; invalid edits during playback retain playing state and surface a diagnostic; Restore replaces the source via a normal undoable transaction; Undo restores an invalid draft without interrupting audio; file chooser imports a 65-byte UTF-8 Japanese-comment score and reloads it exactly.
- Frequency measurements come from an analyser attached to the actual audio output; they are not subjective audio-quality evidence.
- Earlier moving-score passes exercised comparison previews, transformations, and answers; those features were removed after the user rejected their complexity. Historical recordings are not evidence of the current simplified surface. Current source/history, playback, persistence, and mobile evidence is recorded in the development log.
- No first-time user study, screen-reader session, or human audio perception study has been conducted.

## What this is not

- Not a full DAW. There is no mixer, multitrack timeline, audio file import, or plugin host in the workspace.
- Not an integrated AI service. Scores are plain text; nothing is sent to an external model.
- Not an award submission. The direction aspires to the craft of Awwwards, Webby Awards, FWA, and UX Design Awards examples documented in [`docs/development/2026-10-02-musical-workspace.md`](docs/development/2026-10-02-musical-workspace.md), without claiming any award or usability evidence.
