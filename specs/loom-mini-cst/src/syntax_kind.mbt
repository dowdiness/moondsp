///|
pub(all) enum MiniSyntaxKind {
  SKeywordToken
  LParenToken
  RParenToken
  QuoteToken
  IdentToken
  WhitespaceToken
  ErrorToken
  EofToken
  RootNode
  CallNode
  NotationNode
  AtomNode
  ErrorNode
} derive(Debug, Eq)

///|
pub impl Show for MiniSyntaxKind with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @seam.ToRawKind for MiniSyntaxKind with to_raw(self) {
  @seam.RawKind(
    match self {
      SKeywordToken => 0
      LParenToken => 1
      RParenToken => 2
      QuoteToken => 3
      IdentToken => 4
      WhitespaceToken => 5
      ErrorToken => 6
      EofToken => 7
      RootNode => 8
      CallNode => 9
      NotationNode => 10
      AtomNode => 11
      ErrorNode => 12
    },
  )
}

///|
pub fn MiniSyntaxKind::from_raw(raw : @seam.RawKind) -> MiniSyntaxKind {
  match raw.0 {
    0 => SKeywordToken
    1 => LParenToken
    2 => RParenToken
    3 => QuoteToken
    4 => IdentToken
    5 => WhitespaceToken
    6 => ErrorToken
    7 => EofToken
    8 => RootNode
    9 => CallNode
    10 => NotationNode
    11 => AtomNode
    12 => ErrorNode
    _ => ErrorToken
  }
}
