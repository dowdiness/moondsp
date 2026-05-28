# Loom upstream requirements from mini-CST authoring evidence

- **Status:** Requirements extracted from the `moondsp` mini-CST spike.
- **Audience:** upstream `dowdiness/loom` / `dowdiness/seam` follow-ups.
- **Scope:** authoring-only parser/projection ergonomics. This does not approve
  a production mini parser switch.

## Evidence base

The current evidence is intentionally spec-local:

- Production mini authoring still uses `mini/incr_authoring.mbt`, which keeps a
  last successful `PatternDoc`, accepts editor source-edit spans, and reuses one
  lowering cache across reparses.
- The Loom comparison lives under `specs/loom-mini-cst/` and constructs a
  parser with `@loom.new_parser(input, mini_grammar)`, shares
  `parser.runtime()` with the projection memo, and exposes the result through a
  long-lived observer.
- `specs/loom-mini-cst/src/projection.mbt::LoomMiniAtomProjection::new` carries
  `previous_doc`, `previous_atoms`, `previous_source`, and
  `pending_source_edit` because stable semantic identity is not provided by the
  CST API alone.
- `specs/loom-mini-cst/src/projection_test.mbt` contains the provenance matrix,
  recovery matrix helper, and PR #104 control-method cache-reuse helper that
  define the current regression evidence.

These requirements are about upstreaming the reusable parts of that pattern.
They do not ask `moondsp` to add loom/seam to root `moon.mod`, route
`mini.parse` through Loom, or redo PR #104's `.cutoff(...)`, `.gain(...)`, and
`.pan(...)` projection parity.

## 1. Stable identity across edits

### Requirement

Loom should provide, or document a small companion abstraction for, stable
projection identity across editor edits. The abstraction must be stronger than
"this CST subtree was reused" or "this token has the same source span". A
semantic projection needs to map unchanged user-facing leaves to the same domain
IDs after:

- insertions among duplicate tokens;
- deletions that shift later tokens left;
- replacements inside one duplicate family;
- whitespace-only edits;
- line/layer insertions that change surrounding CST shape; and
- temporary syntax diagnostics followed by recovery.

The API should let an authoring layer supply an editor edit span when available,
fall back to source diffing when it is not, and keep enough baseline information
for recovery after a malformed intermediate document. Domain code must still be
able to choose its public ID shape; in `moondsp` that shape is
`mini:sound:<name>:<n>` and `mini:note:<value>:<n>`.

### Current workaround in `moondsp`

`LoomMiniAtomProjection` realigns projected atoms itself. It preserves prefix
and suffix IDs around an edit window, allocates fresh IDs inside the changed
window, and carries a pending source-edit span through diagnostic states so the
next valid parse can still reuse the correct baseline.

### Acceptance evidence to preserve

An upstream identity helper should be able to replace the spec-local realignment
without weakening these checks:

- duplicate sound/note insertion, deletion, and replacement rows in the
  provenance matrix;
- whitespace-only edits preserving sourced event IDs;
- `$:` line insertion and layer-comma edits preserving unaffected IDs;
- parse-error recovery from `s("bd sd bd bd"` to `s("bd sd bd bd")` producing
  `mini:sound:bd:0`, `mini:sound:sd:0`, `mini:sound:bd:2`,
  `mini:sound:bd:1`; and
- lowered-event ID and lowering-cache reuse checks, including the PR #104
  unchanged control-method chain case.

## 2. Projection helper ergonomics

### Requirement

Loom/seam should make direct CST projection boring and hard to misuse. A
semantic projection needs direct-child and direct-token queries with predictable
cardinality behavior, source ranges, and ordering. It should not rely on
accidental recursive traversal when validating method arguments or nested
callback syntax.

Useful upstream surface area would include:

- a consistent projection layer around the existing direct child/token query
  primitives, including optional/required `token_of_kind`-style helpers;
- cardinality helpers that turn "expected one direct method name" or "expected
  no direct comma" into concise projection code;
- projection examples that use `@loom.new_parser`, `parser.runtime()`,
  `parser.syntax_tree()`, and `parser.diagnostics()` without constructing a raw
  imperative parser inside a derived computation; and
- guidance for the `SyntaxNode -> private IR -> domain document` pattern, so
  projection code does not encode domain semantics directly in CST traversal.

### Current workaround in `moondsp`

The mini spike uses direct seam queries where they exist, but still keeps local
traversal wrappers and many repeated cardinality checks in `projection.mbt`.
That was acceptable for a spec, but it is too much hand-rolled boilerplate for a
reusable authoring pattern.

### Acceptance evidence to preserve

A helper pass is successful only if the existing projection tests keep catching
nested-argument mistakes, invalid callback-shaped method arguments, and
mode-incompatible atoms. Ergonomic helpers must not make the projection more
permissive than the current spec-local semantics.

## 3. Diagnostics plus last-good semantic document

### Requirement

Loom should document, and ideally provide a small attachment template for, the
canonical authoring pattern:

1. parse diagnostics update immediately;
2. a malformed CST does not replace the last successful semantic document;
3. the next successful parse can reuse the last successful semantic document
   and the original edit baseline; and
4. callers can adapt the richer state back to a compatibility
   `Result[..., String]` API when a project has not chosen a public diagnostic
   type.

The important distinction is that parser diagnostics and semantic projection
state are related but not the same cell. Diagnostics should be observable for an
editor, while the semantic document used for reuse remains the last known-good
one until projection succeeds again.

### Current workaround in `moondsp`

`LoomMiniAtomProjection::new` reads parser diagnostics before projection. When
diagnostics are present, it returns `Err("loom mini syntax has diagnostics")`
without updating `previous_doc`, `previous_atoms`, or `previous_source`. If the
malformed edit came from the last successful source, it stores a
`pending_source_edit`; after recovery, that pending span drives semantic ID
realignment and is cleared only after a successful document is built.

### Acceptance evidence to preserve

The recovery matrix helper should remain the minimum regression gate:

- initial valid input has zero diagnostics;
- malformed input has parser diagnostics and projection returns the expected
  error;
- both Loom projection and `MiniAuthoringPipeline` reject the malformed state;
- recovered input has zero diagnostics; and
- recovered sourced event IDs match the current mini authoring pipeline.

A future upstream example should also cover semantic projection failures that
are not syntax diagnostics, such as mode-incompatible atoms, and state whether
those failures retain or replace the last-good semantic document.

## 4. Authoring-only dependency boundaries

### Requirement

Loom adoption must be easy to isolate as authoring infrastructure. A downstream
library should be able to keep runtime parsing independent from Loom while using
Loom for editor diagnostics, CST projection, and incremental authoring tests.

For `moondsp`, that means:

- no accidental loom/seam path dependencies in root `moon.mod`;
- no dependency from browser/runtime packages to the nested
  `specs/loom-mini-cst` module;
- a publishable dependency story before any production package depends on Loom;
- wasm-gc/browser build proof if Loom enters any package reachable from the
  AudioWorklet path; and
- a clear authoring facade so existing mini callers do not need to learn Loom
  APIs.

### Current workaround in `moondsp`

The spike is a nested, non-publishing module with path dependencies to editable
Loom/seam checkouts. That is useful as an upstream API canary, but it is not a
release plan for the published `dowdiness/moondsp` package.

### Acceptance evidence to preserve

An upstream or downstream promotion plan should include a manifest check proving
that Loom remains out of the runtime graph unless the same change also proves
browser target compatibility. Until then, `specs/loom-mini-cst/` remains the
right home for Loom evidence in this repository.

## Open upstream design questions

- Does stable projection identity live on syntax tokens, CST nodes, an edit
  lineage map, or a separate authoring projection helper?
- Should projection cardinality helpers live in `seam` because they operate on
  CST views, or in `loom` because they are part of parser-authoring guidance?
- Is the diagnostics/last-good pattern a library type, an example attachment, or
  both?
- How should whole-source `set_source` recovery differ from editor-span
  `apply_edit` recovery when no precise edit span is available?
