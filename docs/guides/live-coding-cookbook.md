# Live-coding cookbook

Build a beat, add notes, and turn the loop into a song. All examples work in
the moondsp browser editor. See the
[Mini notation reference](../mini-notation.md) for the full syntax.

## Start the editor

```bash
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
./playwright-sync-wasm.sh
cd web/live
npm ci
npm run dev
```

Open <http://localhost:5180> and press **Play**. The editor detects
`song(...)` automatically; otherwise it runs a single pattern. If the port
is busy, Vite prints another URL.

At 60 BPM, one cycle lasts one second. At 120 BPM, it lasts half a second.
A cycle is a unit of time, not a fixed bar or beat.

> `.pan()`, `.room()`, `.attack()`, `.hold()`, `.release()`, and `.gate()` work
> with the browser instruments. `.gain()`, `.lpf(hz, resonance?)`, and
> `.hpf(hz, resonance?)` shape note and chord voices; each optional resonance
> value controls that filter's Q. Drum templates keep their authored level and
> filter shape.

## Make a beat

One kick per cycle:

```mini
s("bd")
```

Four kicks per cycle:

```mini
s("bd*4")
```

A simple drum pattern:

```mini
s("bd hh sd hh")
```

Available drums:

| Name | Sound |
|---|---|
| `bd` | kick |
| `sd` | snare |
| `cp` | clap |
| `hh` | closed hi-hat |
| `oh` | open hi-hat |

Square brackets split one step into smaller steps:

```mini
s("bd sd [hh hh] sd")
```

A comma plays patterns together:

```mini
s("bd sd, hh*8")
```

`?` gives an event a 50% chance to play:

```mini
s("bd sd, hh*8?")
```

Use `.degradeBy(p)` for another drop rate:

```mini
s("bd sd, hh*8").degradeBy(0.2)
```

## Change the speed

```mini
s("bd hh sd hh").fast(2)
```

```mini
s("bd hh sd hh").slow(4)
```

Inside the quotes, `*n` repeats one item and `/n` stretches one item:

```mini
s("bd*4 sd/2")
```

Apply a change every few cycles:

```mini
s("bd*4").every(3, fast(2))
```

```mini
s("bd hh sd hh").every(4, rev)
```

Use `.rev()` to reverse every cycle:

```mini
s("bd hh sd hh").rev()
```

## Make a Euclidean rhythm

`sound(k,n)` spreads `k` hits across `n` steps:

```mini
s("bd(3,8)")
```

A third number rotates the rhythm:

```mini
s("sd(2,8,2)")
```

Combine several rhythms:

```mini
s("bd(3,8), hh(5,8), sd(2,8,2)")
```

For longer independent cycles, name each layer:

```mini
let three = s("bd(3,8)").slow(3);
let five = s("hh(5,8)").slow(5);
three + five
```

The two layers keep their own clocks.

## Add notes and chords

`note()` accepts note names or MIDI numbers:

```mini
note("C4 E4 G4 C5")
```

```mini
note("60 64 67 72")
```

`chord()` accepts common chord names:

```mini
chord("C Am F G7").slow(4)
```

Layer drums, bass, and chords with `+`:

```mini
let drums = s("bd hh sd hh").slow(4);
let bass = note("C2 C2 A1 G1").slow(4);
let chords = chord("C Am F G7").slow(4);
drums + bass + chords
```

`+` is the short form of `stack(drums, bass, chords)`.

Method calls bind before `+`:

```mini
s("bd") + s("hh").fast(2)
```

This speeds up only the hi-hat. Add parentheses to speed up both layers:

```mini
(s("bd") + s("hh")).fast(2)
```

Hear the difference in
[`overlay-grouping.mini`](../../examples/overlay-grouping.mini).

## Shape the sound

Envelope times are seconds. They do not change with tempo.

```mini
note("E4 G4 D4")
  .slow(21)
  .attack(2)
  .hold(3)
  .release(8)
```

Pan from left (`-1`) to right (`1`):

```mini
let melody = note("E4 G4 A4 C5").slow(4);
melody.pan(-0.45) + melody.rev().pan(0.45)
```

`.jux(f)` puts the original on the left and a changed copy on the right:

```mini
note("C4 E4 G4").jux(rev)
```

Send sound to the shared room reverb. `0` is dry and `1` is the largest send:

```mini
let drums = s("bd sd hh sd").slow(4).room(0.2);
let chords = chord("Cmaj9 Am7 Fmaj9 G6").slow(8).room(0.7);
drums + chords
```

Compare dry and wet versions in
[`shared-room-comparison.mini`](../../examples/shared-room-comparison.mini).

## Build a song

Write a `song(...)` expression in the editor:

```mini-song
let beat = s("bd hh sd hh").slow(4);
let bass = note("C2 C2 A1 G1").slow(4);
let chords = chord("C Am F G7").slow(4);
let lead = note("E4 G4 A4 G4").slow(4).jux(rev);

song(
  bpm(96),
  section("intro", 8, chords),
  section("groove", 16, beat + bass + chords),
  section("full", 16, beat + bass + chords + lead),
  part("intro-1", "intro"),
  part("groove-1", "groove"),
  part("full-1", "full")
)
```

`section(name, cycles, pattern)` defines music. `part(id, section)` places each
section in order. Keep every part ID unique.

For a larger song, read
[`light-orbit.mini`](../../examples/light-orbit.mini).

## Compose, vary, and preview sections

Build harmony once, then keep different chord tones and onsets in each layer.
The same four-cycle progression is reused by the bass and upper voicing.

```mini-song
let changes = chord("C Am F G").slow(4);
let bass = changes.lowest().transpose(-12).mask("x ~ x ~").gain(0.28);
let harmony = changes.voicing(48, 79).mask("x ~ x x").gain(0.12);
let motif = note("E4 G4 A4 G4").slow(4).gain(0.16);
let beat = s("bd hh sd hh").degradeBy(0.2, 119);
song(
  bpm(120),
  section("theme", 4, stack(bass, harmony, motif, beat)),
  section("variation", 4, stack(bass, harmony,
    motif.steps("C D E F G A B", 1).phase(transpose(2), 0.5), beat)),
  section("interlude", 4, stack(harmony, motif.tail(note("C5")), s("hh ~ hh ~"))),
  section("return", 4, stack(bass, harmony, motif, beat)),
  part("theme", "theme"),
  part("variation", "variation"),
  part("interlude", "interlude"),
  part("reprise", "return")
)
```

Choose **Paper Lanterns — composed variations** in Examples for the
[56-second song](../../examples/section-composition.mini) built from these
techniques. Its 16-cycle progression supplies the bass and chord voices.
The variation moves the motif up two scale degrees, then drops its last
quarter an octave. The interlude removes the bass and kick/snare, leaving
masked high echoes; the return rewrites the final four cycles into a C-major
cadence. Edit the `degradeBy` seed to choose a different hi-hat version.

Press **Restart** to accept the arrangement.
**Play from here** seeks to a section boundary;
**Loop section** repeats that section; the Start/End fields loop any
half-open cycle range, including one crossing sections; **Whole song** clears
the preview and starts from zero. Controls use the accepted song, not an
invalid or pending draft. Section buttons retain exact fraction boundaries;
numeric fields accept 0.001-cycle steps. Seeking clears active voices and
room tails; natural loop wrap lets them decay.

The cycle is the timeline unit: at 120 BPM, four cycles take two seconds.
There is no time-signature/bar-number mapping. `.phase(transpose(2), 0.5)`
changes onsets in the latter half of the motif's four-cycle period; a
note crossing the midpoint keeps its original pitch. The optional `to`
boundary defaults to 1; only `transpose(n)` is accepted here.
`.tail(note("C5"))` replaces the final cycle; a period shorter than one
cycle needs an explicit shorter duration, as in `.tail(note("C5"), 0.5)`.
Its replacement must be a direct note, chord, or sound literal.
`.transpose(n)` moves chromatically by semitones; `.steps(scale, n)` uses
the supplied ascending pitch classes. `.lowest()` chooses the lowest
simultaneous tone, not necessarily the harmonic root.
`.voicing(low, high, count?)` folds chord tones by octaves into an inclusive
MIDI range; omission keeps every fitting tone, while an explicit count
keeps only the lowest tones.

Applied to `stack(...)`, `.lowest()` selects and `.voicing(...)` ranks
tones across all layers at each onset. These projections form one playback
material, so edits to the grouped layers enter together.

`.degradeBy(probability, seed)` uses stable per-event decisions: the same
accepted source, musical position, and seed produce the same hits across
restarts, seeks, loop passes, and tempo changes. To fix a chosen version,
keep its seed and accepted source; changing either can change the result.
There is no export-to-literal freeze operation. Drums retain independent
pattern rhythm; `.mask("x ~ x x")` filters source onsets rather than
retriggering missed notes. Note/chord gain can emphasize chosen attacks;
dedicated meter, swing, accent, and continuous automation syntax is not part of this
composition path. Source edits remain quantized at existing material entry
boundaries rather than a new global immediate-update mode.

| Scope | Available authoring or control |
|---|---|
| Already present | Named song sections and parts, shared `let` patterns, chord symbols, independent pattern periods, event-seeded dropout, per-material live edits |
| Extended | Accepted-section seek, cross-section range loop, explicit dropout seed, signed pitch and scale-degree moves |
| New | Lowest-tone/register extraction, onset masks, motif phase transform and tail replacement, composition demo and browser controls |

## Recipes

The live app embeds the HTML block below at build time. Each recipe loads a
complete, runnable pattern into the editor.

<!-- LIVE_RECIPES_START -->
<p class="recipe-scope">Loading a recipe replaces the editor. Undo restores the previous code. Loading while playing submits a live edit; press <strong>Restart</strong> to hear the source from the beginning. Recipes do not autoplay.</p>

<details class="recipe" id="recipe-shared-voicing">
<summary>Share one chord progression between bass and upper voices</summary>
<p>Write the progression once, then derive a sub-bass line and a register-folded voicing from it. You hear a low root on each change and a compact cluster above, both locked to the same harmony.</p>
<pre><code id="recipe-shared-voicing-code">let changes = chord("Cmaj7 Am7 Fmaj7 G7").slow(16);
let bass = changes.lowest().transpose(-24).gain(0.22).lpf(650).attack(0.008).hold(0.22).release(0.18);
let harmony = changes.voicing(60, 83, 3).gain(0.08).lpf(1800).attack(0.12).hold(0.35).release(0.65).room(0.18);
let beat = s("bd hh sd hh").slow(4);

song(
  bpm(120),
  section("groove", 16, stack(bass, harmony, beat)),
  part("groove-1", "groove")
)</code></pre>
<button type="button" class="example" data-recipe="recipe-shared-voicing">Load shared voicing</button>
<p>Edit <code>voicing(60, 83, 3)</code> to <code>voicing(48, 71)</code> to lower the upper voices by an octave and keep all four fitting tones instead of three. The bass stays unchanged because it reads the same progression independently.</p>
<p>Related: <a href="../mini-notation.md#harmony-and-voicing">Harmony and voicing</a> · <a href="../mini-notation.md#song-placement">Song structure</a> · <a href="live-playback.md#playback-edits">Edits while playing</a></p>
</details>

<details class="recipe" id="recipe-motif-tail">
<summary>Vary a motif and end on a cadence</summary>
<p>Hear the original motif, a response shifted up two scale degrees with another two-semitone lift in its second half, then the original with a descending final cycle. Put sound controls after <code>.tail()</code> so the replacement has the same timbre.</p>
<pre><code id="recipe-motif-tail-code">let motif = note("E4 G4 A4 G4").slow(4);
let statement = motif.gain(0.14).attack(0.008).hold(0.10).release(0.22);
let varied = motif.steps("C D E F G A B", 2).phase(transpose(2), 0.5).gain(0.14).attack(0.008).hold(0.10).release(0.22);
let cadence = motif.tail(note("G4 E4 D4 C4"), 1).gain(0.14).attack(0.008).hold(0.10).release(0.22);

song(
  bpm(120),
  section("statement", 4, statement),
  section("response", 4, varied),
  section("close", 4, cadence),
  part("a", "statement"),
  part("b", "response"),
  part("c", "close")
)</code></pre>
<button type="button" class="example" data-recipe="recipe-motif-tail">Load motif and cadence</button>
<p>Change <code>.phase(transpose(2), 0.5)</code> to <code>.phase(transpose(2), 0.25, 0.75)</code> to apply the extra semitone shift only in the middle half. Notes outside that window still receive the earlier scale-degree shift.</p>
<p>Related: <a href="../mini-notation.md#pitch-and-phrase-variations">Pitch and phrase variations</a> · <a href="live-playback.md#playback-preview">Preview controls</a></p>
</details>

<details class="recipe" id="recipe-sparse-rhythm">
<summary>Keep a sparse, repeatable rhythm with masks and seeds</summary>
<p>Use <code>.mask()</code> to drop specific onsets and <code>.degradeBy(p, seed)</code> to thin a pattern with a fixed random version. Keep the source and seed unchanged for the same hits across restarts and loop passes.</p>
<pre><code id="recipe-sparse-rhythm-code">let kick = s("bd ~ bd ~ bd bd ~ ~").slow(4);
let hats = s("hh*8").slow(4).degradeBy(0.35, 7);
let snare = s("sd ~ sd ~").slow(4).mask("x ~ ~ ~");

song(
  bpm(120),
  section("groove", 8, stack(kick, hats, snare)),
  part("groove-1", "groove")
)</code></pre>
<button type="button" class="example" data-recipe="recipe-sparse-rhythm">Load sparse rhythm</button>
<p>Change the seed in <code>degradeBy(0.35, 7)</code> to <code>degradeBy(0.35, 19)</code> and press Restart to compare hat versions. The kick and masked snare stay fixed; neither uses random drops.</p>
<p>Related: <a href="../mini-notation.md#onset-masks-and-seeds">Onset masks and seeded variation</a> · <a href="../mini-notation.md#inside-quoted-notation">Inside quoted notation</a> · <a href="live-playback.md#playback-transport">Transport</a></p>
</details>

<details class="recipe" id="recipe-space-timbre">
<summary>Shape space and timbre with envelopes, gates, filters, and room</summary>
<p>Envelope times are seconds and do not follow tempo. <code>.gate()</code> shortens each note within its step. <code>.lpf()</code> and <code>.hpf()</code> soften or clear frequencies; <code>.room()</code> sends into the shared reverb. Drums keep their authored level and filter shape — <code>.gain()</code>, <code>.lpf()</code>, and <code>.hpf()</code> do not change <code>s("...")</code>.</p>
<pre><code id="recipe-space-timbre-code">let drums = s("bd ~ sd ~").slow(2).room(0.15);
let bass = note("C2 ~ C2 Eb2").slow(4).gate(0.35).lpf(520).gain(0.22).attack(0.005).release(0.16);
let pad = chord("Cm7 Abmaj7").slow(8).attack(0.6).hold(0.4).release(2.0).gain(0.06).lpf(1400).room(0.55);
let bell = note("G5 ~ Eb5 ~").slow(4).attack(0.01).hold(0.04).release(0.5).gain(0.05).hpf(2200).room(0.75);

song(
  bpm(96),
  section("space", 8, stack(drums, bass, pad, bell)),
  part("space-1", "space")
)</code></pre>
<button type="button" class="example" data-recipe="recipe-space-timbre">Load space and timbre</button>
<p>Change <code>.gate(0.35)</code> on the bass to <code>.gate(0.8)</code> to fill more of each step while its onsets stay fixed. The bass deliberately omits <code>.hold()</code>: an explicit hold in seconds would override the gate-derived ending.</p>
<p>Related: <a href="../mini-notation.md#method-chains">Sound shape</a> · <a href="../mini-notation.md#inside-quoted-notation">Inside quoted notation</a> · <a href="live-playback.md#playback-limits">Instrument limits</a></p>
</details>

<details class="recipe" id="recipe-section-arrangement">
<summary>Arrange sections and preview a song</summary>
<p>Define named sections with a cycle count, then place them in order with <code>part()</code>. Without an explicit start, a part follows the latest end of all preceding parts. Use <code>bpm()</code> inside the song; omission uses 60 BPM. A cycle is the timeline unit — there is no bar or time-signature mapping.</p>
<pre><code id="recipe-section-arrangement-code">let beat = s("bd hh sd hh").slow(4);
let bass = note("C2 C2 A1 G1").slow(4).gain(0.22);
let chords = chord("C Am F G").slow(4).gain(0.08).room(0.2);

song(
  bpm(96),
  section("intro", 8, chords),
  section("groove", 16, stack(beat, bass, chords)),
  section("outro", 8, chords),
  part("intro-1", "intro"),
  part("groove-1", "groove"),
  part("outro-1", "outro")
)</code></pre>
<button type="button" class="example" data-recipe="recipe-section-arrangement">Load section arrangement</button>
<p>Add a <code>section("bridge", 8, stack(bass, chords))</code> and a matching <code>part("bridge-1", "bridge")</code> between groove and outro, then press Restart to hear the new order from the beginning.</p>
<p>Press Restart, then Loop section beside groove. To preview the transition, set From cycle to <code>7</code> and To cycle to <code>10</code>, then press Loop range. Whole song clears the loop and starts from zero.</p>
<p>Related: <a href="../mini-notation.md#song-placement">Song structure</a> · <a href="live-playback.md#playback-preview">Preview controls</a></p>
</details>
<!-- LIVE_RECIPES_END -->

## Edit while playing

- Edits start when the changed phrase next begins.
- Different layers can change at different times.
- Invalid code leaves the last working version playing.
- Tempo changes work while playing.
- Envelope times stay in seconds when tempo changes.
- After changing song sections or parts, press **Restart** to hear the new
  arrangement from the beginning. Pause and Play control transport without
  reloading the source.

## More examples

- [`overlay-groove.mini`](../../examples/overlay-groove.mini) — drums, bass,
  melody, pan, and envelopes.
- [`room-of-light.mini`](../../examples/room-of-light.mini) — a short song.
- [`shared-room-afterglow.mini`](../../examples/shared-room-afterglow.mini) —
  a longer song with shared reverb.
