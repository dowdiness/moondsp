///|
/// Parse sound notation string into Pat[ControlMap].
fn parse_sound_notation(
  content : String,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  guard !content.is_empty() else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser::new(content, sound=true)
  sub.parse_notation()
}

///|
/// Parse note notation string into Pat[ControlMap].
fn parse_note_notation(
  content : String,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  guard !content.is_empty() else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser::new(content, sound=false)
  sub.parse_notation()
}

///|
/// Parse chord notation string into Pat[ControlMap].
/// Space-separated chord names are sequenced; each chord is a stacked pattern.
fn parse_chord_notation(
  content : String,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  guard !content.is_empty() else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser::new(content, sound=false, chord=true)
  sub.parse_notation()
}

///|
priv struct NotationProjectionModifier {
  kind : String
  from : Int
  to : Int
  value : Double
  args : Array[Int]
}

///|
priv struct NotationProjectionNode {
  kind : String
  from : Int
  base_to : Int
  mut end : Int
  value : String
  mut parent : Int?
  children : Array[Int]
  mut weight : Int
  modifiers : Array[NotationProjectionModifier]
}

///|
fn NotationParser::projection_node(
  self : NotationParser,
  kind : String,
  from : Int,
  base_to : Int,
  value : String,
  children : Array[Int],
) -> Int raise ParseError {
  guard self.projection_nodes is Some(nodes) else { return -1 }
  guard nodes.length() < 256 else {
    raise ParseError("notation projection exceeds 256 source nodes")
  }
  let index = nodes.length()
  for child in children {
    nodes[child].parent = Some(index)
  }
  nodes.push({
    kind,
    from,
    base_to,
    end: base_to,
    value,
    parent: None,
    children,
    weight: 1,
    modifiers: [],
  })
  index
}

///|
fn NotationParser::projection_modifier(
  self : NotationParser,
  node : Int?,
  kind : String,
  from : Int,
  to : Int,
  value : Double,
  args : Array[Int],
) -> Unit {
  match (self.projection_nodes, node) {
    (Some(nodes), Some(index)) => {
      nodes[index].modifiers.push({ kind, from, to, value, args, })
      nodes[index].end = to
    }
    _ => ()
  }
}

///|
/// Sub-parser for the notation content inside quotes.
priv struct NotationParser {
  input : String
  mut pos : Int
  sound : Bool
  chord : Bool
  source_offset : Int
  mut query_work : MiniQueryWork?
  recognized_atoms : Array[RecognizedAtom]?
  mut depth : Int
  mut projection_nodes : Array[NotationProjectionNode]?
  mut projection_root : Int?
  mut last_modifier_value : Int
  mut last_euclid_args : Array[Int]
}

///|
#alias(new)
fn NotationParser::NotationParser(
  input : String,
  sound~ : Bool,
  chord? : Bool = false,
  source_offset? : Int = 0,
  assess? : Bool = false,
  recognized_atoms? : Array[RecognizedAtom]? = None,
) -> NotationParser {
  {
    input,
    pos: 0,
    sound,
    chord,
    source_offset,
    recognized_atoms,
    depth: 0,
    projection_nodes: None,
    projection_root: None,
    last_modifier_value: 0,
    last_euclid_args: [],
    query_work: if assess {
      Some(Atom)
    } else {
      None
    },
  }
}

///|
fn NotationParser::at_end(self : NotationParser) -> Bool {
  self.pos >= self.input.length()
}

///|
fn NotationParser::skip_spaces(self : NotationParser) -> Unit {
  while !self.at_end() && mini_is_space(self.input[self.pos]) {
    self.pos += 1
  }
}

///|
/// Parse top-level notation: layer ( "," layer )*
fn NotationParser::parse_notation(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let first = self.parse_layer()
  let layers : Array[@pattern.Pat[@pattern.ControlMap]] = [first]
  let layer_roots : Array[Int] = match self.projection_root {
    Some(index) => [index]
    None => []
  }
  let costs : Array[MiniQueryWork]? = self.query_work.map(_ => [])
  if self.query_work is Some(cost) {
    costs.unwrap().push(cost)
  }
  while !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_spaces()
    layers.push(self.parse_layer())
    if self.projection_root is Some(index) {
      layer_roots.push(index)
    }
    if self.query_work is Some(cost) {
      costs.unwrap().push(cost)
    }
  }
  if costs is Some(costs) {
    self.query_work = Some(
      if costs.length() == 1 {
        costs[0]
      } else {
        Overlay(costs)
      },
    )
    return @pattern.Pat::silence()
  }
  if layer_roots.length() > 1 {
    let from = self.projection_nodes.unwrap()[layer_roots[0]].from
    self.projection_root = Some(
      self.projection_node("parallel", from, self.pos, "", layer_roots),
    )
  }
  if layers.length() == 1 {
    layers[0]
  } else {
    @pattern.stack(layers)
  }
}

///|
/// Parse a layer: sequence of space-separated elements.
fn NotationParser::parse_layer(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  self.skip_spaces()
  let layer_start = self.pos
  let elements : Array[@pattern.Pat[@pattern.ControlMap]] = []
  let weights : Array[Int] = []
  let child_nodes : Array[Int] = []
  let costs : Array[MiniQueryWork]? = self.query_work.map(_ => [])
  let mut total_weight = 0
  let mut weighted = false
  while !self.at_end() &&
        self.input[self.pos] != ',' &&
        self.input[self.pos] != ']' {
    let (element, weight, node) = self.parse_element()
    elements.push(element)
    weights.push(weight)
    if node is Some(index) {
      child_nodes.push(index)
      self.projection_nodes.unwrap()[index].weight = weight
    }
    total_weight += weight
    weighted = weighted || weight != 1
    guard !weighted || total_weight <= 256 else {
      raise ParseError("relative duration sum must not exceed 256")
    }
    if self.query_work is Some(cost) {
      costs.unwrap().push(cost)
      for _ in 1..<weight {
        costs.unwrap().push(Quiet)
      }
    }
    self.require_element_boundary()
    self.skip_spaces()
  }
  guard !elements.is_empty() else {
    raise ParseError(
      "position \{self.pos}: expected at least one element in layer",
    )
  }
  if costs is Some(costs) {
    self.query_work = Some(
      if costs.length() == 1 {
        costs[0]
      } else {
        Slots(costs)
      },
    )
    return @pattern.Pat::silence()
  }
  if child_nodes.length() == 1 && !weighted {
    self.projection_root = Some(child_nodes[0])
  } else if !child_nodes.is_empty() {
    self.projection_root = Some(
      self.projection_node("sequence", layer_start, self.pos, "", child_nodes),
    )
  }
  if !weighted {
    return if elements.length() == 1 {
      elements[0]
    } else {
      @pattern.sequence(elements)
    }
  }
  @pattern.sequence_weighted(elements, weights)
}

///|
const RELATIVE_DURATION_WEIGHT_LIMIT : Int = 16

///|
fn NotationParser::read_relative_duration(
  self : NotationParser,
) -> Int raise ParseError {
  let at_pos = self.pos
  self.pos += 1
  let digits_start = self.pos
  let mut weight = 0
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    weight = if weight > RELATIVE_DURATION_WEIGHT_LIMIT {
      weight
    } else {
      weight * 10 + self.input[self.pos].to_int() - '0'.to_int()
    }
    self.pos += 1
  }
  guard self.pos > digits_start &&
    weight > 0 &&
    weight <= RELATIVE_DURATION_WEIGHT_LIMIT else {
    raise ParseError(
      "position \{at_pos}: '@' requires a positive integer from 1 to 16",
    )
  }
  weight
}

///|
fn NotationParser::parse_element(
  self : NotationParser,
) -> (@pattern.Pat[@pattern.ControlMap], Int, Int?) raise ParseError {
  guard (self.recognized_atoms is None && self.projection_nodes is None) ||
    self.depth < 32 else {
    raise ParseError("source exceeds notation nesting depth 32")
  }
  self.skip_spaces()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of notation")
  }
  let start = self.pos
  let mut source_node : Int? = None
  let base = if self.input[self.pos] == '[' {
    self.pos += 1
    self.depth += 1
    let inner = self.parse_notation()
    let inner_node = self.projection_root
    self.depth -= 1
    guard !self.at_end() && self.input[self.pos] == ']' else {
      raise ParseError("position \{self.pos}: expected ']'")
    }
    self.pos += 1
    if self.projection_nodes is Some(_) {
      source_node = Some(
        self.projection_node(
          "group",
          start,
          self.pos,
          "",
          match inner_node {
            Some(index) => [index]
            None => []
          },
        ),
      )
    }
    inner
  } else {
    let atom = self.parse_atom()
    if self.projection_nodes is Some(_) {
      source_node = Some(
        self.projection_node(
          "atom",
          start,
          self.pos,
          self.input[start:self.pos].to_owned(),
          [],
        ),
      )
    }
    atom
  }
  let mut pat = base
  let mut weight = 1
  let mut applied = true
  while applied {
    applied = false
    if !self.at_end() {
      let c = self.input[self.pos]
      if c == '(' {
        let modifier_start = self.pos
        pat = self.maybe_apply_euclid(pat)
        if self.pos > modifier_start {
          self.projection_modifier(
            source_node,
            "euclid",
            modifier_start,
            self.pos,
            self.last_euclid_args[0].to_double(),
            self.last_euclid_args,
          )
        }
        applied = true
      } else if c == '*' {
        let modifier_start = self.pos
        pat = self.apply_replicate(pat)
        self.projection_modifier(
          source_node,
          "repeat",
          modifier_start,
          self.pos,
          self.last_modifier_value.to_double(),
          [],
        )
        applied = true
      } else if c == '/' {
        let modifier_start = self.pos
        pat = self.apply_step_slow(pat)
        self.projection_modifier(
          source_node,
          "slow",
          modifier_start,
          self.pos,
          self.last_modifier_value.to_double(),
          [],
        )
        applied = true
      } else if c == '?' {
        let salt = self.pos
        self.pos += 1
        if self.query_work is Some(cost) {
          self.query_work = Some(MapEvents(cost))
        } else {
          pat = pat.degrade_by(0.5, seed=salt)
        }
        self.projection_modifier(source_node, "degrade", salt, self.pos, 0.5, [])
        applied = true
      } else if c == '@' {
        let modifier_start = self.pos
        weight = self.read_relative_duration()
        self.projection_modifier(
          source_node,
          "weight",
          modifier_start,
          self.pos,
          weight.to_double(),
          [],
        )
        applied = true
      }
    }
    if self.query_work is Some(cost) {
      cost.check(0.0)
    }
  }
  (pat, weight, source_node)
}

///|
fn NotationParser::require_element_boundary(
  self : NotationParser,
) -> Unit raise ParseError {
  if self.at_end() {
    return
  }
  let c = self.input[self.pos]
  if mini_is_space(c) || c == ',' || c == ']' {
    return
  }
  raise ParseError("position \{self.pos}: expected separator between elements")
}

///|
/// Apply `*n` to a pattern: in-slot replication via `pat.fast(n)`.
fn NotationParser::apply_replicate(
  self : NotationParser,
  pat : @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let op_pos = self.pos
  self.pos += 1 // consume '*'
  let n = self.read_int_signed(op_pos)
  guard n > 0 else {
    raise ParseError(
      "position \{op_pos}: '*' requires a positive integer, got \{n}",
    )
  }
  self.last_modifier_value = n
  if self.query_work is Some(cost) {
    self.query_work = Some(
      Precision(Accelerate(cost, n.to_double()), n.to_double()),
    )
    return pat
  }
  pat.fast(@pattern.Rational::from_int(n))
}

///|
/// Apply `/n` to a pattern: in-slot stretch via `pat.slow(n)`.
fn NotationParser::apply_step_slow(
  self : NotationParser,
  pat : @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let op_pos = self.pos
  self.pos += 1 // consume '/'
  let n = self.read_int_signed(op_pos)
  guard n > 0 else {
    raise ParseError(
      "position \{op_pos}: '/' requires a positive integer, got \{n}",
    )
  }
  self.last_modifier_value = n
  if self.query_work is Some(cost) {
    self.query_work = Some(
      Precision(Accelerate(cost, 1.0 / n.to_double()), n.to_double()),
    )
    return pat
  }
  pat.slow(@pattern.Rational::from_int(n))
}

///|
/// Optionally apply euclid `(k,n[,r])` if it follows the current position.
fn NotationParser::maybe_apply_euclid(
  self : NotationParser,
  pat : @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  if self.at_end() || self.input[self.pos] != '(' {
    return pat
  }
  let euclid_start = self.pos
  self.pos += 1 // consume '('
  self.skip_spaces()
  let k = self.read_int_signed(euclid_start)
  self.skip_spaces()
  guard !self.at_end() && self.input[self.pos] == ',' else {
    raise ParseError("position \{self.pos}: expected ',' in euclid (k,n)")
  }
  self.pos += 1 // consume ','
  self.skip_spaces()
  let n = self.read_int_signed(euclid_start)
  self.skip_spaces()
  let mut rotation = 0
  if !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1 // consume ','
    self.skip_spaces()
    rotation = self.read_int_signed(euclid_start)
    self.skip_spaces()
  }
  guard !self.at_end() && self.input[self.pos] == ')' else {
    raise ParseError("position \{self.pos}: expected ')' to close euclid")
  }
  self.pos += 1 // consume ')'
  self.last_euclid_args = [k, n, rotation]
  if self.query_work is Some(cost) {
    guard n <= 128 else {
      raise ParseError("playback Euclidean rhythm exceeds 128 steps")
    }
    self.query_work = Some(
      if n <= 0 || k <= 0 {
        Quiet
      } else {
        Slots(Array::make(n, cost))
      },
    )
    return pat
  }
  pat.euclid(k, n, rotation~)
}

///|
/// Read a signed integer at current position (no decimal point allowed).
fn NotationParser::read_int_signed(
  self : NotationParser,
  err_pos : Int,
) -> Int raise ParseError {
  let start = self.pos
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  let digits_start = self.pos
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    self.pos += 1
  }
  guard self.pos > digits_start else {
    self.pos = start
    raise ParseError("position \{err_pos}: expected integer")
  }
  let s = self.input[start:self.pos].to_owned()
  let mut value = 0
  let mut i = 0
  let negative = !s.is_empty() && s[0] == '-'
  if negative {
    i = 1
  }
  while i < s.length() {
    value = value * 10 + (s[i].to_int() - '0'.to_int())
    i += 1
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// Parse an atom: `~` for a rest; otherwise an identifier in sound mode, a
/// number or note name in note mode, or a named/explicit chord in chord mode.
fn NotationParser::parse_atom(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let start = self.pos
  let pat = self.parse_atom_value()
  if self.recognized_atoms is Some(atoms) && self.input[start] != '~' {
    let complete = self.at_end() ||
      mini_is_space(self.input[self.pos]) ||
      (match self.input[self.pos] {
        ',' | ']' | '(' | '*' | '/' | '?' | '@' => true
        _ => false
      })
    if complete {
      atoms.push(
        RecognizedAtom(
          if self.sound {
            "sound"
          } else if self.chord {
            "chord"
          } else {
            "note"
          },
          {
            start: self.source_offset + start,
            end: self.source_offset + self.pos,
          },
        ),
      )
    }
  }
  pat
}

///|
fn NotationParser::parse_atom_value(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let start = self.pos
  if self.query_work is Some(_) {
    self.query_work = Some(Atom)
  }
  if self.input[self.pos] == '~' {
    self.pos += 1
    if self.query_work is Some(_) {
      self.query_work = Some(Quiet)
    }
    return @pattern.Pat::silence()
  }
  if self.sound {
    // Read identifier
    let name = self.read_ident()
    guard !name.is_empty() else {
      raise ParseError("position \{start}: expected sound name")
    }
    match drum_midi(name) {
      Some(midi) => @pattern.sound(midi.to_double())
      None => raise ParseError("position \{start}: unknown drum name '\{name}'")
    }
  } else if self.chord {
    let name = self.read_chord_name_text()
    guard !name.is_empty() else {
      raise ParseError("position \{start}: expected chord name")
    }
    match @pattern.parse_chord(name) {
      Some(notes) => {
        if self.query_work is Some(_) {
          self.query_work = Some(Overlay(Array::make(notes.length(), Atom)))
          return @pattern.Pat::silence()
        }
        let note_pats = notes.map(fn(midi) { @pattern.note(midi.to_double()) })
        @pattern.stack(note_pats)
      }
      None => raise ParseError("position \{start}: unknown chord '\{name}'")
    }
  } else {
    // Read number or note name (e.g., "60" or "C4")
    try self.read_note_number(start) catch {
      ParseError(_) => self.read_note_name_atom(start)
    } noraise {
      pat => pat
    }
  }
}

///|
/// Read through a closing brace so malformed contents are rejected as one atom.
fn NotationParser::read_explicit_chord_text(self : NotationParser) -> String {
  let start = self.pos
  while !self.at_end() && self.input[self.pos] != '}' {
    self.pos += 1
  }
  if !self.at_end() {
    self.pos += 1
  }
  self.input[start:self.pos].to_owned()
}

///|
/// In note mode, try to read a note name (e.g., "C4", "F#3", "Bb5") and
/// return a note pattern. Called when number parsing fails.
/// Reads the full note name including accidentals (#, s, b, f) and octave digits.
fn NotationParser::read_note_name_atom(
  self : NotationParser,
  start : Int,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let name = self.read_note_name_text()
  guard !name.is_empty() else {
    raise ParseError("position \{start}: expected note name or number")
  }
  match @pattern.note_name_to_midi(name) {
    Some(midi) => @pattern.note(midi)
    None => raise ParseError("position \{start}: unknown note name '\{name}'")
  }
}

///|
/// Read a note name text: letter (A-G) + optional accidental (#/s/b/f) + optional signed octave digits.
/// Unlike read_ident(), this includes accidentals which are not alphanumeric.
fn NotationParser::read_note_name_text(self : NotationParser) -> String {
  let start = self.pos
  // Read root note letter (must start with A-G)
  if !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'g') || (c >= 'A' && c <= 'G') {
      self.pos += 1
    } else {
      return self.input[start:self.pos].to_owned()
    }
  }
  // Read optional accidental(s)
  while !self.at_end() {
    let c = self.input[self.pos]
    if c == '#' || c == 's' || c == 'b' || c == 'f' {
      self.pos += 1
    } else {
      break
    }
  }
  // Read optional signed octave digits
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  while !self.at_end() {
    let c = self.input[self.pos]
    if c >= '0' && c <= '9' {
      self.pos += 1
    } else {
      break
    }
  }
  self.input[start:self.pos].to_owned()
}

///|
/// Read a named chord or a complete brace-delimited MIDI pitch set.
/// Shared by pattern parsing, work assessment, and source-origin document parsing.
fn NotationParser::read_chord_name_text(self : NotationParser) -> String {
  if !self.at_end() && self.input[self.pos] == '{' {
    return self.read_explicit_chord_text()
  }
  let start = self.pos
  // Read root note letter (must start with A-G)
  if !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'g') || (c >= 'A' && c <= 'G') {
      self.pos += 1
    } else {
      return self.input[start:self.pos].to_owned()
    }
  }
  // Read optional accidental(s)
  while !self.at_end() {
    let c = self.input[self.pos]
    if c == '#' || c == 's' || c == 'b' || c == 'f' {
      self.pos += 1
    } else {
      break
    }
  }
  // Read quality suffix and octave
  while !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '+' ||
      c == 'ø' {
      self.pos += 1
    } else {
      break
    }
  }
  self.input[start:self.pos].to_owned()
}

///|
fn NotationParser::read_ident(self : NotationParser) -> String {
  let start = self.pos
  while !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      (c >= '0' && c <= '9' && self.pos > start) {
      self.pos += 1
    } else {
      break
    }
  }
  self.input[start:self.pos].to_owned()
}

///|
fn NotationParser::read_note_number(
  self : NotationParser,
  start : Int,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let num_start = self.pos
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  let mut has_digit = false
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    self.pos += 1
    has_digit = true
  }
  if !self.at_end() && self.input[self.pos] == '.' {
    self.pos += 1
    while !self.at_end() &&
          self.input[self.pos] >= '0' &&
          self.input[self.pos] <= '9' {
      self.pos += 1
      has_digit = true
    }
  }
  guard has_digit else {
    self.pos = num_start
    raise ParseError("position \{start}: expected number")
  }
  let n = parse_double_manual(self.input, num_start, self.pos)
  @pattern.note(n)
}
