# Songs and sections

`song` arranges patterns into named, length-bounded sections and places those
sections on a long-form timeline. It is generic over section content and does
not depend on DSP, voices, or browser code.

## Architecture context

In moondsp's layered design, `song` models macro-level musical structure
between pattern queries and the scheduler:

```text
[ mini ] (text notation: song(section(...), part(...)))
   ↓
[ song ] ← (sections, parts, time scopes, macro arrangements)
   ↓
[ scheduler ] (event-to-voice scheduling & block quantization)
   ↓
[ voice ] / [ engine ] (voice allocation & mixing)
   ↓
[ graph ] (topology validation & compilation)
   ↓
[ dsp ] (primitives: buffers, oscillators, filters, envelopes)
```

- **Upstream consumers**: [`mini/`](../mini/) parses `parse_song` and
  `parse_song` expressions into `Song` layouts.
- **Downstream dependencies**: [`pattern/`](../pattern/) provides the underlying
  `Pat[A]`, `Rational`, and `TimeSpan` query types. `song` has zero dependencies
  on DSP buffers, synthesis graphs, or audio hardware.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Song Composition** | `Song[C]`, `Section[C]`, `SongPart[C]`, `SongContent` | `Song::Song`, `Song::from_sections`, `Section::Section`, `Section::single`, `SongPart::SongPart`, `SongPart::at` |
| **Section & Layers** | `Section[C]`, `SectionBody[C]`, `SectionLayer[C]` | `Section::layer`, `Section::get_layer`, `Section::body`, `Section::query`, `Section::apply_patch` |
| **Timeline & Occurrence** | `Song[C]`, `SectionOccurrence[C]` | `Song::duration`, `Song::occurrences`, `Song::occurrence_at`, `Song::query`, `SectionOccurrence::span` |
| **Time Scopes** | `TimeScope` | `TimeScope::TimeScope`, `TimeScope::identity`, `TimeScope::at_rate`, `TimeScope::fast`, `TimeScope::slow` |
| **Live Editing & Documents** | `SongDoc[C]`, `SectionDoc[C]`, `SongSnapshot[C]` | `SongDoc::SongDoc`, `SongDoc::to_song`, `SongDoc::lower`, `SectionDoc::to_section`, `SongSnapshot::entries`, `SongEntry::content`, `SongEntry::placement` |
| **Errors** | `SongBuildError`, `SongDocEditError`, `SectionDocBuildError`, `NegativeStart` | `SongBuildError::EmptySong`, `DuplicateOccurrence`, `DuplicateOccurrenceId`, `InvalidOccurrenceId` |

## Build a section

`Section[C]` gives content a name, duration in cycles, and local `TimeScope`.
Structure never looks inside `C`; querying a section as a pattern requires
`C : SongContent`, which untracked snapshots (`UntrackedPatternSnapshot[ScoreEvent]`) and
tracked snapshots (`TrackedPatternSnapshot[ScoreEvent]`) implement (ADR-0021).
`single` is the concise one-cycle constructor.

```mbt check
///|
test "wrap a pattern as a section" {
  let section = @song.Section::single(
    name="verse",
    body=section_test_content("readme:verse", @score.note(60.0)),
  )
  let events = section.query(
    @pattern.TimeSpan(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )

  assert_eq(section.name(), "verse")
  assert_true(section.length_cycles() == @pattern.Rational::from_int(1))
  assert_true(section.scope().is_identity())
  assert_eq(events.length(), 1)
  assert_true(events[0].value.sound is Note(_, pitch~) && pitch == 60.0)
}
```

Use the full constructor when the section needs an explicit duration or time
rate. A section's duration controls arrangement placement; its pattern can
repeat inside that interval.

## Layer a section

A section body is either one pattern or an ordered set of named layers. Adding a
new layer stacks its events. Reusing a layer name replaces that layer instead
of adding a duplicate.

```mbt check
///|
test "combine named section layers" {
  let section = @song.Section::single(
    name="groove",
    body=section_test_content(
      "readme:groove:main",
      @score.hit(@score.Drum::parse("bd").unwrap()),
    ),
  ).layer(
    name="bass",
    body=section_test_content("readme:groove:bass", @score.note(36.0)),
  )
  let events = section.query(
    @pattern.TimeSpan(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )

  assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("main") is Some(_))
  assert_true(section.get_layer("bass") is Some(_))
  assert_eq(events.length(), 2)
}
```

`SectionPatch::add_layer` rejects an existing name. `set_layer` rejects a
missing name. Use `Section::layer` when replacement-by-name is the desired
behavior.

## Arrange a song

`Song::from_sections` places sections sequentially in array order. Occurrence
names default to section names.

```mbt check
///|
test "arrange sections sequentially" {
  let intro = @song.Section::Section(
    name="intro",
    length_cycles=@pattern.Rational::from_int(2),
    scope=@song.TimeScope::identity(),
    body=@song.SectionBody::single(
      section_test_content("readme:intro", @score.note(60.0)),
    ),
  )
  let chorus = @song.Section::single(
    name="chorus",
    body=section_test_content("readme:chorus", @score.note(67.0)),
  )
  let arrangement = @song.Song::from_sections([intro, chorus])
  let events = arrangement.query(
    @pattern.TimeSpan(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(3),
    ),
  )

  assert_true(arrangement.duration() == @pattern.Rational::from_int(3))
  assert_eq(arrangement.occurrence_count(), 2)
  assert_eq(events.length(), 3)
  assert_true(events[0].value.sound is Note(_, pitch~) && pitch == 60.0)
  assert_true(events[2].value.sound is Note(_, pitch~) && pitch == 67.0)
}
```

The same section may appear more than once. Use distinct occurrence names, or
stable occurrence IDs in identity-bearing documents, to address each placement.

## Explicit placement, gaps, and overlap

`SongPart::at` assigns an explicit start cycle, at or after 0: a song starts
at cycle 0, and every constructor that takes a start (`SongPart::at`,
`with_id_at`, `SongOccurrenceDoc::at`) raises `NegativeStart` for an earlier
one. Explicit placements may leave
gaps or overlap; `Song::query` preserves all overlapping events.

```mbt check
///|
test "query explicitly placed occurrences" {
  let a = @song.Section::single(
    name="a",
    body=section_test_content("readme:explicit:a", @score.note(60.0)),
  )
  let b = @song.Section::single(
    name="b",
    body=section_test_content("readme:explicit:b", @score.note(64.0)),
  )
  let arrangement = @song.Song::Song(parts=[
    @song.SongPart::at(
      start=@pattern.Rational::from_int(0),
      name="a1",
      section=a,
    ),
    @song.SongPart::at(start=@pattern.Rational(1L, 2L), name="b1", section=b),
  ])
  let overlap = arrangement.query(
    @pattern.TimeSpan(@pattern.Rational(1L, 2L), @pattern.Rational::from_int(1)),
  )

  assert_eq(overlap.length(), 2)
  assert_eq(arrangement.occurrences_at(@pattern.Rational(3L, 4L)).length(), 2)
}
```

`gap_spans` reports uncovered ranges. `fill_gaps` inserts sized occurrences of a
fill section while preserving existing placement order and IDs.

## Section-local time

`TimeScope` changes the rate at which a section queries its body:

- `identity` keeps the original rate;
- `fast(factor)` fits more pattern cycles into section time;
- `slow(factor)` stretches pattern cycles;
- `at_rate(rate)` specifies the rate directly.

Rates must be positive. Pattern event spans are transformed into song time when
the section or song is queried.

## Identity-bearing authoring

Runtime types (`Section` and `Song`) are enough for fixed arrangements.
Interactive editors should use:

- `SectionDoc` with stable `SectionId` and `SectionLayerId` values;
- `SongOccurrenceDoc` with a stable `OccurrenceId`;
- `SongDoc` for insertion, movement, renaming, replacement, and explicit starts;
- `SongSnapshot` as the lowered value consumed by the scheduler.

Content revision and layout revision are separate. Renaming an occurrence
changes authored content without moving it; inserting, moving, removing, or
resizing an occurrence changes layout. `entries()` lists the canonical playback
entries. Each `SongEntry` has its content, the content entry it plays
(`content_entry`), the placement of content time on the song clock
(`placement`), its occurrence span, and the occurrence, section, and layer
identity used for selective live updates.

Document edit methods return new values and reject duplicate identities, names,
invalid indices, and removal of the final occurrence.

Tracked content is a type: a `Song[TrackedPatternSnapshot]` holds a tracked
snapshot in every layer, so querying a slice's content yields events with
their source origin, frame, and local onset/pitch. Section rate, clipping,
placement, and repeating playback change event spans without reinterpreting
those source-local coordinates. An untracked pattern cannot replace a tracked
layer's body; choosing the content type is the only way to change kind.

## Package boundary

`song` owns long-form musical structure. It relies on exact pattern time and
stable identity, but it does not schedule sample blocks or allocate voices.

- [`pattern/`](../pattern/) — patterns and exact rational time.
- [`identity/`](../identity/) — stable authoring IDs and revisions.
- [`scheduler/`](../scheduler/) — block transport and voice dispatch.
- [Live-coding cookbook](../docs/guides/live-coding-cookbook.md#build-a-song)
