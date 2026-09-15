# Songs and sections

`song` arranges patterns into named, length-bounded sections and places those
sections on a long-form timeline. It remains generic in the event payload and
does not depend on DSP, voices, or browser code.

## Build a section

`Section[A]` gives a pattern a name, duration in cycles, and local `TimeScope`.
`from_pattern` is the concise one-cycle constructor.

```mbt check
///|
test "wrap a pattern as a section" {
  let section = @song.Section::from_pattern(
    name="verse",
    body=@pattern.note(60.0),
  )
  let events = section.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )

  assert_eq(section.name(), "verse")
  assert_true(section.length_cycles() == @pattern.Rational::from_int(1))
  assert_true(section.scope().is_identity())
  assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
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
  let section = @song.Section::from_pattern(
    name="groove",
    body=@pattern.sound(36.0),
  ).layer(name="bass", body=@pattern.note(36.0))
  let events = section.query(
    @pattern.TimeSpan::new(
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
    body=@song.SectionBody::single(@pattern.note(60.0)),
  )
  let chorus = @song.Section::from_pattern(
    name="chorus",
    body=@pattern.note(67.0),
  )
  let arrangement = @song.Song::from_sections([intro, chorus])
  let events = arrangement.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(3),
    ),
  )

  assert_true(arrangement.duration() == @pattern.Rational::from_int(3))
  assert_eq(arrangement.occurrence_count(), 2)
  assert_eq(events.length(), 3)
  assert_true(events[0].value.get("note") == Some(60.0))
  assert_true(events[2].value.get("note") == Some(67.0))
}
```

The same section may appear more than once. Use distinct occurrence names, or
stable occurrence IDs in identity-bearing documents, to address each placement.

## Explicit placement, gaps, and overlap

`SongPart::at` assigns an explicit start cycle. Explicit placements may leave
gaps or overlap; `Song::query` preserves all overlapping events.

```mbt check
///|
test "query explicitly placed occurrences" {
  let a = @song.Section::from_pattern(name="a", body=@pattern.note(60.0))
  let b = @song.Section::from_pattern(name="b", body=@pattern.note(64.0))
  let arrangement = @song.Song::Song(parts=[
    @song.SongPart::at(
      start=@pattern.Rational::from_int(0),
      name="a1",
      section=a,
    ),
    @song.SongPart::at(
      start=@pattern.Rational::new(1L, 2L),
      name="b1",
      section=b,
    ),
  ])
  let overlap = arrangement.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::new(1L, 2L),
      @pattern.Rational::from_int(1),
    ),
  )

  assert_eq(overlap.length(), 2)
  assert_eq(
    arrangement.occurrences_at(@pattern.Rational::new(3L, 4L)).length(),
    2,
  )
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
resizing an occurrence changes layout. `query_sourced_events` retains
occurrence, section, and layer identity for selective live updates.

Document edit methods return new values and reject duplicate identities, names,
invalid indices, and removal of the final occurrence.

## Package boundary

`song` owns long-form musical structure. It relies on exact pattern time and
stable identity, but it does not schedule sample blocks or allocate voices.

- [`pattern/`](../pattern/) — patterns and exact rational time.
- [`identity/`](../identity/) — stable authoring IDs and revisions.
- [`scheduler/`](../scheduler/) — block transport and voice dispatch.
- [Live-coding cookbook](../docs/guides/live-coding-cookbook.md#build-a-song)
