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
/// Sub-parser for the notation content inside quotes.
priv struct NotationParser {
  input : String
  mut pos : Int
  sound : Bool // true = drum names, false = note numbers
  chord : Bool // true = chord names (stacked notes per name)
  source_offset : Int
}

///|
#alias(new)
fn NotationParser::NotationParser(
  input : String,
  sound~ : Bool,
  chord? : Bool = false,
  source_offset? : Int = 0,
) -> NotationParser {
  { input, pos: 0, sound, chord, source_offset }
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
  while !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1 // consume ','
    self.skip_spaces()
    layers.push(self.parse_layer())
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
  let elements : Array[@pattern.Pat[@pattern.ControlMap]] = []
  while !self.at_end() &&
        self.input[self.pos] != ',' &&
        self.input[self.pos] != ']' {
    elements.push(self.parse_element())
    self.require_element_boundary()
    self.skip_spaces()
  }
  guard !elements.is_empty() else {
    raise ParseError(
      "position \{self.pos}: expected at least one element in layer",
    )
  }
  if elements.length() == 1 {
    elements[0]
  } else {
    @pattern.sequence(elements)
  }
}

///|
/// Parse an element: (atom | "[" notation "]") postfix*
/// where postfix = euclid | "*" int | "/" int
/// and   euclid  = "(" int "," int ("," int)? ")"
fn NotationParser::parse_element(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  self.skip_spaces()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of notation")
  }
  let base = if self.input[self.pos] == '[' {
    self.pos += 1 // consume '['
    let inner = self.parse_notation()
    guard !self.at_end() && self.input[self.pos] == ']' else {
      raise ParseError("position \{self.pos}: expected ']'")
    }
    self.pos += 1 // consume ']'
    inner
  } else {
    self.parse_atom()
  }
  // Apply zero or more postfix modifiers in left-to-right order.
  let mut pat = base
  let mut applied = true
  while applied {
    applied = false
    if !self.at_end() {
      let c = self.input[self.pos]
      if c == '(' {
        pat = self.maybe_apply_euclid(pat)
        applied = true
      } else if c == '*' {
        pat = self.apply_replicate(pat)
        applied = true
      } else if c == '/' {
        pat = self.apply_step_slow(pat)
        applied = true
      } else if c == '?' {
        // Per-occurrence seed from source position so adjacent `?` elements
        // hash independently — sequence places each inner pattern at the
        // same local arc, so a fixed seed would drop them in lockstep.
        let salt = self.pos
        self.pos += 1 // consume '?'
        pat = pat.degrade_by(0.5, seed=salt)
        applied = true
      }
    }
  }
  pat
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
/// Parse an atom: identifier (for sound mode), number or note name (for note mode),
/// or chord name (for chord mode).
fn NotationParser::parse_atom(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let start = self.pos
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
    // Read chord name (including accidentals like #, b)
    let name = self.read_chord_name_text()
    guard !name.is_empty() else {
      raise ParseError("position \{start}: expected chord name")
    }
    match @pattern.parse_chord(name) {
      Some(notes) => {
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
/// Read a chord name text: letter (A-G) + optional accidental (#/s/b/f)
/// + quality suffix (alphanumeric, +, ø) + optional octave digits.
/// Unlike read_ident(), this includes accidentals which are not alphanumeric.
fn NotationParser::read_chord_name_text(self : NotationParser) -> String {
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
