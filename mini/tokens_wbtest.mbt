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
test "mini tokens keep spans for malformed syntax" {
  let tokens = tokenize_mini_authoring_source("s(\"bd sd\"")
  inspect(tokens[tokens.length() - 1].identity_key, content="quote:\":1")
  inspect(tokens[tokens.length() - 1].start, content="8")
  inspect(tokens[tokens.length() - 1].end, content="9")
}
