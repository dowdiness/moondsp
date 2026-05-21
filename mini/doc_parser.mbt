///|
priv struct MiniDocBuilder {
  previous : @pattern.PatternDoc[@pattern.ControlMap]?
  counters : Map[String, Int]
  token_id_by_location : Map[String, String]?
}

///|
#alias(new)
fn MiniDocBuilder::MiniDocBuilder(
  previous~ : @pattern.PatternDoc[@pattern.ControlMap]?,
  tokens? : Array[MiniToken]? = None,
) -> MiniDocBuilder {
  {
    previous,
    counters: {},
    token_id_by_location:
      match tokens {
        None => None
        Some(tokens) => {
          let index : Map[String, String] = {}
          for token in tokens {
            if mini_token_kind_equal(token.kind, Identifier) {
              let suffix = mini_token_identity_occurrence_suffix(token)
              let key =
                mini_doc_token_id_key("sound", token.text, token.start, token.end)
              let id = "mini:sound:\{token.text}:\{suffix}"
              index[key] = id
            } else if mini_token_kind_equal(token.kind, Number) {
              let suffix = mini_token_identity_occurrence_suffix(token)
              let key =
                mini_doc_token_id_key("note", token.text, token.start, token.end)
              let id = "mini:note:\{token.text}:\{suffix}"
              index[key] = id
            }
          }
          Some(index)
        }
      },
  }
}

///|
fn mini_doc_token_id_key(
  kind : String,
  value : String,
  start : Int,
  end : Int,
) -> String {
  "mini-doc-token-id|\{kind}|\{start}|\{end}|\{value}"
}

///|
fn MiniDocBuilder::id(
  self : MiniDocBuilder,
  value : String,
) -> @identity.PatternNodeId raise ParseError {
  ignore(self)
  let result = try? @identity.PatternNodeId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => raise ParseError("internal mini id was invalid: \{value}")
  }
}

///|
fn MiniDocBuilder::next_occurrence(self : MiniDocBuilder, key : String) -> Int {
  let index = match self.counters.get(key) {
    Some(value) => value
    None => 0
  }
  self.counters[key] = index + 1
  index
}

///|
fn MiniDocBuilder::atom_id(
  self : MiniDocBuilder,
  kind : String,
  value : String,
) -> @identity.PatternNodeId raise ParseError {
  let key = "\{kind}:\{value}"
  let occurrence = self.next_occurrence(key)
  self.id("mini:\{kind}:\{value}:\{occurrence}")
}

///|
fn MiniDocBuilder::token_atom_id(
  self : MiniDocBuilder,
  kind : String,
  value : String,
  start : Int,
  end : Int,
) -> @identity.PatternNodeId? raise ParseError {
  match self.token_id_by_location {
    None => None
    Some(index) => {
      let key = mini_doc_token_id_key(kind, value, start, end)
      match index.get(key) {
        None => None
        Some(id) => Some(self.id(id))
      }
    }
  }
}

///|
fn MiniDocBuilder::atom_id_at(
  self : MiniDocBuilder,
  kind : String,
  value : String,
  start : Int,
  end : Int,
) -> @identity.PatternNodeId raise ParseError {
  match self.token_atom_id(kind, value, start, end) {
    Some(id) => id
    None => self.atom_id(kind, value)
  }
}

///|
fn MiniDocBuilder::node_id(
  self : MiniDocBuilder,
  kind : String,
  signature : String,
) -> @identity.PatternNodeId raise ParseError {
  self.id("mini:\{kind}:\{signature}")
}

///|
fn MiniDocBuilder::reuse_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
) -> @pattern.PatternDoc[@pattern.ControlMap]? raise ParseError {
  match self.previous {
    None => None
    Some(previous) =>
      if previous.contains_node(id) {
        let result = try? previous.subdoc(root=id)
        match result {
          Ok(doc) => Some(doc)
          Err(_) =>
            raise ParseError(
              "internal mini id could not be reused: \{id.value()}",
            )
        }
      } else {
        None
      }
  }
}

///|
fn unwrap_doc_result(
  result : Result[
    @pattern.PatternDoc[@pattern.ControlMap],
    @pattern.PatternDocError,
  ],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  match result {
    Ok(doc) => doc
    Err(_) => raise ParseError("internal mini PatternDoc construction failed")
  }
}

///|
fn MiniDocBuilder::pure_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  value : @pattern.ControlMap,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => @pattern.PatternDoc::pure(id~, value~)
  }
}

///|
fn MiniDocBuilder::sequence_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  if docs.length() == 1 {
    return docs[0]
  }
  let id = self.node_id("seq", doc_root_signature(docs))
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? @pattern.PatternDoc::sequence(id~, docs~))
  }
}

///|
fn MiniDocBuilder::stack_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  if docs.length() == 1 {
    return docs[0]
  }
  let id = self.node_id("stack", doc_root_signature(docs))
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? @pattern.PatternDoc::stack(id~, docs~))
  }
}

///|
fn MiniDocBuilder::fast_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id(
    "fast",
    "\{doc.root().value()}:\{factor.num}:\{factor.den}",
  )
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.fast(id~, factor~))
  }
}

///|
fn MiniDocBuilder::slow_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id(
    "slow",
    "\{doc.root().value()}:\{factor.num}:\{factor.den}",
  )
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.slow(id~, factor~))
  }
}

///|
fn MiniDocBuilder::rev_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("rev", doc.root().value())
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.rev(id~))
  }
}

///|
fn MiniDocBuilder::euclid_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  k : Int,
  n : Int,
  rotation : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("euclid", "\{doc.root().value()}:\{k}:\{n}:\{rotation}")
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.euclid(id~, k~, n~, rotation~))
  }
}

///|
fn MiniDocBuilder::degrade_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  p : Double,
  seed : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("degrade", "\{doc.root().value()}:\{p}:\{seed}")
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.degrade_by(id~, p~, seed~))
  }
}

///|
fn MiniDocBuilder::every_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  n : Int,
  f : Callback,
  callback_signature : String,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id(
    "every",
    "\{doc.root().value()}:\{n}:\{callback_signature}",
  )
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.every(id~, n~, f~))
  }
}

///|
fn MiniDocBuilder::jux_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  f : Callback,
  callback_signature : String,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("jux", "\{doc.root().value()}:\{callback_signature}")
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => unwrap_doc_result(try? doc.jux(id~, f~))
  }
}

///|
fn MiniDocBuilder::scalar_control_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  key : String,
  value : Double,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let control_id = self.node_id(
    "control",
    "\{doc.root().value()}:\{key}:\{value}",
  )
  let control_doc = self.pure_doc(
    control_id,
    @pattern.ControlMap::single(key, value),
  )
  let id = self.node_id(
    "merge_control",
    "\{doc.root().value()}:\{key}:\{value}",
  )
  match self.reuse_doc(id) {
    Some(doc) => doc
    None =>
      unwrap_doc_result(
        try? @pattern.PatternDoc::merge_control(
          id~,
          left=doc,
          right=control_doc,
        ),
      )
  }
}

///|
fn doc_root_signature(
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> String {
  let mut result = ""
  for index in 0..<docs.length() {
    if index > 0 {
      result = "\{result}:"
    }
    result = "\{result}\{docs[index].root().value()}"
  }
  result
}

///|
fn stable_seed(value : String) -> Int {
  let mut hash = 17
  for index in 0..<value.length() {
    hash = (hash * 131 + value[index].to_int()) & 0x3fffffff
  }
  hash
}

///|
fn parse_doc_internal(
  input : String,
  previous : @pattern.PatternDoc[@pattern.ControlMap]?,
  tokens? : Array[MiniToken]? = None,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  guard input.length() > 0 else { return Err("empty input") }
  let p = Parser::new(input)
  let builder = MiniDocBuilder::new(previous~, tokens~)
  let result = p.parse_doc_expr(builder) catch {
    ParseError(msg) => return Err(msg)
  }
  p.skip_whitespace()
  guard p.at_end() else {
    return Err(
      "position \{p.pos}: unexpected trailing input '\{input[p.pos:].to_owned()}'",
    )
  }
  Ok(result)
}

///|
/// Parse a mini-notation string into an identity-bearing pattern document.
///
/// IDs are deterministic from the parsed structure and ignore whitespace-only
/// edits. Reparse with `parse_doc_reusing` to preserve unchanged subtree
/// generations for lowering-cache reuse.
pub fn parse_doc(
  input : String,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  parse_doc_internal(input, None)
}

///|
/// Parse a mini-notation string while reusing unchanged subtrees from a previous
/// parsed document when their deterministic `PatternNodeId`s still appear.
pub fn parse_doc_reusing(
  input : String,
  previous : @pattern.PatternDoc[@pattern.ControlMap],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  parse_doc_internal(input, Some(previous))
}

///|
fn parse_doc_with_token_identities(
  input : String,
  previous : @pattern.PatternDoc[@pattern.ControlMap]?,
  tokens : Array[MiniToken],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  parse_doc_internal(input, previous, tokens=Some(tokens))
}

///|
pub fn parse_snapshot(
  input : String,
) -> Result[@pattern.PatternSnapshot[@pattern.ControlMap], String] {
  match parse_doc(input) {
    Err(msg) => Err(msg)
    Ok(doc) => {
      let result = try? doc.lower()
      match result {
        Ok(snapshot) => Ok(snapshot)
        Err(_) => Err("internal mini PatternDoc lowering failed")
      }
    }
  }
}

///|
pub fn parse_snapshot_reusing(
  input : String,
  previous : @pattern.PatternDoc[@pattern.ControlMap],
) -> Result[@pattern.PatternSnapshot[@pattern.ControlMap], String] {
  match parse_doc_reusing(input, previous) {
    Err(msg) => Err(msg)
    Ok(doc) => {
      let result = try? doc.lower()
      match result {
        Ok(snapshot) => Ok(snapshot)
        Err(_) => Err("internal mini PatternDoc lowering failed")
      }
    }
  }
}

///|
fn Parser::parse_doc_expr(
  self : Parser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let mut doc = self.parse_doc_primary(builder)
  while !self.at_end() && self.input[self.pos] == '.' {
    self.pos += 1
    doc = self.parse_doc_method(builder, doc)
  }
  doc
}

///|
fn Parser::parse_doc_primary(
  self : Parser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.skip_whitespace()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of input")
  }
  let stack_start = self.pos
  if self.match_keyword("stack(") {
    self.skip_whitespace()
    guard !self.at_end() && self.input[self.pos] != ')' else {
      raise ParseError(
        "position \{stack_start}: stack() requires at least one argument",
      )
    }
    let args : Array[@pattern.PatternDoc[@pattern.ControlMap]] = [
      self.parse_doc_expr(builder),
    ]
    self.skip_whitespace()
    while !self.at_end() && self.input[self.pos] == ',' {
      self.pos += 1
      self.skip_whitespace()
      args.push(self.parse_doc_expr(builder))
      self.skip_whitespace()
    }
    self.expect_char(')')
    return builder.stack_doc(args)
  }
  if self.match_keyword("s(") {
    let (content, content_start) = self.read_quoted_string_with_start()
    self.expect_char(')')
    return parse_sound_doc_notation(
      content,
      builder,
      source_offset=content_start,
    )
  }
  if self.match_keyword("note(") {
    let (content, content_start) = self.read_quoted_string_with_start()
    self.expect_char(')')
    return parse_note_doc_notation(
      content,
      builder,
      source_offset=content_start,
    )
  }
  raise ParseError("position \{self.pos}: expected 's(', 'note(', or 'stack('")
}

///|
fn Parser::read_quoted_string_with_start(
  self : Parser,
) -> (String, Int) raise ParseError {
  self.expect_char('"')
  let start = self.pos
  while !self.at_end() && self.input[self.pos] != '"' {
    self.pos += 1
  }
  let content = self.input[start:self.pos].to_owned()
  self.expect_char('"')
  (content, start)
}

///|
fn Parser::parse_doc_method(
  self : Parser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
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
      builder.fast_doc(doc, @pattern.Rational::from_int(n.to_int()))
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
      builder.slow_doc(doc, @pattern.Rational::from_int(n.to_int()))
    }
    "rev" => {
      self.expect_char('(')
      self.expect_char(')')
      builder.rev_doc(doc)
    }
    "degradeBy" => {
      self.expect_char('(')
      self.skip_whitespace()
      let p = self.read_number()
      self.skip_whitespace()
      self.expect_char(')')
      builder.degrade_doc(doc, p, stable_seed(doc.root().value()))
    }
    "cutoff" => {
      let cutoff = self.read_method_number_argument()
      builder.scalar_control_doc(doc, "cutoff", cutoff)
    }
    "gain" => {
      let gain = self.read_method_number_argument()
      builder.scalar_control_doc(doc, "gain", gain)
    }
    "pan" => {
      let pan = self.read_method_number_argument()
      builder.scalar_control_doc(doc, "pan", pan)
    }
    "every" => {
      self.expect_char('(')
      self.skip_whitespace()
      let n_dbl = self.read_number()
      self.skip_whitespace()
      self.expect_char(',')
      self.skip_whitespace()
      let f_name = self.read_ident()
      let (f, callback_signature) = self.parse_doc_callback(
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
      builder.every_doc(doc, n, f, callback_signature)
    }
    "jux" => {
      self.expect_char('(')
      self.skip_whitespace()
      let f_name = self.read_ident()
      let (f, callback_signature) = self.parse_doc_callback(
        method_start,
        f_name,
        calling_method="jux",
      )
      self.skip_whitespace()
      self.expect_char(')')
      builder.jux_doc(doc, f, callback_signature)
    }
    _ => raise ParseError("position \{method_start}: unknown method '\{name}'")
  }
}

///|
fn Parser::parse_doc_callback(
  self : Parser,
  method_start : Int,
  name : String,
  calling_method~ : String,
) -> (Callback, String) raise ParseError {
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
      (make_fast(@pattern.Rational::from_int(k)), "fast:\{k}")
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
      (make_slow(@pattern.Rational::from_int(k)), "slow:\{k}")
    }
    "rev" => {
      if !self.at_end() && self.input[self.pos] == '(' {
        self.expect_char('(')
        self.expect_char(')')
      }
      (make_rev(), "rev")
    }
    _ =>
      raise ParseError(
        "position \{method_start}: \{calling_method}() callback must be fast(N), slow(N), or rev; got '\{name}'",
      )
  }
}

///|
fn parse_sound_doc_notation(
  content : String,
  builder : MiniDocBuilder,
  source_offset~ : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  guard content.length() > 0 else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser::new(content, sound=true, source_offset~)
  sub.parse_doc_notation(builder)
}

///|
fn parse_note_doc_notation(
  content : String,
  builder : MiniDocBuilder,
  source_offset~ : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  guard content.length() > 0 else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser::new(content, sound=false, source_offset~)
  sub.parse_doc_notation(builder)
}

///|
fn NotationParser::parse_doc_notation(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let first = self.parse_doc_layer(builder)
  let layers : Array[@pattern.PatternDoc[@pattern.ControlMap]] = [first]
  while !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_spaces()
    layers.push(self.parse_doc_layer(builder))
  }
  builder.stack_doc(layers)
}

///|
fn NotationParser::parse_doc_layer(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.skip_spaces()
  let elements : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  while !self.at_end() &&
        self.input[self.pos] != ',' &&
        self.input[self.pos] != ']' {
    elements.push(self.parse_doc_element(builder))
    self.skip_spaces()
  }
  guard elements.length() > 0 else {
    raise ParseError(
      "position \{self.pos}: expected at least one element in layer",
    )
  }
  builder.sequence_doc(elements)
}

///|
fn NotationParser::parse_doc_element(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.skip_spaces()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of notation")
  }
  let base = if self.input[self.pos] == '[' {
    self.pos += 1
    let inner = self.parse_doc_notation(builder)
    guard !self.at_end() && self.input[self.pos] == ']' else {
      raise ParseError("position \{self.pos}: expected ']'")
    }
    self.pos += 1
    inner
  } else {
    self.parse_doc_atom(builder)
  }
  let mut doc = base
  let mut applied = true
  while applied {
    applied = false
    if !self.at_end() {
      let c = self.input[self.pos]
      if c == '(' {
        doc = self.maybe_apply_doc_euclid(builder, doc)
        applied = true
      } else if c == '*' {
        doc = self.apply_doc_replicate(builder, doc)
        applied = true
      } else if c == '/' {
        doc = self.apply_doc_step_slow(builder, doc)
        applied = true
      } else if c == '?' {
        self.pos += 1
        let seed = stable_seed(doc.root().value())
        doc = builder.degrade_doc(doc, 0.5, seed)
        applied = true
      }
    }
  }
  doc
}

///|
fn NotationParser::apply_doc_replicate(
  self : NotationParser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let op_pos = self.pos
  self.pos += 1
  let n = self.read_int_signed(op_pos)
  guard n > 0 else {
    raise ParseError(
      "position \{op_pos}: '*' requires a positive integer, got \{n}",
    )
  }
  builder.fast_doc(doc, @pattern.Rational::from_int(n))
}

///|
fn NotationParser::apply_doc_step_slow(
  self : NotationParser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let op_pos = self.pos
  self.pos += 1
  let n = self.read_int_signed(op_pos)
  guard n > 0 else {
    raise ParseError(
      "position \{op_pos}: '/' requires a positive integer, got \{n}",
    )
  }
  builder.slow_doc(doc, @pattern.Rational::from_int(n))
}

///|
fn NotationParser::maybe_apply_doc_euclid(
  self : NotationParser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  if self.at_end() || self.input[self.pos] != '(' {
    return doc
  }
  let euclid_start = self.pos
  self.pos += 1
  self.skip_spaces()
  let k = self.read_int_signed(euclid_start)
  self.skip_spaces()
  guard !self.at_end() && self.input[self.pos] == ',' else {
    raise ParseError("position \{self.pos}: expected ',' in euclid (k,n)")
  }
  self.pos += 1
  self.skip_spaces()
  let n = self.read_int_signed(euclid_start)
  self.skip_spaces()
  let mut rotation = 0
  if !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_spaces()
    rotation = self.read_int_signed(euclid_start)
    self.skip_spaces()
  }
  guard !self.at_end() && self.input[self.pos] == ')' else {
    raise ParseError("position \{self.pos}: expected ')' to close euclid")
  }
  self.pos += 1
  builder.euclid_doc(doc, k, n, rotation)
}

///|
fn NotationParser::parse_doc_atom(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let start = self.pos
  if self.sound {
    let name = self.read_ident()
    guard name.length() > 0 else {
      raise ParseError("position \{start}: expected sound name")
    }
    match drum_midi(name) {
      Some(midi) => {
        let id = builder.atom_id_at(
          "sound",
          name,
          self.source_offset + start,
          self.source_offset + self.pos,
        )
        builder.pure_doc(
          id,
          @pattern.ControlMap::single("sound", midi.to_double()),
        )
      }
      None => raise ParseError("position \{start}: unknown drum name '\{name}'")
    }
  } else {
    let (note, token, token_start, token_end) = self.read_note_number_value(
      start,
    )
    let id = builder.atom_id_at(
      "note",
      token,
      self.source_offset + token_start,
      self.source_offset + token_end,
    )
    builder.pure_doc(id, @pattern.ControlMap::single("note", note))
  }
}

///|
fn NotationParser::read_note_number_value(
  self : NotationParser,
  start : Int,
) -> (Double, String, Int, Int) raise ParseError {
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
  let token = self.input[num_start:self.pos].to_owned()
  (
    parse_double_manual(self.input, num_start, self.pos),
    token,
    num_start,
    self.pos,
  )
}
