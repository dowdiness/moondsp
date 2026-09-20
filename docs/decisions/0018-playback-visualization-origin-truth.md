# ADR-0018: Playback visualization follows event origins

- **Status:** Proposed (domain semantics agreed; preliminary synthetic transport measurements recorded; production implementation and end-to-end validation pending)
- **Date:** 2026-09-15
- **Source:** Domain-modeling interview for [browser status issue #156](https://github.com/dowdiness/moondsp/issues/156) and pattern source highlighting
- **Related:** [Domain glossary](../../CONTEXT.md), [scheduler edit semantics](../../scheduler/README.mbt.md#pattern-edits), [playback position goal](../plans/2026-09-09-playback-position-ui.md)
- **Evidence:** [2026-09-19 synthetic transport probe](../performance/2026-09-19-playback-visualization-probe.txt). This probe evaluates transport feasibility only; it does not prove real-onset integration, editor mapping, or audio-thread allocation safety.

## Context

In live coding, music is edited while it is playing. When a newly edited score is accepted, its individual musical parts ("materials", such as patterns or tracks) do not switch immediately: each material transitions independently at its next musical entry boundary (e.g., the start of its cycle).

Because transitions occur independently:
- A new score can be accepted while older material versions continue generating playback events until their entry boundaries arrive.
- Even after all pending transitions take effect, previous synthesizer voices may continue ringing out during their release tails.
- Consequently, a single global score version or revision ID cannot determine which authored token produced a given sound event.

Composers need visual feedback showing which parts of their code are currently executing. The desired feedback is a brief visual pulse around the exact source token ("source atom") that triggered a playback onset—not a display of synthesizer voice sustain/release duration, and not a proof of audible sound (since gain may be zero or muted).

To provide accurate feedback without misleading the user, the editor interface must strictly separate three distinct layers of state:
1. The **visible draft** currently being edited (which may contain uncommitted edits or syntax errors).
2. The **accepted score** acknowledged by the audio runtime.
3. The **active material versions** currently producing audio events in the scheduler.

## Decision

### 1. Origin truth: exact identity continuity

Playback visualization attributes each sound event to its precise origin and maps that origin back to the visible editor draft using persistent token identity.

- **Full event provenance**: Every playback event carries its originating playback run (session), material snapshot, source atom ID, and the path of named-reference use sites leading to it.
- **Exact identity continuity**: The editor resolves event origins against the visible draft solely through tracked token identity. It must never use heuristic matching, such as note-value equality (e.g. matching "c3" to an arbitrary "c3"), token spelling, or nearest-cursor position.
- **Deletion and recreation breaks continuity**: If an atom is deleted and retyped with the exact same text, it receives a new identity. It does not inherit the identity of the deleted atom, and events from the older version will not highlight the new token.
- **Per-atom eligibility**: Highlighting eligibility is determined atom by atom, not globally for the whole score or material. An unchanged atom remains highlightable even if text moves (e.g. inserting whitespace), another material changes, or a neighboring atom is edited. If an origin cannot be resolved exactly, its highlight is suppressed rather than guessed.
- **Resilience to syntax errors**: An invalid draft does not disable highlighting across the entire score. As long as edit history confirms that an atom and its reference path remain unambiguously represented in the draft, that atom continues to highlight. Ambiguous or broken origins are suppressed. This neither accepts the invalid draft nor affects currently sounding materials.
- **Path integrity**: Stable atom identity alone is insufficient if the reference path leading to it has changed. If an intermediate named reference is modified such that it no longer resolves to the same definition, its highlight must be suppressed.
- **Bounded origin retention**: Origin mappings are retained only while older materials can still generate events and unexpired visualization events remain in flight. The engine does not keep an unbounded history of past revisions.

### 2. Visual meaning: onset pulses, not voice lifecycles

The visual display conveys event triggering, not audio energy or voice lifecycles.

- **Target tokens**: Highlighting applies to pattern-mode sound and note atoms. A chord name is treated as a single source atom even though it generates multiple notes.
- **Primary vs. secondary indication**: The source atom definition is the primary highlight target. Named-reference call sites are highlighted as secondary context to indicate which reference triggered the event.
- **Dispatched events vs. audible sound**: Visual pulses indicate that an event was dispatched for playback. This includes events rendered with zero gain or under mute. Conversely, rests and events eliminated by pattern transformations (such as `degradeBy`) produce no onset and must not pulse.
- **Brief onset pulse**: Highlights are brief onset pulses rather than indications of musical duration or synthesizer voice sustain/release. Retriggering an atom restarts its pulse. Simultaneous events can highlight multiple atoms, but duplicate simultaneous onsets for the same atom range do not generate duplicate decorations.
- **Listener-time alignment**: Pulses are scheduled to match estimated listener time, calculated from audio render timestamps plus available output latency. This is an estimate for visual synchronization, not a claim of sample-accurate physical audio alignment.
- **Expired and late events**: Observations that arrive after their highlight duration has already elapsed are discarded. Observations that arrive partially late display only their remaining duration, rather than starting a fresh full-duration pulse.
- **Run boundaries and tab visibility**: Active highlights are cleared immediately when a playback run stops. Observations accumulated while a browser tab was hidden are discarded upon resumption, never replayed as a backlog.
- **Editor stability**: Visual decorations must never alter editor cursor position, text selection, layout, or scroll offset. Under `prefers-reduced-motion`, highlights appear instantaneously without fade animations.
- **Core invariant**: A pulse confirms that the represented source atom was executed by the audio engine; it does not claim that all visible draft code, controls, or transforms have taken effect.

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

- **Audio-thread isolation**: The audio thread must never wait for the UI thread, allocate unbounded memory, or serialize large structures (such as ASTs or source maps) on the render path.
- **Separate channels**: Low-frequency status updates (tempo, position, pending counts) are sent separately from high-frequency onset telemetry.
- **Fixed-capacity ring buffer & credit handoff**: The initial transport candidate uses a fixed-capacity ring buffer with bounded messages in flight (e.g. credit-based batching). On buffer overflow, the oldest unread observations are dropped in favor of newer ones.
- **Audio rendering is independent**: Dropping visualization telemetry must never drop, delay, or glitch the corresponding audio events.
- **Diagnostic counters**: Cumulative drop counts are tracked for testing and validation, not displayed as user-facing error dialogs.
- **Pre-production verification gate**: Message-passing is an initial candidate, not a proven allocation-free solution. Before adopting it in production, matched AudioWorklet benchmark probes (comparing visualization on vs. off) must measure GC pause times, callback timing budgets, telemetry lag, and underruns under heavy workloads and stalled UI threads. Zero observed GC pauses does not prove zero allocation.
- **SharedArrayBuffer fallback**: If the message-passing transport causes audio regressions, evaluate a fixed-capacity `SharedArrayBuffer` ring buffer (under an explicit cross-origin isolation deployment contract). Shared memory will not be adopted unless proven necessary.

## Discriminating examples

| Scenario | Expected behavior |
| --- | --- |
| Bass pattern changes while drum pattern remains unchanged | Drums continue highlighting uninterrupted; pending status indicates 1 material transition (bass). |
| `note("c3 e3")` is edited to `note("c3 g3")` while the old pattern plays | Preserved `c3` may continue highlighting; removed old `e3` must never highlight the new `g3`. |
| An unchanged atom shifts because whitespace was inserted | The highlight follows the atom's tracked identity to its new text offset. |
| An atom is deleted and an identically spelled atom is typed in its place | Old events must not highlight the new atom; deleting and recreating breaks identity continuity. |
| An unrelated line in the score introduces a syntax error | Exactly traceable atoms in valid lines continue highlighting; the draft status shows rejected. |
| A named definition is used at two call sites | Highlights indicate the definition atom and the specific call site that triggered the event, not all call sites. |
| Track gain is set to zero or muted | Dispatched onsets still pulse; no assertion of audible physical sound is made. |
| A rest or degraded event produces no audio onset | No pulse is displayed. |
| Browser tab resumes focus after highlight intervals elapsed | Stale events are discarded; no backlog of pulses is replayed. |
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
- Transform and reference coverage must be systematically verified before claiming full pattern-mode support. An approximate second scheduler must not be created in JavaScript to bypass this requirement.

## Scope

- **In scope**: Authoritative playback status projection and pattern-mode source atom highlighting.
- **Out of scope**: Song-mode source highlighting, timeline and waveform displays, playback seeking controls, and synthesizer voice lifecycle visualization.
- **Non-goals**: Existing playback entry, restart, tempo, and last-good score semantics must not be altered to accommodate visualization. Public browser APIs expose only the telemetry required for this feature, never mutable routing or voice-pool internals.

Implementation will proceed in two sequenced steps:
1. Playback status reporting under [#156](https://github.com/dowdiness/moondsp/issues/156).
2. Pattern-origin highlighting (encompassing source mapping, AudioWorklet telemetry, and editor decorations end-to-end).
