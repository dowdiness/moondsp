# Playback position UI

Status: future goal. No implementation is scheduled by this document.

## Goal

Make the current playback position visible so composers can understand where
music is playing and audition a passage without replaying the whole song.

The UI must distinguish four separate playback dimensions:
1. Current playback state (e.g., playing vs. stopped).
2. Engine-reported playback position.
3. Acceptance status of edited scores (submitted, accepted, or rejected).
4. Pending material transitions waiting for their entry boundaries.

Accepting a score does not imply that all materials immediately adopt the new
source, because each material transitions at its own boundary. Conversely, a
syntax or evaluation error in the draft score must never lead the UI to claim
that rejected edits are currently playing.

[ADR-0018](../decisions/0018-playback-visualization-origin-truth.md) defines the
proposed contract for status reporting and pattern-onset source highlighting.
Under its source-identity model, unchanged tokens can continue highlighting
during partial material transitions or in the presence of unrelated syntax
errors. Seeking and song-mode source highlighting remain outside that proposal;
the broader navigation questions below remain open.

## Design questions

- Choose a useful position display for both finite songs and repeating patterns.
  Consider sections, elapsed time, and musical time without assuming every
  pattern shares one bar length.
- Define where Play starts after Stop, and how returning to the beginning works.
- Decide how users select a section or position to audition.
- Define seek behavior for sustained notes, automation, and effect tails before
  adding position controls. Display the audio engine's reported position.

Button layout, shortcuts, and stop/resume behavior remain undecided. The current
playback-control cleanup does not include a timeline, seeking, or new transport
semantics. Validate the future UI with a long song and overlapping patterns of
unequal lengths.

## Reference

DAWs distinguish transport state from start-position selection, with different
stop and resume policies. See the official manuals for
[Ableton Live](https://www.ableton.com/en/live-manual/12/arrangement-view/),
[Logic Pro](https://support.apple.com/guide/logicpro/playback-and-navigation-lgcp9ede81be/mac),
[Cubase](https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/playback/playback_transport_menu_functions_r.html),
and [FL Studio](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/toolbar_panels.htm).
