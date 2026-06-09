// Phase 0 Check #3: prove loom's `DiagnosticSet` can be normalized to the
// existing production browser parse-error contract — a plain-string message
// carrying an indexable position, consumed by a `length()` accessor and a
// per-char (UTF-16 code unit) accessor, exactly as
// `browser/internal/playback_host/playback_host.mbt`
// (`get_pattern_error_length` / `get_pattern_error_char`) does today.
//
// The browser contract lines remain the source of truth; this adapter only
// shows the loom diagnostic shape maps onto them.

///|
/// Parse `source` and collapse the result into the production contract shape:
/// `Ok(atom_count)` when the parser produced no diagnostics, otherwise
/// `Err(message)` where `message` is a plain string beginning with an indexable
/// character offset (mirroring production messages such as `"0:invalid ..."`).
pub fn adapt_parse(source : String) -> Result[Int, String] {
  let parser = probe_parser(source)
  let diagnostics = parser.diagnostics().read_or_abort()
  if diagnostics.is_empty() {
    Ok(probe_atom_count(parser))
  } else {
    Err(format_first_diagnostic(diagnostics))
  }
}

///|
/// Render the first diagnostic as `"<offset>: <message>"`. The leading integer
/// offset is the indexable position indicator the contract relies on; when a
/// diagnostic has no primary span it degrades to offset `0`, matching the
/// production `"0:..."` fallback.
fn format_first_diagnostic(diagnostics : @core.DiagnosticSet) -> String {
  match diagnostics.items() {
    [first, ..] => {
      let offset = match first.primary {
        Some(range) => range.start().value()
        None => 0
      }
      "\{offset}: \{first.message}"
    }
    // Defensive: `is_empty()` was false, so this branch is unreachable.
    [] => "0: unknown parse error"
  }
}

///|
/// Length of a parse-error message in chars (UTF-16 code units) — the canary
/// analogue of `get_pattern_error_length`.
pub fn canary_error_length(message : String) -> Int {
  message.length()
}

///|
/// i-th character (UTF-16 code unit) of a parse-error message, `0` when out of
/// range — the canary analogue of `get_pattern_error_char`.
pub fn canary_error_char(message : String, i : Int) -> Int {
  if i < 0 || i >= message.length() {
    0
  } else {
    message[i].to_int()
  }
}
