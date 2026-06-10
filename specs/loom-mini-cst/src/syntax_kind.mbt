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
  NoteKeywordToken
  StackKeywordToken
  NoteCallNode
  StackCallNode
  CommaToken
  DotToken
  NumberToken
  MethodCallNode
  MethodNameToken
  StarToken
  SlashToken
  QuestionToken
  LBracketToken
  RBracketToken
  LayerNode
  SubNotationNode
  PostfixNode
  EuclidNode
  DollarColonToken
  DollarStackNode
  DollarLineNode
  ColonToken
  StringContentToken
  SongNode
  SongSectionNode
  SongBpmNode
  SongPartNode
  SongPartIdNode
  SongFillNode
  SongStringNode
  SongRationalNode
  SongSectionBodyNode
} derive(Debug, Eq)

///|
pub impl Show for MiniSyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @seam.ToRawKind for MiniSyntaxKind with fn to_raw(self) {
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
      NoteKeywordToken => 13
      StackKeywordToken => 14
      NoteCallNode => 15
      StackCallNode => 16
      CommaToken => 17
      DotToken => 18
      NumberToken => 19
      MethodCallNode => 20
      MethodNameToken => 21
      StarToken => 22
      SlashToken => 23
      QuestionToken => 24
      LBracketToken => 25
      RBracketToken => 26
      LayerNode => 27
      SubNotationNode => 28
      PostfixNode => 29
      EuclidNode => 30
      DollarColonToken => 31
      DollarStackNode => 32
      DollarLineNode => 33
      ColonToken => 34
      StringContentToken => 35
      SongNode => 36
      SongSectionNode => 37
      SongBpmNode => 38
      SongPartNode => 39
      SongPartIdNode => 40
      SongFillNode => 41
      SongStringNode => 42
      SongRationalNode => 43
      SongSectionBodyNode => 44
    },
  )
}

///|
/// Raw kind for mini atom nodes, exposed for black-box spec assertions.
pub fn mini_atom_node_raw_kind() -> @seam.RawKind {
  AtomNode.to_raw()
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
    13 => NoteKeywordToken
    14 => StackKeywordToken
    15 => NoteCallNode
    16 => StackCallNode
    17 => CommaToken
    18 => DotToken
    19 => NumberToken
    20 => MethodCallNode
    21 => MethodNameToken
    22 => StarToken
    23 => SlashToken
    24 => QuestionToken
    25 => LBracketToken
    26 => RBracketToken
    27 => LayerNode
    28 => SubNotationNode
    29 => PostfixNode
    30 => EuclidNode
    31 => DollarColonToken
    32 => DollarStackNode
    33 => DollarLineNode
    34 => ColonToken
    35 => StringContentToken
    36 => SongNode
    37 => SongSectionNode
    38 => SongBpmNode
    39 => SongPartNode
    40 => SongPartIdNode
    41 => SongFillNode
    42 => SongStringNode
    43 => SongRationalNode
    44 => SongSectionBodyNode
    _ => ErrorToken
  }
}
