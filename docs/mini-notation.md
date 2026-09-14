# Mini notation

`mini/` parses compact text patterns into `Pat[ControlMap]` for the
scheduler and browser live-coding surface. Mini owns event timing and numeric
controls, not DSP graph topology; see
[`mini-graph-authoring-boundary.md`](mini-graph-authoring-boundary.md) for the
contract that bridges Mini events into graph templates. Production parsing is
still the hand-written MoonBit parser; the loom CST work remains an evaluation
path under `specs/loom-mini-cst/`.

## Top-level forms

Use `s("...")` for drum sounds, `note("...")` for MIDI note numbers or
note names, and `chord("...")` for chord names:

```text
s("bd sd hh sd")
note("60 64 67 72")
note("C4 E4 G4 C5")
chord("C Am F G7")
```

To combine multiple top-level patterns, prefer Strudel-style `$:` stack lines:

```text
$: s("bd sd hh sd")
$: note("60 64 67 72").slow(2)
```

This is equivalent to stacking the two patterns. `$:` is a top-level program
form, not syntax inside the quoted mini string. A single `$:` line is accepted
and behaves like the contained expression.

The explicit function form is also supported:

```text
stack(s("bd sd hh sd"), note("60 64 67 72"))
```

Once a program uses `$:` lines, each non-empty line must start with `$:`.
Blank lines are ignored.

Use `+` for an ordered overlay inside any expression:

```text
note("60 64") + s("bd sd")
s("bd") + s("hh").fast(2)
(s("bd") + s("hh")).fast(2)
```

Method chains bind more tightly than `+`: the second example speeds up only
the hats, while the third speeds up both layers. Parentheses group expressions
without adding a source node. `+` preserves left-to-right event order and
duplicates; it does not merge control maps.

The same syntax works in named definitions, `$:` lines, and song sections.
Regrouping a raw overlay preserves known material content and playback clocks;
source ancestry still reflects the authored grouping. Quoted `+` remains part
of the notation, for example `chord("C+7")`. Ordinary newlines alone do not
combine expressions.

In the live app's **Examples** panel, select an example and press **Play**:

- [Overlay groove](../examples/overlay-groove.mini) layers drums, bass, and
  stereo melodies with `+`; a parenthesized `.slow(2)` affects both melodies.
- [Grouping A/B](../examples/overlay-grouping.mini) plays `kick + hats.fast(2)`
  followed by `(kick + hats).fast(2)`: hear only the hats speed up, then both
  layers. The two sections last 20 seconds in total at BPM 96.

## Inside quoted notation

Within `s("...")`, `note("...")`, and `chord("...")`:

- Spaces make a sequence within one cycle: `bd sd hh sd`.
- Commas stack layers inside the same source: `bd sd, hh hh hh`.
- Brackets group sub-notation: `bd [sd hh]`.
- Postfixes apply left-to-right to atoms or groups:
  - `*n` repeats faster inside the slot: `bd*4`.
  - `/n` stretches slower inside the slot: `bd/2`.
  - `?` applies deterministic 50% drop: `bd?`.
  - `(k,n[,rotation])` applies Euclidean rhythm: `bd(3,8)`.

Examples:

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

## Method chains

Methods apply to any top-level expression or `$:` line expression:

```text
s("bd sd").fast(2).rev()
$: s("bd(3,8)").jux(rev)
$: note("48 60 67").slow(3)
$: chord("C Am F G7").slow(4)
```

Supported methods:

- `.fast(n)` / `.slow(n)`: speed up or slow down; use positive integer factors.
- `.rev()`: reverse events within each cycle.
- `.degradeBy(p)`: deterministic event dropping, with probability from 0 to 1.
- `.pan(p)`: stereo position from -1 (left) to 1 (right).
- `.room(p)`: send from 0 to 1 into the browser's shared reverb; the dry signal remains.
- `.attack(s)`, `.hold(s)`, `.release(s)`: note/chord envelope times in seconds,
  from 0 to 86400. Explicit times do not scale with tempo or `.fast`/`.slow`.
  Omit `.hold` to use the pattern's note length.
- `.every(n, fast(k)|slow(k)|rev)`: transform every nth cycle; `n` is a positive integer.
- `.jux(fast(k)|slow(k)|rev)`: original left, transformed copy right.
- `.gain(g)`, `.cutoff(hz)`: parsed control values. The current browser instruments
  have no bindings for these keys, so they do not affect volume or filtering there.

Method chains bind more tightly than `+`. Compare `a + b.fast(2)` (only `b`)
with `(a + b).fast(2)` (both layers). The **Grouping A/B** live example plays
this comparison.

## Browser live examples

The live browser UI supports both `+` expressions and explicit `$:` layers.
`$:` mirrors the layered shape of Strudel sessions:

```text
$: s("bd(3,8), hh(5,16)?, sd(2,8,4)").slow(2)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)
$: chord("C Am F G7").slow(4)
```

## Song placement

Use Song mode for `song(...)`, with comma-separated items:

- `section("name", length, expression)`: define a positive-length section;
  its expression can use `+`, grouping, and named patterns.
- `part("id", "section")`: append a section occurrence.
- `part("id", "section", start)`: place it at an absolute cycle; overlaps play together.
- `part_id("id", "label", "section"[, start])`: separate stable identity from display name.
- `fill("prefix", "section")`: fill uncovered time between occurrences.
- `bpm(n)`: set the song tempo; this remains editable during playback.

Section lengths and explicit starts accept integers or fractions such as `3/2`.
Use unique occurrence IDs. Examples select their mode and tempo automatically.
