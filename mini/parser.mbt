///|
/// Recursive descent parser for mini-notation.
///
/// Grammar:
///   expr     = primary ( "." method )*
///   primary  = "s(" string ")" | "note(" string ")"
///            | "stack(" expr ( "," expr )* ")"
///   method   = "fast(" number ")" | "slow(" number ")" | "rev()"
///            | "degradeBy(" number ")"
///            | "every(" int "," callback ")"
///            | "jux(" callback ")"
/// callback = "fast(" int ")" | "slow(" int ")" | "rev" "()"?
///   string   = '"' notation '"'
///   notation = layer ( "," layer )*
///   layer    = element+
///   element  = (atom | "[" notation "]") postfix*
///   postfix  = euclid | "*" int | "/" int | "?"
///   euclid   = "(" int "," int ("," int)? ")"
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
#alias(new)
fn Parser::Parser(input : String) -> Parser {
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
/// If `kw` matches the input at `self.pos`, consume it and return true.
/// Otherwise leave `self.pos` untouched and return false. Char-by-char
/// to avoid the StringView→String allocation `to_owned`/`to_string` would
/// require.
fn Parser::match_keyword(self : Parser, kw : String) -> Bool {
  let len = kw.length()
  if self.pos + len > self.input.length() {
    return false
  }
  for i in 0..<len {
    if self.input[self.pos + i] != kw[i] {
      return false
    }
  }
  self.pos += len
  true
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
  self.input[start:self.pos].to_owned()
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
fn Parser::read_method_number_argument(
  self : Parser,
) -> Double raise ParseError {
  self.expect_char('(')
  self.skip_whitespace()
  let value = self.read_number()
  self.skip_whitespace()
  self.expect_char(')')
  value
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
  let content = self.input[start:self.pos].to_owned()
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
/// Parse primary:
///   "s(" string ")" | "note(" string ")" | "stack(" expr ("," expr)* ")"
fn Parser::parse_primary(
  self : Parser,
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  self.skip_whitespace()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of input")
  }
  // Each match_keyword check is exact (keyword + '('), so branch order
  // doesn't disambiguate — `s(` won't accidentally consume `stack(`
  // because the second char ('t' vs '(') makes match_keyword("s(") fail.
  let stack_start = self.pos
  if self.match_keyword("stack(") {
    self.skip_whitespace()
    guard !self.at_end() && self.input[self.pos] != ')' else {
      raise ParseError(
        "position \{stack_start}: stack() requires at least one argument",
      )
    }
    let args : Array[@pattern.Pat[@pattern.ControlMap]] = [self.parse_expr()]
    self.skip_whitespace()
    while !self.at_end() && self.input[self.pos] == ',' {
      self.pos += 1 // consume ','
      self.skip_whitespace()
      args.push(self.parse_expr())
      self.skip_whitespace()
    }
    self.expect_char(')')
    return if args.length() == 1 { args[0] } else { @pattern.stack(args) }
  }
  if self.match_keyword("s(") {
    let content = self.read_quoted_string()
    self.expect_char(')')
    return parse_sound_notation(content)
  }
  if self.match_keyword("note(") {
    let content = self.read_quoted_string()
    self.expect_char(')')
    return parse_note_notation(content)
  }
  raise ParseError("position \{self.pos}: expected 's(', 'note(', or 'stack('")
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
    "degradeBy" => {
      self.expect_char('(')
      self.skip_whitespace()
      let p = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      pat.degrade_by(p)
    }
    "cutoff" => {
      let cutoff = self.read_method_number_argument()
      @pattern.merge_control(pat, @pattern.s_cutoff(cutoff))
    }
    "gain" => {
      let gain = self.read_method_number_argument()
      @pattern.merge_control(pat, @pattern.s_gain(gain))
    }
    "pan" => {
      let pan = self.read_method_number_argument()
      @pattern.merge_control(pat, @pattern.s_pan(pan))
    }
    "every" => {
      self.expect_char('(')
      self.skip_whitespace()
      let n_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let f_name = self.read_ident()
      let f = self.parse_callback(method_start, f_name, calling_method="every")
      self.skip_whitespace()
      self.expect_char(')')
      let n = require_integer(n_dbl, method_start, "every() first argument")
      guard n > 0 else {
        raise ParseError(
          "position \{method_start}: every() requires a positive integer, got \{n}",
        )
      }
      @pattern.every(n, f, pat)
    }
    "jux" => {
      self.expect_char('(')
      self.skip_whitespace()
      let f_name = self.read_ident()
      let f = self.parse_callback(method_start, f_name, calling_method="jux")
      self.skip_whitespace()
      self.expect_char(')')
      pat.jux(f)
    }
    _ => raise ParseError("position \{method_start}: unknown method '\{name}'")
  }
}

///|
/// Reject silent integer truncation. `every(2.5, ...)` and
/// `every(2, fast(1.9))` should raise rather than round to 2/1.
fn require_integer(
  value : Double,
  method_start : Int,
  label : String,
) -> Int raise ParseError {
  let n = value.to_int()
  if value != n.to_double() {
    raise ParseError(
      "position \{method_start}: \{label} requires an integer, got \{value}",
    )
  }
  n
}

///|
/// Callback grammar shared between `.every(n, f)` and `.jux(f)`.
/// Type alias avoids parsing ambiguity between the outer fn's
/// `raise ParseError` effect and the returned function type.
type Callback = (@pattern.Pat[@pattern.ControlMap]) -> @pattern.Pat[
  @pattern.ControlMap,
]

///|
fn make_fast(factor : @pattern.Rational) -> Callback {
  fn(p) { p.fast(factor) }
}

///|
fn make_slow(factor : @pattern.Rational) -> Callback {
  fn(p) { p.slow(factor) }
}

///|
fn make_rev() -> Callback {
  fn(p) { p.rev() }
}

///|
/// Parse the callback argument for `.every(n, f)` or `.jux(f)`.
/// Supported forms: `fast(N)` | `slow(N)` | `rev` | `rev()`.
///
/// `calling_method` is the user-visible method name (`"every"` or
/// `"jux"`) used in error messages — keeps the parse error specific
/// to whichever method the user actually wrote.
fn Parser::parse_callback(
  self : Parser,
  method_start : Int,
  name : String,
  calling_method~ : String,
) -> Callback raise ParseError {
  match name {
    "fast" => {
      self.expect_char('(')
      self.skip_whitespace()
      let k_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      let k = require_integer(k_dbl, method_start, "\{calling_method}(fast(k))")
      guard k > 0 else {
        raise ParseError(
          "position \{method_start}: \{calling_method}(fast(k)) requires a positive integer, got \{k}",
        )
      }
      make_fast(@pattern.Rational::from_int(k))
    }
    "slow" => {
      self.expect_char('(')
      self.skip_whitespace()
      let k_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      let k = require_integer(k_dbl, method_start, "\{calling_method}(slow(k))")
      guard k > 0 else {
        raise ParseError(
          "position \{method_start}: \{calling_method}(slow(k)) requires a positive integer, got \{k}",
        )
      }
      make_slow(@pattern.Rational::from_int(k))
    }
    "rev" => {
      // Accept both `rev` and `rev()` as the callback form.
      if !self.at_end() && self.input[self.pos] == '(' {
        self.expect_char('(')
        self.expect_char(')')
      }
      make_rev()
    }
    _ =>
      raise ParseError(
        "position \{method_start}: \{calling_method}() callback must be fast(N), slow(N), or rev; got '\{name}'",
      )
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
#alias(new)
fn NotationParser::NotationParser(
  input : String,
  sound~ : Bool,
) -> NotationParser {
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
  let negative = s.length() > 0 && s[0] == '-'
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
