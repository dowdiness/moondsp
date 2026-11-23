///|
/// Recursive descent parser for mini-notation.
///
/// Grammar:
///   binding  = "let" identifier "=" expr ";"
///   dollar_stack = ( "$:" expr )+    (each "$:" starts its line)
///   expr     = chain ( "+" chain )*
///   chain    = primary ( "." method )*
///   primary  = "s(" string ")" | "note(" string ")"
///            | "stack(" expr ( "," expr )* ")" | "(" expr ")" | identifier
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
/// Parser state: input string + current position.
priv struct Parser {
  input : String
  mut pos : Int32
  bindings : Map[String, MiniDefinition]
  admission : PlaybackAdmission?
  mut recognition : Bool
  mut recognized_pattern : Bool
  recognized_atoms : Array[RecognizedAtom]
  recognized_literals : Array[RecognizedLiteral]
  recognized_references : Array[RecognizedReference]
  mut last_binding_span : MiniSpan
  syntax_depth_limit : Int32?
  mut limit : Int32
}

///|
/// One `$:` block: from after its `$:` to where the next block's `$:` begins.
priv struct MiniDollarBlock {
  start : Int32
  end : Int32
}

///|
fn Parser::Parser(
  input : String,
  admission~ : PlaybackAdmission? = None,
  syntax_depth_limit~ : Int32? = None,
) -> Parser {
  {
    input,
    pos: 0,
    bindings: Map([]),
    admission,
    recognition: false,
    recognized_pattern: false,
    recognized_atoms: [],
    recognized_literals: [],
    recognized_references: [],
    last_binding_span: { start: 0, end: 0, },
    syntax_depth_limit,
    limit: input.length(),
  }
}

///|
/// Split a `$:` program into its blocks, as the Loom grammar does. A block
/// runs from its `$:` across lines and comments to the next `$:` that is the
/// first token on its line, outside quotes and comments. Returns `None` when
/// the source does not start with `$:`.
fn mini_collect_dollar_blocks(
  input : String,
  start~ : Int32 = 0,
) -> Array[MiniDollarBlock]? {
  let markers : Array[Int32] = []
  // Whether a newline came before this point since the last token.
  let mut line_start = true
  let mut pos = start
  while pos < input.length() {
    let c = input[pos]
    if mini_is_space(c) {
      line_start = line_start || c == '\n'
      pos += 1
    } else if c != '"' && mini_opaque_end(input, pos) is Some(end_) {
      for i in pos..<end_ {
        line_start = line_start || input[i] == '\n'
      }
      pos = end_
    } else if line_start &&
      c == '$' &&
      pos + 1 < input.length() &&
      input[pos + 1] == ':' {
      markers.push(pos)
      pos += 2
      line_start = false
    } else {
      guard !markers.is_empty() else { return None }
      pos = mini_opaque_end(input, pos).unwrap_or(pos + 1)
      line_start = false
    }
  }
  guard !markers.is_empty() else { return None }
  Some(
    markers.mapi((i, marker) => {
      start: marker + 2,
      end: if i + 1 < markers.length() {
        markers[i + 1]
      } else {
        input.length()
      },
    }),
  )
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.limit
}

///|
/// Return the end of a complete comment. An unterminated block is left at its
/// opening delimiter so normal parsing rejects it instead of accepting a prefix.
fn mini_comment_end(input : String, start : Int32) -> Int32? {
  guard start + 1 < input.length() && input[start] == '/' else { return None }
  let mut end_ = start + 2
  match input[start + 1] {
    '/' => {
      while end_ < input.length() && input[end_] != '\n' {
        end_ += 1
      }
      Some(end_)
    }
    '*' => {
      while end_ + 1 < input.length() {
        if input[end_] == '*' && input[end_ + 1] == '/' {
          return Some(end_ + 2)
        }
        end_ += 1
      }
      None
    }
    _ => None
  }
}

///|
/// The end of the quote or comment that starts at `start`, as the parser reads
/// them: a quote runs to the next quote, and an unterminated quote or block
/// comment to the end of the input.
fn mini_opaque_end(input : String, start : Int32) -> Int32? {
  if input[start] == '"' {
    let mut end_ = start + 1
    while end_ < input.length() && input[end_] != '"' {
      end_ += 1
    }
    return Some(if end_ < input.length() { end_ + 1 } else { end_ })
  }
  match mini_comment_end(input, start) {
    Some(end_) => Some(end_)
    None =>
      if start + 1 < input.length() &&
        input[start] == '/' &&
        input[start + 1] == '*' {
        Some(input.length())
      } else {
        None
      }
  }
}

///|
fn Parser::skip_whitespace(self : Parser) -> Unit {
  while true {
    while !self.at_end() && mini_is_space(self.input[self.pos]) {
      self.pos += 1
    }
    match mini_comment_end(self.input, self.pos) {
      Some(end_) if end_ <= self.limit => self.pos = end_
      _ => break
    }
  }
}

///|
fn Parser::expect_char(self : Parser, c : Char) -> Unit raise SourceProblem {
  if self.at_end() {
    raise Mistake(self.pos, "expected '\{c}', got end of input")
  }
  let code = c.to_int().to_uint16()
  if self.input[self.pos] != code {
    raise Mistake(self.pos, "expected '\{c}', got '\{self.input[self.pos]}'")
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
  self.input[start:self.pos].to_owned()
}

///|
/// Read a number (integer or float, possibly negative).
fn Parser::read_number(self : Parser) -> Double raise SourceProblem {
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
    raise Mistake(start, "expected number")
  }
  parse_double_manual(self.input, start, self.pos)
}

///|
/// `(value)` after a control method's name at `method_at`.
fn Parser::read_method_control_argument(
  self : Parser,
  method_at : Int32,
) -> ControlArgument raise SourceProblem {
  self.expect_char('(')
  let argument = self.read_control_argument(method_at)
  self.skip_whitespace()
  self.expect_char(')')
  argument
}

///|
fn Parser::read_control_argument(
  self : Parser,
  method_at : Int32,
) -> ControlArgument raise SourceProblem {
  { value: self.read_control_value(), method_at, }
}

///|
/// A control argument: a number, a quoted Mini pattern of numbers such as
/// `"0.3 <0.6 0.9>"`, or a signal such as `sine.range(200, 4000).slow(4)`.
/// The quoted notation is read when the expression is resolved.
fn Parser::read_control_value(
  self : Parser,
) -> MiniValue[QuotedNotation] raise SourceProblem {
  self.skip_whitespace()
  let start = self.pos
  guard !self.at_end() else { raise Mistake(start, "expected a control value") }
  if self.input[self.pos] == '"' {
    let (text, at) = self.read_quoted_string_with_start()
    return Steps({ text, at, })
  }
  let name = self.read_ident()
  if name.is_empty() {
    return Number(self.read_number())
  }
  guard MiniShape::parse(name) is Some(shape) else {
    let signals = MiniShape::all().map(MiniShape::name).join(", ")
    raise Mistake(
      start,
      "expected a number, a quoted pattern, or a signal (\{signals}), got '\{name}'",
    )
  }
  let mut low = 0.0
  let mut high = 1.0
  let mut rate = @pattern.Rational::from_int(1)
  while true {
    let before = self.pos
    self.skip_whitespace()
    guard !self.at_end() && self.input[self.pos] == '.' else {
      self.pos = before
      break
    }
    self.pos += 1
    let method_start = self.pos
    let name = self.read_ident()
    guard SignalMethod::parse(name) is Some(signal_method) else {
      let expected = or_list(SignalMethod::all().map(SignalMethod::name))
      raise Mistake(
        method_start,
        "unknown signal method '\{name}'; use \{expected}",
      )
    }
    match signal_method {
      Range => {
        self.expect_char('(')
        self.skip_whitespace()
        let from = self.read_number()
        self.skip_whitespace()
        self.expect_char(',')
        self.skip_whitespace()
        let to = self.read_number()
        self.skip_whitespace()
        self.expect_char(')')
        // Ranges compose: the new range maps the current one.
        let span = to - from
        let next_low = from + span * low
        high = from + span * high
        low = next_low
      }
      Fast =>
        rate = rate *
          self.read_positive_factor(method_start, signal_method.name())
      Slow =>
        rate = rate /
          self.read_positive_factor(method_start, signal_method.name())
    }
  }
  Signal({ shape, low, high, rate, })
}

///|
/// Simple manual double parsing to avoid strconv dependency issues.
fn parse_double_manual(s : String, start : Int32, end : Int32) -> Double {
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
/// Convert the parser's plain decimal syntax to exact musical time.
fn parse_decimal_rational(
  input : String,
  start : Int32,
  end_ : Int32,
  error_position : Int32,
) -> @pattern.Rational raise SourceProblem {
  let negative = input[start] == '-'
  let digits_start = if negative { start + 1 } else { start }
  let mut point = end_
  for index in digits_start..<end_ {
    if input[index] == '.' {
      point = index
      break
    }
  }
  let mut whole = 0L
  for index in digits_start..<point {
    let digit = (input[index].to_int() - '0'.to_int()).to_int64()
    guard whole <= (9223372036854775807L - digit) / 10L else {
      raise Mistake(
        error_position, "decimal factor exceeds exact rational range",
      )
    }
    whole = whole * 10L + digit
  }
  let mut fractional_end = end_
  while fractional_end > point + 1 && input[fractional_end - 1] == '0' {
    fractional_end -= 1
  }
  let fractional_digits = if point < end_ {
    fractional_end - point - 1
  } else {
    0
  }
  guard fractional_digits <= 18 else {
    raise Mistake(
      error_position, "exact decimal factors support at most 18 fractional digits",
    )
  }
  let mut denominator = 1L
  let mut fractional = 0L
  for index in (point + 1)..<fractional_end {
    denominator *= 10L
    fractional = fractional * 10L +
      (input[index].to_int() - '0'.to_int()).to_int64()
  }
  guard whole <= (9223372036854775807L - fractional) / denominator else {
    raise Mistake(error_position, "decimal factor exceeds exact rational range")
  }
  let numerator = whole * denominator + fractional
  @pattern.Rational(if negative { -numerator } else { numerator }, denominator)
}

///|
/// Read the quoted string contents between double quotes.
fn Parser::read_quoted_string(self : Parser) -> String raise SourceProblem {
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
/// Reject silent integer truncation. `every(2.5, ...)` and
/// `every(2, fast(1.9))` should raise rather than round to 2/1.
fn require_integer(
  value : Double,
  method_start : Int32,
  label : String,
) -> Int32 raise SourceProblem {
  let n = value.to_int()
  if value != n.to_double() {
    raise Mistake(method_start, "\{label} requires an integer, got \{value}")
  }
  n
}

///|
/// Consume a declaration header. Bindings are immutable and ordered, so no
/// unresolved or cyclic dependency can enter the lowered pattern.
fn Parser::read_binding_name(self : Parser) -> String? raise SourceProblem {
  self.skip_whitespace()
  let start = self.pos
  if self.read_ident() != "let" {
    self.pos = start
    return None
  }
  self.skip_whitespace()
  let name_start = self.pos
  let name = self.read_ident()
  guard !name.is_empty() else {
    raise Mistake(name_start, "expected pattern name")
  }
  if is_reserved_name(name) {
    raise Mistake(name_start, "reserved pattern name '\{name}'")
  }
  if self.bindings.contains(name) {
    raise Mistake(name_start, "duplicate pattern '\{name}'")
  }
  self.skip_whitespace()
  self.expect_char('=')
  self.last_binding_span = {
    start: name_start,
    end: name_start + name.length(),
  }
  Some(name)
}

///|
fn Parser::parse_bindings(
  self : Parser,
  builder : MiniDocBuilder,
) -> Unit raise SourceProblem {
  while true {
    self.skip_whitespace()
    guard self.read_binding_name() is Some(name) else { break }
    // Resolve before checking the terminator to preserve diagnostic precedence.
    // Compile unused declarations too; publish a name only after success.
    let syntax = resolve_mini_expr(self.parse_syntax_expr(), self.bindings)
    let name_span = self.last_binding_span
    if self.admission is Some(admission) {
      ignore(admission.definition(name_span, syntax))
    }
    self.skip_whitespace()
    self.expect_char(';')
    self.bindings[name] = {
      syntax,
      body: compile_score(syntax, builder),
      name_span,
    }
  }
}

///|
/// `(n)` after a method named `name`: a finite positive decimal, exactly.
fn Parser::read_positive_factor(
  self : Parser,
  method_start : Int32,
  name : String,
) -> @pattern.Rational raise SourceProblem {
  self.expect_char('(')
  self.skip_whitespace()
  let value_start = self.pos
  let value = self.read_number()
  let value_end = self.pos
  self.skip_whitespace()
  self.expect_char(')')
  guard !value.is_nan() && !value.is_inf() && value > 0.0 else {
    raise Mistake(
      method_start,
      "\{name}() requires a finite positive number, got \{value}",
    )
  }
  parse_decimal_rational(self.input, value_start, value_end, method_start)
}

///|
/// Raise unless only whitespace is left.
fn Parser::expect_end(self : Parser) -> Unit raise SourceProblem {
  self.skip_whitespace()
  guard self.at_end() else { raise Mistake(self.pos, "trailing input") }
}
