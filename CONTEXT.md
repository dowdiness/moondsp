# moondsp

Live coding keeps the score being edited distinct from the score accepted for playback and the material currently sounding.

## Language

**Live playback**:
The ongoing interaction in which a score can be played, edited while sounding, stopped, and played again. An invalid draft does not replace the accepted score.

**Draft score**:
The text and pattern/song mode currently selected for editing. It may change before a reply to an earlier submission arrives.

**Accepted score**:
The latest submitted score acknowledged for playback. Acceptance does not mean all of its materials have become audible at once; continuing edits take effect at each material's next entry.
_Avoid_: Applied score when referring only to acceptance

**Current diagnostic**:
A diagnostic belonging to the draft score currently being edited. A reply can establish an accepted score without being current enough to change the diagnostic.

**Playback run**:
One Play attempt, ending at Stop or audio failure. Replies belonging to an earlier run cannot change the next run.

**Tempo edit**:
Uncommitted text in the global tempo control. It may be incomplete and does not itself change playback.

**Requested tempo**:
A committed global tempo change submitted for playback. Being numerically valid does not guarantee that the current transport can represent it.

**Effective tempo**:
The tempo accepted by the audio runtime, at its 0.001-BPM precision. It can come from a global tempo request or an accepted song; rejection retains the previous effective tempo.

**Playback material**:
An independently cycling musical part (such as a pattern or track). When an accepted score adds, replaces, or removes a material, that change takes effect at the material's own entry boundary (e.g., the start of its cycle).
_Avoid_: Assuming all materials update at the same instant

**Material version**:
The specific source content active for one playback material. Because each material transitions at its own boundary, different materials can continue playing older versions after a newer score has been accepted.

**Pending material transition**:
An accepted addition, replacement, or removal waiting for its material's entry boundary to take effect. The pending count tracks affected musical materials, not score submissions or audio routes.
_Avoid_: Counting one material multiple times across separate output routes or subsequent draft edits

**Playback onset**:
The start of a musical event dispatched for playback that can be attributed to a specific source token, even when rendered with zero gain or muted. Rests and events excluded by pattern transformations (such as degradation) do not produce playback onsets.

**Estimated audible onset**:
The projected listener-time of a rendered event, mapped from audio-context time through `getOutputTimestamp()` when available; otherwise estimated using current time and reported base/output latency. Timestamp mapping already accounts for output timing: do not add latency twice. This is a visual estimate, not proof that the listener heard the event.

**Source atom**:
The smallest authored sound, note, or chord token attributable as the origin of a playback event. A chord name is treated as a single atom even though it expands into multiple notes.

**Source atom identity**:
The persistent identity of an authored atom across non-destructive edits, including offset shifts caused by edits elsewhere. Deleting and recreating an atom, including undo reinsertion, creates a new identity rather than continuing the old one.
_Avoid_: Relying on identical spelling or string matching to establish continuity

**Source frame**:
The persistent identity of an unchanged notation literal's complete content. It anchors local onset and pitch coordinates before enclosing expression transforms or Song placement. Editing literal content retires its frame even when individual atoms survive; those atoms may remain highlighted in code without claiming that old events match the edited diagram.

**Named pattern definition**:
A particular authored declaration of a reusable pattern. Its identity is distinct from both its name's spelling and the current contents of its body.

**Pattern reference**:
A particular occurrence of a pattern name used as an expression. Two references to the same definition are distinct occurrences.

**Reference binding**:
The continuously established relationship between a pattern reference and its definition. A broken or ambiguous relationship does not regain its former identity merely by reconnecting the same reference and definition later.

**Event origin**:
An event's source atom and route through named pattern references. It exists before playback and does not by itself identify a playback run or material version.

**Playback origin path**:
The authored provenance chain connecting a playback material to the source atom responsible for an event, tracing through any intermediate pattern references.

**Represented playback origin**:
An event origin whose source atom and reference path can be traced with exact identity into the currently visible draft. An origin remains represented across partial material transitions or when unrelated syntax errors exist in the draft.

**Playback highlight**:
A held indication of the latest dispatched onset group on represented source atoms, with traversed pattern references shown as secondary context. Simultaneous notes stay lit together until the next onset across the score; rests retain the preceding indication. Pause, run changes, and tab visibility changes clear it. It reflects event execution, not adoption of all visible draft edits, event duration, or voice lifetime.

**Superseded onset**:
A reported onset older than the latest due onset group. It is discarded rather than replayed late; delayed batches show only their newest due group.
