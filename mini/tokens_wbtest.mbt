///|
fn token_keys(tokens : Array[MiniToken]) -> Array[String] {
  let keys : Array[String] = []
  for token in tokens {
    keys.push(token.identity_key)
  }
  keys
}

///|
fn token_key_set(tokens : Array[MiniToken]) -> Map[String, Bool] {
  let keys : Map[String, Bool] = {}
  for token in tokens {
    keys[token.identity_key] = true
  }
  keys
}

///|
fn assert_has_token_key(tokens : Array[MiniToken], key : String) -> Unit {
  guard token_key_set(tokens).contains(key) else {
    abort("expected token key: \{key}")
  }
}

///|
fn assert_lacks_token_key(tokens : Array[MiniToken], key : String) -> Unit {
  guard !token_key_set(tokens).contains(key) else {
    abort("unexpected token key: \{key}")
  }
}

///|
fn assert_token_keys_equal(
  left : Array[MiniToken],
  right : Array[MiniToken],
) -> Unit {
  let left_keys = token_keys(left)
  let right_keys = token_keys(right)
  guard left_keys.length() == right_keys.length() else {
    abort("token key lengths differ")
  }
  for index in 0..<left_keys.length() {
    guard left_keys[index] == right_keys[index] else {
      abort(
        "token key mismatch at \{index}: \{left_keys[index]} != \{right_keys[index]}",
      )
    }
  }
}

///|
fn assert_token_edit_span(
  span : MiniTokenEditSpan,
  old_start~ : Int,
  old_end~ : Int,
  new_start~ : Int,
  new_end~ : Int,
) -> Unit {
  guard span.old_start == old_start &&
    span.old_end == old_end &&
    span.new_start == new_start &&
    span.new_end == new_end else {
    abort(
      "unexpected edit span: old[\{span.old_start},\{span.old_end}) new[\{span.new_start},\{span.new_end})",
    )
  }
}

///|
fn source_edit(
  old_start~ : Int,
  old_end~ : Int,
  new_end~ : Int,
) -> MiniSourceEditSpan {
  { old_start, old_end, new_end }
}

///|
test "mini tokens ignore whitespace in identity keys" {
  let compact = tokenize_mini_authoring_source("s(\"bd sd\")")
  let spaced = tokenize_mini_authoring_source("s( \"  bd   sd  \" )")
  assert_token_keys_equal(compact, spaced)
}

///|
test "mini tokens replacement changes only replaced identifier key" {
  let edited = tokenize_mini_authoring_source("s(\"bd cp hh\")")
  assert_has_token_key(edited, "ident:bd:0")
  assert_lacks_token_key(edited, "ident:sd:0")
  assert_has_token_key(edited, "ident:cp:0")
  assert_has_token_key(edited, "ident:hh:0")
}

///|
test "mini tokens insertion keeps surviving identifier keys" {
  let inserted = tokenize_mini_authoring_source("s(\"hh bd sd oh\")")
  assert_has_token_key(inserted, "ident:hh:0")
  assert_has_token_key(inserted, "ident:bd:0")
  assert_has_token_key(inserted, "ident:sd:0")
  assert_has_token_key(inserted, "ident:oh:0")
}

///|
test "mini token edit span isolates duplicate-token insertion" {
  let old_tokens = tokenize_mini_authoring_source("s(\"bd bd sd\")")
  let new_tokens = tokenize_mini_authoring_source("s(\"bd bd bd sd\")")
  assert_token_edit_span(
    mini_token_edit_span(old_tokens, new_tokens),
    old_start=5,
    old_end=5,
    new_start=5,
    new_end=6,
  )
}

///|
test "mini token realignment preserves suffix duplicate identities" {
  let aligned = realign_mini_authoring_tokens(
    "s(\"bd bd sd\")", "s(\"bd bd bd sd\")",
  )
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:bd:0")
  inspect(keys[4], content="ident:bd:1")
  inspect(keys[5], content="ident:bd:2")
  inspect(keys[6], content="ident:sd:0")
}

///|
test "mini token realignment preserves suffix identities after deletion" {
  let aligned = realign_mini_authoring_tokens(
    "s(\"bd bd bd sd\")", "s(\"bd bd sd\")",
  )
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:bd:0")
  inspect(keys[4], content="ident:bd:1")
  inspect(keys[5], content="ident:sd:0")
}

///|
test "mini token realignment gives changed-window repeats fresh identities" {
  let aligned = realign_mini_authoring_tokens("s(\"bd sd\")", "s(\"sd bd\")")
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:sd:1")
  inspect(keys[4], content="ident:bd:1")
}

///|
test "mini source edit span disambiguates insertion before first duplicate" {
  let aligned = realign_mini_authoring_tokens_with_source_edit(
    "s(\"bd bd bd\")",
    "s(\"bd bd bd bd\")",
    source_edit(old_start=3, old_end=3, new_end=6),
  )
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:bd:3")
  inspect(keys[4], content="ident:bd:0")
  inspect(keys[5], content="ident:bd:1")
  inspect(keys[6], content="ident:bd:2")
}

///|
test "mini source edit span disambiguates insertion before middle duplicate" {
  let aligned = realign_mini_authoring_tokens_with_source_edit(
    "s(\"bd bd bd\")",
    "s(\"bd bd bd bd\")",
    source_edit(old_start=6, old_end=6, new_end=9),
  )
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:bd:0")
  inspect(keys[4], content="ident:bd:3")
  inspect(keys[5], content="ident:bd:1")
  inspect(keys[6], content="ident:bd:2")
}

///|
test "mini source edit span disambiguates insertion before last duplicate" {
  let aligned = realign_mini_authoring_tokens_with_source_edit(
    "s(\"bd bd bd\")",
    "s(\"bd bd bd bd\")",
    source_edit(old_start=9, old_end=9, new_end=12),
  )
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:bd:0")
  inspect(keys[4], content="ident:bd:1")
  inspect(keys[5], content="ident:bd:3")
  inspect(keys[6], content="ident:bd:2")
}

///|
test "mini source edit span preserves suffix identities after duplicate deletion" {
  let aligned = realign_mini_authoring_tokens_with_source_edit(
    "s(\"bd bd bd bd\")",
    "s(\"bd bd bd\")",
    source_edit(old_start=6, old_end=9, new_end=6),
  )
  let keys = token_keys(aligned)
  inspect(keys[3], content="ident:bd:0")
  inspect(keys[4], content="ident:bd:2")
  inspect(keys[5], content="ident:bd:3")
}

///|
test "mini tokens keep spans for malformed syntax" {
  let tokens = tokenize_mini_authoring_source("s(\"bd sd\"")
  inspect(tokens[tokens.length() - 1].identity_key, content="quote:\":1")
  inspect(tokens[tokens.length() - 1].start, content="8")
  inspect(tokens[tokens.length() - 1].end, content="9")
}
