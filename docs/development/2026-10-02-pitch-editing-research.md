# Pitch editing in a text-first musical workspace

Research date: 2026-10-02. Research only; no application changes.

## Recommendation and confidence

**For moondsp, investigate a focused-note control combining exact pitch entry, relative semitone/octave adjustment, and explicit audition. Do not make a miniature piano keyboard the default solely because this is music software.** This is a design recommendation, not a demonstrated usability winner.

The strongest transferable pattern is selection-based editing: identify the note, change its pitch without changing its time or surrounding phrase, hear the result, and undo. A keyboard, piano roll, scale grid, and continuous ribbon serve different tasks. No robust comparative study found in this search establishes which is best for changing a pitch token inside source code.

Retain the user-confirmed direction: text editing primary; cursor-linked supplementary controls; typography at code scale; explanations in Help. Keep the current native selector as a comparison baseline, rather than treating replacement as progress by definition. Its source currently generates 60 chromatic choices, C2 through B6, in `web/live/src/pattern-controls.ts`. That menu range is not a statement about the engine's supported pitch range.

## Evidence labels and method

- **DOCUMENTED:** first-party manuals, tutorials, or specifications describe behavior. Adoption and documentation do not demonstrate superiority.
- **OBSERVED:** browser interaction performed during this investigation. This is not a novice usability study or a listening study.
- **EMPIRICAL:** a study reports participant data. Population, task, sample, and transfer limits are recorded below.
- **[INFERENCE]:** a proposed consequence for moondsp, still needing validation.

Four independent research slices covered DAWs, code-native/web/performance interfaces, empirical HCI, and accessibility. The parent inspected public browser interfaces and integrated their findings. Searches targeted official product documentation, NIME/SMC proceedings, author repositories, ACM/CHI, and W3C. This was a targeted primary-source investigation, not an exhaustive systematic review. No external AI service received repository content. No accounts, publication, or saved/shared songs were required.

## 1. Define the task before choosing the widget

| User intention | What must stay stable | Suitable candidate, not a proven winner |
|---|---|---|
| “Change this note to F-sharp 4” | Other notes, rhythm, source structure | Direct note-name/number entry or a searchable discrete chooser |
| “A little higher; now an octave lower” | Target note and temporal position | Semitone/octave nudges; optional quantized drag |
| “I don't know the note name; let me hear choices” | Distinction between trying and committing | Auditionable ordered pitches, with relative controls and optional keyboard/scale view |
| “Keep this melody's shape, but move it lower” | Intervals and timing of the selected phrase | Explicit selection plus chromatic transposition |
| “Reshape the melody” | Temporal relationships and clear event identity | A pitch-versus-time view can justify its space |
| “Play expressively, bend between notes” | Continuous gesture and timing | Ribbon, MPE surface, pitch wheel, or another performance controller |
| “Tune a note in cents / a nonstandard tuning” | Exact tuning, not just its nearest semitone | Continuous/numeric tuning control with explicit units |

[INFERENCE] A good note-correction control need not be a good performance instrument. Nor does expressive performance prove a control is efficient for editing source. In particular, a whole-phrase transpose and snapping individual notes to a scale are different musical operations: the latter can change intervals.

## 2. What existing products actually do

All rows in this section are DOCUMENTED unless explicitly marked OBSERVED. Manuals are current pages accessed on the research date; rolling pages without a displayed version/date are not assigned one.

| Source | Relevant behavior | Transfer and counterevidence |
|---|---|---|
| [Ableton Live 12, Editing MIDI](https://www.ableton.com/en/manual/editing-midi/), §§10.1–10.6 | Notes occupy time/pitch rows. Up/Down transposes selected notes by semitone; Shift adds octave steps. Preview enables audition. Scale highlighting, folding, and Fit to Scale are separate operations. Pitch spelling can use sharps, flats, both, or Auto. | Selection and relative changes transfer. The piano ruler is an axis, audition surface, and row-selection control—not itself proof that clicking a tiny keyboard is the best replacement operation. |
| [Logic Pro for iPad, Change note pitch](https://support.apple.com/guide/logicpro-ipad/transpose-notes-lpip36aa2edb/3.3/ipados/26), guide selector 3.3 | Drag selected notes vertically; alternatively use the Inspector's Note value, dragging it or tapping to choose pitch. Octave transposition is also a contextual action. | A touch precedent for direct note manipulation plus precise entry, not just miniature keys. This remains a piano-roll workflow. |
| [Logic Pro for Mac, Quantize pitch](https://support.apple.com/guide/logicpro/quantize-the-pitch-of-notes-lgcpf4f544d2/12.3/mac/15.6), guide selector 12.3 | Apply a chosen root/scale to selected notes. | Scale conversion is explicit. Do not infer scale snapping during every drag, or undocumented keyboard bindings. |
| [FL Studio Piano roll](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/pianoroll.htm) and [Menu](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/pianoroll_menu.htm), rolling manual | Preview Keyboard auditions; note bars are edited separately. Scale shading and Snap to Scale have different effects. Snap settings do not automatically rewrite existing notes without editing them. | Visual scale assistance need not prohibit chromatic notes. Do not conflate previewing a piano key with changing a selected event. |
| [Bitwig, Keyboard Editing with Note Events](https://www.bitwig.com/userguide/latest/precise_editing_notes/) and [Working with Note Events](https://www.bitwig.com/userguide/latest/working_with_note_events), rolling guide | Default mapping: Up/Down changes selected events by one semitone; Shift+Up/Down by 12. Audition and micro-pitch expression are separate facilities. | Strong precedent for relative pitch correction. These arrow keys belong to a note editor, not a text editor; importing them globally would break caret navigation. |
| [Soundslice, Tablet/touch interface](https://www.soundslice.com/help/en/creating/basics/255/tablet-interface/), current help | Touch keyboard/fretboard follows selection. A key replaces a selected rest, appends to a selected note to create a chord, or toggles an existing pitch off. Auto-advance changes entry workflow. | Keyboard shape does not determine action semantics. moondsp's single-token replacement must not accidentally become chord insertion or note deletion. Current help takes precedence over older launch descriptions. |
| [Strudel, Notes](https://strudel.cc/learn/notes/), rolling documentation | Named notes, MIDI numbers, decimal pitches, and frequency-based notation; editing and updating code auditions changes. | Text remains an exact, shareable musical representation. Capability is not evidence that novices know what value to enter. |
| [Sonic Pi Tutorial 8](https://sonic-pi.net/tutorial-08.html), §§8.1–8.3 | Named/numeric pitches, lists, scales, and chords support programmable composition. | Musical abstraction can stay in code; a supplementary UI must preserve it rather than flatten it into a second arrangement. |
| [Ableton Learning Music](https://learningmusic.ableton.com/notes-and-scales/notes-and-scales.html) and [pitch patterns](https://learningmusic.ableton.com/notes-and-scales/make-patterns-with-pitch.html) | Lessons separate continuous high/low exploration from discrete pitch patterns and later scale organization. | A limited musical vocabulary can scaffold exploration. The learning-site framing does not establish measured transfer to code editing. |
| [Chrome Music Lab Song Maker](https://musiclab.chromeexperiments.com/Song-Maker) | OBSERVED: a time/pitch grid, keyboard interaction instructions, and settings for scale/root/range; the scale options included Major, Chromatic, and Pentatonic. | A counterexample to requiring conventional piano-key graphics for making a melody. It does not expose moondsp-style source correspondence. |
| [LinnStrument Getting Started](https://www.rogerlinndesign.com/support/linnstrument-getting-started) and [settings](https://www.rogerlinndesign.com/support/linnstrument-support-panel-settings) | Chromatic rows, default fourths between rows, configurable pitch lights, quantization, and continuous finger bends. | Isomorphic shapes and continuous expression matter for performance. Hardware affordances do not directly transfer to tiny mouse/touch widgets. |
| [Ableton Push manual](https://www.ableton.com/en/push/manual) | Scale/note modes and expressive per-note pitch interaction. | A performance/recording precedent, not evidence for a token picker. |
| [Melodyne 5 Pitch Tool](https://helpcenter.celemony.com/M5/doc/melodyneStudio5/en/M5tour_ToolPitch_2?env=standAlone) | Analyzed audio blobs, pitch grids, audition, absolute/relative entry, and continuous pitch manipulation. | Audio correction is not symbolic note editing. Only carefully bounded ideas such as exact entry and audition transfer. |

Two non-musical code precedents are also relevant: [Processing Tweak](https://processing.org/environment/) attaches manipulation to running code; Bret Victor's [Scrubbing Calculator](https://worrydream.com/ScrubbingCalculator/) describes exploring values by dragging. Neither is comparative evidence for a pitch-specific widget. They support investigating source-associated manipulation, not overriding normal text selection with a drag handler.

### Live browser inspection record

Two public products were exercised in managed Chromium at 1360×900. No login or song publication occurred; research tabs were closed afterward.

1. **Song Maker:** opened keyboard help, clicked the canvas, issued Right/Up/Enter and Backspace, and captured resulting screens. Opened Settings and inspected actual select options. Selected `chromatic`, submitted, and observed the expanded pitch grid and retained form value. This establishes an available chromatic mode and inspectable interaction—not accuracy, novice success, exact MIDI output, or a successful named-pitch audition. A later attempt to click the settings cancel control timed out; it is not counted as a successful interaction.
2. **Ableton Explore pitch:** dismissed the instructional overlay and exercised the low-to-high drag surface. Inspected the pitch marker and the widget's `data-isquantized="false"` configuration. This distinguishes a continuous exploration surface from an exact named-note chooser. No acoustic frequency measurement or subjective listening judgment was made. A subsequent visit to Make melodies supplied lesson context, not an exercised melody-editing result.

Cookie/tutorial overlays obstructed initial actions and were dismissed where needed. These observations are explicitly narrower than product documentation and are not performance benchmarks. The current moondsp UI was not modified or re-tested during this research-only task.

## 3. What empirical research can and cannot establish

| Primary source | Participants / task | Finding | Transfer limit |
|---|---|---|---|
| Hirai, Topliss & Piumsomboon, [XR Musical Keyboard](https://nime.org/proceedings/2025/nime2025_6.pdf), NIME 2025, pp.40–45, §5 | Four participants in their twenties, mostly keyboard-inexperienced; four familiar elementary melodies, six-key versus conventional twelve-key layout in XR | Mean comparative ease rating 3.69/5, where 5 favored six keys; melody means varied 2.75–4.50. Some participants found black keys useful for orientation. | Tiny pilot, subjective ratings, no objective code-editing task. It neither proves conventional piano superiority nor proves a reduced grid is best. |
| Vamvakousis & Ramirez, [Temporal Control in EyeHarp](http://mtg.upf.edu/system/files/publications/Temporal%20Control%20In%20the%20EyeHarp%20Gaze-Controlled%20Musical%20Interface.pdf), NIME 2012, §§4–5 | Ten participants with at least five years' musical training; timed scales and octave intervals using gaze, then computer keyboard | Reported gaze mean asynchrony −94 ms for close scale notes and −46 ms for octave intervals; practice effects discussed. | Accessible text did not provide a numerical keyboard summary adequate for ranking conditions. Timing in trained performance is not token correction, nor a piano-versus-grid comparison. |
| Cavez et al., [Challenges of Music Score Writing and the Potentials of Interactive Surfaces](https://inria.hal.science/hal-04497643), CHI 2024; [DOI](https://doi.org/10.1145/3613904.3642079) | Interviews with nine professional composers | Accessible abstract reports tension between rule-enforced engraving and flexible creative work, including use of paper. | Abstract-level evidence only in this investigation: ACM access failed; repository PDF retrieval returned HTML. Not a comparison of pitch widgets. |
| Hirai, [Redesigning a Piano Roll](https://zenodo.org/records/6573069), SMC 2022, version 1 | Custom temperaments and melody input design | Explores arbitrary pitch sets and constraints for melody making; usability evaluation is future work. | No participant evidence. Relevant counterexample to assuming all musical pitch is twelve-tone equal temperament. |
| Orio, Schnell & Wanderley, [Input Devices for Musical Expression: Borrowing Tools from HCI](https://arxiv.org/pdf/2010.01571), NIME 2001, archived 2020 | Methodological review/proposal | Separates musical tasks such as isolated tones, scales, phrase contour, continuous modulation, and synchronization. | Not a controlled pitch-layout comparison. The 2020 archive date is not a new experiment. |
| Larsen & Knoche, [States and Sound](https://vbn.aau.dk/ws/portalfiles/portal/295153583/nime2017_paper0021.pdf), NIME 2017 | State/sound models applied to five assistive musical interfaces | Makes triggering, sustained interaction, and feedback explicit. | Framework, not user-comparison evidence; pitch/bend mapping is outside its model's scope. |

McPherson, Morreale & Harrison's 2019 [Musical Instruments for Novices](https://link.springer.com/chapter/10.1007/978-3-319-92069-6_12) was identified as a cross-domain review, but the author PDF was inaccessible (404/anti-bot response). It is not used as evidence for a particular layout. Targeted searches for comparative touchscreen/piano-roll note-entry accuracy did not yield a usable direct study. This is a search limitation, not a claim that no such study exists.

**Evidence conclusion:** a compact piano's supposed intuitive superiority is unsupported here. Exact-value controls and relative nudges have strong product precedents, but their superiority for moondsp remains a hypothesis. Familiarity, musical training, disability, input device, and the user's actual task can change the outcome.

## 4. Candidate comparison for moondsp

Every judgment in this table is [INFERENCE], not a numerical usability score.

| Candidate | Main advantage | Main cost / failure mode | Recommendation |
|---|---|---|---|
| Current native pitch select | Explicit finite choices, browser/OS behavior, small closed footprint | Long octave-spanning list; weak representation of relative movement; no inherent audition | Keep as baseline; do not discard without comparison |
| Editable pitch value + semitone/octave nudges | Exact and relative tasks share one focused target; compact | Note names need knowledge; custom parsing, focus and boundaries require care | Leading candidate for source-note correction |
| Quantized drag/scrub | Fast repeated relative exploration without reopening a menu | Hidden gesture, accidental text selection conflict, precision and touch issues | Optional accelerator on a dedicated affordance, not the only route |
| Small piano picker | Familiar spatial vocabulary for pianists; supports audition and octave context | Black-key targets, range navigation, trained-user bias, ambiguous replace/add/play semantics | Optional expanded view; compare before making it default |
| Equal-size chromatic or scale-degree grid | Uniform targets; scale mode can reduce the choice set | Less familiar geography; scale mode hides pitches and introduces state | Candidate for novice ear-led exploration, with chromatic escape |
| Piano roll | Melody contour, time, and multi-note relations are visible together | Consumes space; introduces selection/time semantics and code-to-event mapping problems | Justified only by phrase-level tasks, not as permanent decoration under every line |
| Continuous slider/ribbon | Pitch bends and ear-led continuous exploration | Does not naturally express exact discrete note choice; silent quantization can mislead | Separate continuous-pitch task, not default note replacement |
| Text alone | Maximum source fidelity and compositional expressiveness | Requires syntax and pitch vocabulary | Always retain; supplementary controls must not degrade it |

## 5. Proposed interaction contract, not an implementation commitment

### Compact at rest; richer for the selected note

Keep the cursor-linked phrase controls. Show pitch values at code scale, without reinstating voice/step-count headings or an always-visible keyboard. Activating a supplementary pitch value may expose a small contextual control for that note. This does not mean hiding the entire phrase GUI until a button is pressed.

[INFERENCE] The control should provide:

- An unambiguous target association: the selected source note remains visibly identifiable.
- Exact pitch entry, preserving the language's accepted note-name/number forms.
- Discoverable semitone and octave adjustment, not just a long list.
- An explicit way to hear the candidate. A keyboard or equal-target pitch palette is an expanded alternative, not the definition of the control.

Do not install ordinary click/drag behavior over source text if it steals caret placement, word selection, or scrolling. The current supplementary value is a safer activation target than making every source-token click open a popup. Any source-token shortcut must preserve the normal editor operation.

### Source edits and audition are different state transitions

The mental model should be: **select a source note → try/change its pitch → hear it → keep or undo it**. A secondary GUI must not become a second composition model.

- Committed pitch changes use the same document transaction/history as typing; other notes, rests, rhythm, comments and surrounding syntax remain unchanged.
- A pointer scrub or continuous key-repeat adjustment should form one intelligible undo gesture, not a history entry per pointer event. Separate deliberate edits should remain separately undoable.
- For immediate-commit nudges, Escape closes the control; Undo reverses the edit. Do not make Escape secretly undo already accepted source changes.
- A separate audition action must not change the source, dirty state, history, or accepted composition. If future interaction includes uncommitted candidate browsing, acceptance/cancellation must be visibly distinct from immediate editing.
- Replaying a looping phrase and auditioning an isolated candidate are different. Existing acceptance/material-entry timing must not be falsely presented as immediate sound response. Isolated audition would require a real audio-path design; it is not assumed to exist today.
- Do not forcibly respell untouched flats as sharps, normalize every number to a name, or clamp a valid authored pitch to the current menu range simply by opening a control. Show unsupported representations as text rather than silently approximating them.
- Source positions can change while a control is open. Retarget or close safely when its associated note is removed/changed; never overwrite a different token based on a stale offset.

### Relative changes and scales

Chromatic semitone movement should be explicit and predictable. “Next note in the scale” is a different operation and needs an explicit scale/key context. Do not guess the key from a short phrase and silently restrict edits. Scale highlighting is safer than automatic rewriting, but still requires meaningful source-derived or explicitly chosen context. Changing a scale must not silently transpose existing music.

For a group of notes, distinguish interval-preserving chromatic transposition from scale-degree transformations. Any future phrase view must represent source structure accurately: repetitions, nesting, chords, and transformations cannot be flattened into a second independently editable truth without a well-defined mapping.

## 6. Accessibility and input ownership

The cited WCAG success criteria are normative; W3C Understanding pages and ARIA APG examples are informative guidance, not certification.

- [WCAG 2.5.7, Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html), AA: offer equivalent single-pointer operation without dragging. A keyboard shortcut alone does not meet that separate requirement. Buttons, direct entry via an on-screen keyboard, or another tap route can.
- [WCAG 2.5.8, Target Size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum), AA: generally 24×24 CSS px or a specified exception. [44×44](https://www.w3.org/TR/WCAG22/#target-size-enhanced) is the enhanced AAA criterion, not the AA threshold. Small typography need not mean tiny hit targets. Invisible hit regions must not overlap neighboring controls or intercept editable source.
- [APG Spinbutton](https://www.w3.org/WAI/ARIA/apg/patterns/spinbutton/): ordered values and readable `aria-valuetext` can represent named pitches. Roles alone do not prove screen-reader usability. Typed pitch names may warrant an editable combobox rather than forcing note text into a native numeric input.
- [APG Slider](https://www.w3.org/WAI/ARIA/apg/patterns/slider/): suitable for a meaningful continuous/discrete range, with explicit touch-assistive-technology caveats. It is not automatically preferable for 60 named notes.
- [APG Combobox](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/) and [Dialog](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/): define focus, acceptance, cancellation and return behavior deliberately. A small popover need not be modal; do not use `aria-modal` without actual modal behavior.
- Editor-focused arrows retain caret movement and text selection. Pitch shortcuts apply only within the focused pitch control or an explicitly invoked command. Returning from the control must preserve the appropriate source selection without overwriting a newer selection.
- Focus and target source must remain visible at viewport edges and zoom; see [Focus Not Obscured](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum). Sound, color, or spatial position alone must not communicate the selected pitch.

No screen-reader session, physical touch-device test, or accessibility conformance assessment was performed in this investigation.

## 7. Validation that could overturn the recommendation

Compare the current native selector with the proposed value/nudge control and an expanded piano or equal-target pitch picker. Give variants equivalent audition capability when testing layout; otherwise a preference may reflect sound feedback rather than geometry.

Recruit separately among first-time music/programming users, musicians without programming experience, and live coders. Record piano familiarity rather than assuming all musicians play keyboards. Counterbalance variant order and use comparable phrases to reduce practice effects. Include actual touch devices, keyboard-only use, and relevant assistive-technology sessions rather than treating viewport emulation as touch validation.

Use tasks that expose different intentions:

1. Make one note slightly higher without knowing its name.
2. Replace a specific note with a named pitch, then move it an octave while preserving rhythm.
3. Match a heard target; distinguish pitch-name knowledge from ear-led exploration.
4. Change a short melody while maintaining its intended contour; compare whether a phrase view becomes necessary.
5. Alternate ordinary source editing and GUI pitch adjustment without losing selection or editing the wrong note.
6. Undo a gesture; recover from an invalid draft; return to the accepted sounding material without losing work.
7. Explain which note will change, whether an action only auditions or changes code, when playback will adopt it, and what Undo/Escape will do.

Record time, wrong-note changes, accidental source edits, focus loss, help use, and recovery. Also observe exploratory behavior and ask participants to explain the model in their own words. Fast completion alone does not establish that people understand the tool or can transfer learning to an unfamiliar phrase. No fixed sample or statistical power claim is made before selecting a study design and expected effect size.

The recommendation should change if, for example, beginners cannot discover relative adjustment, a piano picker helps them hear and choose without causing selection errors, or phrase-shape tasks dominate single-note correction. Do not ship a replacement solely because it looks more musical. Preserve the text-first mental model and choose the smallest interaction that participants can understand and use reliably.
