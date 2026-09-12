///|
/// Recursive descent parser for mini-notation.
///
/// Grammar:
///   program  = binding* (expr | dollar_stack)
///   binding  = "let" identifier "=" expr ";"
///   dollar_stack = ( "$:" expr newline? )+
///   expr     = primary ( "." method )*
///   primary  = "s(" string ")" | "note(" string ")"
///            | "stack(" expr ( "," expr )* ")" | identifier
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
  definitions : Map[String, MiniDefinition]
  bindings : Map[String, @pattern.Pat[@pattern.ControlMap]]
  doc_bindings : Map[String, @pattern.PatternDoc[@pattern.ControlMap]]
}

///|
#alias(new)
fn Parser::Parser(input : String) -> Parser {
  { input, pos: 0, definitions: {}, bindings: {}, doc_bindings: {}, }
}

///|
priv struct MiniDollarStackLine {
  start : Int
  end : Int
}

///|
fn mini_collect_dollar_stack_lines(
  input : String,
  start? : Int = 0,
) -> Result[Array[MiniDollarStackLine]?, String] {
  let lines : Array[MiniDollarStackLine] = []
  let mut saw_program = false
  let mut pos = start
  while pos < input.length() {
    let line_start = pos
    let mut line_end = pos
    while line_end < input.length() && input[line_end] != '\n' {
      line_end += 1
    }
    let mut content_end = line_end
    if content_end > line_start && input[content_end - 1] == '\r' {
      content_end -= 1
    }
    let mut first = line_start
    while first < content_end && input[first] == ' ' {
      first += 1
    }
    if first < content_end {
      if first + 2 <= content_end &&
        input[first] == '$' &&
        input[first + 1] == ':' {
        saw_program = true
        let expr_start = first + 2
        let mut expr_first = expr_start
        while expr_first < content_end && input[expr_first] == ' ' {
          expr_first += 1
        }
        if expr_first == content_end {
          return Err("position \{first}: $: requires an expression")
        }
        lines.push({ start: expr_start, end: content_end, })
      } else if saw_program {
        return Err("position \{first}: expected '$:' stack line")
      } else {
        return Ok(None)
      }
    }
    pos = if line_end < input.length() { line_end + 1 } else { line_end }
  }
  if saw_program {
    Ok(Some(lines))
  } else {
    Ok(None)
  }
}

///|
fn mini_parse_dollar_stack_program(
  input : String,
  lines : Array[MiniDollarStackLine],
  parser? : Parser = Parser::new(input),
) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  let args : Array[@pattern.Pat[@pattern.ControlMap]] = []
  for line in lines {
    parser.pos = line.start
    let pat = parser.parse_expr() catch { ParseError(msg) => return Err(msg) }
    parser.skip_inline_whitespace()
    if parser.pos != line.end {
      return Err(
        "position \{parser.pos}: unexpected trailing input '\{input[parser.pos:line.end].to_owned()}'",
      )
    }
    args.push(pat)
  }
  Ok(if args.length() == 1 { args[0] } else { @pattern.stack(args) })
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.input.length()
}

///|
fn Parser::skip_whitespace(self : Parser) -> Unit {
  while !self.at_end() && mini_is_space(self.input[self.pos]) {
    self.pos += 1
  }
}

///|
fn Parser::skip_inline_whitespace(self : Parser) -> Unit {
  while !self.at_end() &&
        (self.input[self.pos] == ' ' || self.input[self.pos] == '\t') {
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
  let syntax = self.parse_syntax_expr()
  let resolved = resolve_mini_expr(syntax, self.definitions)
  compile_mini_pattern(resolved, self.bindings)
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
/// Consume a declaration header. Bindings are immutable and ordered, so no
/// unresolved or cyclic dependency can enter the lowered pattern.
fn Parser::read_binding_name(self : Parser) -> String? raise ParseError {
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
    raise ParseError("position \{name_start}: expected pattern name")
  }
  match name {
    "let" | "s" | "note" | "chord" | "stack" | "song" =>
      raise ParseError(
        "position \{name_start}: reserved pattern name '\{name}'",
      )
    _ => ()
  }
  if self.definitions.contains(name) {
    raise ParseError("position \{name_start}: duplicate pattern '\{name}'")
  }
  self.skip_whitespace()
  self.expect_char('=')
  Some(name)
}

///|
fn Parser::parse_bindings(
  self : Parser,
  builder? : MiniDocBuilder? = None,
) -> Unit raise ParseError {
  while true {
    self.skip_whitespace()
    guard self.read_binding_name() is Some(name) else { break }
    let syntax = self.parse_syntax_expr()
    let body = resolve_mini_expr(syntax, self.definitions)
    self.skip_whitespace()
    self.expect_char(';')
    // Compile every definition, including unused ones, exactly once per input.
    // Both backends receive the same resolved syntax and lexical scope.
    match builder {
      None => self.bindings[name] = compile_mini_pattern(body, self.bindings)
      Some(builder) =>
        self.doc_bindings[name] = compile_mini_doc(
          body,
          builder,
          self.doc_bindings,
        )
    }
    self.definitions[name] = { id: name, body, }
  }
}

///|
type Callback = (@pattern.Pat[@pattern.ControlMap]) -> @pattern.Pat[
  @pattern.ControlMap,
]
