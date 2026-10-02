# moondsp

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

People making music in the browser, especially people trying live coding for the first time. Experienced musicians and programmers must retain a capable text editor rather than graduating into a different tool.

## Product Purpose

Make musical ideas directly manipulable and programmable. A visitor should hear a pattern before needing syntax, discover how musical changes correspond to code, and continue editing while the music plays.

## Positioning

Text editing is the primary way of composing. Graphical controls supplement it and derive from the same musical score. The code remains available to people and AI tools; a separate opaque GUI project is not the musical source of truth.

At the direction checkpoint, the user chose to retain cursor-linked controls: the focused phrase shows its supplementary GUI by default. Do not replace this with an initially hidden, explicit-open-only workflow without a new product decision.

The user subsequently requested editor-sized supplementary controls with no visible Melody/Drums headings or step-count captions. Keep the controls typographically subordinate to the code, without a separate card-like panel.

## Operating Context

The existing application is `web/live`, a TypeScript, CodeMirror 6, Vite application backed by the MoonBit browser audio engine. It supports patterns and arranged songs, live updates, examples, syntax help, and inline gain/filter controls. Browser audio starts after a user gesture.

## Capabilities and Constraints

- Draft code, accepted code, and currently sounding material are distinct; invalid edits never replace the accepted score. See `CONTEXT.md`.
- Changes can take effect at different material entry boundaries. Do not present a visual pulse as proof that all edits are audible.
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
