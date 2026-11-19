# ADR-0021: Song structure is generic over its content

- **Status:** Accepted 2026-11-19. Implemented.
- **Date:** 2026-11-19
- **Refines:** [ADR-0005](0005-song-section-layer.md) and
  [ADR-0008](0008-contiguous-song-layout.md). Their decision that song
  structure stays polymorphic holds; the type parameter moves from the event
  payload `A` of `Pat[A]` to the section content `C` itself.
- **Related:** [ADR-0020 controls as typed signals](0020-controls-as-signals.md),
  [ADR-0018 playback visualization follows event origins](0018-playback-visualization-origin-truth.md)

## Context

ADR-0005 made `Section[A]` polymorphic in the payload of the pattern it
holds, so every layer was a `Pat[A]`. ADR-0020 then made controls typed
signals, and every event carries `Controls` built from one compiled
`ControlMap` pattern. After that change three properties of the song model
were accidental:

1. **The payload parameter could only ever be `ControlMap`.** Pattern
   documents, snapshots, buses, and origins only work for `ControlMap`
   payloads, so `Section[A]` for any other `A` could not be lowered, sourced,
   or played.
2. **Exact content lived beside the body.** A section built from an
   origin-bearing pattern kept `source_snapshot : PatternSnapshotWithOrigins?`
   next to a `body : Pat[A]` derived from it. The invariant "the body is the
   snapshot's pattern" held only by construction (`Section::with_origins`,
   `SectionDoc::single_with_origins`), and every reader branched on the
   option: song events carried `source_origin : EventOrigin?`, and the
   anonymous branch filled `-1.0` placeholders.
3. **Replacing a body silently dropped exactness.** Editing a layer with a
   runtime pattern cleared the snapshot, so the same type held two
   capabilities that the scheduler and the browser had to tell apart at
   run time.

## Decision

1. **Structure is generic over content.** `Section[C]`, `SectionBody[C]`,
   `SectionLayer[C]`, `SectionPatch[C]`, `Song[C]`, `SongPart[C]`,
   `SectionOccurrence[C]`, and the document types `SectionDoc[C]`,
   `SectionLayerDoc[C]`, `SongOccurrenceDoc[C]`, `SongDoc[C]` hold exactly
   one content value per layer. Structural operations (layout, renaming,
   patching, identity, revisions) never look inside `C`.
2. **Pattern queries require `C : SongContent`.** The open trait
   `SongContent { pat(Self) -> Pat[ControlMap] }` is the only requirement
   for `Section::body`, `Section::query`, `SectionBody::to_pattern`,
   `Song::query`, and `SongDoc::lower`. It is implemented for
   `Pat[ControlMap]` (anonymous runtime content) and for
   `PatternSnapshotWithOrigins` (exact content).
3. **Exactness is a type, not an option.** A song of exact content is a
   `Song[PatternSnapshotWithOrigins]`; there is no `source_snapshot` field
   and no `with_origins` constructor. `Section::from_pattern` becomes
   `Section::single(name~, body~)` for any content.
4. **The lowered song exposes entries and slices, not events.**
   `SongSnapshot::entries()` lists the canonical playback entries, every
   content entry of every layer of every occurrence, in one place: each
   `SongEntry[C]` carries its `SongEventOrigin`, its scoped entry body, and
   its occurrence span, so the scheduler walks this list instead of deriving
   the order again. `SongEntry::slice(arc)` and `SongSnapshot::slices(arc)`
   return a `SongSlice[C]`: the content, its entry index, the content-local
   query arc, the placement back to the song clock, and the origin. Querying
   the content is the consumer's job, so song structure stays independent of
   what the content's events carry. Playback keys an entry by occurrence,
   layer identity, and entry key, so reordering or inserting layers keeps
   the other layers' entries.
   `SongSnapshotEvent`, `query_sourced_events`, and `SongSnapshot::query`
   are removed; `snapshot.song().query(arc)` remains for plain events.
5. **Mini parses to the content it has.** A tracked song source parses to
   `PlayBody::ExactArrangement(Song[PatternSnapshotWithOrigins], Bool)`; an
   untracked one to `Arrangement(Song[Pat[ControlMap]], Bool)`.
   `parse_song` returns `ParsedSong[Pat[ControlMap]]`.
6. **The scheduler names the two playable kinds.** `@scheduler.SongMaterial`
   is `Runtime(SongSnapshot[Pat[ControlMap]])` or
   `Exact(SongSnapshot[PatternSnapshotWithOrigins])`, and
   `PlaybackSnapshot::song` / `repeat_song` take it. Exact entries report
   `source_origin : Some(origin)` from the content; runtime entries report
   `None`. This mirrors the existing `Pattern` / `PatternWithOrigins` split.

The same change specializes the pattern document layer to `ControlMap`
(`PatternDoc`, snapshots, `EventWithOrigin`, `ControlBus`, and related types
lose their payload parameter; `Pat[A]` stays generic) and replaces
`EventBuses` with `@pattern.Controls`. It also states each control's domain
once, in `@control.Control::admits`: Mini checks it for the keys it parses
with a range, and `note_gate` checks `attack` and `hold` because runtime
patterns skip parsing. `note_gate` returns the checked duration as a
`@voice.GateSeconds`, which the scheduler uses without checking again.

## Consequences

- Each layer has one source of truth. The derived-body invariant, its
  constructors, and every branch on `source_snapshot` are gone.
- A runtime pattern can no longer replace an exact layer's body in place;
  converting between kinds is an explicit choice of content type.
- Consumers that want events from a song read a slice and query its content.
  This is one more step than `query_sourced_events`, in exchange for song
  code that never depends on event provenance.
- Future content types (for example authoring documents, or a non-DSP
  timeline reader) reuse the structure. They need `SongContent` only to be
  queried as patterns.

## Rejected alternatives

- **Specialize song to `ControlMap` (keep `source_snapshot`).** Removes the
  dead payload parameter but keeps the optional witness beside the body and
  the run-time branch on exactness.
- **A separate `SourcedSection` type beside `Section`.** Duplicates the
  structural API (layers, patches, layout) for the second content kind.
- **A closed `Playable` enum as the content.** Puts the runtime/exact split
  inside every section instead of at the one place that must tell them
  apart, the scheduler.
