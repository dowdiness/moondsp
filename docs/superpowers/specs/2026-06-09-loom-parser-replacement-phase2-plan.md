# Phase 2 Implementation Plan: loom parser replacement for mini doc + song projection parity

## Objective
Deliver a verified, stepwise rollout for authoring-path parity in the spike `specs/loom-mini-cst/`, while avoiding shipping integration into `mini/` and avoiding loom publish. Scope is limited to `doc`- and `song`-level parser parity, with measurable harnesses and issue-driven closure.

## Exit criteria
- Doc-level parity: positive/negative corpus is green for structural + value-level snapshot parity (id + `ControlMap` + `TimeSpan`) across the fixed `[0, 8)`-cycle parity window (see Orchestrator resolution 1) and deterministic message-shape contract only (Err exists).
- Positive-control calibration: at least one deliberately divergent oracle/loom input pair is proven to fail before green acceptance.
- Song-level parity: helper-level structural parity against `@mini.parse_song_with_bpm` is green over a dedicated corpus and covers explicit oracle error cases.
- Provenance coverage is expanded from hand-picked rows to the full doc corpus.
- All edits remain confined to spike boundary and do not modify shipping `mini/` integration.

Phase 1, 3, 4 names refer to the orchestrator’s sequence below (fixed): Piece 1 → Piece 4 → Piece 2 → Piece 3.

---

## Piece 1 — Systematic differential corpus harness (build first, then calibrate)

### Step 1 (Piece 1)
Create a canonical doc corpus source in the spike test module by harvesting mini doc inputs from `mini/mini_test.mbt` and the existing `specs/loom-mini-cst/src/projection_test.mbt` corpus into one deduplicated list, preserving explicit malformed/valid labels and source-line diagnostics expectations.
- Invariant: every case that is meaningful to the hand-written parser is represented exactly once and can be replayed against both implementations.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon check`.

### Step 2 (Piece 1)
Add a value-level event parity helper in the same test module. **Correctness note (Codex finding 1 — `ControlMap` has NO derived `Eq`; `pattern_node()` returns `PatternNodeId?`; `Event.whole`/`part` are `TimeSpan?`):** do NOT assert a raw tuple equality. Instead canonicalize each lowered `PatternSnapshotEvent` to a comparable form and compare those: the optional `pattern_node()` as `id.value()` or `"<none>"`; the `ControlMap` value via `.entries() == .entries()` (`Map[String,Double]` supports structural `==`) — or a sorted-key canonical string if map `==` proves unavailable; and `whole`/`part` `TimeSpan?` each rendered to a canonical `num/den` rational string with an explicit `None` token. Compare the ordered list of canonical events, queried over the fixed `[0, 8)`-cycle window (Orchestrator resolution 1), identical on both sides.
- Invariant: leaf-ID-only parity is insufficient; passing implies equivalent lowered ControlMap payload + timing over `[0,8)`. The helper must compile without any new `Eq`/`Show` derive on production `@pattern` types.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon check` (compile gate only; the parity claim is PROVEN at the Step 5 `moon test` gate).

### Step 3 (Piece 1)
Implement a differential boundary runner for doc-level inputs that:
- executes both `@mini.parse_doc` and `LoomMiniAtomProjection::parse_doc`,
- enforces success parity or error parity for malformed inputs,
- records message mismatches for Err cases without failing (separate characterization log),
- runs the Step-2 value-level parity helper when both parse succeed.
- Invariant: failures to align on either side are treated as actionable parity holes, while message string drift is isolated and non-fatal by contract.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon check` (compile gate only; parity proven at Step 5).

### Step 4 (Piece 1, mandatory positive-control)
Before claiming any corpus pass, calibrate against the **Step-2 value-level helper specifically** (Codex finding 4 — calibrating only the legacy root/leaf-ID check is theatre, since it can pass despite ControlMap/TimeSpan regressions). Construct a divergence the ID-level check would MISS but the value-level helper must catch — e.g. two snapshots with identical node IDs but a differing `ControlMap` value (gain/note) or a differing `whole` TimeSpan — and assert the value-level helper reports mismatch. Only after a green corpus run proves the helper fires on this skew may the gate be retained as a regression sentinel.
- Invariant: the VALUE-LEVEL helper (not just ID parity) is sensitive and not vacuous.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon test specs/loom-mini-cst/src/projection_test.mbt`.

### Step 5 (Piece 1)
Wire the canonical corpus runner through a single doc-level boundary test entrypoint and execute it once as the Piece-1 green gate.
- Invariant: complete doc-parsing compatibility is measured as a whole, not just isolated examples.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon test`.

## Piece 4 — Grammar/projection gap closure (looped triage after Piece 1)

### Step 6 (Piece 4)
Run the Piece 1 corpus, collect failures, and triage each as one of: grammar mismatch, projection mapping mismatch, expected oracle mismatch, or unsupported behavior.
- Invariant: no divergence is silently ignored; every delta has an explicit ownership bucket.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon test specs/loom-mini-cst/src/projection_test.mbt`.

### Step 7 (Piece 4)
For each triaged doc mismatch, make minimal targeted fixes in CST grammar (`syntax_kind.mbt`, `token.mbt`, `lexer.mbt`, `parser.mbt`) and/or `projection.mbt`, with one fix at a time.
- Invariant: each iteration should reduce the bounded failure set without regressing previously green cases.
- Extend: `specs/loom-mini-cst/src/syntax_kind.mbt`, `specs/loom-mini-cst/src/token.mbt`, `specs/loom-mini-cst/src/lexer.mbt`, `specs/loom-mini-cst/src/parser.mbt`, `specs/loom-mini-cst/src/projection.mbt`.
- Verify: `NEW_MOON_MOD=0 moon check`.

### Step 8 (Piece 4)
Repeat Step 6 until the doc corpus is green under value-parity and negative parity, recording any intentional exceptions in design notes.
- Invariant: Piece 1 completes only when the doc corpus has zero unsanctioned parity failures.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon test`.

## Piece 2 — Song-level projection and song boundary parity (net-new surface)

### Step 9 (Piece 2)
**Scope note (Codex finding 3):** the spike currently exposes ONLY `LoomMiniAtomProjection`/`parse_doc()` → `PatternDoc`; there is NO song grammar or song-projection surface yet. Step 9–10 are substantial net-new construction (new syntax kinds + tokens + lexer rules + parser productions for the outer forms, plus a new projection entrypoint — e.g. `LoomMiniSongProjection` or a `parse_song()` method returning `ParsedSong`), not a harness tweak. Sequence them as their own check-after-each-edit substeps.

Extend spike grammar to parse outer song wrapper forms and keep doc-pattern body handling delegated to existing doc expression projection logic:
- `song(item, ...)`, `bpm(n)`, `section("name", length_rational, pattern_expr)`, `part("occ","section"[,start])`, `part_id("id","name","section"[,start])`, `fill("prefix","section")`.
- Invariant: song syntax parsing remains a single composition point and does not duplicate doc grammar logic.
- Extend: `specs/loom-mini-cst/src/syntax_kind.mbt`, `specs/loom-mini-cst/src/token.mbt`, `specs/loom-mini-cst/src/lexer.mbt`, `specs/loom-mini-cst/src/parser.mbt`.
- Verify: `NEW_MOON_MOD=0 moon check`.

### Step 10 (Piece 2)
Add projection wiring in `specs/loom-mini-cst/src/projection.mbt` to materialize parsed song CST into `ParsedSong{song: @song.Song[ControlMap], bpm: Double?}` by reusing mini song models (`Section`, `Song`, `SongPart`) and section-body lowered snapshots.
- Invariant: projection semantics for section bodies are identical to doc parser outputs when embedded under song clauses.
- Extend: `specs/loom-mini-cst/src/projection.mbt`.
- Verify: `NEW_MOON_MOD=0 moon check`.

### Step 11 (Piece 2)
Add a new song-level boundary helper (in spike test module) that decomposes equality. **Correctness note (Codex finding 2 — `@song` exposes no stable section identity: `SongPart.id` is optional, `Section` carries no `SectionId`, `SectionOccurrence` exposes only a `Section` object).** Compare by NAME and lowered value, never by object identity:
- sections keyed by `section.name()`: same name set and same `length_cycles`,
- each section’s lowered body parity via the Step-2 value-level event helper over the `[0,8)` window (this is the primary comparison, not a fallback — it is what makes section-body parity assertable without identity),
- part layout: ordered by the oracle's part order, compared on `name` (display) + `start` (`Rational?`) + the resolved section's `name()` + the optional occurrence `id` (compare `Some/None` shape and value when present),
- bpm equality including `Some/None` shape,
- fill outcomes: compare the post-`fill_gaps` Song's resulting parts (by the same name/start/section-name decomposition) rather than internal fill spans,
- TimeScope: confirm both sides use `@song.TimeScope::identity()` for sections (the oracle hardcodes it) so scope is not a hidden divergence axis,
- both-parse and both-Err parity for malformed inputs (duplicate section, duplicate bpm, unknown section, invalid occurrence id, non-positive section length, non-positive bpm, empty `song()`, trailing input).
- Verify-before-asserting (Orchestrator resolution 2): Step 9's FIRST action is `NEW_MOON_MOD=0 moon ide outline song/` to confirm the `name()`/`length_cycles`/parts/`start`/`id` accessors above actually exist; if any is missing, widen the lower-to-snapshot comparison rather than adding an `Eq` to `@song` types.
- Invariant: song-level structural and temporal meaning are equivalent, not just parser string parity.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt` (new helper + tests).
- Verify: `NEW_MOON_MOD=0 moon check`.

### Step 12 (Piece 2)
Build a canonical song corpus by sourcing `mini/song_mini_test.mbt` cases and a focused malformed set, then run a dedicated dual-parser parity test for `@mini.parse_song_with_bpm`.
- Invariant: all oracle-level positive/negative song behaviors are exercised in one reproducible boundary.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon test`.

## Piece 3 — Snapshot/provenance systematization

### Step 13 (Piece 3)
Lift existing provenance checks in `projection_test.mbt` from hand-picked rows into a corpus-driven matrix: record parse status, IDs, last-good state transitions, and event/value parity linkage for the canonical doc inputs.
- Invariant: provenance drift is measured as a maintained historical expectation set, not anecdotal spot checks.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt`.
- Verify: `NEW_MOON_MOD=0 moon test` (Codex finding 5 — this step makes a measurement claim, so it must RUN, not just compile; `moon check` is insufficient here).

### Step 14 (Piece 3)
Persist provenance/snapshot summaries as markdown notes in the spike test section (or companion report file under the spike docs) with clear “fixed vs known gap” buckets so future phases can diff behavior and audit recovery behavior.
- Invariant: no unresolved provenance expectation is left implicit.
- Extend: `specs/loom-mini-cst/src/projection_test.mbt` (or add `specs/loom-mini-cst/docs/phase2-provenance-notes.md` if reporting would be noisy in tests).
- Verify: `NEW_MOON_MOD=0 moon check`.

## Design-correctness issues flagged before implementation
- Event parity window definition is under-specified for transformed timing operators (`slow`, `fast`) across cycle boundaries; this plan assumes parity over one representative cycle as used by existing `query_one_cycle` behavior, but that window must be explicitly documented and asserted as deterministic.
- Song structural comparison currently depends on `Song`/`Section`/`SongPart` accessors and `SongSnapshot` query APIs being stable enough for deterministic decomposition; if any type lacks direct ordered occurrence introspection, a canonical projection-to-doc intermediate may be required.
- The test harness currently treats parser-message text as non-contractual for both sides; this can hide user-facing regressions even when parsing behavior is unchanged semantically.

## Orchestrator resolutions (Opus) to the flags above

1. **Parity window (flag 1).** The differential test is apples-to-apples — both
   oracle and loom lower identically — so even a one-cycle window validly detects
   divergence. But to avoid a blind spot for `slow(n)` (which pushes content past
   cycle 0), the harness queries an identical, named, generous fixed window on
   BOTH sides: `[0, 8)` cycles (covers `slow`/`fast` factors the mini corpus
   uses). Define it as a single named constant in the harness; document why 8.
   If any corpus input uses a factor whose period exceeds 8, the triage loop
   (Piece 4) widens the constant rather than special-casing the input.
2. **Song accessors (flag 2).** Make this Step 9's FIRST action and a
   verify-before-asserting gate, not an assumption: run `NEW_MOON_MOD=0 moon ide
   outline song/` and confirm `@song.Song`/`Section`/`SongPart` expose ordered,
   deterministic accessors (parts, section lookup, occurrence id, start, name).
   If sufficient → decompose directly. If NOT → fall back to lowering each section
   body to a snapshot and reusing Piece 1's event-parity machinery, comparing only
   the scalar part/section metadata that IS accessible. Do NOT add a derived `Eq`
   to `@song` production types.
3. **Err-message characterization (flag 3).** Correct for Phase 2: the authoring
   path's only hard contract is `Result[_, String]`. The char-position error UX
   (`get_pattern_error_length`/`get_pattern_error_char`) is the BROWSER/runtime
   path = Phase 3's error-adapter scope (Phase 0 already prototyped an
   `error_adapter`). So characterize-don't-fail is right HERE — but the divergence
   table the harness records is a REQUIRED Phase 2 deliverable handed forward to
   Phase 3's error-adapter design, not discarded.
