///|
fn is_whitespace_char(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

///|
fn is_ident_char(ch : Char) -> Bool {
  let code = ch.to_int()
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  ch == '_' ||
  ch == '-'
}

///|
fn is_digit_char(ch : Char) -> Bool {
  let code = ch.to_int()
  code >= 48 && code <= 57
}

///|
fn is_ident_start_char(ch : Char) -> Bool {
  let code = ch.to_int()
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch == '_'
}

///|
pub fn mini_step_lexer(
  source : String,
  start : Int,
) -> @core.LexStep[MiniToken] {
  let cursor = @core.LexCursor::new(source, start)
  if cursor.is_done() {
    return Done
  }
  match cursor.view() {
    ['s', 't', 'a', 'c', 'k', '(', ..] => {
      for _ in 0..<5 {
        ignore(cursor.advance_char())
      }
      cursor.produced(StackKeyword)
    }
    ['n', 'o', 't', 'e', '(', ..] => {
      for _ in 0..<4 {
        ignore(cursor.advance_char())
      }
      cursor.produced(NoteKeyword)
    }
    ['s', '(', ..] => {
      ignore(cursor.advance_char())
      cursor.produced(SKeyword)
    }
    ['$', ':', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(DollarColon)
    }
    ['(', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(LParen)
    }
    [')', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(RParen)
    }
    [',', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Comma)
    }
    ['.', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Dot)
    }
    ['*', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Star)
    }
    ['/', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Slash)
    }
    ['?', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Question)
    }
    ['[', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(LBracket)
    }
    [']', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(RBracket)
    }
    ['"', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Quote)
    }
    [ws, ..] if is_whitespace_char(ws) => {
      ignore(cursor.take_while(is_whitespace_char))
      cursor.produced(Whitespace)
    }
    ['-', d, ..] if is_digit_char(d) => {
      ignore(cursor.advance_char())
      ignore(cursor.take_while(is_digit_char))
      match cursor.view() {
        ['.', d2, ..] if is_digit_char(d2) => {
          ignore(cursor.advance_char())
          ignore(cursor.take_while(is_digit_char))
        }
        _ => ()
      }
      cursor.produced(Number)
    }
    [d, ..] if is_digit_char(d) => {
      ignore(cursor.take_while(is_digit_char))
      match cursor.view() {
        ['.', d2, ..] if is_digit_char(d2) => {
          ignore(cursor.advance_char())
          ignore(cursor.take_while(is_digit_char))
        }
        _ => ()
      }
      cursor.produced(Number)
    }
    [ident, ..] if is_ident_start_char(ident) => {
      ignore(cursor.take_while(is_ident_char))
      cursor.produced(Ident)
    }
    [ch, .. rest] => {
      cursor.set_view(rest)
      @core.LexStep::Invalid(
        at=start,
        width=cursor.len(),
        message="Unexpected character: \{ch.to_string()}",
      )
    }
    _ => cursor.invalid("Invalid character")
  }
}

///|
pub fn lex(source : String) -> @core.LexResult[MiniToken] {
  let buffer = @core.TokenBuffer::new_from_steps(
    source,
    @core.PrefixLexer::new(lex_step=mini_step_lexer),
    eof_token=EOF,
    error_token=Error(""),
    error_token_from_message=Some(fn(msg) { Error(msg) }),
  )
  @core.LexResult::with_starts(
    buffer.get_tokens(),
    buffer.get_starts(),
    diagnostics=buffer.get_diagnostics(),
  )
}

///|
pub fn tokenize(source : String) -> Array[@core.TokenInfo[MiniToken]] {
  lex(source).tokens()
}

///|
pub fn token_debug(source : String) -> Array[String] {
  let tokens = lex(source).tokens()
  let starts = @core.build_starts(tokens)
  let rows : Array[String] = []
  for index, token in tokens {
    let start = starts[index]
    rows.push("\{token.token.to_string()}@[\{start},\{start + token.len})")
  }
  rows
}
