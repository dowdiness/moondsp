# ADR-0034: A song is built one way, from identified parts

- **Status:** Accepted
- **Date:** 2026-11-28
- **Supersedes in part:** [ADR-0005](0005-song-section-layer.md)
  (`TimeScope`, `SectionBody`, `SectionPatch`, named layers),
  [ADR-0008](0008-contiguous-song-layout.md) (`Song::query`,
  `Song::from_sections`, name lookup),
  [ADR-0009](0009-stable-identity-groundwork.md) (occurrence ids derived from
  display names, revisions for incremental invalidation), and
  [ADR-0021](0021-song-structure-generic-over-content.md) decision 1 (the
  document types) and the `snapshot.song().query(arc)` remark in decision 4.
- **Related:** issue #304, [ADR-0032](0032-mini-song-identities-are-their-names.md),
  [ADR-0033](0033-the-scheduler-decides-what-continues.md)

## Context

The `song` package had two hierarchies for one concept. `Section`,
`SectionLayer`, `SongPart` and `Song` were the first layout model (ADR-0005,
ADR-0008); `SectionDoc`, `SectionLayerDoc`, `SongOccurrenceDoc` and `SongDoc`
were added beside them for identities and incremental edits (ADR-0009), and
`SongDoc::lower` turned a document into a `SongSnapshot` holding a `Song`.

Checked with `moon ide analyze song` on 2026-11-28, production used little of
either:

- Mini built every song as a `SongDoc` (ADR-0032) and lowered it at once.
  The scheduler, the player, signal views and Mini's admission read the
  `SongSnapshot`: its entries, and the occurrences and duration of the `Song`
  inside, whose occurrences returned the *first* hierarchy's `Section`. So
  even with `SongDoc` as the only entry point, two public section types
  remained, one to write and one to read.
- `SongDoc::lower` raised `SongBuildError`, which could not happen: the
  document had already checked emptiness and repeated ids and names.
- Nothing read the document editing API, any revision (ADR-0033 decides
  continuity from the arrangement), `SectionPatch`, `Song::query`,
  `Section::query`, name or time lookups, `Song::fill_gaps` (Mini fills gaps
  with its own identities, ADR-0032), `Song::from_sections`, or the name of an
  occurrence, section or layer. Mini reports mistakes with the names in its
  own source, and its identities are encoded names.
- `TimeScope` wrapped one positive rate behind six constructors; the groove
  and meter it was meant to grow into have been deferred since ADR-0005.

Multiple layers and non-identity rates cannot be written in Mini, but the
scheduler plays them, keys voices by layer id, and tests both, so they stay.

## Decision

1. **One hierarchy, keyed by ids.** `SectionLayer(id~, content~)`,
   `Section(id~, length_cycles~, rate?, layers~)`, `SongPart(id~, section~)`
   and `SongPart::at(id~, start~, section~)`, and `Song(parts~)`. Songs,
   sections and layers have no names; identity is the id.
2. **`Song` is what is built and what is played.** `Song(parts~)` lays the
   parts out once and raises `SongBuildError::EmptySong` or
   `DuplicateOccurrence(id)`. The scheduler, the player and Mini take a
   `Song` (`PlaybackSnapshot::song`, `Score::song`, `ParsedSong::song`,
   `CompiledMaterial::TrackedSong` / `UntrackedSong`). `Song::entries()`
   (for `C : SongContent`) lists the playback entries; `occurrences()`,
   `duration()` and `gap_spans()` describe the layout.
3. **A section is a non-empty list of layers with a rate.** `rate` is a
   positive `Rational`, 1 by default. `Section` raises `SectionBuildError`:
   `NonPositiveLength`, `NonPositiveRate`, `EmptyLayers`, or
   `DuplicateLayer(id)`. A one-layer section is a list of one.
4. **Gap filling is Mini's.** Mini reads `gap_spans()` and adds its fill parts
   with the identities ADR-0032 gives them.
5. **Removed:** `SongDoc`, `SongSnapshot`, `SongOccurrenceDoc`, `SectionDoc`,
   `SectionLayerDoc`, `SectionDocBody`, `SectionBody`, `SectionPatch`,
   `TimeScope`, every revision and edit method, `Song::query`,
   `Section::query` / `body`, name and time lookups, `fill_gaps`,
   `from_sections`, `SongPart::with_id` / `with_id_at`, and the errors only
   they raised.

## Consequences

- A song has one type to build and one to read, and every check runs once,
  where the value is built.
- A display name, if a future editor needs one, belongs to that editor's own
  document, as Mini's names belong to Mini's source.
- An editor that edits songs incrementally rebuilds the `Song`; the scheduler
  already decides from the arrangement whether the result can replace the
  playing one (ADR-0033).
- Tests observe what a song plays through `entries()`, as the scheduler does,
  instead of a second query path that production never used.
- Two parts may share a display name in Mini when their `part_id`s differ.

## Rejected alternatives

- **Keep `SongDoc` as the public entry and make `Song(parts~)` internal.**
  `Song` and its `Section` stay public as the read side, so the two section
  types remain.
- **Keep names.** No production reader; Mini already holds them.
- **Keep `TimeScope`.** It is a positive rate under another name until groove
  or meter exist.
