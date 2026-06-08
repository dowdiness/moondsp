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
  match projection.accepted_doc() {
    Some(doc) => Some(doc.revision())
    None => None
  }
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
  match projection.parse_doc() {
    Err(_) => ()
    Ok(_) => abort("expected malformed source to fail the current parse")
  }
  if last_good_accepted_revision(projection) != Some(first_rev) {
    abort("expected accepted doc to retain the last good doc on parse error")
  }

  // Recover to a content-distinct valid source: the accepted channel advances to
  // it (its revision differs from the first by the fingerprint).
  projection.set_source("s(\"bd sd hh\")")
  let recovered_rev = projection_boundary_doc(projection.parse_doc()).revision()
  if recovered_rev == first_rev {
    abort("expected the recovered parse to carry a new revision")
  }
  if last_good_accepted_revision(projection) != Some(recovered_rev) {
    abort("expected accepted doc to advance to the recovered doc")
  }
  projection.dispose()
}
