# Songs and sections

`song` places length-bounded sections on a long-form timeline. It is generic
over section content and does not depend on DSP, voices, or browser code.

## Architecture context

In moondsp's layered design, `song` models macro-level musical structure
between pattern queries and the scheduler:

```text
[ mini ] (text notation: song(section(...), part(...)))
   ↓
[ song ] ← (sections, layers, parts, song layout)
   ↓
[ scheduler ] (event-to-voice scheduling & block quantization)
   ↓
[ voice ] / [ engine ] (voice allocation & mixing)
   ↓
[ graph ] (topology validation & compilation)
   ↓
[ dsp ] (primitives: buffers, oscillators, filters, envelopes)
```

- **Upstream consumers**: [`mini/`](../mini/) builds a `Song` from song
  notation (`parse_song`, `PlaybackInput::compile`); the scheduler and player
  play it.
- **Downstream dependencies**: [`pattern/`](../pattern/) provides `Pat`,
  `Rational`, `TimeSpan`, and `Placement`; [`identity/`](../identity/)
  provides the ids. `song` has no dependency on DSP buffers, synthesis graphs,
  or audio hardware.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Sections** | `Section[C]`, `SectionLayer[C]` | `Section(id~, length_cycles~, rate?, layers~)`, `SectionLayer(id~, content~)`, `layers`, `rate` |
| **Songs** | `Song[C]`, `SongPart[C]`, `SectionOccurrence[C]` | `Song(parts~)`, `SongPart(id~, section~)`, `SongPart::at(id~, start~, section~)`, `occurrences`, `duration`, `gap_spans` |
| **Playback entries** | `SongEntry[C]`, `SongEventOrigin`, `SongContent` | `Song::entries`, `SongEntry::content`, `content_entry`, `placement`, `origin` |
| **Errors** | `SectionBuildError`, `SongBuildError`, `NegativeStart` | `NonPositiveLength`, `NonPositiveRate`, `EmptyLayers`, `DuplicateLayer`, `EmptySong`, `DuplicateOccurrence` |

## Sections

A `Section[C]` is one or more layers of content that play together for
`length_cycles`. Structure never looks inside `C`; reading a song's playback
entries requires `C : SongContent`, which untracked snapshots
(`UntrackedPatternSnapshot[ScoreEvent]`) and tracked snapshots
(`TrackedPatternSnapshot[ScoreEvent]`) implement (ADR-0021).

`rate` is content cycles per section cycle and defaults to 1: at `2` the
layers play twice as fast inside the same length. A section must last, its
rate must be positive, and it needs at least one layer; layers are keyed by
their ids, which must differ.

## Songs

A `Song[C]` lays out `SongPart`s in the order they are written. A part
without a start begins where the parts before it end; `SongPart::at` places
it explicitly, at or after cycle 0 (`NegativeStart` otherwise), and may leave
a gap or overlap another part. A song needs a part, and its parts need
distinct occurrence ids. It lasts from cycle 0 to its latest end.

```mbt check
///|
test "lay out parts, with a gap and an overlap" {
  let verse = section("verse", cycles(2), untracked("readme:verse", 60.0))
  let arrangement = song([
    SongPart(id=oid("verse1"), section=verse),
    at("pad", cycles(1), verse),
    at("verse2", cycles(4), verse),
  ])
  assert_eq(arrangement.duration(), cycles(6))
  assert_eq(layout(arrangement), [
    ("verse1", span(cycles(0), cycles(2))),
    ("pad", span(cycles(1), cycles(3))),
    ("verse2", span(cycles(4), cycles(6))),
  ])
  assert_eq(arrangement.gap_spans(), [span(cycles(3), cycles(4))])
}
```

## Playback entries

`entries()` lists the canonical playback entries: every content entry of every
layer of every occurrence, in song order. Each `SongEntry` has its content, the
content entry it plays (`content_entry`), the placement of content time on the
song clock (`placement`: the occurrence start and section rate), its occurrence
span, and its `SongEventOrigin` — the occurrence, section and layer ids the
scheduler keys voices and live updates by.

Tracked content is a type: a `Song[TrackedPatternSnapshot]` holds a tracked
snapshot in every layer, so querying an entry's content yields events with
their source origin. Section rate, clipping, placement, and repeating playback
change event spans without reinterpreting those source-local coordinates.

## Package boundary

`song` owns long-form musical structure. It relies on exact pattern time and
stable identity, but it does not schedule sample blocks or allocate voices.

- [`pattern/`](../pattern/) — patterns and exact rational time.
- [`identity/`](../identity/) — stable ids.
- [`scheduler/`](../scheduler/) — block transport and voice dispatch.
- [Live-coding cookbook](../docs/guides/live-coding-cookbook.md#build-a-song)
