///|
/// Parse a mini-notation string into a pattern of control maps.
///
/// Supported forms:
/// - `s("bd sd hh sd")` — drum sounds (space = sequence, comma = stack, brackets = sub-group)
/// - `note("60 64 67")` / `note("C4 E4 G4")` — MIDI note numbers or note names
/// - `chord("C Dm G7")` — chord names, each lowered to stacked note events
/// - Euclidean rhythms: `s("bd(3,8)")` distributes 3 pulses across 8 steps;
///   `s("bd(3,8,2)")` adds left-rotation; works on groups too: `s("[bd sd](5,8)")`
/// - Step operators (postfix on atoms or groups):
///   `bd*4` — replicate within slot (4 events in one slot);
///   `bd/2` — stretch within slot (`pat.slow(n)`);
///   `bd?` — degrade-by-50% (deterministic per-event drop);
///   stacks with euclid in left-to-right order: `bd*2(3,8)?` is legal
/// - Strudel-style stack lines: `$: s("bd")` / `$: note("C4")` stack top-level lines
/// - Method chains:
///   `.fast(n)`, `.slow(n)`, `.rev()`,
///   `.degradeBy(p)` (drop with probability p),
///   `.cutoff(f)`, `.gain(g)`, `.pan(p)` (merge per-event controls),
///   `.every(n, fast(k)|slow(k)|rev)` (apply f every n cycles),
///   `.jux(fast(k)|slow(k)|rev)` — split stereo, apply f to right channel
pub fn parse(
  input : String,
) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  guard !input.is_empty() else { return Err("empty input") }
  match mini_collect_dollar_stack_lines(input) {
    Err(msg) => return Err(msg)
    Ok(Some(lines)) => return mini_parse_dollar_stack_program(input, lines)
    Ok(None) => ()
  }
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
