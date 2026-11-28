# ADR-0032: A Mini song's sections and parts are identified by their names

- **Status:** Accepted; since [ADR-0034](0034-a-song-is-built-one-way.md) Mini builds a `Song` directly rather than lowering a `SongDoc`
- **Date:** 2026-11-27
- **Related:** issue #293, [ADR-0016](0016-loom-backed-runtime-mini-parser.md),
  [ADR-0030](0030-players-accept-scores.md),
  [ADR-0031](0031-playback-material-is-one-view.md)

## Context

A lowered song carries an occurrence, section and layer identity for every
entry. Mini source declares none of these except `part_id("…")`. Before
issue #293, Mini kept a bare `Song` and `player` rebuilt a `SongDoc` from it,
synthesizing ids from spelling (`"live:" + occurrence id` as the *section*
id, so two parts of one section had different section ids) and lowering a
second time. A part without `part_id` took its name as its id unchanged, so
part names and `fill` prefixes outside the identity alphabet
`[A-Za-z0-9_.:-]` were rejected.

`CONTEXT.md` says a named pattern definition's identity is distinct from its
name's spelling. That identity comes from the Draft's source map, which
tracks definitions across edits. The source map does not track `section(…)`
or `part(…)` declarations, and it crosses the browser wire with a fixed shape
(schema 1).

## Decision

1. **Mini's song parser builds the `SongDoc` and lowers it once**, with the
   identities the source gives:
   - occurrence: the `part_id` when written, otherwise the part's name; a
     `fill` occurrence: its name, the prefix and gap index;
   - section: its name;
   - layer: `main`, the one layer of a Mini section.
2. **Names and part ids are encoded into the identity alphabet.** Code
   units outside it, and `.` itself, are written as unpadded lowercase hex
   between dots (`é.` → `.e9..2e.`), so any text works and distinct texts
   stay distinct. A `part_id` is encoded like a name, so written ids and
   names share one space: `part("a")` and `part_id("a", …)` are the same
   part, while `part("a.b")` and `part_id("a.2e.b", …)` are not. Mini checks
   parts for repeats before building the document and reports a repeated
   name, or a repeated id when either part wrote one, where it repeats; an
   empty name or id is a mistake at that part.
3. **Renaming a section or an unnamed-id part gives it a new identity.** This
   differs from named pattern definitions on purpose: nothing tracks these
   declarations across edits, and nothing in playback continuity depends on
   their identity (below).

## Consequences

- What section identity affects: `SongEventOrigin::section`, and through it
  `SongVoiceScope::section` / `layer` matching, which no production caller
  uses. Material retention across live edits keys entries by occurrence and
  layer id and the entry's own key (`song_entry_specs`), so renaming a
  section does not drop retained material by itself.
- Renaming a section, or the name of a part with a `part_id`, plays on;
  renaming a part without one places another occurrence, which needs a
  Restart while playing (ADR-0033).
- Names and part ids containing `.` get a different id than before #293
  (`a.b` → `a.2e.b`); this matters only across the upgrade. A `part_id`
  outside the identity alphabet, rejected before, is accepted.
- Giving tracked sections and parts identities that survive renames would
  mean tracking their declarations in the source map and changing the wire
  schema; it is not done until playback needs it.
