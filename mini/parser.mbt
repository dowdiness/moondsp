///|
/// Recursive descent parser for mini-notation.
///
/// Grammar:
///   expr     = primary ( "." method )*
///   primary  = "s(" string ")" | "note(" string ")"
///   method   = "fast(" number ")" | "slow(" number ")" | "rev()"
///   string   = '"' notation '"'
///   notation = layer ( "," layer )*
///   layer    = element+
///   element  = atom | "[" notation "]"
///   atom     = identifier | number

///|
priv suberror ParseError {
  ParseError(String)
}

///|
/// Parser state: input string + current position.
priv struct Parser {
  input : String
  mut pos : Int
}

///|
fn Parser::new(input : String) -> Parser {
  { input, pos: 0 }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.input.length()
}

///|
fn Parser::skip_whitespace(self : Parser) -> Unit {
  while !self.at_end() && self.input[self.pos] == ' ' {
    self.pos += 1
  }
}

///|
fn Parser::expect_char(self : Parser, c : Char) -> Unit raise ParseError {
  if self.at_end() {
    raise ParseError("position \{self.pos}: expected '\{c}', got end of input")
  }
  let code = c.to_int().to_uint16()
  if self.input[self.pos] != code {
    raise ParseError(
      "position \{self.pos}: expected '\{c}', got '\{self.input[self.pos]}'",
    )
  }
  self.pos += 1
}

///|
/// Read an identifier: [a-zA-Z_][a-zA-Z0-9_]*
fn Parser::read_ident(self : Parser) -> String {
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
  self.input[start:self.pos].to_string()
}

///|
/// Read a number (integer or float, possibly negative).
fn Parser::read_number(self : Parser) -> Double raise ParseError {
  let start = self.pos
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
    self.pos = start
    raise ParseError("position \{start}: expected number")
  }
  parse_double_manual(self.input, start, self.pos)
}

///|
/// Simple manual double parsing to avoid strconv dependency issues.
fn parse_double_manual(s : String, start : Int, end : Int) -> Double {
  let mut result = 0.0
  let mut i = start
  let negative = i < end && s[i] == '-'
  if negative {
    i += 1
  }
  // Integer part
  while i < end && s[i] >= '0' && s[i] <= '9' {
    result = result * 10.0 + (s[i].to_int() - '0'.to_int()).to_double()
    i += 1
  }
  // Fractional part
  if i < end && s[i] == '.' {
    i += 1
    let mut frac = 0.1
    while i < end && s[i] >= '0' && s[i] <= '9' {
      result = result + (s[i].to_int() - '0'.to_int()).to_double() * frac
      frac = frac * 0.1
      i += 1
    }
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
/// Read the quoted string contents between double quotes.
fn Parser::read_quoted_string(self : Parser) -> String raise ParseError {
  self.expect_char('"')
  let start = self.pos
  while !self.at_end() && self.input[self.pos] != '"' {
    self.pos += 1
  }
  let content = self.input[start:self.pos].to_string()
  self.expect_char('"')
  content
}

///|
/// Parse the top-level expression: primary ( "." method )*
fn Parser::parse_expr(
  self : Parser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let mut pat = self.parse_primary()
  while !self.at_end() && self.input[self.pos] == '.' {
    self.pos += 1 // consume '.'
    pat = self.parse_method(pat)
  }
  pat
}

///|
/// Parse primary: "s(" string ")" | "note(" string ")"
fn Parser::parse_primary(
  self : Parser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  self.skip_whitespace()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of input")
  }
  // Try "s("
  if self.pos + 2 <= self.input.length() &&
    self.input[self.pos] == 's' &&
    self.input[self.pos + 1] == '(' {
    self.pos += 2
    let content = self.read_quoted_string()
    self.expect_char(')')
    return parse_sound_notation(content)
  }
  // Try "note("
  if self.pos + 5 <= self.input.length() {
    let maybe_note = self.input[self.pos:self.pos + 5].to_string()
    if maybe_note == "note(" {
      self.pos += 5
      let content = self.read_quoted_string()
      self.expect_char(')')
      return parse_note_notation(content)
    }
  }
  raise ParseError("position \{self.pos}: expected 's(' or 'note('")
}

///|
/// Parse method call: "fast(" number ")" | "slow(" number ")" | "rev()"
fn Parser::parse_method(
  self : Parser,
  pat : @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let method_start = self.pos
  let name = self.read_ident()
  match name {
    "fast" => {
      self.expect_char('(')
      self.skip_whitespace()
      let n = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      guard n > 0.0 else {
        raise ParseError(
          "position \{method_start}: fast() requires a positive number, got \{n}",
        )
      }
      pat.fast(@pattern.Rational::from_int(n.to_int()))
    }
    "slow" => {
      self.expect_char('(')
      self.skip_whitespace()
      let n = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      guard n > 0.0 else {
        raise ParseError(
          "position \{method_start}: slow() requires a positive number, got \{n}",
        )
      }
      pat.slow(@pattern.Rational::from_int(n.to_int()))
    }
    "rev" => {
      self.expect_char('(')
      self.expect_char(')')
      pat.rev()
    }
    _ => raise ParseError("position \{method_start}: unknown method '\{name}'")
  }
}

///|
/// Parse sound notation string into Pat[ControlMap].
fn parse_sound_notation(
  content : String,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  guard content.length() > 0 else {
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
  guard content.length() > 0 else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser::new(content, sound=false)
  sub.parse_notation()
}

///|
/// Sub-parser for the notation content inside quotes.
priv struct NotationParser {
  input : String
  mut pos : Int
  sound : Bool // true = drum names, false = note numbers
}

///|
fn NotationParser::new(input : String, sound~ : Bool) -> NotationParser {
  { input, pos: 0, sound }
}

///|
fn NotationParser::at_end(self : NotationParser) -> Bool {
  self.pos >= self.input.length()
}

///|
fn NotationParser::skip_spaces(self : NotationParser) -> Unit {
  while !self.at_end() && self.input[self.pos] == ' ' {
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
    self.skip_spaces()
  }
  guard elements.length() > 0 else {
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
/// Parse an element: atom or "[" notation "]"
fn NotationParser::parse_element(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  self.skip_spaces()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of notation")
  }
  if self.input[self.pos] == '[' {
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
}

///|
/// Parse an atom: identifier (for sound mode) or number (for note mode).
fn NotationParser::parse_atom(
  self : NotationParser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  let start = self.pos
  if self.sound {
    // Read identifier
    let name = self.read_ident()
    guard name.length() > 0 else {
      raise ParseError("position \{start}: expected sound name")
    }
    match drum_midi(name) {
      Some(midi) => @pattern.sound(midi.to_double())
      None => raise ParseError("position \{start}: unknown drum name '\{name}'")
    }
  } else {
    // Read number
    self.read_note_number(start)
  }
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
  self.input[start:self.pos].to_string()
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
