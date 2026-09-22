# Playback position UI

Status: origin-preserving compiler, Mini Draft, browser ownership/wire adapters,
and version-correlated admission implemented. Playback observations and
visualization remain future work.

## Goal

Make the current playback position visible so composers can understand where
music is playing and audition a passage without replaying the whole song.

The UI must distinguish four separate playback dimensions:
1. Current playback state (e.g., playing vs. stopped).
2. Engine-reported playback position.
3. Acceptance status of edited scores (submitted, accepted, or rejected).
4. Pending material transitions waiting for their entry boundaries.

Accepting a score does not imply that all materials immediately adopt the new
source, because each material transitions at its own boundary. Conversely, a
syntax or evaluation error in the draft score must never lead the UI to claim
that rejected edits are currently playing.

[ADR-0018](../decisions/0018-playback-visualization-origin-truth.md) defines the
proposed contract for status reporting and pattern-onset source highlighting.
Under its source-identity model, unchanged tokens can continue highlighting
during partial material transitions or in the presence of unrelated syntax
errors. Seeking and song-mode source highlighting remain outside that proposal;
the broader navigation questions below remain open.

The pattern-origin implementation contracts below were selected on 2026-09-20.
The shared kernels, exact snapshots, checked source identity types, typed
document transforms, causal Draft transactions, partial binding recognition,
frozen playback inputs, and complete-path origin location are implemented.
The live editor now submits those frozen inputs through strict wire validation;
the scheduler retains exact origins across material transitions. This does not
implement playback observations or browser highlighting.

## Design questions

- Choose a useful position display for both finite songs and repeating patterns.
  Consider sections, elapsed time, and musical time without assuming every
  pattern shares one bar length.
- Define where Play starts after Stop, and how returning to the beginning works.
- Decide how users select a section or position to audition.
- Define seek behavior for sustained notes, automation, and effect tails before
  adding position controls. Display the audio engine's reported position.

Button layout, shortcuts, and stop/resume behavior remain undecided. The current
playback-control cleanup does not include a timeline, seeking, or new transport
semantics. Validate the future UI with a long song and overlapping patterns of
unequal lengths.

## Pattern-origin implementation contracts

These contracts implement ADR-0018's pattern-mode requirements. Status reporting
under #156 still precedes release of highlighting. Song highlighting, seeking,
new transport semantics, and wholesale parser migration are excluded.

Interface 1's compiler APIs, Interfaces 2–3's MoonBit authoring core, scheduler
capability adapters, and browser/worklet submission are available. Observation
transport and visualization remain proposed. The authoring cutover removes the
old owner and setters without aliases.

### Caller interface and vocabulary

Name public operations after what the caller does, not the compiler machinery
behind them. The editor uses one `@mini.Draft`: it edits the draft, prepares
playback input, and locates event origins. It does not manipulate token
registries, binding-edge tables, source generations, or lowering caches.

The application-facing vocabulary is:

- `Draft`: the mutable score being edited, including invalid intermediate text;
- `DraftVersion`: an opaque identity for one state of that draft;
- `EditTransaction`: an atomic batch of text edits against a draft version;
- `DraftState`: a read-only view of text, version, and the currently known
  diagnostic, not a declaration of playback acceptance or readiness;
- `PlaybackInput`: an immutable input that the player can evaluate for
  acceptance, not an accepted score; and
- `OriginLocation`: where a particular event's source is represented in the
  current draft, or why it cannot be located.

`@mini.Draft` replaces `MiniAuthoringPipeline`; it does not wrap another owner.
Package qualification supplies the Mini context. The owner applies explicit
transactions rather than reactive string-equality backdating.

Use `origin` consistently for source identity and the reference route to it.
Use `location` only for current text ranges. Use `version` for draft state,
not `frame`, which already has an audio meaning. “Authored” describes how a
pattern was created, not whether its events have origins, so it is not the name
of the stronger execution capability.

The lower-level compiler contract uses the deliberately explicit
`PatternSnapshotWithOrigins` and `lower_with_origins`. The longer name states
the guarantee without requiring callers to interpret “tracked,” “mapped,” or
“authored.” Keep the existing `lower` verb rather than inventing a second
`compile` convention for the same operation.

### Invariants

1. Identity follows editing history, not equal text, values, offsets, or revisions.
2. Exact attributed execution and ordinary execution share the existing `Pat`
   kernels. Erasing provenance preserves event values and whole/part spans,
   material boundaries, entry keys, periods, and content-signature knowledge.
3. Source atoms, reference bindings, voice-effect scopes, material versions, and
   playback runs have distinct identities and owners.
4. A draft, a successfully compiled draft, an accepted score, and the source of a
   currently playing material are not interchangeable.
5. Presentation observes successful dispatch. It neither queries a second
   scheduler nor reconstructs execution from active voices.

### Interface 1: origin-preserving compilation

**Owner:** `pattern` owns compilation and its opaque result. `mini` supplies
source identities and resolved references from the draft owner. The scheduler
consumes the result; it does not manufacture provenance.

#### Types and construction

| Type | Meaning |
| --- | --- |
| `SourceEpoch` | Internal identity namespace for one uninterrupted source-tracking lifetime; unrelated to audio power. |
| `SourceAtomId` | One continuously represented sound, note, or chord atom. |
| `DefinitionId` | One named-pattern definition, identified by its declaration-name occurrence. |
| `ReferenceId` | One occurrence of a pattern name used as an expression. |
| `ReferenceBindingId` | One uninterrupted, proven reference-to-definition relationship. |
| `EventOrigin` | A source atom plus an immutable outer-to-inner sequence of reference bindings. |
| `ScopedValue[A, EventOrigin]` | Private exact-compiler payload containing `A`, mandatory origin, and separate voice scope; no text coordinates. General lowering specializes the same kernel with `Unit` origin. |
| `PatternSnapshotWithOrigins[A]` | Opaque snapshot whose emitted events have exact origins. |
| `PatternSnapshot[A]` | Existing general snapshot; no exact text-origin promise. |

Epochs and identity tables belong to the implementation and its wire adapter,
not the editor caller's interface. Source IDs are opaque, epoch-qualified
values. `DraftVersion` hides the epoch and transaction counter; callers retain
and compare versions but do not allocate them or perform arithmetic on them.

A factory in the main-thread authoring module allocates non-reused source
epochs. Each epoch allocates atom/definition/reference/binding serials from a
monotone counter. Serials and draft revisions use checked integers in
`1..=2^53-1`, with initial draft revision zero. This fits MoonBit `Int64` and
exact JavaScript integers. They never wrap; exhaustion is an explicit failure.
Wire tables may qualify local serials once with the enclosing source epoch.

`PatternNodeId` remains a **different identity** for the existing document graph
and voice scopes. In particular, the browser's current snapshot-local graph-ID
derivation and `stable_seed(doc.root().value())` behavior must not be replaced
with causal source IDs. Source epochs, atom IDs, and reference binding IDs must
never enter degradation seeds, entry keys, or musical content signatures.

Keep the existing `PatternDoc` graph; do not introduce a second authoring IR.
Its lower-level construction and compilation contracts are:

```text
PatternDoc::atom(id, source_atom, value) -> PatternDoc[A]
PatternDoc::control_atom(id, source_atom, key, value) -> PatternDoc[ControlMap]
PatternDoc::reference_with_binding(id, resolved_reference) -> PatternDoc[A]
PatternDoc::lower_with_origins(cache?) ->
    PatternSnapshotWithOrigins[A] raise PatternDocError
```

An optional existing `PatternLoweringCache` avoids two new method names for
the same operation. Cache use cannot change the result or its guarantees.
The implementation uses the package's existing concrete raising convention,
not a new `Result` boundary. These compiler operations are not additional
methods on the editor's `Draft`.

`control_atom` derives the same musical signature as the existing control
constructor. Generic `atom` does not invent a known signature for arbitrary
values. `ResolvedReference` contains the definition identity, definition
document, reference identity, and reference-binding identity; it is produced
by name resolution, not assembled from a spelling guess during lowering.

**A chord keeps its existing generated tone nodes and stack structure.** Each
tone receives the same source-atom ID, but retains its own graph ID and
voice-effect scope. This preserves tone-specific voice operations and material
structure; generated tone IDs are not primary highlight targets.

`pure`, `from_pattern`, ordinary `reference`, and general `lower` remain genuine
programmatic operations. They do not claim that a graph node is an editor atom.
`lower_with_origins` rejects an unattributed event-producing leaf or a reference
without its source binding before returning the stronger snapshot:

- `MissingAtomOrigin(node)` for a runtime-only primary-event source;
- `MissingReferenceBinding(node)` for a source reference without its binding;
  and existing structural errors for missing/duplicate document nodes.

The right-hand control provider in a merge is not a primary-event source and
does not need an atom. Its controls can affect a left event without becoming
that event's primary origin. A silence-only document is exact vacuously.

#### Operation laws

| Operation | Origin behavior | Existing behavior to retain |
| --- | --- | --- |
| fast / slow / reverse / gate | Carry the input origin. | Existing time arithmetic and parameter guards. |
| sequence / stack | Carry each selected child's origin. | Ordering, entry decomposition, and material boundaries. |
| euclid / degrade | Carry origins of retained events; no origin for removed events. | Selection, seeds, and whole/part spans. |
| value-only filter-map | `Some` inherits origin; `None` removes the event. | Unknown callback signatures remain unknown. |
| every / jux | Apply a known `TimeTransform` to attributed payloads. | Cycle choice, pan values, and atomic jux material structure. |
| merge-control | Preserve the left event's origin. | Fold overlapping right controls in the current order. |
| reference with binding | Prepend its reference binding. | Existing material naming and separate voice-scope semantics. |

`PatternDoc::every` and `PatternDoc::jux` change from `Pat -> Pat` callbacks to
the existing `TimeTransform` data type. Arbitrary pattern callbacks remain on
`Pat`; a caller deliberately using one can wrap the result as a general runtime
document. Value-only callbacks need not be banned: lifting `A -> A?` cannot
invent an untraceable event source.

Extract private control-merge, jux, and payload-map kernels **before** using
them for attributed values. Both ordinary APIs and exact compilation use these
kernels. Do not compose public `stack`/`filter_map` and assume their material
metadata is equivalent. Delete the separate `SourcedPat` timing implementation.

Exact and general document compilation may specialize payload types, but must
not contain separate timing algorithms. An exact snapshot's raw-event and
ordinary-snapshot projections share its compiled execution. Browser routing
uses an exact-preserving `select_control`, not erasure followed by re-attribution.

Do not silently upgrade document content signatures while changing callback
representation. In particular, preserve the current unknown-signature policy
where document every/jux used opaque callbacks; improved signature precision
would change material reconciliation and is a separate behavioral change.
Compare the browser path against current `parse_play_source` lowering: raw
`mini.parse` already uses a different default degradation seed and is not a
universal baseline for browser randomness.

Source IDs and bindings are excluded from musical `same_content`, but included
in provenance-sensitive cache identity. Exact and general cache results cannot
be interchanged. A same-music update must refresh its source metadata without
forcing a musical restart or reusing a stale origin.

Voice-scope ancestry remains separate, including the currently broad scopes of
some transforms. Preserve transformed and untransformed branch scope behavior
individually. Do not narrow retune/release/kill scopes as a side effect of
correcting source attribution.

#### Consumers and failure ownership

General snapshot queries expose scoped events; origin-preserving queries expose
`EventWithOrigin[A]`, containing the event, its origin, and its voice scope.
Remove `pattern_node()` as a purported primary-source accessor. Move scope
consumers to scoped-event accessors and origin consumers to
`EventWithOrigin.origin`; do not retain a misleading alias.

The scheduler's existing snapshot/source sum gains a pattern-with-origins case.
General patterns and songs remain explicit runtime-only cases. At its dispatch
seam, one exhaustive match distinguishes events with origins from runtime-only
events; only the former can create source-highlight observations. Failure to
compile with origins must not be converted to the runtime-only case.

For valid Mini authored submissions, an unattributed leaf or missing binding is
a compiler contract failure, not “accepted, but highlighting disabled.”

### Interface 2: draft ownership and submission

**Owner:** `@mini.Draft`, implemented in the Mini package and intended to be
instantiated once per editor document as **MoonBit compiled to JavaScript on
the main thread**. The remaining browser integration makes TypeScript `Player`
hold this owner and orchestrate commands. CodeMirror supplies transactions;
the worklet consumes frozen inputs. Neither infers another identity history.

Export the bridge from a root-module `browser/authoring` JS package importing
`mini`, and integrate its generated artifact into
`web/live/scripts/sync-assets.mjs`. Do not put parser state in the separate
`packages/browser/host` audio-power module. This live-editor integration does
not require adding a new public npm entry point.

#### Public operations

```text
DraftVersion                    // opaque document epoch + revision
TextEdit = (from, to, inserted)  // OLD-document UTF-16 code units
EditTransaction = (base: DraftVersion, edits: Array[TextEdit])

Draft::new(text) -> Draft raise DraftEditError
Draft::state() -> DraftState
Draft::edit(transaction) -> Result[DraftState, DraftEditError]
Draft::prepare_playback() -> Result[PlaybackInput, DraftDiagnostic]
Draft::locate_origin(origin) -> OriginLocation
Draft::reset(text) -> Result[DraftState, DraftEditError]
Draft::dispose() -> Unit
```

`prepare_playback` captures valid source input. It does not submit a command,
allocate audio resources, or promise runtime acceptance. Pattern and song
preparation both return `Ok(PlaybackInput)`; invalid drafts return `Err`.
Whether the input contains origins is a property of the input, not a third
preparation outcome alongside success and failure.

`reset` explicitly abandons old source continuity; ordinary edits use `edit`.
`state` and `locate_origin` are read-only. `DraftState` exposes no mutable source
or binding tables. Diagnostics carry their `DraftVersion`, including failures
discovered by `prepare_playback` after partial syntax recognition.

Construction can exhaust the epoch namespace; edits/reset report explicit
identity exhaustion rather than wrapping or partially publishing state.
Source epochs may rotate within one document epoch after a tracking gap or
confirmed mode transition. Unknown syntax alone retains the prior mode.

The local consuming API is `PlaybackInput::compile(previous?, max_query_span?)`:
`Pattern(exact_snapshot, bpm)` retains origin capability;
`Runtime(PlaySource)` handles songs and explicit `PlaybackInput::text` inputs.
`encode_wire`/`decode_wire` and player submission are implemented. The optional
previous document applies only to explicit runtime text; exact compilation
uses the frozen witnesses without reusing an old document. Preparation and
compilation do not alter manual command semantics.

All edits in one transaction are ordered, nonoverlapping, and relative to its
single base version. Validate the whole change before mutation, derive the new
text from the edits, and publish atom/binding/text changes together. There is
no independently supplied “new full text” that can disagree with them.

A `ViewUpdate` containing multiple transactions calls `Draft::edit` once for
**each** transaction in order. A transaction containing multiple ranges calls
it once with all ranges. Do not collapse transaction history into
`update.changes`.

Every nonempty text-change transaction advances the draft version, including
replacement with identical text. Selection-only changes do not. Do not let
String equality or incremental backdating suppress a causal transition.

Identity-relevant lexical and partial syntax recognition runs eagerly after
each transaction. **Submission and lowering may be debounced; this recognition
may not.** This deliberately replaces the earlier shorthand “debounce parsing.”

An atom retains identity only if its entire span survives replacement, maps
to exactly one complete atom extent, and keeps its provable source role.
Insertion strictly inside it retires it. Endpoint insertion preserves it only
if the new lexical extent still matches: whitespace can preserve an atom, while
a merge/split cannot. Changing `note(...)` to `s(...)` changes atom roles.
Cut/paste, same-text replacement, delete/retype, and undo reinsertion do not
resurrect retired identities. An atomic transaction has no invented intermediate
states between its ranges.

Rename the pipeline's `accepted_doc` concept to `last_valid_doc`: it is an
internal compilation baseline, not proof of playback acceptance. Applications
use `DraftState` rather than that baseline to present the current draft. The
existing browser `Session` remains the accepted-score authority.

#### Immutable input and receipt

`PlaybackInput` is an opaque immutable value. `Draft::prepare_playback` creates
draft inputs; `PlaybackInput::text(text)` deliberately creates text-only inputs
for programmatic callers. Neither constructor means the runtime has accepted
the input. Do not reuse the existing parsed `mini.PlaySource` name: input and
parsed source are different stages.

The private transport representation has two alternatives:

```text
DraftInput(version: DraftVersion, body:
    Pattern(text, source_map)
  | Song(text))
TextInput(text)
```

The application forwards the opaque value to `update` or `restart`; it does not
construct or switch over these records. The wire adapter encodes them, and the
worklet decoder restores the corresponding capability.

The pattern source map contains bounded tables of:

- atom ID, source range, and atom role;
- definition ID and declaration-header/name ranges;
- reference ID and reference range; and
- reference-binding ID, reference ID, and target definition ID.

Schema-1 encodes these IDs as serials under `sourceMap.epoch`, a checked positive
safe integer. This source epoch is independent of the document epoch in
`DraftVersion`: mode changes and tracking-limit recovery rotate source identity
without resetting the document version. Decoding must preserve both epochs,
never reconstruct source IDs from the receipt's document epoch.

The input freezes text, version, and source map together. Include facts from
the submitted program, including declarations that strict compilation checks
even when unused. Do not include an edit log, old drafts, closures, DSP objects,
or a second serialized AST language.

The worklet decodes integer/range/uniqueness constraints once, parses the same
text with the existing grammar, and checks that source-map entries match the
parsed atoms and resolved references. It never guesses absent entries or
issues IDs. `Draft` is authoritative for historical continuity; the decoder
can verify snapshot consistency, not reconstruct the editor's unseen history.

Build the decoded source and prepared playback candidate in private staging.
Only complete successful preparation/admission commits it. Character/metadata
FFI upload must not partially mutate accepted playback state.

`SchedulerSession.update/restart` accept `PlaybackInput`. `TextInput` is an
explicit choice for programmatic playback, never recovery from failure to
compile a pattern with origins. `Draft::prepare_playback` creates a song input
without a source map for valid songs; it does not classify that successful
preparation as an error or lesser readiness state.

Audio and last-good semantics do not change when selecting either capability.
Entering a confirmed song-mode draft retires exact pattern source facts;
returning to pattern mode begins a fresh source epoch. It does not attempt song
highlighting through the pattern resolver. Incomplete syntax alone is not a
mode switch and must not globally retire independent facts.

The wire schema is versioned and strictly decoded at the existing adapter.
Receipts for **both** pattern and song draft inputs echo their `DraftVersion`
alongside `RequestId`. Text-only programmatic inputs and source-free play/pause
do not invent a draft version. Receipt operation/version mismatch is a protocol
failure. A well-formed retired-run reply is handled by the existing run-liveness
owner.

| Outcome | Draft state | Playback state |
| --- | --- | --- |
| Valid edit | Advance version and current source facts. | Unchanged until submission succeeds. |
| Syntax/semantic error | Advance version; retain provable facts; set current diagnostic. | Keep accepted score and reservations. |
| Accepted older version | Do not roll back current draft or clear its diagnostic. | Record the real acceptance. |
| Rejected submission | Diagnostic changes only if its version is current. | Keep prior accepted state/reservations. |
| Audio close/reopen | Preserve `Draft` and source IDs. | Retire old run; new run cannot consume its observations. |
| Draft reset | New source epoch; no inferred continuity. | Last accepted music is not silently replaced. |
| Bad base/ranges/schema | Explicit error; no partial commit or identity inference. | No candidate commit. |

`Draft` lives independently of audio power. Existing `Session`, `PlaybackState`,
`EntryState`, and `EntrySource` continue to own musical transitions. A draft
version is never a global highlight eligibility gate: an older material may
legitimately produce a currently represented atom.

Do not confuse an audio-connection epoch with a musical restart. A successful
restart creates a new playback-run identity even on the same worklet connection;
pause/resume and ordinary source acceptance do not. The existing runtime
`Player` owns that transition. A rejected restart retains the old run.

#### Bounds and lifetime

Keep current text and source indices, a bounded last-valid baseline/cache, a
monotone serial, and explicitly live playback/submission/observation records.
Discard retired atom/binding records and intermediate edits. Non-reuse of
serials eliminates permanent tombstone sets and lifetime maps indexed by
spelling.

Bound **automatic** source submissions to one automatic update in flight and
one latest-unsent draft version. Coalesce older unsent automatic updates.
Explicit update/restart commands retain their existing immediate dispatch and
request ordering: a pending automatic update must not add a busy rejection,
delay, or coalescing rule to a manual restart. Manual commands cancel older
unsent automatic updates, just as they currently cancel debounce. Completion
of an older automatic request cannot submit a draft superseded by that manual
command. Play/pause retain their existing ordering. This feature adds no manual
command queue or new manual-command admission policy.

Origin metadata remains live while referenced by an active/pending material,
an unread worklet ring record, an in-flight observation batch, or an unexpired
UI observation. Retirement is reported only after the worklet-side owners
release it; the UI retains its own unexpired observations independently.
Use existing material state plus transport ownership, not a “last N revisions”
cache or continued voice existence. Metadata publication precedes the first
observation that references it. Status/live-set messages are coalesced with
bounded in-flight ownership, not appended as an unlimited retirement history.

Use the existing 8192-UTF-16-unit playback source limit as the exact tracking
domain. A larger editor document remains editable but reports
`TrackingUnavailable` and cannot be submitted. Entering that state retires all
exact facts and rotates the source epoch; its current version still sequences
editor changes, but carries no exact-source capability. Recovery builds fresh
facts in that new epoch, never continuity across the unprocessed interval.
This explicit capability limit is distinct from ordinary syntax errors.
Runtime node/depth/query admission remains in force; a local recognition-depth
failure marks only the unprovable region opaque, not every independent atom in
an otherwise bounded draft.

Counter exhaustion returns `IdentityExhausted`; recovery requires an explicit
reset, never wraparound. A malformed transaction returns `DraftEditError`;
do not automatically “repair” it with text matching.

### Interface 3: reference continuity in invalid drafts

**Owner:** the same main-thread source owner, on each atomic draft transition.
The worklet validates submitted binding facts but does not maintain another
incremental binding history.

A declaration's identity follows its whole binding-name token in declaration
role. Body edits alone do not replace it; name edits do. A use's identity
follows its whole expression-reference identifier, not a method name, literal
token, or declaration name.

```text
BindingState =
    Bound(ReferenceBindingId, ReferenceId, DefinitionId)
  | Unresolved(ReferenceId, UndefinedName | DuplicateName | OpaqueScope)
```

A token that is no longer a recognizable reference has no live `ReferenceId`,
rather than an unresolved record for an invented reference. These states
describe the current draft; they do not accept invalid runtime definitions.

| Transition | Edge identity |
| --- | --- |
| Bound to the same uniquely proven declaration | Retain. |
| Bound to another declaration | Retire old edge; create a new edge. |
| Bound to ambiguous/undefined/unprovable scope | Retire old edge. |
| Unresolved to a proven declaration | Create a new edge, even for former endpoints. |
| Use or declaration deleted/recreated | New endpoint and edge identities. |

Endpoint equality is not continuity. For example, inserting a duplicate
declaration and then deleting it must not revive the previous edge, even if the
final text is identical. The old event's origin remains unrepresented.

#### Partial recognition, not permissive execution

Extend the existing Mini lexer, parser, and `MiniExpr` recognition to emit
partial role/scope facts alongside diagnostics. Do not implement a second
accepted-language parser in TypeScript, scan binding names with regexes, or
insert virtual repair tokens. Full syntax and lowering are still required for
playback acceptance.

Recognize completed atom/reference subexpressions inside incomplete enclosing
expressions. A complete literal does not lose its atoms merely because the
outer call lacks `)`. A certain declaration header and statement extent can
retain its symbolic identity despite an erroneous body.

Recover declaration islands at lexically certain semicolons outside strings
and comments; Mini expressions do not contain those separators. Recovery may
leave the preceding body invalid without compiling it or inventing its missing
parentheses. Unterminated strings/comments can make a suffix opaque, but do
not erase independent prefix facts. Missing statement terminators do not
license guessed boundaries.

Use existing dollar-stack splitting rules, including their handling of
newlines; do not make every newline a synchronization point.

For a use, a target is proven only when:

1. the use role and enclosing scope are known;
2. exactly one matching recognized declaration definitely precedes it; and
3. no opaque preceding region could introduce or alter that binding.

Known matching duplicates before the use produce `DuplicateName`. Errors in
other-name bodies do not destroy the relationship when their headers and
statement extents remain certain. A declaration body can be invalid while its
symbolic target remains known; this does not make that body executable.

Preserve ordered immutable bindings, define-before-use, and current rejection
of duplicate/undefined names and unused invalid declarations. Share the
binding-lookup rule between strict compilation and partial recognition.
On every completely valid program, both projections must resolve every use
to the same declaration. Retain `ResolvedMiniExpr`; its reference case carries
a resolved declaration record instead of merely a copied value.

#### Resolution for presentation

```text
Draft::locate_origin(EventOrigin) -> OriginLocation
OriginLocation =
    Located(atom_range, reference_ranges)
  | Unavailable(SourceReset | AtomRetired | BrokenReference)
```

Locate an origin only when its source epoch and atom are live and **every**
`ReferenceBindingId` in its immutable path remains live with its original
endpoints. A direct atom has an empty path. Return the definition atom as the
primary range and the actually traversed references as secondary ranges.

If any binding fails, return `Unavailable(BrokenReference)`; do not shorten
the path or show a definition-only pulse. Other independently locatable
origins remain eligible. Changes to controls, siblings, or content revisions
alone are not reasons to reject an origin.

The presentation module separately checks run liveness and listener-time
expiry, then passes only represented, unexpired pulses to the renderer.
`Unresolved`, `Unavailable`, and an expired onset are ordinary domain
results. Malformed edits/wire data and impossible authored compilation are
errors. Neither category becomes a fabricated origin or a misleading success.

### Migration map

| Existing seam | Required cutover |
| --- | --- |
| `pattern/pattern_doc.mbt` | Atom/reference-with-binding constructors, `PatternSnapshotWithOrigins`, shared lowering, separate origin and voice scope. |
| `pattern/control.mbt`, `pattern/combinators.mbt` | Extract shared private payload kernels; retain musical metadata policy. |
| `mini/doc_parser.mbt` | Explicit atom witnesses; preserve chord tone nodes; use `MiniCallback::operation`; remove exact-path spelling fallback. |
| `mini/parser.mbt`, `mini/expression_compile.mbt` | Separate partial declaration/role recognition from strict body lowering; retain resolved declaration and edge identity. |
| `mini/draft.mbt`, `mini/source_recognition.mbt`, `mini/lexical.mbt` | Implemented: causal spans and checked serials, bounded live tables, internal `last_valid_doc`, shared grammar recognition. |
| Pipeline `set_input` / `set_input_with_source_edit` | Removed: callers use `Draft::edit` and `Draft::reset`; no inferred-middle matching or separate text/span setters. |
| Stateless `parse` / `parse_doc` | Remain programmatic; do not promise cross-draft continuity. |
| `mini/source_parser.mbt` | Pattern inputs with source maps versus explicit song/programmatic inputs without them. |
| CM6 adapter and `main.ts` | Deliver each transaction with all of its ranges before debounce. |
| `playback.ts`, `audio.ts`, `playback-protocol.ts` | Hold `Draft`, pass opaque `PlaybackInput`, correlate draft-version receipts, bound automatic updates only, preserve manual command semantics. |
| `web/playback-controller.js`, browser exports/input staging, `browser/internal/playback_host/live_update.mbt` | Decode and stage witnesses; compile exact input; commit only accepted candidate; no worklet identity guessing. |
| Scheduler snapshot/source adapters | Preserve exact capability through routing and reconciliation; emit origin only after successful dispatch. |
| Public interfaces, cookbook/API docs, affected tests | Migrate callback and origin accessors; retain scope behavior; document deliberate capability changes. |

General `from_pattern` callers remain general; no mass conversion to fake
atoms. Move source-identity tests to explicit transactions and exact-event
origins. Replace broad-path-as-primary-origin expectations, but retain tests
defending voice-scope behavior. Do not preserve tests that assert incidental
compilation callback counts instead of observable behavior.

### Acceptance cases and proof boundaries

Implementation must cover these discriminating cases:

1. Same-text atom replacement retires that atom but preserves its sibling.
2. Insert/delete inside an atom in separate transactions cannot restore its ID,
   even when CodeMirror's composed change is empty.
3. One multi-range transaction preserves an untouched middle atom.
4. Whitespace shifts preserve identities; token merges/splits and role changes
   retire affected identities.
5. Missing closing parentheses preserve recognizable atoms while submission
   remains invalid.
6. An unrelated erroneous declaration body with certain boundaries preserves
   independent references; an opaque suffix cannot be guessed.
7. Definition-body/control changes preserve unaffected atom/binding lifetimes.
8. Duplicate insertion/removal, rebind-away-and-back, and undo never resurrect
   a retired edge.
9. Two uses of one definition share its atom but have different edge paths.
10. Every/jux/reverse/gain-zero/chord preserve exact atoms, music, material
    metadata, degradation seeds, and existing voice-scope operations.
11. Older acceptance during a newer invalid draft updates accepted truth, not
    the current diagnostic.
12. Audio restart preserves authoring identities but retires old-run telemetry;
    explicit document reset does not preserve authoring identities.
13. Bad wire witnesses, wrong base version, limit exits, and exhausted counters
    cannot partially commit or fall back to guessed attribution.
14. Strict-valid grammar forms agree with partial recognition, including
    comments, UTF-16 offsets, dollar-stack syntax, and nested references.
15. Retention remains bounded under many updates, partial material transitions,
    dropped observations, and stalled UI; no visual pressure alters audio.
16. Manual restart during an in-flight automatic update is still dispatched,
    cancels older unsent automatic input, and cannot be undone by that input
    being submitted on the older request's completion.

Evidence obtained during design:

- The earlier isolated shared-kernel probe passed ten musical/material parity
  cases on JS and native. It also showed why naïve public jux composition is
  insufficient: it changed one material into two.
- A new throwaway model using the installed CodeMirror `ChangeSet` passed
  twelve edit/binding/receipt scenarios and all 2,187 length-seven traces over
  two binding targets plus an unresolved state. Retired edges never revived.
- **The model supplies recognized spans/targets as fixtures.** It does not
  validate the proposed partial Mini parser, wire implementation, renderer,
  or audio-thread allocation behavior.

Implementation order:

1. Pin current musical/material/voice-scope behavior; extract shared kernels and
   add exact compilation without enabling highlighting.
2. Implement the transactional authoring owner and partial-recognition binding
   lifetimes, with strict/partial agreement checks.
3. Wire immutable submissions through the existing playback owner, preserving
   accepted-score and material transitions.
4. Connect successful dispatch, bounded observations, and the central resolver;
   enable highlighting only when the complete path works.

Full operator/grammar coverage, JS/native/wasm checks, actual
editor-to-worklet-to-UI scenarios, and ADR-0018's matched audio performance and
allocation gates remain mandatory. These are implementation verification
gates, not unresolved ownership/interface choices.

## Reference

DAWs distinguish transport state from start-position selection, with different
stop and resume policies. See the official manuals for
[Ableton Live](https://www.ableton.com/en/live-manual/12/arrangement-view/),
[Logic Pro](https://support.apple.com/guide/logicpro/playback-and-navigation-lgcp9ede81be/mac),
[Cubase](https://www.steinberg.help/r/cubase-pro/15.0/en/cubase_nuendo/topics/playback/playback_transport_menu_functions_r.html),
and [FL Studio](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/toolbar_panels.htm).
