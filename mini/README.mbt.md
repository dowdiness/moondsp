# Mini notation

`mini` turns short text programs into moondsp patterns and songs.

```text
s("bd hh sd hh").fast(2)
```

The package owns parsing and source identity. It does not choose DSP graphs or
instruments. Parsed events contain controls such as `sound`, `note`, `pan`, and
`room`; the scheduler and host decide how those controls affect audio.

## Architecture context

In moondsp's layered design, `mini` is the top-level text-to-pattern authoring
surface:

```text
[ mini ] ← (text notation, document parsing, lowering cache)
   ↓
[ pattern / song ] (exact rational time, event queries, combinators)
   ↓
[ scheduler ] (event-to-voice scheduling & block quantization)
   ↓
[ voice ] / [ engine ] (voice allocation & mixing)
   ↓
[ graph ] (topology validation & compilation)
   ↓
[ dsp ] (primitives: buffers, oscillators, filters, envelopes)
```

- **Upstream consumers**: Web editors (e.g. `web/live/`), REPLs, and live-coding
  interfaces pass text code directly to `mini`.
- **Downstream dependencies**: [`pattern/`](../pattern/) provides `Pat[ControlMap]`,
  `Rational`, and `PatternDoc`; [`song/`](../song/) provides `Song[ControlMap]`
  layouts; [`identity/`](../identity/) supplies node IDs for live-editing trees.
  `mini` has zero dependencies on audio buffers, DSP, or voice pools.

## API quick reference

| Category | Types / Functions | Key operations |
|---|---|---|
| **Text Parsing** | `parse`, `parse_song`, `parse_song_with_bpm` | Parse string into `Pat[ControlMap]`, `Song[ControlMap]`, or `ParsedSong` |
| **Documents** | `parse_doc`, `parse_snapshot` | Parse deterministic graph documents or general snapshots without cross-draft source continuity |
| **Live Authoring** | `Draft`, `DraftVersion`, `EditTransaction`, `TextEdit` | `Draft::new`, `state`, `edit`, `reset`, `prepare_playback`, `locate_origin`, `dispose` |
| **Frozen Playback Input** | `PlaybackInput`, `PreparedPlayback` | `PlaybackInput::text`, `source`, `version`, `compile`; exact pattern or explicitly runtime-only source |
| **Programmatic Doc Building** | `MiniDocBuilder` | `MiniDocBuilder::with_previous`, `MiniDocBuilder::sound_atom`, `MiniDocBuilder::note_atom`, `MiniDocBuilder::sequence`, `MiniDocBuilder::fast` |
| **Song & Utilities** | `ParsedSong`, `drum_midi` | `ParsedSong::song`, `ParsedSong::bpm`, `drum_midi` |

## Choose an entry point

| Function | Use it when you need |
|---|---|
| `parse` | A runtime `Pat[ControlMap]` |
| `parse_song` | A `Song[ControlMap]` layout |
| `parse_song_with_bpm` | A song plus authored BPM metadata |
| `parse_doc` | A general graph document, optionally reusing previous subtrees |
| `parse_snapshot` | A parsed and lowered document snapshot |
| `Draft` | Causal atom/reference identities across valid and invalid edits, frozen playback input, and current source locations |

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

### Identity across edits

`Draft` owns text and source lifetimes. Submit each editor transaction through
`edit(EditTransaction::EditTransaction(base~, edits~))`. Every `TextEdit` uses
half-open **old-document UTF-16** coordinates. All ranges are validated before
anything changes; stale versions, overlapping/out-of-range edits, and boundaries
inside surrogate pairs are rejected. There is no inferred full-text setter.

Replacing an atom with the same spelling still retires it. Empty transactions
do not advance the version. Separate inverse edits must remain separate
transactions: composing them to an empty change would erase identity history.
Whitespace at an atom boundary preserves identity only while its lexical extent
and role remain unchanged. Graph node IDs and musical seeds are independent.

Completed atom and reference facts survive missing outer delimiters. Recognition
uses the existing expression/notation parsers and recovers only at certain
semicolon or dollar-stack boundaries, not invented closing tokens. A reference
binding survives only while its declaration stays uniquely provable. Ambiguity,
undefined names, opaque preceding scope, and deletion retire the binding; undo
does not revive it.

`prepare_playback()` returns a frozen `PlaybackInput` or a version-tagged
`DraftDiagnostic`. Preparing input is **not playback acceptance**. The input owns
its captured text/version/source witnesses; subsequent edits or disposal do not
change it. `compile()` returns `PreparedPlayback::Pattern(exact_snapshot, bpm)`
for a tracked pattern or `PreparedPlayback::Runtime(play_source)` for a song.
`PlaybackInput::text(text)` explicitly selects runtime-only programmatic input.
An exact compilation failure never falls back to runtime-only playback.

`locate_origin(origin)` returns `Located(atom_range, reference_ranges)` with
outer-to-inner reference ranges, or `Unavailable(SourceReset | AtomRetired |
BrokenReference)`. It requires the entire original binding path, not a partial
match. Old-version origins can remain locatable during invalid drafts.

Tracking is limited to 8192 UTF-16 code units; larger text remains editable but
cannot prepare playback. Crossing the limit, confirmed source-mode changes, and
explicit `reset` establish fresh source epochs. Unknown syntax alone does not
select a new mode. Current indices and the internal last-valid document are
bounded; no per-spelling allocation history is retained. Checked serials and
revisions never wrap. `Draft::new` raises `DraftEditError` on epoch exhaustion;
`edit` and `reset` return explicit errors without partially changing the draft.

Browser transaction adapters, worklet transport, onset observations, and visual
highlighting are not connected to this API yet. See the
[implementation contract](../docs/plans/2026-09-09-playback-position-ui.md).

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

`parse_doc` creates a `PatternDoc[ControlMap]` with deterministic graph IDs, not
causal source identities. Pass the previous successful document back through
`previous` to reuse unchanged subtrees:

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

Use `Draft` rather than this stateless loop when editing needs exact source
continuity. Its last-valid document is internal parse state, not a playback
acceptance channel. Parsing remains whole-source; this is not token-level
incremental parsing. Call `dispose()` when the owner is no longer needed.

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
