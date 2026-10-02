# Browser composition prior art

This note records first-party behavior used to scope the composition extension. `[Source]` describes the cited product documentation; `[Repo]` records moondsp **before** this extension; `[Decision]` records the resulting boundary. These products are precedents, not evidence that moondsp implements their full feature sets.

## Harmony: register is not voice leading

**Strudel.** `[Source]` Strudel's `chord(...).voicing()` selects among dictionary shapes to minimize jumps between successive chords; its documentation describes this as automated voice leading. The dictionary sets the available shapes. The `anchor` selects the vertical register by choosing the candidate whose top note is closest to the anchor (default `c5`); `mode` constrains the relation to it (`below`, `above`, `duck`, or `root`), and `offset` shifts voicing choice. Thus an anchor is a register constraint, not the voice-leading algorithm. Strudel's tonal functions additionally map scale-degree numbers through `scale(...)`, transpose in semitones or scale steps, and provide chord roots at a chosen octave. Sources: [Understanding Chords and Voicings](https://strudel.cc/understand/voicings/); [Tonal Functions](https://strudel.cc/learn/tonal/).

`[Repo]` The prior surface accepted authored pitches (`note("E4 G4")` or MIDI values) and chord symbols (`chord("Am G")`); octave defaults to 4 for note names without an octave. `[Decision]` Add authored scale-step transposition, lowest-simultaneous-tone projection, and bounded register voicing. This is not harmonic root detection or automatic voice leading: there is no dictionary, anchor, or optimization of inter-chord motion.

## Repeatable variation and live replacement

**Sonic Pi.** `[Source]` `use_random_seed` chooses the starting point of a deterministic pseudo-random stream: re-running with the same seed reproduces the same random sequence, while a changed seed gives a different one. `live_loop` supports named repeating processes; its official live-coding example changes a loop parameter and reruns code while sound continues. Sources: [Tutorial 4: Randomisation](https://sonic-pi.net/tutorial-04.html); [Appendix A, Tips for Sonic Pi](https://sonic-pi.net/tutorial-a.html).

**SuperCollider.** `[Source]` `Pdef` registers a named event-pattern definition that can be replaced while running. All streams referencing it observe replacement; the switch may be quantized or conditioned, and can crossfade when applicable synth definitions expose `amp`. `Pdefn` is the corresponding namespace for non-event/value patterns. Source: [Pdef class reference](https://doc.sccode.org/Classes/Pdef.html).

`[Repo]` moondsp degradation was already deterministic per event and seed, but Mini did not expose a user-selectable seed. Accepted score edits transitioned each affected playback material at its own entry boundary; a bad edit left the accepted score intact (see [CONTEXT.md](../../CONTEXT.md)). `[Decision]` Expose the optional integer seed in Mini and preserve song-coordinate choices through preview loops. This is not Sonic Pi's general random stream, and does not add pitch randomization, a freeze-to-literal export, or a global synchronized replacement mode.

## Performance launching and arrangement

**Ableton Live Clip View.** `[Source]` A clip's start/end delimit unlooped playback; its loop controls specify a separate loop position and length. Set buttons can capture start/end from the playhead, quantized by the global setting. The clip time-signature field is display-only, not a change to playback timing. These are clip-local controls, not an arrangement-wide loop across separate clips. Source: [Clip View, clip and loop region settings](https://www.ableton.com/en/manual/clip-view/#clip-and-loop-region-settings).

**Ableton Live Session View.** `[Source]` Session View is a grid for spontaneous/random-access clip launching, distinct from the fixed Arrangement timeline. Each track plays at most one Session clip at once; a scene is a row whose launch triggers its clips together. Clip quantization controls launch onset (including `None` for no quantization); launch modes include Trigger, Gate, Toggle, and Repeat. Arrangement clips instead play at their timeline positions. Sources: [Session View](https://www.ableton.com/en/manual/session-view/); [Launching Clips](https://www.ableton.com/en/manual/launching-clips/).

`[Repo]` moondsp `song(...)` already authored ordered/placed sections: `section(name, cycles, pattern)`, `part(id, section[, absolute_cycle])`, optional `fill(...)`, and song BPM. `[Decision]` Add accepted-arrangement seek and half-open range loop across sections, not a Session grid, per-track clip launcher, or bar-number/time-signature conversion. User-triggered preview restarts at the selected cycle; routine accepted source edits keep their existing material entry-boundary policy.
