///|
pub(all) enum MiniToken {
  SKeyword
  NoteKeyword
  StackKeyword
  LParen
  RParen
  Comma
  Dot
  Number
  Star
  Slash
  Question
  LBracket
  RBracket
  DollarColon
  Quote
  Ident
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for MiniToken with fn output(self, logger) {
  logger.write_string(
    match self {
      SKeyword => "s"
      NoteKeyword => "note"
      StackKeyword => "stack"
      LParen => "("
      RParen => ")"
      Comma => ","
      Dot => "."
      Number => "<number>"
      Star => "*"
      Slash => "/"
      Question => "?"
      LBracket => "["
      RBracket => "]"
      DollarColon => "$:"
      Quote => "\""
      Ident => "<ident>"
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for MiniToken with fn is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for MiniToken with fn is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for MiniToken with fn to_raw(self) {
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
      NoteKeyword => 8
      StackKeyword => 9
      Comma => 10
      Dot => 11
      Number => 12
      Star => 13
      Slash => 14
      Question => 15
      LBracket => 16
      RBracket => 17
      DollarColon => 18
    },
  )
}
