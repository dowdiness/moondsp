///|
/// Parse a mini-notation string into a pattern of control maps.
///
/// Supported forms:
/// - `s("bd sd hh sd")` — drum sounds (space = sequence, comma = stack, brackets = sub-group)
/// - `note("60 64 67")` — MIDI note numbers
/// - Method chains: `.fast(n)`, `.slow(n)`, `.rev()`
pub fn parse(
  input : String,
) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  guard input.length() > 0 else { return Err("empty input") }
  let p = Parser::new(input)
  let result = p.parse_expr() catch { ParseError(msg) => return Err(msg) }
  p.skip_whitespace()
  guard p.at_end() else {
    return Err(
      "position \{p.pos}: unexpected trailing input '\{input[p.pos:].to_string()}'",
    )
  }
  Ok(result)
}
