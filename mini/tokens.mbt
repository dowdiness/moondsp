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
fn mini_token_occurrence(
  counters : Map[String, Int],
  kind : MiniTokenKind,
  text : String,
) -> Int {
  let base = "\{mini_token_kind_label(kind)}:\{text}"
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
    identity_key: "\{mini_token_kind_label(kind)}:\{text}:\{occurrence}",
  }
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
  let mut fingerprint = 0
  for token in tokens {
    fingerprint += mini_token_kind_label(token.kind).length()
    fingerprint += token.text.length()
    fingerprint += token.start
    fingerprint += token.end
    fingerprint += token.identity_key.length()
  }
  fingerprint
}
