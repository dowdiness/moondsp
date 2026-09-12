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
