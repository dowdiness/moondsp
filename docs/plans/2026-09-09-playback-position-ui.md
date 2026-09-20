# Playback position UI

Status: future goal. No implementation is scheduled by this document.

## Goal

Make the current playback position visible so composers can understand where
music is playing and audition a passage without replaying the whole song.

The UI should distinguish playback state, playback position, acceptance of an
edited score, and pending material transitions. Acceptance does not mean all
materials are using the new source. A code error must not make the display claim
that rejected edits are playing.

[ADR-0018](../decisions/0018-playback-visualization-origin-truth.md) records the
proposed basic-status and pattern-onset highlighting contract. Its source
identity rules permit highlighting unchanged atoms during partial transitions
and unrelated syntax errors. Seeking and song-mode source highlighting remain
outside that proposal; the broader navigation questions below are still open.

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
