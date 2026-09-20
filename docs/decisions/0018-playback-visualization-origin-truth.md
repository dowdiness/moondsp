# ADR-0018: Playback visualization follows event origins

- **Status:** Proposed — product semantics resolved in the interview; preliminary synthetic transport measurements recorded; production implementation and validation pending
- **Date:** 2026-09-15
- **Source:** Domain-modeling interview for [browser status issue #156](https://github.com/dowdiness/moondsp/issues/156) and pattern source highlighting
- **Related:** [Domain glossary](../../CONTEXT.md), [scheduler edit semantics](../../scheduler/README.mbt.md#pattern-edits), [playback position goal](../plans/2026-09-09-playback-position-ui.md)
- **Evidence:** [2026-09-19 synthetic transport probe](../performance/2026-09-19-playback-visualization-probe.txt). This is not a real-onset/editor integration proof; allocation and physical-output safety remain inconclusive.

## Context

A score can be accepted while its materials continue generating future onsets
from older sources until their independent entry boundaries. Acceptance is not
simultaneous replacement, and the end of all pending transitions is not the end
of old release tails. A global accepted revision cannot identify which source
produced a particular event.

The desired feedback is a short pulse around the source atom that produced a
playback onset, not a voice-lifetime display or proof of audible sound. The
editor must preserve the distinction between the visible draft, the accepted
score, and the material versions generating events.

## Decision

### Origin truth

Attribute each event to its originating playback run, material snapshot, atom,
and named-reference use path. Resolve that origin against the visible draft
using exact identity continuity, never note-value equality, token spelling, or
nearest-position guesses. Retain origin mappings while old materials can still
generate events and while their non-expired visualization events remain relevant;
do not keep unbounded revision history.

Highlight eligibility is decided per atom, not per score or whole material
version. An unchanged atom can remain represented when another material changes,
when text moves, or when a sibling atom is replaced. Deletion and recreation of
an equivalent token do not establish identity continuity. If the origin cannot
be resolved exactly, suppress its indication rather than pointing to new text.

A syntax error does not globally disable highlighting. Continue where edit
history proves the atom and reference path remain represented, and suppress
ambiguous or invalidated origins. This neither accepts the invalid draft nor
changes the last valid material reservations. Stable atom identity alone is not
proof that an edited reference still denotes the same definition; the origin
path must remain valid too.

### Visual meaning

- Highlight pattern-mode sound and note atoms; a chord name is one atom.
- Use the definition atom as the primary indication and named-reference use
  sites as secondary context.
- Indicate dispatched events even at zero gain or under mute. Rests and events
  excluded by transformations such as degradation do not create pulses.
- Use a short onset pulse, not musical duration or voice lifetime. Retriggering
  restarts the pulse. Simultaneous events may indicate several atoms; duplicate
  simultaneous origins need not create multiple decorations on one range.
- Align to estimated listener-time using render timing and available output
  timing information. Do not claim sample-accurate physical audio alignment.
- Discard expired events. Partially late events use only their remaining pulse
  interval rather than starting a fresh full-duration pulse on arrival.
- Invalidate outstanding indications when their playback run ends. Never replay
  a hidden tab's backlog when it becomes visible again.
- Preserve cursor, selection, text layout, and scroll position. Reduced-motion
  rendering uses an immediate indication without a fade.

A pulse means the represented atom executed. It does not assert that every
currently visible transform, control, or edit has become active.

### Status truth

Keep three independent dimensions in the status projection:

1. Playback state, active mode, effective tempo, and engine-reported position.
2. The visible draft's relationship to submitted, accepted, and rejected edits.
3. The number of pending independent material additions, replacements, and removals.

Count musical materials once, not once per output route or voice. A later edit
can replace a reservation without adding a second pending material. A rejected
draft does not clear existing reservations. Report runtime musical position;
absolute sample count multiplied by the latest tempo cannot reconstruct a
transport that has undergone tempo edits.

Do not label an acceptance receipt `Applied`. Zero pending materials means no
material entry transition remains, not that a rejected draft is playing or that
all old voices have ended. A countdown or a public list of internal route IDs is
not required.

### Bounded observation transport

The first transport candidate uses fixed-capacity onset storage and a bounded
batch for blocks containing onsets. The audio producer must never wait for the
UI, grow an unbounded queue, or serialize complete source maps per onset.
Ordinary low-rate status observations remain separate from onset traffic.

On overflow, discard the oldest buffered onset observations and retain the
latest. Expose a cumulative drop count for diagnostics and validation, not as a
normal user-facing warning. Losing an indication must never drop or delay the
corresponding audio event. Use a bounded handoff as well as a bounded batch:
limiting each message alone does not bound a stalled consumer's message queue.

This is a candidate, not an allocation-free claim. Before shipping, compare
visualization off/on in matched dense-pattern AudioWorklet probes, including a
stalled or hidden UI, repeated triggers, and material transitions. Measure
allocation, GC, callback timing, observation lag, and underruns separately; zero
observed GC is not proof of zero allocation. Pin the workload, environment, and
numerical comparison criteria before interpreting the results.

If the message path shows a material regression, do not merge it as the default.
Evaluate a fixed shared ring with an explicit cross-origin-isolation deployment
contract. Shared memory is not selected until needed: the current Live deployment
does not already establish that requirement. Buffer capacity, batch cadence,
clock calibration, and the measurement thresholds remain implementation-probe
outputs rather than unmeasured constants in this ADR.

## Discriminating examples

| Scenario | Required observation |
| --- | --- |
| Bass changes while drums remain unchanged | Drums continue highlighting; pending status includes bass. |
| `note("c3 e3")` changes to `note("c3 g3")` while the old material continues | Preserved old `c3` may highlight current `c3`; removed old `e3` must not highlight `g3`. |
| An unchanged atom shifts because whitespace is inserted | Follow its identity to its new range. |
| An atom is deleted and an identically spelled atom is created | Old events must not highlight the replacement merely because spelling matches. |
| Another line becomes syntactically invalid | Exactly traceable origins keep highlighting; the draft remains rejected. |
| A named definition is reused at two sites | Indicate the source atom and the actual originating reference site, not every same-named use. |
| Gain is zero | Dispatched onsets still pulse; no claim of audible energy is made. |
| A rest or degraded event produces no dispatched onset | No pulse. |
| A tab resumes after the highlight intervals elapsed | No replay of stale pulses. |
| Playback stops and starts before an old batch arrives | Old-run observations cannot affect the new run. |
| Telemetry storage overflows | Old observations may be omitted; audio remains independent and drop diagnostics increase. |

## Alternatives and consequences

Global revision equality is simpler but both hides valid unchanged atoms and
misattributes old-material events. Mapping by value or spelling is cheaper but
ambiguous for duplicate notes, references, and edits. A separate old-source view
would preserve more visual history but expands the interface; it is not selected.

Exact origin tracking requires preserving source identity through the real
playback path. Existing authoring provenance is a building block, not evidence
that every current transform already preserves the atom-level paths this UI
requires. Transform and reference coverage must be established before claiming
complete pattern-mode support. Do not implement a second approximate scheduler
in the UI to avoid that work.

## Scope

Deliver basic authoritative playback status and pattern-mode source highlighting.
Song-mode source highlighting, seeking, waveform/timeline displays, and voice
lifecycle visualization are excluded. Do not change existing playback entry,
restart, tempo, or last-good semantics to simplify the display. Public browser
observations expose only the data required by this feature, not mutable routing
or voice-pool internals.

Implementation has not started. The proposed split is a status change under
#156 and a dependent pattern-origin highlighting change; the latter includes
source mapping, telemetry, and editor behavior end to end.
