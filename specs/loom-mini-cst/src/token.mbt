///|
pub(all) enum MiniToken {
  SKeyword
  LParen
  RParen
  Quote
  Ident
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for MiniToken with output(self, logger) {
  logger.write_string(
    match self {
      SKeyword => "s"
      LParen => "("
      RParen => ")"
      Quote => "\""
      Ident => "<ident>"
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for MiniToken with is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for MiniToken with is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for MiniToken with to_raw(self) {
  @seam.RawKind(
    match self {
      SKeyword => 0
      LParen => 1
      RParen => 2
      Quote => 3
      Ident => 4
      Whitespace => 5
      Error(_) => 6
      EOF => 7
    },
  )
}
