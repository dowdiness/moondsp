# ADR-0018: Playback visualization follows event origins

- **Status:** Accepted; Pattern/Song onset integration implemented 2026-10-04. Physical-device alignment and listening quality are not claimed.
- **Date:** 2026-09-15
- **Source:** Domain-modeling interview for [browser status issue #156](https://github.com/dowdiness/moondsp/issues/156) and pattern source highlighting
- **Related:** [Domain glossary](../../CONTEXT.md), [scheduler edit semantics](../../scheduler/README.mbt.md#pattern-edits), [playback position goal](../plans/2026-09-09-playback-position-ui.md)
- **Evidence:** [Production integration and bounded observer checks](../development/2026-10-03-musical-experience.md#actual-onset-linkage--2026-10-04); earlier [synthetic transport probe](../performance/2026-09-19-playback-visualization-probe.txt).

## Context

In live coding, music is edited while it is playing. When a newly edited score is accepted, its individual musical parts ("materials", such as patterns or tracks) do not switch immediately: each material transitions independently at its next musical entry boundary (e.g., the start of its cycle).

Because transitions occur independently:
- A new score can be accepted while older material versions continue generating playback events until their entry boundaries arrive.
- Even after all pending transitions take effect, previous synthesizer voices may continue ringing out during their release tails.
- Consequently, a single global score version or revision ID cannot determine which authored token produced a given sound event.

Composers need visual feedback identifying the most recently dispatched notes. The exact source tokens ("source atoms") stay highlighted until the next onset—not for the duration of synthesizer sustain/release, and not as proof of audible sound (since gain may be zero or muted). This held indication replaces the initial brief-pulse presentation at the user's request on 2026-10-04.

To provide accurate feedback without misleading the user, the editor interface must strictly separate three distinct layers of state:
1. The **visible draft** currently being edited (which may contain uncommitted edits or syntax errors).
2. The **accepted score** acknowledged by the audio runtime.
3. The **active material versions** currently producing audio events in the scheduler.

## Decision

### 1. Origin truth: exact identity continuity

Playback visualization attributes each sound event to its precise origin and maps that origin back to the visible editor draft using persistent token identity.

- **Full event provenance**: The scheduler dispatches from active material snapshots, preserving the source atom ID and complete named-reference path. The Worklet attaches its observation generation; a global score-version comparison never substitutes for that provenance.
- **Exact identity continuity**: The editor resolves event origins against the visible draft solely through tracked token identity. It must never use heuristic matching, such as note-value equality (e.g. matching "c3" to an arbitrary "c3"), token spelling, or nearest-cursor position.
- **Deletion and recreation breaks continuity**: If an atom is deleted and retyped with the exact same text, it receives a new identity. It does not inherit the identity of the deleted atom, and events from the older version will not highlight the new token.
- **Per-atom eligibility**: Highlighting eligibility is determined atom by atom, not globally for the whole score or material. An unchanged atom remains highlightable even if text moves (e.g. inserting whitespace), another material changes, or a neighboring atom is edited. If an origin cannot be resolved exactly, its highlight is suppressed rather than guessed.
- **Resilience to syntax errors**: An invalid draft does not disable highlighting across the entire score. As long as edit history confirms that an atom and its reference path remain unambiguously represented in the draft, that atom continues to highlight. Ambiguous or broken origins are suppressed. This neither accepts the invalid draft nor affects currently sounding materials.
- **Path integrity**: Stable atom identity alone is insufficient if the reference path leading to it has changed. If an intermediate named reference is modified such that it no longer resolves to the same definition, its highlight must be suppressed.
- **Bounded origin retention**: The engine does not keep an unbounded history of past revisions. The UI retains at most 256 observations, covering the current onset group and pending listener-time observations, and rechecks their exact draft identities after edits.

### 2. Visual meaning: latest onset, not voice lifecycles

The visual display conveys event triggering, not audio energy or voice lifecycles.

- **Target tokens**: Highlighting applies to sound, note, and chord atoms in Pattern and Song. A chord name remains one source atom even when it generates multiple notes. A visible inline diagram additionally identifies the dispatched local occurrence.
- **Primary vs. secondary indication**: The source atom definition is the primary highlight target. Named-reference call sites are highlighted as secondary context to indicate which reference triggered the event.
- **Dispatched events vs. audible sound**: Highlights indicate that an event was dispatched for playback, including zero-gain or muted events. Rests and events eliminated by pattern transformations (such as `degradeBy`) produce no onset: they leave the previous highlight unchanged rather than highlighting the rest.
- **Hold until the next onset**: One latest-onset group is shared across the score, not one independently held note per material. Its exact source atoms, reference context, and represented diagram occurrences stay highlighted until a later dispatched onset reaches estimated listener time. Simultaneous events share an audio timestamp and remain highlighted together; duplicate source ranges do not create duplicate decorations. A later onset replaces the previous group even if its origin cannot be represented in the current draft.
- **Listener-time alignment**: Map render timestamps through `AudioContext.getOutputTimestamp()` when valid; otherwise use current context time plus reported base/output latency. Do not add latency again to the output-timestamp mapping. This remains an estimate, not sample-accurate physical-device alignment.
- **Late events**: A delayed batch jumps directly to its newest due onset group, without replaying intermediate notes. Older observations cannot replace a newer group. Grouping and ordering use the audio timestamp, not the listener-time estimate that can shift between drains.
- **Run boundaries and tab visibility**: Active highlights are cleared immediately when a playback run stops. Observations accumulated while a browser tab was hidden are discarded upon resumption, never replayed as a backlog.
- **Editor stability**: Visual decorations must never alter editor cursor position, text selection, layout, or scroll offset. Under `prefers-reduced-motion`, highlights appear instantaneously without fade animations.
- **Core invariant**: A highlight confirms that the represented source atom was executed by the audio engine; it does not claim that all visible draft code, controls, or transforms have taken effect or that its voice is still sounding.
- **Diagram continuity**: A stable literal-content frame carries local onset and pitch before outer transformations and Song placement. The diagram highlights only the represented atom/frame/onset/pitch occurrence. Any content edit retires the frame, so surviving atoms can remain highlighted in code without falsely identifying an event in edited geometry.

### 3. Status truth: three independent dimensions

The UI status projection tracks three orthogonal dimensions:

1. **Transport status**: Playback state (playing vs. stopped), active mode (pattern vs. song), effective tempo, and engine-reported musical position.
2. **Draft and submission status**: The relationship of the visible draft to submitted, accepted, and rejected edits (e.g. uncommitted edits, pending submission, or rejected with diagnostics).
3. **Material transition status**: The count of pending material transitions (additions, replacements, and removals waiting for their entry boundaries).

Key operational rules:
- **Count musical materials**: The pending count tracks distinct musical materials (patterns or tracks), not audio output routes or synthesizer voices.
- **Replace pending reservations**: A subsequent edit to a material already waiting for an entry boundary replaces that reservation without incrementing the pending material count.
- **Rejections preserve reservations**: Rejecting an invalid draft leaves existing accepted material reservations intact.
- **Runtime musical position**: Playback position must be reported directly by the audio runtime. Multiplying elapsed sample counts by the current tempo produces incorrect positions whenever tempo changes occurred during playback.
- **Do not label receipts "Applied"**: The UI must not label an acceptance receipt as `Applied`. A pending material count of zero indicates that all material entry transitions have completed; it does not mean that a rejected draft is playing, nor that all older voice release tails have finished.

### 4. Bounded observation transport

Telemetry from the AudioWorklet audio thread to the UI thread must adhere to strict real-time constraints:

- **Audio-thread isolation**: Observation writes use preallocated storage and primitive fields. The audio thread never waits for the UI, serializes source maps, or sends per-onset objects.
- **Separate channels**: Existing low-frequency status messages remain separate from high-frequency onset telemetry.
- **Fixed capacity**: One Player-owned engine ring and a shared-memory transport each hold 256 observations, with at most 32 complete reference bindings per observation. Invalid or oversized paths are dropped, never truncated.
- **Ownership handoff**: Shared slots use atomic free/writing/ready/reading states. A writer can replace an unread ready slot but skips a reader-owned slot without waiting. Readers cannot observe partially written Float64 rows.
- **Audio rendering is independent**: Overflow discards visual observations, not audio events. Cumulative overwrite, busy-slot, and engine-drop counters are diagnostic only.
- **Deployment contract**: The live editor uses `SharedArrayBuffer` under explicit COOP/COEP headers. No message-batching fallback is added: without isolation, audio and editing work but onset observation is disabled.
- **Evidence limit**: Generated observer hot functions contain no added GC-allocation instructions; the existing pattern query and whole engine are not certified allocation-free. Matched on/off Worklet measurements remain limited by integer-millisecond timing and headless buffered callbacks, not a proof of glitch-free physical output.

## Discriminating examples

| Scenario | Expected behavior |
| --- | --- |
| Bass pattern changes while drum pattern remains unchanged | Drums continue highlighting uninterrupted; pending status indicates 1 material transition (bass). |
| `note("c3 e3")` is edited to `note("c3 g3")` while the old pattern plays | Preserved `c3` may continue highlighting; removed old `e3` must never highlight the new `g3`. |
| An unchanged atom shifts because whitespace was inserted | The highlight follows the atom's tracked identity to its new text offset. |
| An atom is deleted and an identically spelled atom is typed in its place | Old events must not highlight the new atom; deleting and recreating breaks identity continuity. |
| An unrelated line in the score introduces a syntax error | Exactly traceable atoms in valid lines continue highlighting; the draft status shows rejected. |
| A named definition is used at two call sites | Highlights indicate the definition atom and the specific call site that triggered the event, not all call sites. |
| Track gain is set to zero or muted | Dispatched onsets still highlight; no assertion of audible physical sound is made. |
| A rest or degraded event produces no audio onset | The preceding onset remains highlighted; the rest itself does not highlight. |
| Browser tab resumes focus | Hidden-period observations are discarded; only new observations can establish a highlight. |
| Playback stops and restarts before previous telemetry arrives | Observations from the previous playback run are discarded and cannot affect the new run. |
| Telemetry ring buffer overflows under heavy load | Oldest visual observations are dropped while audio renders normally; diagnostic drop count increments. |

## Alternatives and consequences

- **Alternative 1: Global score revision equality**  
  *Rejected*. Simpler to implement, but disables highlighting for valid unchanged atoms whenever any edit occurs, and misattributes events from older materials to new source code.
- **Alternative 2: Value- or spelling-based matching**  
  *Rejected*. Lower tracking overhead, but inherently ambiguous when identical notes, chord names, or identifiers appear repeatedly in a score.
- **Alternative 3: Dedicated split view for past score versions**  
  *Rejected*. Preserves historical visual context, but introduces unacceptable interface complexity for live coding.

**Consequences**:
- Exact origin tracking requires preserving token identity through the entire pipeline: parser, AST, compiler, and scheduler.
- Authoring provenance in the parser is a necessary foundation, but each pattern transformation and reference resolution must explicitly maintain origin paths.
- Transform, reference, Song retiming, and source-retirement behavior are covered by exact-origin regressions and real browser playback. No JavaScript pattern scheduler is used.

## Scope

- **In scope**: Authoritative playback status, Pattern/Song source atom and reference highlights, and exact occurrences in the existing focused inline notation.
- **Out of scope**: A global musical playhead inferred in JavaScript, seeking controls, synthesizer voice-lifecycle visualization, and proof of physical audibility. The output waveform is a separate signal observation.
- **Non-goals**: Existing playback entry, restart, tempo, and last-good score semantics must not be altered to accommodate visualization. Public browser APIs expose only the telemetry required for this feature, never mutable routing or voice-pool internals.

Playback status and origin highlighting share the existing transport and
acceptance semantics. Inline notation continues to follow the source cursor;
onset decorations do not change selection, history, scroll, or widget geometry.
