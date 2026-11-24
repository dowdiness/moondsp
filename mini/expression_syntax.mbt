///|
/// Shared expression syntax. This representation contains data and source spans,
/// never runtime closures or compiled documents.
priv struct MiniSpan {
  start : Int32
  end : Int32
}

///|
/// The kind of a quoted pattern literal such as `s("bd sd")`.
priv enum MiniLiteral {
  Sound
  Note
  Chord
}

///|
priv enum MiniCallback {
  Fast(Int32)
  Slow(Int32)
  Rev
}

///|
priv enum MiniFilterKind {
  LowPass
  HighPass
}

///|
fn MiniFilterKind::control_key(self : MiniFilterKind) -> @control.Control {
  match self {
    LowPass => Lpf
    HighPass => Hpf
  }
}

///|
fn MiniFilterKind::resonance_control_key(
  self : MiniFilterKind,
) -> @control.Control {
  match self {
    LowPass => LpfResonance
    HighPass => HpfResonance
  }
}

///|
/// A periodic signal shape with values in [0, 1] and period one cycle.
priv enum MiniShape {
  Sine
  Cosine
  Saw
  Isaw
  Tri
  Square
}

///|
/// Every signal shape. Keep this the only expression that constructs one.
fn MiniShape::all() -> Array[MiniShape] {
  [Sine, Cosine, Saw, Isaw, Tri, Square]
}

///|
fn MiniShape::parse(name : String) -> MiniShape? {
  MiniShape::all().iter().find_first(shape => shape.name() == name)
}

///|
fn MiniShape::name(self : MiniShape) -> String {
  match self {
    Sine => "sine"
    Cosine => "cosine"
    Saw => "saw"
    Isaw => "isaw"
    Tri => "tri"
    Square => "square"
  }
}

///|
/// The shape at cycle position `t`. Allocates nothing.
fn MiniShape::at(self : MiniShape, t : Double) -> Double {
  let phase = t - t.floor()
  match self {
    Sine => 0.5 + 0.5 * @math.sin(2.0 * @math.PI * phase)
    Cosine => 0.5 + 0.5 * @math.cos(2.0 * @math.PI * phase)
    Saw => phase
    Isaw => 1.0 - phase
    Tri => if phase < 0.5 { 2.0 * phase } else { 2.0 - 2.0 * phase }
    Square => if phase < 0.5 { 0.0 } else { 1.0 }
  }
}

///|
/// `low + (high - low) × shape(t × rate)`.
priv struct MiniSignal {
  shape : MiniShape
  low : Double
  high : Double
  rate : @pattern.Rational
}

///|
/// The signal before its rate, as a function of cycle position.
fn MiniSignal::function(self : MiniSignal) -> (Double) -> Double {
  let shape = self.shape
  let low = self.low
  let span = self.high - self.low
  t => low + span * shape.at(t)
}

///|
/// A control argument: one value, quoted notation of numbers, or a
/// continuous signal. `S` is the notation as written, or as read.
priv enum MiniValue[S] {
  Number(Double)
  Steps(S)
  Signal(MiniSignal)
}

///|
/// A control argument as written in a method call such as `.room("0.2 0.4")`.
priv struct ControlArgument {
  value : MiniValue[QuotedNotation]
  /// Where a value outside the control's domain is marked: the method name.
  method_at : Int32
}

///|
/// A transform; `A` is its control arguments, as written or as read.
priv enum MiniTransform[A] {
  Fast(@pattern.Rational)
  Slow(@pattern.Rational)
  Gate(@pattern.Rational)
  Rev
  Degrade(Double)
  Control(@control.Control, A)
  Filter(MiniFilterKind, A, A?)
  Every(Int32, MiniCallback)
  Jux(MiniCallback)
}

///|
/// The quoted content of a notation, as written.
priv struct QuotedNotation {
  text : String
  /// Whole-source position of the content's first code unit.
  at : Int32
}

///|
priv struct MiniExpr {
  span : MiniSpan
  node : MiniExprNode
}

///|
priv enum MiniExprNode {
  /// A quoted pattern literal such as `note("c4 e4")`. Its notation is a
  /// language of its own, read when the expression is resolved, so a mistake
  /// in it does not hide the rest of the expression from source recognition.
  Literal(MiniLiteral, QuotedNotation)
  /// `silence()`
  Silence
  Stack(Array[MiniExpr])
  Reference(String)
  Apply(MiniExpr, MiniTransform[ControlArgument])
  /// `.s("bass pad")`: the instrument each note plays.
  Instruments(MiniExpr, QuotedNotation)
}

///|
fn Parser::parse_syntax_expr(
  self : Parser,
  depth~ : Int32 = 0,
) -> MiniExpr raise SourceProblem {
  guard self.admission is None || depth < 32 else {
    raise OverLimit(Nesting(32))
  }
  if self.syntax_depth_limit is Some(limit) {
    guard depth < limit else { raise OverLimit(Nesting(limit)) }
  }
  let start = self.pos
  let first = self.parse_syntax_chain(depth)
  let operands = [first]
  while true {
    let before_ws = self.pos
    self.skip_whitespace()
    if self.at_end() || self.input[self.pos] != '+' {
      self.pos = before_ws
      break
    }
    self.pos += 1
    self.skip_whitespace()
    guard !self.at_end() else {
      raise Mistake(self.pos, "expected an expression after '+'")
    }
    match self.input[self.pos] {
      '+' | ')' | ',' | ';' =>
        raise Mistake(self.pos, "expected an expression after '+'")
      _ => ()
    }
    operands.push(self.parse_syntax_chain(depth))
  }
  if operands.length() == 1 {
    first
  } else {
    let end = operands[operands.length() - 1].span.end
    { span: { start, end, }, node: Stack(operands), }
  }
}

///|
/// Parse one primary and its left-to-right transform chain.
fn Parser::parse_syntax_chain(
  self : Parser,
  depth : Int32,
) -> MiniExpr raise SourceProblem {
  self.skip_whitespace()
  let start = self.pos
  let mut expr = self.parse_syntax_primary(depth)
  let mut chain_depth = depth
  while true {
    let before_ws = self.pos
    self.skip_whitespace()
    if self.at_end() || self.input[self.pos] != '.' {
      self.pos = before_ws
      break
    }
    self.pos += 1
    self.skip_whitespace()
    chain_depth += 1
    if self.syntax_depth_limit is Some(limit) {
      guard chain_depth < limit else { raise OverLimit(Nesting(limit)) }
    }
    let node = self.parse_method(expr)
    expr = { span: { start, end: self.pos, }, node, }
  }
  expr
}

///|
/// Parentheses group an expression without introducing a runtime or document
/// node. Returning the inner expression also keeps reference spans anchored
/// at the name inside the parentheses.
fn Parser::parse_syntax_primary(
  self : Parser,
  depth : Int32,
) -> MiniExpr raise SourceProblem {
  guard !self.at_end() else {
    raise Mistake(self.pos, "unexpected end of input")
  }
  let start = self.pos
  if self.input[self.pos] == '(' {
    if self.recognition {
      self.recognized_pattern = true
    }
    self.pos += 1
    self.skip_whitespace()
    let inner = self.parse_syntax_expr(depth=depth + 1)
    self.skip_whitespace()
    self.expect_char(')')
    return inner
  }
  match self.read_call(PatternCall::parse) {
    None => {
      let name = self.read_ident()
      guard !name.is_empty() else {
        let expected = PatternCall::all().map(call => "'\{call.opening()}'")
        expected.push("'('")
        raise Mistake(self.pos, "expected \{or_list(expected)}")
      }
      if self.recognition {
        self.recognized_pattern = true
        self.record_reference_fact(name, start, self.pos)
      }
      { span: { start, end: self.pos, }, node: Reference(name), }
    }
    Some(Stack) => {
      if self.recognition {
        self.recognized_pattern = true
      }
      self.skip_whitespace()
      guard !self.at_end() && self.input[self.pos] != ')' else {
        raise Mistake(start, "stack() requires at least one argument")
      }
      let args = [self.parse_syntax_expr(depth=depth + 1)]
      self.skip_whitespace()
      while !self.at_end() && self.input[self.pos] == ',' {
        self.pos += 1
        args.push(self.parse_syntax_expr(depth=depth + 1))
        self.skip_whitespace()
      }
      self.expect_char(')')
      { span: { start, end: self.pos, }, node: Stack(args), }
    }
    Some(Silence) => {
      self.expect_char(')')
      if self.recognition {
        self.recognized_pattern = true
      }
      { span: { start, end: self.pos, }, node: Silence, }
    }
    Some(Literal(literal)) => {
      if self.recognition {
        self.recognized_pattern = true
      }
      let (text, at) = self.read_quoted_string_with_start()
      let notation = { text, at, }
      if self.recognition {
        self.record_literal_facts(literal, notation)
      }
      self.expect_char(')')
      { span: { start, end: self.pos, }, node: Literal(literal, notation), }
    }
  }
}

///|
/// The method after `receiver` and its `.`, applied to `receiver`.
fn Parser::parse_method(
  self : Parser,
  receiver : MiniExpr,
) -> MiniExprNode raise SourceProblem {
  let method_start = self.pos
  let name = self.read_ident()
  guard Method::parse(name) is Some(called) else {
    raise Mistake(method_start, "unknown method '\{name}'")
  }
  let transform : MiniTransform[ControlArgument] = match called {
    Instruments => {
      self.expect_char('(')
      let (text, at) = self.read_quoted_string_with_start()
      self.expect_char(')')
      return Instruments(receiver, { text, at, })
    }
    Fast => Fast(self.read_method_factor(method_start, name))
    Slow => Slow(self.read_method_factor(method_start, name))
    Gate => {
      self.expect_char('(')
      self.skip_whitespace()
      let value_start = self.pos
      let value = self.read_number()
      let value_end = self.pos
      self.skip_whitespace()
      self.expect_char(')')
      guard !value.is_nan() && !value.is_inf() && value >= 0.0 && value <= 1.0 else {
        raise Mistake(method_start, "gate() expects a fraction between 0 and 1")
      }
      let factor = parse_decimal_rational(
        self.input,
        value_start,
        value_end,
        method_start,
      )
      guard factor >= @pattern.Rational::from_int(0) &&
        factor <= @pattern.Rational::from_int(1) else {
        raise Mistake(method_start, "gate() expects a fraction between 0 and 1")
      }
      Gate(factor)
    }
    Rev => {
      self.expect_char('(')
      self.expect_char(')')
      Rev
    }
    DegradeBy => {
      self.expect_char('(')
      self.skip_whitespace()
      let p = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      Degrade(p)
    }
    Lpf => self.read_filter(LowPass, method_start)
    Hpf => self.read_filter(HighPass, method_start)
    Attack => Control(Attack, self.read_method_control_argument(method_start))
    Hold => Control(Hold, self.read_method_control_argument(method_start))
    Release => Control(Release, self.read_method_control_argument(method_start))
    Gain => Control(Gain, self.read_method_control_argument(method_start))
    Pan => Control(Pan, self.read_method_control_argument(method_start))
    Room => Control(Room, self.read_method_control_argument(method_start))
    Every => {
      self.expect_char('(')
      self.skip_whitespace()
      let n_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let f = self.parse_transform_callback(
        method_start,
        calling_method="every",
      )
      self.skip_whitespace()
      self.expect_char(')')
      let n = require_integer(n_dbl, method_start, "every() first argument")
      guard n > 0 else {
        raise Mistake(
          method_start,
          "every() requires a positive integer, got \{n}",
        )
      }
      Every(n, f)
    }
    Jux => {
      self.expect_char('(')
      self.skip_whitespace()
      let f = self.parse_transform_callback(method_start, calling_method="jux")
      self.skip_whitespace()
      self.expect_char(')')
      Jux(f)
    }
  }
  Apply(receiver, transform)
}

///|
fn Parser::parse_transform_callback(
  self : Parser,
  method_start : Int32,
  calling_method~ : String,
) -> MiniCallback raise SourceProblem {
  let name = self.read_ident()
  guard Callback::parse(name) is Some(callback) else {
    let expected = or_list(Callback::all().map(Callback::written))
    raise Mistake(
      method_start,
      "\{calling_method}() callback must be \{expected}; got '\{name}'",
    )
  }
  match callback {
    Fast => {
      self.expect_char('(')
      self.skip_whitespace()
      let k_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      let k = require_integer(k_dbl, method_start, "\{calling_method}(fast(k))")
      guard k > 0 else {
        raise Mistake(
          method_start,
          "\{calling_method}(fast(k)) requires a positive integer, got \{k}",
        )
      }
      Fast(k)
    }
    Slow => {
      self.expect_char('(')
      self.skip_whitespace()
      let k_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      let k = require_integer(k_dbl, method_start, "\{calling_method}(slow(k))")
      guard k > 0 else {
        raise Mistake(
          method_start,
          "\{calling_method}(slow(k)) requires a positive integer, got \{k}",
        )
      }
      Slow(k)
    }
    Rev => {
      // Accept both `rev` and `rev()` as the callback form.
      if !self.at_end() && self.input[self.pos] == '(' {
        self.expect_char('(')
        self.expect_char(')')
      }
      Rev
    }
  }
}

///|
/// The positive factor of a `fast(n)` or `slow(n)` method named `name`.
fn Parser::read_method_factor(
  self : Parser,
  method_start : Int32,
  name : String,
) -> @pattern.Rational raise SourceProblem {
  let factor = self.read_positive_factor(method_start, name)
  guard factor > @pattern.Rational::from_int(0) else {
    raise Mistake(
      method_start,
      "\{name}() requires a representable positive factor",
    )
  }
  factor
}

///|
/// The arguments of `.lpf(hz[, q])` or `.hpf(hz[, q])`, after the name.
fn Parser::read_filter(
  self : Parser,
  kind : MiniFilterKind,
  method_start : Int32,
) -> MiniTransform[ControlArgument] raise SourceProblem {
  self.expect_char('(')
  let frequency_hz = self.read_control_argument(method_start)
  self.skip_whitespace()
  let resonance = if !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    Some(self.read_control_argument(method_start))
  } else {
    None
  }
  self.skip_whitespace()
  self.expect_char(')')
  Filter(kind, frequency_hz, resonance)
}
