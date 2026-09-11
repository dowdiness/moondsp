///|
/// Shared expression syntax. This representation contains data and source spans,
/// never runtime closures or compiled documents.
priv struct MiniSpan {
  start : Int
  end : Int
}

///|
priv enum MiniLiteral {
  Sound
  Note
  Chord
}

///|
priv enum MiniCallback {
  Fast(Int)
  Slow(Int)
  Rev
}

///|
priv enum MiniTransform {
  Fast(@pattern.Rational)
  Slow(@pattern.Rational)
  Rev
  Degrade(Double)
  Control(String, Double)
  Every(Int, MiniCallback)
  Jux(MiniCallback)
}

///|
priv struct MiniExpr {
  span : MiniSpan
  node : MiniExprNode
}

///|
priv enum MiniExprNode {
  Literal(MiniLiteral, String, Int)
  Stack(Array[MiniExpr])
  Reference(String)
  Apply(MiniExpr, MiniTransform)
}

///|
fn Parser::parse_syntax_expr(self : Parser) -> MiniExpr raise ParseError {
  self.skip_whitespace()
  let start = self.pos
  let node = self.parse_syntax_primary()
  let mut expr = MiniExpr::{ span: { start, end: self.pos }, node }
  while true {
    let before_ws = self.pos
    self.skip_whitespace()
    if self.at_end() || self.input[self.pos] != '.' {
      self.pos = before_ws
      break
    }
    self.pos += 1
    let transform = self.parse_transform()
    expr = { span: { start, end: self.pos }, node: Apply(expr, transform) }
  }
  expr
}

///|
fn Parser::parse_syntax_primary(self : Parser) -> MiniExprNode raise ParseError {
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of input")
  }
  let start = self.pos
  if self.match_keyword("stack(") {
    self.skip_whitespace()
    guard !self.at_end() && self.input[self.pos] != ')' else {
      raise ParseError(
        "position \{start}: stack() requires at least one argument",
      )
    }
    let args = [self.parse_syntax_expr()]
    self.skip_whitespace()
    while !self.at_end() && self.input[self.pos] == ',' {
      self.pos += 1
      args.push(self.parse_syntax_expr())
      self.skip_whitespace()
    }
    self.expect_char(')')
    return Stack(args)
  }
  let kind = if self.match_keyword("s(") {
    Some(Sound)
  } else if self.match_keyword("note(") {
    Some(Note)
  } else if self.match_keyword("chord(") {
    Some(Chord)
  } else {
    None
  }
  if kind is Some(kind) {
    let (content, content_start) = self.read_quoted_string_with_start()
    self.expect_char(')')
    return Literal(kind, content, content_start)
  }
  let name = self.read_ident()
  if !name.is_empty() {
    return Reference(name)
  }
  raise ParseError(
    "position \{self.pos}: expected 's(', 'note(', 'chord(', or 'stack('",
  )
}

///|
fn Parser::parse_transform(self : Parser) -> MiniTransform raise ParseError {
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
      Fast(@pattern.Rational::from_int(n.to_int()))
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
      Slow(@pattern.Rational::from_int(n.to_int()))
    }
    "rev" => {
      self.expect_char('(')
      self.expect_char(')')
      Rev
    }
    "degradeBy" => {
      self.expect_char('(')
      self.skip_whitespace()
      let p = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      Degrade(p)
    }
    "cutoff" => {
      let cutoff = self.read_method_number_argument()
      Control("cutoff", cutoff)
    }
    "attack" | "hold" | "release" => {
      let seconds = self.read_method_number_argument()
      if seconds.is_nan() ||
        seconds.is_inf() ||
        seconds < 0.0 ||
        seconds > 86400.0 {
        raise ParseError(
          "position \{method_start}: \{name}() expects seconds between 0 and 86400",
        )
      }
      Control(name, seconds)
    }
    "gain" => {
      let gain = self.read_method_number_argument()
      Control("gain", gain)
    }
    "pan" => {
      let pan = self.read_method_number_argument()
      Control("pan", pan)
    }
    "every" => {
      self.expect_char('(')
      self.skip_whitespace()
      let n_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let f_name = self.read_ident()
      let f = self.parse_transform_callback(
        method_start,
        f_name,
        calling_method="every",
      )
      self.skip_whitespace()
      self.expect_char(')')
      let n = require_integer(n_dbl, method_start, "every() first argument")
      guard n > 0 else {
        raise ParseError(
          "position \{method_start}: every() requires a positive integer, got \{n}",
        )
      }
      Every(n, f)
    }
    "jux" => {
      self.expect_char('(')
      self.skip_whitespace()
      let f_name = self.read_ident()
      let f = self.parse_transform_callback(
        method_start,
        f_name,
        calling_method="jux",
      )
      self.skip_whitespace()
      self.expect_char(')')
      Jux(f)
    }
    _ => raise ParseError("position \{method_start}: unknown method '\{name}'")
  }
}

///|
fn Parser::parse_transform_callback(
  self : Parser,
  method_start : Int,
  name : String,
  calling_method~ : String,
) -> MiniCallback raise ParseError {
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
      Fast(k)
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
      Slow(k)
    }
    "rev" => {
      // Accept both `rev` and `rev()` as the callback form.
      if !self.at_end() && self.input[self.pos] == '(' {
        self.expect_char('(')
        self.expect_char(')')
      }
      Rev
    }
    _ =>
      raise ParseError(
        "position \{method_start}: \{calling_method}() callback must be fast(N), slow(N), or rev; got '\{name}'",
      )
  }
}
