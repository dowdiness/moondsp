# moondsp

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

People making music in the browser, especially people trying live coding for the first time. Experienced musicians and programmers must retain a capable text editor rather than graduating into a different tool.

## Product Purpose

Make musical ideas directly manipulable and programmable. A visitor should hear a pattern before needing syntax, discover how musical changes correspond to code, and continue editing while the music plays.

## Positioning

Source text is the musical source of truth, not a separate opaque GUI project. A first-time visitor can enter through a playable starting sound and a drawable melody; experienced users can compose directly in code. Both edit the same score, which stays available to people and their own AI tools.

At the direction checkpoint, the user chose to retain cursor-linked controls: the focused phrase shows its supplementary GUI by default. Do not replace this with an initially hidden, explicit-open-only workflow without a new product decision.

Within the cursor-linked editor ribbon, the user requested editor-sized supplementary controls with no visible Melody/Drums headings or step-count captions. Keep these controls typographically subordinate to the code, without a separate card-like panel.

The drawing belongs inside the editor, directly beneath the note phrase at the cursor—not in a separate workspace. Drawing and exact pitch/rhythm controls edit that source through shared history. There is no independent phrase selector or separate listening mode.

The inline notation is supplementary editor UI, not a miniature standalone music app. Keep code primary: compact pitch rows, labelled note blocks, restrained actions, and opt-in pitch/step details. The user rejected pitch-connecting curves and thin horizontal note marks in favor of familiar, readable music-editor conventions. Preserve exact chromatic editing, touch targets, source structure, and shared history rather than sacrificing them for visual minimalism.

Explicit rests must be usable note-entry positions, including all-rest phrases, without changing their weights or repetitions. Percussion uses a separate sound-row × source-step matrix rather than pitch rows. Its columns edit existing authored atoms; it does not invent equal-time quantization, independent repeated copies, or sample-file import. Code, selection, playback origins, and Undo remain shared with the melodic editor.

Rests should read as ordinary empty space rather than a prominent cell lattice. Notes support direct pitch changes, source-order movement, and edge resizing, not pitch-only dragging. Preserve the written pattern: moving a note reorders complete sibling tokens, keeps weights and repetitions attached, and never silently overwrites occupied notes or crosses a group boundary. This is not arbitrary-time DAW placement; source structure remains the editing model.

Musical phrases should be editable as source-linked ranges, not only one note at a time. Selection, block movement, transposition, and independent duplication share the code document and Undo. Keep independent Duplicate distinct from linked Repeat. Structure controls belong behind a contextual disclosure; time guides must describe local notation honestly. Pending-edit feedback belongs near the edited phrase without claiming that accepted code is already audible.

Chords need source-linked direct manipulation: select a written chord, drag the whole harmony or one constituent tone, and add or remove tones without knowing a chord name. Code edits, playback, and Undo share the existing score. Preserve duration, repetitions, and surrounding code; do not introduce a separate voicing state or audition transport.

Chord editing centers on the selected chord, not a permanent bank of replacements or a form. The editable tone rows open below its source steps; name-based Root/Type choices are optional. An exact supported voicing may use its chord name; arbitrary combinations and inversions must retain every pitch as an explicit MIDI set, never be rounded to a nearby named chord. Listen through the main transport and use shared Undo to compare changes.

Use the viewport as the editor, not as a frame around an editor card. Keep
transport, editing, and file actions compact; move starter choices and
explanations into Help, and make playback inspection optional. Long documents
scroll within the editor while essential controls remain reachable.

The user rejected accumulated composition features. The essential loop is:
edit the score, hear the score, refine or Undo. Keep source-linked subdivision,
repetition, rests, and adjacent timing boundaries beside the notation. Put exact
pitch and phrase timing in optional disclosures. These controls edit the same
atoms and groups as code; repeated occurrences are not independent copies.
One transport owns listening. Do not reintroduce isolated previews, generated
variations, pitch proposals, kept comparisons, or answer buttons behind menus.
Preserve transformations and arrangements in source, without an independent
GUI composition model.

## Operating Context

The existing application is `web/live`, a TypeScript, CodeMirror 6, Vite application backed by the MoonBit browser audio engine. It supports patterns and arranged songs, live updates, examples, syntax help, and inline gain/filter controls. Browser audio starts after a user gesture.

## Capabilities and Constraints

- Draft code, accepted code, and currently sounding material are distinct; invalid edits never replace the accepted score. See `CONTEXT.md`.
- Changes can take effect at different material entry boundaries. Do not present a playback highlight as proof that all edits are audible.
- The DSP graph is compiled. No allocation on the audio thread.
- Existing pattern and song expressiveness must remain available; graphical editing must state its supported syntax without flattening unsupported patterns.
- External AI service integration, accounts, publishing, and paid services are not authorized by this UI task.
- Keep explanatory copy off the working surface where possible. Put tutorials, syntax explanations, and capability limits in Help; use layout, controls, and concise state feedback to explain the work.

## Brand Commitments

Keep the name moondsp. Aim for the craft of Awwwards, Webby Awards, FWA, and UX Design Awards examples without claiming an award or usability evidence not obtained. The user explicitly permits a bold redesign in service of the experience.

## Evidence on Hand

Existing playable examples in `examples/`; current editing and audio behavior in `web/live/tests/`. User-confirmed first-use and two-way editing scenarios in this session. No first-time user study has yet been conducted for the redesign.

## Product Principles

1. Sound before syntax: a meaningful first action requires no code entry.
2. Text first, one score: supplementary direct manipulation edits the same text a person or AI edits.
3. Show cause and effect near the action; distinguish authored intent from accepted and sounding states.
4. Preserve experimentation: undo and error recovery must protect musical work.
5. Reveal complexity without imposing a novice-only ceiling; concentrate explanations in Help.

## Accessibility & Inclusion

Keyboard-operable musical controls, visible focus, reduced-motion support, and layouts usable on mobile as well as desktop are acceptance requirements. English is the incumbent UI language; Japanese localization is not part of the confirmed scope.
