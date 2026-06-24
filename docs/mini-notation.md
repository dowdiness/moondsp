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

The older function form remains supported:

```text
stack(s("bd sd hh sd"), note("60 64 67 72"))
```

Once a program uses `$:` lines, each non-empty line must start with `$:`.
Blank lines are ignored.

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

## Method chains

Methods apply to any top-level expression or `$:` line expression:

```text
s("bd sd").fast(2).rev()
$: s("bd(3,8)").jux(rev)
$: note("48 60 67").slow(3)
$: chord("C Am F G7").slow(4)
```

Supported methods include:

- `.fast(n)` / `.slow(n)`
- `.rev()`
- `.degradeBy(p)`
- `.cutoff(f)`, `.gain(g)`, `.pan(p)`
- `.every(n, fast(k)|slow(k)|rev)`
- `.jux(fast(k)|slow(k)|rev)`

## Browser live examples

The live browser UI uses `$:` for cross-source examples because it mirrors the
layered shape of Strudel sessions:

```text
$: s("bd(3,8), hh(5,16)?, sd(2,8,4)").slow(2)
$: note("48(3,8) 60(2,8,2) 67(3,8) 60(2,8,3)").slow(3)
$: chord("C Am F G7").slow(4)
```
