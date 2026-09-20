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
An independently cycling musical contribution whose accepted replacement, addition, or removal takes effect at its own entry boundary.

**Material version**:
The source content retained for one playback material. Different materials can still use older versions after a newer score has been accepted.

**Pending material transition**:
An accepted addition, replacement, or removal waiting for its material's entry boundary. The pending material count counts affected musical materials, not score submissions or audio routes.

**Playback onset**:
The start of a source-attributable musical event dispatched for playback, even when its rendering is silent. Rests and events excluded by pattern transformations have no playback onset.

**Estimated audible onset**:
The projected listener-time of a rendered event after accounting for output latency. It is a synchronization estimate, not proof that the event produced audible sound.

**Source atom**:
The smallest authored sound, note, or chord token attributable as the origin of a playback event. A chord name is one atom even when it produces several notes.

**Source atom identity**:
The continuity of one authored atom across position-only edits and unrelated edits. Equivalent spelling after deletion and recreation does not establish continuity.

**Playback origin path**:
The authored path from a playback material through named-reference use sites to the source atom responsible for an event.

**Represented playback origin**:
An event origin whose atom and reference-use identities can be traced exactly into the visible draft. An origin can remain represented across partial material transitions or an unrelated syntax error.

**Playback highlight**:
A brief onset indication on a represented source atom, with named-reference use sites as secondary context. It describes event execution, not adoption of all visible edits, event duration, or voice lifetime.

**Expired onset**:
A reported onset whose full highlight interval has already elapsed at the estimated listener-time. It is historical activity, not current playback activity.
