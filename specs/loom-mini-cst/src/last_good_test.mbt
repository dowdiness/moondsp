// Stage 5: the loom-mini-cst projection serves the last-good projected doc on
// parse error via `@incr.AcceptedDerived::accepted_memo`. The current channel
// (`parse_doc`) keeps surfacing diagnostics unchanged; the accepted channel
// (`accepted_doc`) retains the last successful `PatternDoc`.
//
// Acceptance identity is the full `@identity.Revision` (value AND fingerprint),
// matching `PatternDoc`'s `BackdateEq` override. The revision `value` alone
// collides here ("bd sd" and "bd sd hh" both land on value 1), which is exactly
// why the override compares the fingerprint too — comparing only the value would
// wrongly treat a changed doc as unchanged.

///|
/// The accepted doc's full revision, or `None` when nothing is accepted.
fn last_good_accepted_revision(
  projection : LoomMiniAtomProjection,
) -> @identity.Revision? {
  projection.accepted_doc().map(doc => doc.revision())
}

///|
test "loom mini last-good: accepted_doc retains last good across a parse error" {
  let projection = LoomMiniAtomProjection::new("s(\"bd sd\")")
  // A successful first parse is accepted; the accepted revision tracks current.
  let first_rev = projection_boundary_doc(projection.parse_doc()).revision()
  if last_good_accepted_revision(projection) != Some(first_rev) {
    abort("expected accepted doc to capture the first good parse")
  }

  // Edit to a malformed source: the current channel fails, the accepted
  // channel retains the last good doc unchanged.
  projection.set_source("s(\"bd sd")
  guard projection.parse_doc() is Err(_) else {
    abort("expected malformed source to fail the current parse")
  }
  if last_good_accepted_revision(projection) != Some(first_rev) {
    abort("expected accepted doc to retain the last good doc on parse error")
  }

  // Recover to a content-distinct valid source: the accepted channel advances to
  // it (its revision differs from the first only by the fingerprint).
  projection.set_source("s(\"bd sd hh\")")
  let recovered_rev = projection_boundary_doc(projection.parse_doc()).revision()
  // Pin the premise the fingerprint comparison relies on: the recovered doc
  // COLLIDES with the first on the revision `value`, so a hypothetical
  // value-only `backdate_equal` would wrongly treat the two as equal. The full
  // revisions still differ — the difference is the fingerprint alone. Without
  // this assertion, a value that stopped colliding (now or after a revision-
  // scheme change) would let the acceptance check below pass even under a
  // value-only predicate, silently ceasing to guard the fingerprint path.
  if recovered_rev.value() != first_rev.value() {
    abort("expected recovered and first revisions to collide on value")
  }
  if recovered_rev == first_rev {
    abort("expected recovered and first revisions to differ by fingerprint")
  }
  if last_good_accepted_revision(projection) != Some(recovered_rev) {
    abort("expected accepted doc to advance to the recovered doc")
  }
  projection.dispose()
}

///|
test "loom mini last-good: accepted_doc is None before any successful parse" {
  // A projection whose very first parse fails has accepted nothing yet: the
  // accepted channel reports None — not the last-good of some earlier success
  // (there is none), and not an abort.
  let projection = LoomMiniAtomProjection::new("s(\"bd sd")
  guard projection.parse_doc() is Err(_) else {
    abort("expected malformed initial source to fail the first parse")
  }
  if last_good_accepted_revision(projection) != None {
    abort("expected accepted_doc to be None before any successful parse")
  }
  projection.dispose()
}
