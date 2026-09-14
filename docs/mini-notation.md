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

## Syntax reference

This is the canonical syntax reference. The live app embeds the HTML block below
at build time; edit it here rather than maintaining a second copy in the app.
The HTML also renders directly in Markdown viewers without a Markdown parser
in the browser bundle.

<!-- LIVE_SYNTAX_REFERENCE_START -->
<h2 id="top-level-forms">Sounds</h2>
<dl>
  <dt>note("E4 G4")</dt><dd>note names or MIDI numbers</dd>
  <dt>chord("Am G")</dt><dd>chords</dd>
  <dt>s("bd hh sd hh")</dt><dd>drums: bd kick, sd snare, hh closed hat, oh open hat, cp clap</dd>
</dl>
<p class="cheat-note">Notes: <code>C4</code> = MIDI 60. Use <code>#</code> or <code>b</code> for accidentals; octave defaults to 4.</p>
<p class="cheat-note">Chords: <code>C</code> major, <code>Cm</code> minor; also <code>7</code>, <code>maj7</code>, <code>m7</code>, <code>dim</code>, <code>aug</code>, <code>sus2</code>, <code>sus4</code>, <code>6</code>, <code>add9</code>, <code>maj9</code>, <code>m9</code>. In <code>chord("C+7")</code>, the quoted <code>+</code> is part of the chord name, not an overlay.</p>

<h2 id="method-chains">Sound shape</h2>
<dl>
  <dt>.pan(n)</dt><dd>left −1, center 0, right 1</dd>
  <dt>.room(n)</dt><dd>send 0–1 into the shared room reverb</dd>
  <dt>.attack(s)</dt><dd>fade in over s seconds</dd>
  <dt>.hold(s)</dt><dd>stay at peak volume for s seconds</dd>
  <dt>.release(s)</dt><dd>fade out over s seconds</dd>
  <dt>.gate(n)</dt><dd>sound for n of each step, from 0 to 1</dd>
</dl>
<p><code>s("bd hh").slow(2) +<br>note("E4").slow(4).room(0.35)</code></p>
<p class="cheat-note"><code>.room(0)</code> is dry and is the default; <code>.room(1)</code> is the maximum send. Here the drums stay dry and the note sends at 0.35. Both keep their dry signal.</p>
<p class="cheat-note">Envelopes apply to notes and chords. Each time is in seconds, from 0 to 86400.</p>
<p><code>note("E4")<br>&nbsp;&nbsp;.attack(0.01).hold(0.1)<br>&nbsp;&nbsp;.release(0.2)</code></p>
<p class="cheat-note">0.31 seconds total, independent of tempo. Omit hold to follow the pattern's note length. Omitted attack/release use the sound's defaults; release starts from the current level.</p>
<p class="cheat-note"><code>.gate(0.4)</code> keeps every onset in place but shortens each note to 40% of its step, leaving the rest silent. The gate follows tempo. Factors finer than one billionth are rounded to keep long-running timelines representable. An explicit <code>.hold(s)</code> instead uses physical seconds and overrides the event-derived ending.</p>
<p class="cheat-note">Room is one shared stereo space for every part. Its tail continues across note endings, section changes, and live edits; Stop remains immediate.</p>
<p class="cheat-note"><strong>Browser limitation:</strong> <code>.gain(n)</code> and <code>.cutoff(hz)</code> are parsed as control values, but the current browser instruments do not connect them to volume or filter controls. They do not change the sound here.</p>

<h2>Rhythm</h2>
<p class="cheat-note">BPM sets cycles per minute: at 60, one cycle is one second. A cycle has no fixed meter.</p>
<dl>
  <dt>.fast(n)</dt><dd>n× faster</dd>
  <dt>.slow(n)</dt><dd>n× slower; explicit envelope seconds stay unchanged</dd>
  <dt>.rev()</dt><dd>reverse events within each cycle</dd>
  <dt>.degradeBy(p)</dt><dd>drop events with probability p (0–1)</dd>
  <dt>.every(n, f)</dt><dd>apply f every nth cycle</dd>
</dl>
<p class="cheat-note">Use positive integers for fast, slow, and every. Callback <code>f</code> is <code>fast(n)</code>, <code>slow(n)</code>, or <code>rev</code> without parentheses.</p>
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

<h2>Combine patterns</h2>
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
  <dt>bpm(n)</dt><dd>tempo inside song(); editable while playing</dd>
</dl>
<p class="cheat-note">Separate calls with commas. Section lengths and explicit starts accept integers or fractions such as <code>3/2</code>; section lengths must be positive. Pattern expressions inside sections support <code>+</code> and parentheses.</p>
<p class="cheat-note">Select <strong>Song</strong> mode to play a song. The header BPM control sets global tempo; <code>bpm(n)</code> sets it from the score. Examples select their mode and tempo for you.</p>
<!-- LIVE_SYNTAX_REFERENCE_END -->

## Additional notation examples

```text
s("bd(3,8), hh*16?, sd(2,8,2)")
s("[bd sd]*2 hh")
note("60(3,8) 64(2,8,2) 67(3,8)").slow(4)
note("C4(3,8) E4(2,8,2) G4(3,8)").slow(4)
chord("C Am F G7").slow(2)
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
