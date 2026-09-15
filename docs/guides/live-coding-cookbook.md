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

Open <http://localhost:5180>, choose **Pattern** or **Song**, then press
**Play**. If the port is busy, Vite prints another URL.

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

Switch the editor to **Song** mode:

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

## Edit while playing

- Edits start when the changed phrase next begins.
- Different layers can change at different times.
- Invalid code leaves the last working version playing.
- Tempo changes work while playing.
- Envelope times stay in seconds when tempo changes.
- After changing song sections or parts, press **Stop**, then **Play**.

## More examples

- [`overlay-groove.mini`](../../examples/overlay-groove.mini) — drums, bass,
  melody, pan, and envelopes.
- [`room-of-light.mini`](../../examples/room-of-light.mini) — a short song.
- [`shared-room-afterglow.mini`](../../examples/shared-room-afterglow.mini) —
  a longer song with shared reverb.
