# Mini notation

`mini` turns short text programs into moondsp patterns and songs.

```text
s("bd hh sd hh").fast(2)
```

The package owns parsing and source identity. It does not choose DSP graphs or
instruments. Parsed events contain controls such as `sound`, `note`, `pan`, and
`room`; the scheduler and host decide how those controls affect audio.

## Choose an entry point

| Function | Use it when you need |
|---|---|
| `parse` | A runtime `Pat[ControlMap]` |
| `parse_song` | A `Song[ControlMap]` layout |
| `parse_song_with_bpm` | A song plus authored BPM metadata |
| `parse_doc` | An identity-bearing document for live editing |
| `parse_snapshot` | A parsed and lowered document snapshot |
| `MiniAuthoringPipeline` | Repeated edits with last-good state and lowering-cache reuse |

## Parse a pattern

`parse` returns `Result`, so callers must handle invalid input.

```mbt check
///|
test "parse a layered mini pattern" {
  let pat = match @mini.parse("s(\"bd sd\") + note(\"C4 E4\")") {
    Ok(value) => value
    Err(message) => fail(message)
  }
  let cycle = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = pat.query(cycle)

  assert_eq(events.length(), 4)
  assert_true(events[0].value.get("sound") == Some(36.0))
  assert_true(events[1].value.get("sound") == Some(38.0))
  assert_true(events[2].value.get("note") == Some(60.0))
  assert_true(events[3].value.get("note") == Some(64.0))
}
```

Inside quoted notation, spaces make a sequence, commas play items together,
and square brackets subdivide a step. The expression language adds named
bindings, `+` overlays, and methods such as `.fast()`, `.slow()`, `.rev()`,
`.every()`, and `.jux()`.

## Handle errors

Parse errors include a source position when one is available. Do not replace a
working pattern until parsing succeeds.

```mbt check
///|
test "invalid mini input returns an error" {
  match @mini.parse("s(\"bd\") trailing") {
    Err(message) => assert_true(message.contains("position"))
    Ok(_) => fail("expected a parse error")
  }
}
```

The browser editor follows the same rule: invalid text leaves the last accepted
pattern playing.

## Parse a song

Use `parse_song_with_bpm` when the host needs both the layout and its tempo.
Plain `parse_song` returns only the layout.

```mbt check
///|
test "parse song layout and tempo" {
  let parsed = match
    @mini.parse_song_with_bpm(
      "song(bpm(96),section(\"groove\",4,s(\"bd*4\")),part(\"g1\",\"groove\"))",
    ) {
    Ok(value) => value
    Err(message) => fail(message)
  }

  assert_true(parsed.bpm() == Some(96.0))
  assert_true(parsed.song().duration() == @pattern.Rational::from_int(4))
}
```

A song contains named `section` definitions and ordered `part` placements.
Select Song mode in the browser editor before playing one.

## Live-editing documents

`parse_doc` creates a `PatternDoc[ControlMap]` with stable source identities.
Pass the previous successful document back through `previous` to reuse unchanged
subtrees:

```mbt nocheck
///|
let first = @mini.parse_doc("let beat = s(\"bd sd\"); beat")

///|
let edited = match first {
  Ok(doc) =>
    @mini.parse_doc("let beat = s(\"bd hh\"); beat", previous=Some(doc))
  Err(message) => Err(message)
}
```

`MiniAuthoringPipeline` manages this loop for an editor. It keeps the last
successful document across parse errors and reuses one lowering cache. Current
parsing is still whole-document parsing; it is not token-level incremental
parsing. Call `dispose()` when the pipeline is no longer needed.

## Parser model

The production parser is handwritten MoonBit. It parses directly into runtime
patterns or identity-bearing pattern documents; it does not expose a public AST
or CST. The loom CST work under `specs/loom-mini-cst/` is an evaluation path,
not the production parser.

Mini depends on `pattern`, `song`, and `identity`, but not on DSP, graph, voice,
or scheduler packages.

## Learn the language

- [Live-coding cookbook](../docs/guides/live-coding-cookbook.md) — short,
  playable recipes.
- [Mini notation reference](../docs/mini-notation.md) — complete syntax and
  supported chord names.
- [Mini-to-graph boundary](../docs/mini-graph-authoring-boundary.md) — how
  controls reach graph templates without mixing package responsibilities.
