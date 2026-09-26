# Mini notation

`mini/` parses compact text patterns into `Pat[ControlMap]` for the
scheduler and browser live-coding surface. Mini owns event timing and numeric
controls, not DSP graph topology; see
[`mini-graph-authoring-boundary.md`](mini-graph-authoring-boundary.md) for the
contract that bridges Mini events into graph templates. Production parsing is
still the hand-written MoonBit parser; the loom CST work remains an evaluation
path under `specs/loom-mini-cst/`.

## Browser live examples

In the live app's **Examples** panel, select an example and press **Play**:

- [Overlay groove](../examples/overlay-groove.mini) layers drums, bass, and
  stereo melodies with `+`; a parenthesized `.slow(2)` affects both melodies.
- [Grouping A/B](../examples/overlay-grouping.mini) plays `kick + hats.fast(2)`
  followed by `(kick + hats).fast(2)`: hear only the hats speed up, then both
  layers. The two sections last 20 seconds in total at BPM 96.
- [Space in the groove](../examples/rests-and-gates.mini) combines `~` rests
  with two gate lengths so the pulse stays fixed while notes leave audible room.
- [Paper Lanterns](../examples/section-composition.mini) is a 56-second song
  with shared harmony, scale-step variations, onset masks, and a rewritten cadence.

## Syntax reference

This is the canonical syntax reference. The live app embeds the HTML block below
at build time; edit it here rather than maintaining a second copy in the app.
The HTML also renders directly in Markdown viewers without a Markdown parser
in the browser bundle.

<!-- LIVE_SYNTAX_REFERENCE_START -->
<p>Look up syntax here; follow <a href="guides/live-coding-cookbook.md">Recipes</a> to build a musical idea, or <a href="guides/live-playback.md">How playback works</a> for timing and live edits. A trailing <code>?</code> in a method signature marks an optional argument; do not type that question mark.</p>
<h2 id="top-level-forms">Sounds</h2>
<dl>
  <dt>note("E4 G4")</dt><dd>note names or MIDI numbers</dd>
  <dt>chord("Am G")</dt><dd>chords</dd>
  <dt>s("bd hh sd hh")</dt><dd>drums: bd kick, sd snare, hh closed hat, oh open hat, cp clap</dd>
</dl>
<p class="cheat-note">Notes: <code>C4</code> = MIDI 60. Use <code>#</code> or <code>b</code> for accidentals; octave defaults to 4.</p>
<p class="cheat-note">Chords: <code>C</code> major, <code>Cm</code> minor; also <code>7</code>, <code>maj7</code>, <code>m7</code>, <code>dim</code>, <code>aug</code>, <code>sus2</code>, <code>sus4</code>, <code>6</code>, <code>add9</code>, <code>maj9</code>, <code>m9</code>. In <code>chord("C+7")</code>, the quoted <code>+</code> is part of the chord name, not an overlay.</p>

<h2 id="method-chains">Sound shape</h2>
<p class="cheat-note">Shape browser notes and chords with filters: LPF softens high frequencies, while HPF clears low frequencies. Add the optional second argument to emphasize the cutoff frequency.</p>
<dl>
  <dt>.pan(n)</dt><dd>left −1, center 0, right 1</dd>
  <dt>.room(n)</dt><dd>send 0–1 into the shared room reverb</dd>
  <dt>.attack(s)</dt><dd>fade in over s seconds</dd>
  <dt>.hold(s)</dt><dd>stay at peak volume for s seconds</dd>
  <dt>.release(s)</dt><dd>fade out over s seconds</dd>
  <dt>.gate(n)</dt><dd>sound for n of each step, from 0 to 1</dd>
  <dt>.gain(n)</dt><dd>note/chord level; 0 is silent, 1 keeps the template level</dd>
  <dt>.lpf(hz, resonance?)</dt><dd>reduce frequencies above hz; resonance/Q must be finite and greater than 0 (default 0.707)</dd>
  <dt>.hpf(hz, resonance?)</dt><dd>reduce frequencies below hz; resonance/Q must be finite and greater than 0 (default 0.707)</dd>
</dl>
<p><code>s("bd hh").slow(2) +<br>note("E4").slow(4).gain(0.6).lpf(1800, 2).hpf(80).room(0.35)</code></p>
<p class="cheat-note">Resonance is the filter Q: it defaults to <code>0.707</code> when omitted and must be finite and above 0. Higher values create a stronger peak around the cutoff frequency.</p>
<p class="cheat-note"><code>.room(0)</code> is dry and is the default; <code>.room(1)</code> is the maximum send. Here the drums stay dry and the note sends at 0.35. Both keep their dry signal.</p>
<p class="cheat-note">Envelopes apply to notes and chords. Each time is in seconds, from 0 to 86400.</p>
<p><code>note("E4")<br>&nbsp;&nbsp;.attack(0.01).hold(0.1)<br>&nbsp;&nbsp;.release(0.2)</code></p>
<p class="cheat-note">0.31 seconds total, independent of tempo. Omit hold to follow the pattern's note length. Omitted attack/release use the sound's defaults; release starts from the current level.</p>
<p class="cheat-note"><code>.gate(0.4)</code> keeps every onset in place but shortens each note to 40% of its step, leaving the rest silent. <code>.gate(0)</code> is silent; <code>.gate(1)</code> keeps the full step. The gate follows tempo. Factors finer than one billionth are rounded to keep long-running timelines representable. An explicit <code>.hold(s)</code> instead uses physical seconds and overrides the event-derived ending.</p>
<p class="cheat-note">Room is one shared stereo space for every part. Its tail continues across note endings, section changes, and live edits. See <a href="guides/live-playback.md#playback-preview">preview and seek behavior</a> for how navigation affects tails.</p>
<p class="cheat-note"><code>.gain(n)</code>, <code>.lpf(hz, resonance?)</code>, and <code>.hpf(hz, resonance?)</code> control note and chord voices in the browser. Drum templates keep their authored level and filter shape; applying these controls to <code>s("...")</code> leaves the drum sound unchanged.</p>

<h2 id="rhythm">Rhythm</h2>
<p class="cheat-note">BPM sets cycles per minute, not beats in a fixed meter. See <a href="guides/live-playback.md#playback-time">cycles, phrase periods, and seconds</a>.</p>
<dl>
  <dt>.fast(n)</dt><dd>n× faster</dd>
  <dt>.slow(n)</dt><dd>n× slower; explicit envelope seconds stay unchanged</dd>
  <dt>.rev()</dt><dd>reverse events within each cycle</dd>
  <dt>.every(n, f)</dt><dd>apply f every nth cycle</dd>
</dl>
<p class="cheat-note">Use positive integers for fast, slow, and every. Callback <code>f</code> is <code>fast(n)</code>, <code>slow(n)</code>, or <code>rev</code> without parentheses.</p>

<h2 id="harmony-and-voicing">Harmony and voicing</h2>
<dl>
  <dt>.lowest()</dt><dd>keep the lowest simultaneous note at each onset; this is not harmonic root detection</dd>
  <dt>.voicing(low, high, count?)</dt><dd>move tones by octaves into an inclusive MIDI range; omit count to keep all fitting tones, or supply a count to keep only the lowest tones</dd>
</dl>
<p><code>let changes = chord("Cmaj7 Am7 Fmaj7 G7").slow(16);<br>stack(changes.lowest().transpose(-24),<br>&nbsp;&nbsp;changes.voicing(60, 83, 3))</code></p>
<p class="cheat-note">For <code>.voicing(60, 83)</code>, no fitting tone is removed by a count limit. Tones with no octave in the range are dropped; count 0 is silent. Voicing folds octaves, not voice-leading between chords.</p>
<p class="cheat-note">Applied to <code>stack(...)</code>, both methods compare notes across layers. The projection plays and updates as one material.</p>

<h2 id="pitch-and-phrase-variations">Pitch and phrase variations</h2>
<dl>
  <dt>.transpose(n)</dt><dd>move note pitches by n semitones; negative values move down</dd>
  <dt>.steps(scale, n)</dt><dd>move by n scale degrees; supply ascending, unique pitch classes such as "C D E F G A B"; negative values move down</dd>
  <dt>.phase(transpose(n), from, to?)</dt><dd>transpose only notes starting within [from, to) of each entry period; to defaults to 1; requires 0 ≤ from &lt; to ≤ 1</dd>
  <dt>.tail(replacement, cycles?)</dt><dd>replace the final cycles of every entry period; cycles defaults to 1; stretch the replacement to fit without changing the entry period</dd>
</dl>
<p><code>note("C4 E4 G4 A4").slow(8)<br>&nbsp;&nbsp;.steps("C D E F G A B", 1)<br>&nbsp;&nbsp;.phase(transpose(12), 0.5)</code></p>
<p class="cheat-note">The last line changes the latter half of each eight-cycle phrase. For just the middle half, use <code>.phase(transpose(12), 0.25, 0.75)</code>. Only <code>transpose(n)</code> is accepted inside phase. Notes that begin outside the interval keep their pitch even if they extend into it. These fractions are relative to the entry period, not absolute song positions.</p>
<p><code>note("E4 G4 A4 B4").slow(8)<br>&nbsp;&nbsp;.tail(note("G4 E4 D4 C4"), 2)<br>&nbsp;&nbsp;.gain(0.12).release(0.2)</code></p>
<p class="cheat-note">Tail accepts a direct <code>note("...")</code>, <code>chord("...")</code>, or <code>s("...")</code>, not a named pattern or a chained expression. Its duration must be positive and no longer than the entry period. A half-cycle phrase needs an explicit duration, for example <code>note("C4").fast(2).tail(note("E4"), 0.5)</code>; the default 1 would be rejected. Put gain, envelope, and filter controls after tail to apply them to replacement notes too.</p>

<h2 id="onset-masks-and-seeds">Onset masks and seeded variation</h2>
<dl>
  <dt>.mask("x ~ x x")</dt><dd>divide the entry period into equal slots; x keeps existing onsets, ~ removes them; never creates new onsets</dd>
  <dt>.degradeBy(p, seed?)</dt><dd>drop events with probability p from 0 to 1; an optional integer seed selects a repeatable version</dd>
</dl>
<p><code>note("C4 E4 G4 B4").mask("x ~ x ~")</code></p>
<p class="cheat-note">Only C4 and G4 remain. The mask repeats over the pattern's entry period; it does not retrigger a sustained chord.</p>
<p><code>s("hh*8").slow(4).degradeBy(0.22, 119)</code></p>
<p class="cheat-note">Keep the same source and seed for the same per-event choices across restarts and loop passes. Change the seed to try another version. In <strong>Paper Lanterns</strong>, these gaps stay fixed while the melody and arrangement change.</p>

<h2 id="inside-quoted-notation">Inside quoted notation</h2>
<dl>
  <dt>a b c</dt><dd>sequence in one cycle; newlines also separate items</dd>
  <dt>~</dt><dd>rest: reserve one sequence step without emitting an event</dd>
  <dt>[a b]</dt><dd>subdivide a step</dd>
  <dt>a, b</dt><dd>play together</dd>
  <dt>a*4</dt><dd>repeat 4× faster</dd>
  <dt>a/2</dt><dd>stretch 2× slower</dd>
  <dt>a?</dt><dd>50% chance to drop</dd>
  <dt>a(3,8)</dt><dd>3 hits across 8 steps; a(3,8,1) adds rotation</dd>
</dl>
<p><code>$: s("bd ~ sd ~")<br>$: note("C3 ~ Eb3 ~").gate(0.35)</code></p>
<p class="cheat-note">Each <code>~</code> occupies the same share of the cycle as a sounding atom. Gate shortens only the sounding part; neither feature moves the following onset. Hear both in <strong>Space in the groove</strong>.</p>

<h2 id="combine-patterns">Combine patterns</h2>
<dl>
  <dt>let a = p;</dt><dd>name a reusable pattern; define it before use</dd>
  <dt>a + b + c</dt><dd>overlay layers in left-to-right order; duplicates are preserved</dd>
  <dt>stack(a, b)</dt><dd>the explicit form of a + b</dd>
  <dt>a + b.fast(2)</dt><dd>speed up only b; method chains bind before +</dd>
  <dt>(a + b).fast(2)</dt><dd>speed up both layers; parentheses group the expression</dd>
  <dt>$: a<br>$: b</dt><dd>combine top-level layers on separate lines</dd>
  <dt>.jux(f)</dt><dd>original left, transformed copy right</dd>
</dl>
<p><code>s("bd") + s("hh").fast(2)</code></p>
<p><code>(s("bd") + s("hh")).fast(2)</code></p>
<p class="cheat-note">Hear the difference in the <strong>Grouping A/B</strong> example. Grouping also works with slow, rev, and other method chains.</p>
<p class="cheat-note"><code>+</code> works in named definitions, <code>$:</code> lines, and song sections. Ordinary newlines do not combine expressions: use <code>+</code>, <code>stack</code>, or a <code>$:</code> prefix on each top-level layer. Inside quoted notation, use commas to overlay items.</p>
<p class="cheat-note">Define names with <code>let</code> before using them and keep them stable during live edits. Overlay adds events, not their control values.</p>

<h2 id="song-placement">Song structure</h2>
<dl>
  <dt>song(…)</dt><dd>sections and their playback order</dd>
  <dt>section("a", n, p)</dt><dd>name a section lasting n cycles</dd>
  <dt>part("id", "a")</dt><dd>append after the latest end of all preceding parts; use a unique part id</dd>
  <dt>part("id", "a", 8)</dt><dd>place the part at absolute cycle 8; overlapping parts play together</dd>
  <dt>part_id("id", "label", "a")</dt><dd>keep a stable id separate from its display label; optional start as the fourth argument</dd>
  <dt>fill("gap", "a")</dt><dd>fill uncovered time between parts with section a</dd>
  <dt>bpm(n)</dt><dd>tempo in cycles per minute inside song(); use bpm(n); before a standalone pattern; defaults to 60</dd>
</dl>
<p class="cheat-note">Separate calls with commas. Section lengths and explicit starts accept integers or fractions such as <code>3/2</code>; section lengths must be positive. Pattern expressions inside sections support <code>+</code> and parentheses.</p>
<p class="cheat-note">The app recognizes <code>song(...)</code> automatically. Use <code>bpm(n)</code> inside the song to set its tempo; omission uses 60 BPM.</p>

<p>To audition an arrangement, see <a href="guides/live-playback.md#playback-preview">section and range preview</a>. For update timing and structural changes, see <a href="guides/live-playback.md#playback-edits">editing while playing</a>.</p>
<!-- LIVE_SYNTAX_REFERENCE_END -->

## Additional notation examples

```text
s("bd(3,8), hh*16?, sd(2,8,2)")
s("[bd sd]*2 hh")
note("60(3,8) 64(2,8,2) 67(3,8)").slow(4)
note("C4(3,8) E4(2,8,2) G4(3,8)").slow(4)
chord("C Am F G7").slow(2)
s("bd ~ sd ~")
note("C3 ~ C3 Eb3 ~ G2 Bb2 ~").gate(0.35)
note("C3 E3 G3").gain(0.6).lpf(1800, 2).hpf(80)
```

`note(...)` accepts names such as `C4`, `F#3`, and `Bb`; omitted octaves
default to 4. `chord(...)` accepts common chord names such as `C`, `Dm`,
`G7`, `F#m7`, `Bb`, `Cmaj7`, `C+`, `Cø7`, and `Esus4`. Each chord atom lowers
to a stack of note events at the same time position; space-separated chord
names are sequenced like other quoted mini atoms.

Chord quality compatibility is intentionally conservative. The stable spellings
are the plain triad (`C`), `m`, `7`, `maj7`, `m7`, `dim`, `dim7`, `aug`, `sus2`,
`sus4`, `7sus4`, `6`, `m6`, `9`, `maj9`, `m9`, `add9`, and `m7b5`. Convenience
aliases such as `min`, `min7`, `min9`, `M7`, `M9`, `+`, `+7`, `ø`, `ø7`,
`mMaj7`, and `mM7` are supported for authoring ergonomics but should be treated
as aliases rather than separate semantic forms. Unsupported qualities are parse
errors instead of guessed chord names.

## Source identity

Parentheses group expressions without adding a source node. Regrouping a raw
overlay preserves known material content and playback clocks; source ancestry
still reflects the authored grouping. See [Pattern algebra](pattern-algebra.md)
for the distinction between material content and source identity.
