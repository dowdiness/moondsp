# Phase 2 provenance & parity notes (plan Steps 6–8, 13–14)

Status snapshot for the loom-mini-cst spike after the Piece 4 corpus widening
and the Piece 3 corpus-driven provenance matrix. Companion to the executable
record in `src/projection_test.mbt` (`phase2 piece1 doc value-parity corpus`,
`phase2 piece3 corpus-driven provenance matrix`); if this file and those tests
disagree, the tests win.

## Corpus state

`projection_boundary_doc_corpus()` holds **84 inputs**: 66 parse Ok on both
sides, 18 are rejected by both sides. The Step 6 widening grew it from 40 by
folding in the previously tracked follow-up families:

- comma stack layers (notation-level stack), incl. nested under `[...]`
- `stack(...)` roots (plain, method-chained args, 3-arg)
- multiline `$:` stack programs (2- and 3-line, callback methods)
- negative and decimal note atoms
- postfix-operator combinations: euclid+replicate, euclid+degrade,
  replicate+degrade chains, adjacent `?` elements, degrade nested inside
  sub-notation (the position-seeded `?` makes offset-base drift between the
  two parsers observable — none was found)
- nested sub-notation, euclid with interior spaces, tab whitespace
- repeated/overriding control methods, larger tempo factors (`slow(8)` stays
  inside the fixed `[0, 8)` parity window)
- 14 additional malformed forms (unknown drum, empty notation, `*0`, `/0`,
  `*-1`, bad euclid arity, unterminated euclid, trailing comma, empty/
  unterminated `stack`, same-line `$:`, unknown method)

## Piece 4 triage outcome (Steps 6–8)

The widened corpus is green under value-level parity (root id, leaf ids,
ControlMap entries, whole/part TimeSpans over `[0, 8)`) and Ok/Err agreement.
Exactly one genuine divergence was found, and no loom grammar or projection
fix was needed (Step 7 was a no-op — the gap is on the oracle's side):

### Known gap (sanctioned divergence): oracle trailing-junk leniency

`@mini.parse_doc`'s notation parser does not check `at_end()` after the
top-level layer, so a stray `]` outside any bracket group is silently ignored
— and every element after it is silently **dropped**: `s("bd] sd")` parses as
just `bd`, losing `sd`. Loom rejects both `s("bd]")` and `s("bd] sd")` with
diagnostics. Loom's strict rejection is the intended behavior; the oracle
leniency is a production parser defect that Phase 2 cannot fix (all edits are
confined to the spike boundary).

- Pinned by: `known divergence: oracle silently drops trailing junk after
  stray ']', loom rejects` in `src/projection_test.mbt` (asserts BOTH sides,
  including the oracle's data loss, so it fails loudly if either side changes).
- Disposition: candidate `mini/` fix in a later phase; when the oracle gains
  the `at_end()` guard, the pinning test directs folding these inputs into the
  corpus malformed set.

### Fixed (label correction): `fast(slow(2))`

`s("bd").fast(slow(2))` sat in the corpus's *valid* section since Piece 1, but
patterned tempo arguments are rejected by BOTH parsers (loom: `expected
numeric method argument`; mini: `position 13: expected number`). The runner
only checks agreement, so this was harmless — the Step 13 matrix's pinned
ok/err split surfaced the mislabel. Now listed under malformed.

## Piece 3 provenance matrix (Step 13)

`phase2 piece3 corpus-driven provenance matrix` derives a record for every
corpus input from the parsers alone (no hand-picked rows; the bespoke
edit-span rows above it remain as the incremental-edit-path coverage):

- **Parse status**: Ok/Err agreement re-derived per input; one-sided results
  abort as parity holes. Split pinned at 66 ok / 18 err.
- **IDs**: loom vs mini leaf-id parity on every Ok input.
- **Value parity linkage**: the Step 2 value-level event helper (ControlMap +
  TimeSpans over `[0, 8)`) on every Ok input.
- **Last-good transitions** (loom accepted channel, full-revision identity):
  - Ok inputs: good parse is accepted → generic breaking suffix (`input + "("`)
    fails the current channel while `accepted_doc` retains the good revision →
    recovery to the original source restores identical leaf ids and re-accepts.
  - Err inputs: `accepted_doc` is `None` — nothing is served before any
    successful parse.

All 84 records pass with zero unsanctioned divergences.

## Err-message divergence table (required Phase 3 error-adapter input)

Message text is non-contractual in Phase 2 (the authoring contract is
`Result[_, String]`), so these are characterized, not failed — but the table
is the handoff to Phase 3's error-adapter design, per orchestrator
resolution 3. All 18 both-Err inputs diverge in text. Two structural findings:

1. **mini always carries a character position** (`position N: …`); loom never
   does. The Phase 3 error adapter must reconstruct positions from loom
   diagnostics to preserve the browser path's
   `get_pattern_error_length`/`get_pattern_error_char` UX.
2. **7 of 18 inputs collapse to loom's generic** `loom mini syntax has
   diagnostics` (all CST-level failures: unterminated brackets/parens/euclid,
   empty/unterminated `stack`, same-line `$:`). The adapter needs access to
   the underlying CST diagnostics, not just the projection's flattened string.

| input | loom | mini |
|---|---|---|
| `s("bd").fast(slow(2))` | loom atom projection expected numeric method argument | position 13: expected number |
| `s("[bd")` | loom mini syntax has diagnostics | position 3: expected ']' |
| `s("bd sd").jux(fast(2)` | loom mini syntax has diagnostics | position 22: expected ')', got end of input |
| `s("bd").gain(0.5).pan(-0.25` | loom mini syntax has diagnostics | position 27: expected ')', got end of input |
| `s("xyz")` | unknown drum name 'xyz' | position 0: unknown drum name 'xyz' |
| `s("")` | loom atom projection expected at least one atom | position 0: empty notation |
| `note("bd")` | loom atom projection expected note number | position 0: expected number |
| `s("2bd")` | loom atom projection expected sound name | position 0: expected sound name |
| `s("bd*0 sd")` | loom atom projection expected positive integer | position 2: '*' requires a positive integer, got 0 |
| `s("bd/0 sd")` | loom atom projection expected positive integer | position 2: '/' requires a positive integer, got 0 |
| `s("bd*-1 sd")` | loom atom projection expected positive integer | position 2: '*' requires a positive integer, got -1 |
| `s("bd(3) sd")` | loom mini syntax has diagnostics | position 4: expected ',' in euclid (k,n) |
| `s("bd(3,8 sd")` | loom mini syntax has diagnostics | position 7: expected ')' to close euclid |
| `s("bd,")` | loom atom projection expected at least one atom | position 3: expected at least one element in layer |
| `stack()` | loom mini syntax has diagnostics | position 0: stack() requires at least one argument |
| `stack(s("bd")` | loom mini syntax has diagnostics | position 13: expected ')', got end of input |
| `$: s("bd") $: note("60")` | loom mini syntax has diagnostics | position 11: unexpected trailing input '$: note("60")' |
| `s("bd").unknown(1)` | loom atom projection only supports .fast(N), .slow(N), .rev(), .cutoff(N), .gain(N), .pan(N), .jux(...), or .every(...) methods | position 8: unknown method 'unknown' |
