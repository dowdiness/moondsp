///|
/// Parse a mini-notation string into a pattern of control maps.
///
/// Supported forms:
/// - `s("bd sd hh sd")` — drum sounds (space = sequence, comma = stack, brackets = sub-group)
/// - `note("60 64 67")` — MIDI note numbers
/// - Euclidean rhythms: `s("bd(3,8)")` distributes 3 pulses across 8 steps;
///   `s("bd(3,8,2)")` adds left-rotation; works on groups too: `s("[bd sd](5,8)")`
/// - Step operators (postfix on atoms or groups):
///   `bd*4` — replicate within slot (4 events in one slot);
///   `bd/2` — stretch within slot (`pat.slow(n)`);
///   `bd?` — degrade-by-50% (deterministic per-event drop);
///   stacks with euclid in left-to-right order: `bd*2(3,8)?` is legal
/// - Method chains:
///   `.fast(n)`, `.slow(n)`, `.rev()`,
///   `.degradeBy(p)` (drop with probability p),
///   `.cutoff(f)` (merge per-event cutoff control),
///   `.every(n, fast(k)|slow(k)|rev)` (apply f every n cycles),
///   `.jux(fast(k)|slow(k)|rev)` — split stereo, apply f to right channel
pub fn parse(
  input : String,
) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  guard input.length() > 0 else { return Err("empty input") }
  let p = Parser::new(input)
  let result = p.parse_expr() catch { ParseError(msg) => return Err(msg) }
  p.skip_whitespace()
  guard p.at_end() else {
    return Err(
      "position \{p.pos}: unexpected trailing input '\{input[p.pos:].to_owned()}'",
    )
  }
  Ok(result)
}
