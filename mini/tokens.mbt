///|
priv enum MiniTokenKind {
  Identifier
  Number
  StringDelimiter
  Punctuation
  Operator
  Unknown
}

///|
priv struct MiniToken {
  kind : MiniTokenKind
  text : String
  start : Int
  end : Int
  identity_key : String
}

///|
priv struct MiniTokenEditSpan {
  old_start : Int
  old_end : Int
  new_start : Int
  new_end : Int
}

///|
priv struct MiniSourceEditSpan {
  old_start : Int
  old_end : Int
  new_end : Int
}

///|
impl Eq for MiniSourceEditSpan with fn equal(self, other) {
  self.old_start == other.old_start &&
  self.old_end == other.old_end &&
  self.new_end == other.new_end
}

///|
fn mini_token_kind_label(kind : MiniTokenKind) -> String {
  match kind {
    Identifier => "ident"
    Number => "number"
    StringDelimiter => "quote"
    Punctuation => "punct"
    Operator => "op"
    Unknown => "unknown"
  }
}

///|
fn mini_token_base_key(kind : MiniTokenKind, text : String) -> String {
  "\{mini_token_kind_label(kind)}:\{text}"
}

///|
fn mini_token_identity_key(
  kind : MiniTokenKind,
  text : String,
  occurrence : Int,
) -> String {
  "\{mini_token_base_key(kind, text)}:\{occurrence}"
}

///|
fn mini_token_identity_occurrence_suffix(token : MiniToken) -> String {
  let prefix = "\{mini_token_base_key(token.kind, token.text)}:"
  token.identity_key[prefix.length():].to_owned()
}

///|
fn mini_token_occurrence(
  counters : Map[String, Int],
  kind : MiniTokenKind,
  text : String,
) -> Int {
  let base = mini_token_base_key(kind, text)
  let occurrence = match counters.get(base) {
    Some(value) => value
    None => 0
  }
  counters[base] = occurrence + 1
  occurrence
}

///|
fn mini_token(
  counters : Map[String, Int],
  kind : MiniTokenKind,
  text : String,
  start : Int,
  end : Int,
) -> MiniToken {
  let occurrence = mini_token_occurrence(counters, kind, text)
  {
    kind,
    text,
    start,
    end,
    identity_key: mini_token_identity_key(kind, text, occurrence),
  }
}

///|
fn mini_token_with_identity(
  token : MiniToken,
  identity_key : String,
) -> MiniToken {
  {
    kind: token.kind,
    text: token.text,
    start: token.start,
    end: token.end,
    identity_key,
  }
}

///|
fn mini_token_kind_equal(left : MiniTokenKind, right : MiniTokenKind) -> Bool {
  mini_token_kind_label(left) == mini_token_kind_label(right)
}

///|
fn mini_token_signature_equal(left : MiniToken, right : MiniToken) -> Bool {
  mini_token_kind_equal(left.kind, right.kind) && left.text == right.text
}

///|
fn mini_token_edit_span(
  old_tokens : Array[MiniToken],
  new_tokens : Array[MiniToken],
) -> MiniTokenEditSpan {
  let mut prefix = 0
  while prefix < old_tokens.length() &&
        prefix < new_tokens.length() &&
        mini_token_signature_equal(old_tokens[prefix], new_tokens[prefix]) {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < old_tokens.length() - prefix &&
        suffix < new_tokens.length() - prefix &&
        mini_token_signature_equal(
          old_tokens[old_tokens.length() - 1 - suffix],
          new_tokens[new_tokens.length() - 1 - suffix],
        ) {
    suffix += 1
  }
  {
    old_start: prefix,
    old_end: old_tokens.length() - suffix,
    new_start: prefix,
    new_end: new_tokens.length() - suffix,
  }
}

///|
fn mini_first_token_ending_after(
  tokens : Array[MiniToken],
  offset : Int,
) -> Int {
  let mut index = 0
  while index < tokens.length() && tokens[index].end <= offset {
    index += 1
  }
  index
}

///|
fn mini_first_token_starting_at_or_after(
  tokens : Array[MiniToken],
  offset : Int,
) -> Int {
  let mut index = 0
  while index < tokens.length() && tokens[index].start < offset {
    index += 1
  }
  index
}

///|
fn mini_token_edit_span_from_source(
  old_tokens : Array[MiniToken],
  new_tokens : Array[MiniToken],
  source_edit : MiniSourceEditSpan,
) -> MiniTokenEditSpan {
  {
    old_start: mini_first_token_ending_after(old_tokens, source_edit.old_start),
    old_end: mini_first_token_starting_at_or_after(
      old_tokens,
      source_edit.old_end,
    ),
    new_start: mini_first_token_ending_after(new_tokens, source_edit.old_start),
    new_end: mini_first_token_starting_at_or_after(
      new_tokens,
      source_edit.new_end,
    ),
  }
}

///|
fn mini_mark_old_identity(
  used : Map[String, Bool],
  old_tokens : Array[MiniToken],
  index : Int,
) -> Unit {
  used[old_tokens[index].identity_key] = true
}

///|
fn mini_allocate_changed_identity(
  counters : Map[String, Int],
  used : Map[String, Bool],
  token : MiniToken,
) -> String {
  let base = mini_token_base_key(token.kind, token.text)
  let mut occurrence = match counters.get(base) {
    Some(value) => value
    None => 0
  }
  let mut key = mini_token_identity_key(token.kind, token.text, occurrence)
  while used.contains(key) {
    occurrence += 1
    key = mini_token_identity_key(token.kind, token.text, occurrence)
  }
  counters[base] = occurrence + 1
  used[key] = true
  key
}

///|
fn mini_realign_token_identities(
  old_tokens : Array[MiniToken],
  new_tokens : Array[MiniToken],
) -> Array[MiniToken] {
  mini_realign_token_identities_with_span(
    old_tokens,
    new_tokens,
    mini_token_edit_span(old_tokens, new_tokens),
  )
}

///|
fn mini_realign_token_identities_with_span(
  old_tokens : Array[MiniToken],
  new_tokens : Array[MiniToken],
  span : MiniTokenEditSpan,
) -> Array[MiniToken] {
  let used : Map[String, Bool] = {}
  for index in 0..<old_tokens.length() {
    mini_mark_old_identity(used, old_tokens, index)
  }
  let counters : Map[String, Int] = {}
  let aligned : Array[MiniToken] = []
  for index in 0..<new_tokens.length() {
    let identity_key = if index < span.old_start && index < span.new_start {
      old_tokens[index].identity_key
    } else if index >= span.new_end {
      old_tokens[span.old_end + index - span.new_end].identity_key
    } else {
      mini_allocate_changed_identity(counters, used, new_tokens[index])
    }
    aligned.push(mini_token_with_identity(new_tokens[index], identity_key))
  }
  aligned
}

///|
fn realign_mini_authoring_tokens(
  old_input : String,
  new_input : String,
) -> Array[MiniToken] {
  mini_realign_token_identities(
    tokenize_mini_authoring_source(old_input),
    tokenize_mini_authoring_source(new_input),
  )
}

///|
fn realign_mini_authoring_tokens_with_source_edit(
  old_input : String,
  new_input : String,
  source_edit : MiniSourceEditSpan,
) -> Array[MiniToken] {
  let old_tokens = tokenize_mini_authoring_source(old_input)
  let new_tokens = tokenize_mini_authoring_source(new_input)
  mini_realign_token_identities_with_span(
    old_tokens,
    new_tokens,
    mini_token_edit_span_from_source(old_tokens, new_tokens, source_edit),
  )
}

///|
fn mini_is_space(c : UInt16) -> Bool {
  c == ' ' || c == '\n' || c == '\t' || c == '\r'
}

///|
fn mini_is_ident_start(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn mini_is_ident_continue(c : UInt16) -> Bool {
  mini_is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn mini_is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn mini_tokenize_identifier(input : String, start : Int) -> Int {
  let mut pos = start + 1
  while pos < input.length() && mini_is_ident_continue(input[pos]) {
    pos += 1
  }
  pos
}

///|
fn mini_tokenize_number(input : String, start : Int) -> Int {
  let mut pos = start
  if input[pos] == '-' {
    pos += 1
  }
  while pos < input.length() && mini_is_digit(input[pos]) {
    pos += 1
  }
  if pos < input.length() && input[pos] == '.' {
    pos += 1
    while pos < input.length() && mini_is_digit(input[pos]) {
      pos += 1
    }
  }
  pos
}

///|
fn mini_can_start_negative_number(input : String, pos : Int) -> Bool {
  input[pos] == '-' && pos + 1 < input.length() && mini_is_digit(input[pos + 1])
}

///|
fn mini_token_kind_for_single(c : UInt16) -> MiniTokenKind {
  match c {
    '"' => StringDelimiter
    '(' | ')' | '[' | ']' | ',' | '.' => Punctuation
    '*' | '/' | '?' => Operator
    _ => Unknown
  }
}

///|
fn tokenize_mini_authoring_source(input : String) -> Array[MiniToken] {
  let counters : Map[String, Int] = {}
  let tokens : Array[MiniToken] = []
  let mut pos = 0
  while pos < input.length() {
    let c = input[pos]
    if mini_is_space(c) {
      pos += 1
    } else if mini_is_ident_start(c) {
      let end = mini_tokenize_identifier(input, pos)
      tokens.push(
        mini_token(counters, Identifier, input[pos:end].to_owned(), pos, end),
      )
      pos = end
    } else if mini_is_digit(c) || mini_can_start_negative_number(input, pos) {
      let end = mini_tokenize_number(input, pos)
      tokens.push(
        mini_token(counters, Number, input[pos:end].to_owned(), pos, end),
      )
      pos = end
    } else {
      tokens.push(
        mini_token(
          counters,
          mini_token_kind_for_single(c),
          input[pos:pos + 1].to_owned(),
          pos,
          pos + 1,
        ),
      )
      pos += 1
    }
  }
  tokens
}

///|
fn mini_authoring_token_fingerprint(tokens : Array[MiniToken]) -> Int {
  let fingerprint = for token in tokens; total = 0 {
    continue total +
      mini_token_kind_label(token.kind).length() +
      token.text.length() +
      token.start +
      token.end +
      token.identity_key.length()
  } nobreak {
    total
  }
  fingerprint
}
