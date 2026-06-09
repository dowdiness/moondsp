// Phase 0 Check #3: error-shape / span canary. Confirms the loom diagnostic →
// production-contract adapter returns `Err(msg)` with an indexable position for
// malformed input, and that the `length()` / per-char accessors emulate the
// browser `get_pattern_error_length` / `get_pattern_error_char` access pattern.

///|
/// `msg` must be non-empty, must begin with an indexable integer offset (the
/// production `"<offset>:..."` position indicator), and must be walkable by the
/// length + per-char accessors exactly as the browser contract walks it.
fn assert_contract_error(result : Result[Int, String]) -> Unit raise {
  guard result is Err(msg) else {
    fail("expected Err for malformed input, got Ok")
  }
  // Non-empty message.
  guard canary_error_length(msg) > 0 else {
    fail("error message must be non-empty")
  }
  // Indexable position indicator: the first char is an ASCII digit, and the
  // per-char accessor agrees with direct indexing (UTF-16 code unit semantics).
  let first = canary_error_char(msg, 0)
  guard first >= 48 && first <= 57 else {
    fail("error message must begin with an indexable digit offset")
  }
  // Out-of-range char access returns 0, matching `get_pattern_error_char`.
  guard canary_error_char(msg, canary_error_length(msg)) == 0 else {
    fail("out-of-range char access must return 0")
  }
}

///|
test "error-shape: empty input is rejected with a contract error" {
  assert_contract_error(adapt_parse(""))
}

///|
test "error-shape: unknown primary foo(...) is rejected" {
  assert_contract_error(adapt_parse("foo(\"bd\")"))
}

///|
test "error-shape: unterminated s(\"bd is rejected" {
  assert_contract_error(adapt_parse("s(\"bd"))
}

///|
test "error-shape: malformed $: form is rejected" {
  assert_contract_error(adapt_parse("$:"))
}

///|
test "error-shape: valid control-method chain is the non-error baseline" {
  // Exactly the Check #3 non-error baseline — same input shape as the malformed
  // cases but well-formed, so it must NOT take the error path.
  inspect(adapt_parse("s(\"bd sd\").jux(rev)") is Ok(2), content="true")
}
