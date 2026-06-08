// Unit tests for PatternDoc's incr `BackdateEq` participation. The trait
// methods (`changed_at` / `backdate_equal`) are exercised here against the
// published incr pin; the full `accepted_memo` last-good round-trip lives in
// the loom-mini-cst spike (which resolves the unreleased `AcceptedDerived`
// via its working-tree incr path-dep). `PatternDoc[Int]` stands in as the
// non-`Eq`, revision-bearing candidate value.

///|
fn bd_pid(value : String) -> @identity.PatternNodeId {
  guard (try? @identity.PatternNodeId::from_string(value)) is Ok(id) else {
    abort("expected valid pattern node id")
  }
  id
}

///|
/// A revision-0 `pure` doc carrying `value`.
fn bd_doc0(value : Int) -> PatternDoc[Int] {
  PatternDoc::pure(id=bd_pid("root"), value~)
}

///|
/// A revision-1 doc (root reversed once) carrying `value`.
fn bd_doc1(value : Int) -> PatternDoc[Int] {
  let reversed = try? PatternDoc::pure(id=bd_pid("root"), value~).rev(
    id=bd_pid("rev1"),
  )
  guard reversed is Ok(doc) else {
    abort("rev should not fail on a fresh pure doc")
  }
  doc
}

///|
test "patterndoc backdate: changed_at projects the identity revision value" {
  inspect(bd_doc0(1).changed_at().value, content="0")
  inspect(bd_doc1(1).changed_at().value, content="1")
}

///|
test "patterndoc backdate: backdate_equal gates on revision, not content" {
  // Equal revision, different payload → equal (acceptance is revision-gated,
  // proving the override compares the revision identity and not the content).
  inspect(bd_doc0(1).backdate_equal(bd_doc0(99)), content="true")
  // Distinct revisions → not equal.
  inspect(bd_doc0(1).backdate_equal(bd_doc1(1)), content="false")
}
