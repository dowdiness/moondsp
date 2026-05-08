///|
/// Parse a mini-notation string into a pattern of control maps.
///
/// Supported forms:
/// - `s("bd sd hh sd")` — drum sounds (space = sequence, comma = stack, brackets = sub-group)
/// - `note("60 64 67")` — MIDI note numbers
/// - Euclidean rhythms: `s("bd(3,8)")` distributes 3 pulses across 8 steps;
///   `s("bd(3,8,2)")` adds left-rotation; works on groups too: `s("[bd sd](5,8)")`
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
