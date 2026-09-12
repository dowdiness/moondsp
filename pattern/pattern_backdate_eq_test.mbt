// Unit tests for PatternDoc's incr `BackdateEq` participation. The trait
// methods (`changed_at` / `backdate_equal`) are exercised here against the
// published incr pin; the full `accepted_memo` last-good round-trip lives in
// the mini authoring pipeline tests. `PatternDoc[Int]` stands in as the
// non-`Eq`, revision-bearing candidate value.

///|
fn bd_pid(value : String) -> @identity.PatternNodeId {
  @identity.PatternNodeId::from_string(value) catch {
    _ => abort("expected valid pattern node id")
  }
}

///|
/// A revision-0 `pure` doc carrying `value`.
fn bd_doc0(value : Int) -> PatternDoc[Int] {
  PatternDoc::pure(id=bd_pid("root"), value~)
}

///|
/// A revision-1 doc (root reversed once) carrying `value`.
fn bd_doc1(value : Int) -> PatternDoc[Int] {
  PatternDoc::pure(id=bd_pid("root"), value~).rev(id=bd_pid("rev1")) catch {
    _ => abort("rev should not fail on a fresh pure doc")
  }
}

///|
test "patterndoc backdate: changed_at advances monotonically" {
  let initial = bd_doc0(1)
  let transformed = initial.rev(id=bd_pid("changed-at-rev")) catch {
    _ => abort("rev should not fail on a fresh pure doc")
  }
  assert_true(transformed.changed_at() > initial.changed_at())
}

///|
test "patterndoc backdate: backdate_equal gates on revision, not content" {
  // Equal revision, different payload → equal (acceptance is revision-gated,
  // proving the override compares the revision identity and not the content).
  inspect(bd_doc0(1).backdate_equal(bd_doc0(99)), content="true")
  // Distinct revisions → not equal.
  inspect(bd_doc0(1).backdate_equal(bd_doc1(1)), content="false")
}
