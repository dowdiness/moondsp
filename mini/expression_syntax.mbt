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
  Silence
}

///|
priv enum MiniCallback {
  Fast(Int)
  Slow(Int)
  Rev
}

///|
priv enum MiniFilterKind {
  LowPass
  HighPass
}

///|
fn MiniFilterKind::control_key(self : MiniFilterKind) -> String {
  match self {
    LowPass => "lpf"
    HighPass => "hpf"
  }
}

///|
fn MiniFilterKind::resonance_control_key(self : MiniFilterKind) -> String {
  match self {
    LowPass => "lpf_resonance"
    HighPass => "hpf_resonance"
  }
}

///|
priv enum MiniTransform {
  Fast(@pattern.Rational)
  Slow(@pattern.Rational)
  Gate(@pattern.Rational)
  Rev
  Degrade(Double, Int?)
  Transpose(Int)
  Steps(Array[Int], Int)
  Lowest
  Voicing(Int, Int, Int?)
  Mask(Array[Bool])
  Tail(@pattern.Rational, MiniLiteral, String, Int)
  PhaseTranspose(@pattern.Rational, @pattern.Rational, Int)
  Control(String, Double)
  Filter(MiniFilterKind, Double, Double?)
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
fn Parser::parse_syntax_expr(
  self : Parser,
  depth? : Int = 0,
) -> MiniExpr raise ParseError {
  guard self.admission is None || depth < 32 else {
    raise ParseError("playback source exceeds nesting depth 32")
  }
  if self.syntax_depth_limit is Some(limit) {
    guard depth < limit else {
      raise ParseError("source exceeds nesting depth \{limit}")
    }
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
      raise ParseError("position \{self.pos}: expected an expression after '+'")
    }
    match self.input[self.pos] {
      '+' | ')' | ',' | ';' =>
        raise ParseError(
          "position \{self.pos}: expected an expression after '+'",
        )
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
  depth : Int,
) -> MiniExpr raise ParseError {
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
      guard chain_depth < limit else {
        raise ParseError("source exceeds nesting depth \{limit}")
      }
    }
    let transform = self.parse_transform()
    expr = { span: { start, end: self.pos, }, node: Apply(expr, transform), }
  }
  expr
}

///|
/// Parentheses group an expression without introducing a runtime or document
/// node. Returning the inner expression also keeps reference spans anchored
/// at the name inside the parentheses.
fn Parser::parse_syntax_primary(
  self : Parser,
  depth : Int,
) -> MiniExpr raise ParseError {
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of input")
  }
  let start = self.pos
  if self.match_keyword("stack(") {
    if self.recognition {
      self.recognized_pattern = true
    }
    self.skip_whitespace()
    guard !self.at_end() && self.input[self.pos] != ')' else {
      raise ParseError(
        "position \{start}: stack() requires at least one argument",
      )
    }
    let args = [self.parse_syntax_expr(depth=depth + 1)]
    self.skip_whitespace()
    while !self.at_end() && self.input[self.pos] == ',' {
      self.pos += 1
      args.push(self.parse_syntax_expr(depth=depth + 1))
      self.skip_whitespace()
    }
    self.expect_char(')')
    return { span: { start, end: self.pos, }, node: Stack(args), }
  }
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
  let kind = if self.match_keyword("s(") {
    Some(Sound)
  } else if self.match_keyword("note(") {
    Some(Note)
  } else if self.match_keyword("chord(") {
    Some(Chord)
  } else if self.match_keyword("silence()") {
    Some(Silence)
  } else {
    None
  }
  if kind is Some(kind) {
    if self.recognition {
      self.recognized_pattern = true
    }
    if kind is Silence {
      return {
        span: { start, end: self.pos, },
        node: Literal(kind, "", start),
      }
    }
    let (content, content_start) = self.read_quoted_string_with_start()
    if self.recognition {
      self.record_literal_fact(kind, content, content_start)
    }
    self.expect_char(')')
    return {
      span: { start, end: self.pos, },
      node: Literal(kind, content, content_start),
    }
  }
  let name = self.read_ident()
  if !name.is_empty() {
    if self.recognition {
      self.recognized_pattern = true
      self.record_reference_fact(name, start, self.pos)
    }
    return { span: { start, end: self.pos, }, node: Reference(name), }
  }
  raise ParseError(
    "position \{self.pos}: expected 's(', 'note(', 'chord(', 'silence()', 'stack(', or '('",
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
    "gate" => {
      self.expect_char('(')
      self.skip_whitespace()
      let value_start = self.pos
      let value = self.read_number()
      let value_end = self.pos
      self.skip_whitespace()
      self.expect_char(')')
      guard !value.is_nan() && !value.is_inf() && value >= 0.0 && value <= 1.0 else {
        raise ParseError(
          "position \{method_start}: gate() expects a fraction between 0 and 1",
        )
      }
      let factor = parse_decimal_rational(
        self.input,
        value_start,
        value_end,
        method_start,
      )
      guard factor >= @pattern.Rational::from_int(0) &&
        factor <= @pattern.Rational::from_int(1) else {
        raise ParseError(
          "position \{method_start}: gate() expects a fraction between 0 and 1",
        )
      }
      Gate(factor)
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
      let seed = if !self.at_end() && self.input[self.pos] == ',' {
        self.pos += 1
        self.skip_whitespace()
        Some(
          require_integer(self.read_number(), method_start, "degradeBy() seed"),
        )
      } else {
        None
      }
      self.skip_whitespace()
      self.expect_char(')')
      Degrade(p, seed)
    }
    "transpose" => {
      self.expect_char('(')
      self.skip_whitespace()
      let semitones = require_integer(
        self.read_number(),
        method_start,
        "transpose() semitones",
      )
      self.skip_whitespace()
      self.expect_char(')')
      Transpose(semitones)
    }
    "steps" => {
      self.expect_char('(')
      self.skip_whitespace()
      let scale_text = self.read_quoted_string()
      let scale = parse_mini_explicit_scale(scale_text, method_start)
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let steps = require_integer(
        self.read_number(),
        method_start,
        "steps() steps",
      )
      self.skip_whitespace()
      self.expect_char(')')
      Steps(scale, steps)
    }
    "lowest" => {
      self.expect_char('(')
      self.expect_char(')')
      Lowest
    }
    "voicing" => {
      self.expect_char('(')
      self.skip_whitespace()
      let low = require_integer(
        self.read_number(),
        method_start,
        "voicing() low",
      )
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let high = require_integer(
        self.read_number(),
        method_start,
        "voicing() high",
      )
      self.skip_whitespace()
      let count = if !self.at_end() && self.input[self.pos] == ',' {
        self.pos += 1
        self.skip_whitespace()
        Some(
          require_integer(self.read_number(), method_start, "voicing() count"),
        )
      } else {
        None
      }
      self.skip_whitespace()
      self.expect_char(')')
      guard low <= high && (count is None || count.unwrap() >= 0) else {
        raise ParseError(
          "position \{method_start}: voicing() expects low <= high and count >= 0",
        )
      }
      Voicing(low, high, count)
    }
    "mask" => {
      self.expect_char('(')
      self.skip_whitespace()
      let rhythm_text = self.read_quoted_string()
      self.skip_whitespace()
      self.expect_char(')')
      Mask(parse_mini_rhythm_mask(rhythm_text, method_start))
    }
    "tail" => {
      self.expect_char('(')
      self.skip_whitespace()
      let replacement_kind = self.read_ident()
      let kind = match replacement_kind {
        "s" => Sound
        "note" => Note
        "chord" => Chord
        _ =>
          raise ParseError(
            "position \{method_start}: tail() expects s(...), note(...), or chord(...)",
          )
      }
      self.expect_char('(')
      self.skip_whitespace()
      let (replacement, replacement_offset) = self.read_quoted_string_with_start()
      if self.recognition {
        self.record_literal_fact(kind, replacement, replacement_offset)
      }
      self.skip_whitespace()
      self.expect_char(')')
      self.skip_whitespace()
      let tail = if !self.at_end() && self.input[self.pos] == ',' {
        self.pos += 1
        self.skip_whitespace()
        let duration_start = self.pos
        let duration = self.read_number()
        let duration_end = self.pos
        guard duration > 0.0 && !duration.is_nan() && !duration.is_inf() else {
          raise ParseError(
            "position \{method_start}: tail() duration must be positive",
          )
        }
        parse_decimal_rational(
          self.input,
          duration_start,
          duration_end,
          method_start,
        )
      } else {
        @pattern.Rational::from_int(1)
      }
      self.skip_whitespace()
      self.expect_char(')')
      Tail(tail, kind, replacement, replacement_offset)
    }
    "phase" => {
      self.expect_char('(')
      self.skip_whitespace()
      let nested_name = self.read_ident()
      guard nested_name == "transpose" else {
        raise ParseError(
          "position \{method_start}: phase() currently accepts transpose(n)",
        )
      }
      self.expect_char('(')
      self.skip_whitespace()
      let semitones = require_integer(
        self.read_number(),
        method_start,
        "phase() transpose semitones",
      )
      self.skip_whitespace()
      self.expect_char(')')
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let begin_start = self.pos
      let begin_value = self.read_number()
      let begin_end = self.pos
      self.skip_whitespace()
      let (end_, end_value) = if !self.at_end() && self.input[self.pos] == ',' {
        self.pos += 1
        self.skip_whitespace()
        let end_start = self.pos
        let value = self.read_number()
        let end_end = self.pos
        (
          parse_decimal_rational(self.input, end_start, end_end, method_start),
          value,
        )
      } else {
        (@pattern.Rational::from_int(1), 1.0)
      }
      self.skip_whitespace()
      self.expect_char(')')
      let begin = parse_decimal_rational(
        self.input,
        begin_start,
        begin_end,
        method_start,
      )
      guard begin_value >= 0.0 && begin_value < end_value && end_value <= 1.0 else {
        raise ParseError(
          "position \{method_start}: phase() expects 0 <= from < to <= 1",
        )
      }
      PhaseTranspose(begin, end_, semitones)
    }
    "lpf" | "hpf" => {
      self.expect_char('(')
      self.skip_whitespace()
      let frequency_hz = self.read_number()
      self.skip_whitespace()
      let resonance = if !self.at_end() && self.input[self.pos] == ',' {
        self.pos += 1
        self.skip_whitespace()
        let q = self.read_number()
        self.skip_whitespace()
        Some(q)
      } else {
        None
      }
      self.expect_char(')')
      match resonance {
        Some(q) if q.is_nan() || q.is_inf() || q <= 0.0 =>
          raise ParseError(
            "position \{method_start}: \{name}() expects finite resonance above 0",
          )
        _ => ()
      }
      let kind : MiniFilterKind = if name == "lpf" { LowPass } else { HighPass }
      Filter(kind, frequency_hz, resonance)
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
    "room" => {
      let send = self.read_method_number_argument()
      if send.is_nan() || send.is_inf() || send < 0.0 || send > 1.0 {
        raise ParseError(
          "position \{method_start}: room() expects a send between 0 and 1",
        )
      }
      Control("room", send)
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

///|
/// Convert an explicit list of note names to ordered pitch classes. This does
/// not infer a scale from chord names; every degree must be authored.
fn parse_mini_explicit_scale(
  text : String,
  source_pos : Int,
) -> Array[Int] raise ParseError {
  let pitches = []
  let mut start = 0
  for i in 0..<=text.length() {
    if i == text.length() || mini_is_space(text[i]) {
      if start < i {
        let token = text[start:i].to_owned()
        let midi = match @pattern.note_name_to_midi(token) {
          Some(value) => value.to_int()
          None =>
            raise ParseError(
              "position \{source_pos}: invalid scale note '\{token}'",
            )
        }
        pitches.push(midi % 12)
      }
      start = i + 1
    }
  }
  guard !pitches.is_empty() else {
    raise ParseError("position \{source_pos}: steps() scale is empty")
  }
  let mut previous = -1
  for pitch in pitches {
    guard pitch > previous else {
      raise ParseError(
        "position \{source_pos}: steps() scale must have ascending, unique pitch classes",
      )
    }
    previous = pitch
  }
  pitches
}

///|
fn parse_mini_rhythm_mask(
  text : String,
  source_pos : Int,
) -> Array[Bool] raise ParseError {
  let mask = []
  let mut start = 0
  for i in 0..<=text.length() {
    if i == text.length() || mini_is_space(text[i]) {
      if start < i {
        let token = text[start:i].to_owned()
        match token {
          "x" => mask.push(true)
          "~" => mask.push(false)
          _ =>
            raise ParseError(
              "position \{source_pos}: rhythm() slots must be 'x' or '~'",
            )
        }
      }
      start = i + 1
    }
  }
  guard !mask.is_empty() else {
    raise ParseError(
      "position \{source_pos}: rhythm() requires at least one slot",
    )
  }
  mask
}

///|
fn mini_scale_signature(scale : Array[Int]) -> String {
  scale.map(value => value.to_string()).join(",")
}

///|
fn mini_rhythm_signature(mask : Array[Bool]) -> String {
  mask.map(value => if value { "1" } else { "0" }).join("")
}
