///|
/// Parse a mini-notation string into a pattern of control maps.
///
/// Supported forms:
/// - `let name = expr;` — immutable definitions before the final expression or `$:` lines
/// - A defined name is a primary expression; groups use `stack(name, ...)`
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
///   `.lpf(hz, resonance?)`, `.hpf(hz, resonance?)`, `.gain(g)`, `.pan(p)`,
///   `.room(send)` (merge per-event controls),
///   `.every(n, fast(k)|slow(k)|rev)` (apply f every n cycles),
///   `.jux(fast(k)|slow(k)|rev)` — split stereo, apply f to right channel
pub fn parse(
  input : String,
) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  parse_snapshot(input).map(snapshot => snapshot.pat())
}
