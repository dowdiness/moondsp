// Phase 0 canary: a deliberately MINIMAL mini-shaped loom grammar plus probe
// functions that touch the full consumed loom surface (parser construction,
// reactive syntax-tree / diagnostics views, incremental edit via text_change,
// seam CST navigation, and projection-identity). The grammar is NOT a parity
// reimplementation of `mini/`; it exists only so Check #2's dependency scan
// sees the real import set and Check #1's build runs on all three backends.

///|
/// Minimal token alphabet — enough to lex the three representative inputs and
/// the error-shape inputs.
pub(all) enum CanaryToken {
  SKeyword
  LParen
  RParen
  Quote
  Comma
  Dot
  DollarColon
  Ident
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for CanaryToken with fn output(self, logger) {
  logger.write_string(
    match self {
      SKeyword => "s"
      LParen => "("
      RParen => ")"
      Quote => "\""
      Comma => ","
      Dot => "."
      DollarColon => "$:"
      Ident => "<ident>"
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for CanaryToken with fn is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for CanaryToken with fn is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for CanaryToken with fn to_raw(self) {
  @seam.RawKind(
    match self {
      SKeyword => 0
      LParen => 1
      RParen => 2
      Quote => 3
      Comma => 4
      Dot => 5
      DollarColon => 6
      Ident => 7
      Whitespace => 8
      Error(_) => 9
      EOF => 10
    },
  )
}

///|
/// Minimal syntax-kind alphabet for the canary CST.
pub(all) enum CanarySyntaxKind {
  SKeywordToken
  LParenToken
  RParenToken
  QuoteToken
  CommaToken
  DotToken
  DollarColonToken
  IdentToken
  MethodNameToken
  WhitespaceToken
  ErrorToken
  EofToken
  RootNode
  CallNode
  NotationNode
  LayerNode
  AtomNode
  MethodCallNode
  DollarStackNode
  DollarLineNode
  ErrorNode
} derive(Debug, Eq)

///|
pub impl Show for CanarySyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @seam.ToRawKind for CanarySyntaxKind with fn to_raw(self) {
  @seam.RawKind(
    match self {
      SKeywordToken => 0
      LParenToken => 1
      RParenToken => 2
      QuoteToken => 3
      CommaToken => 4
      DotToken => 5
      DollarColonToken => 6
      IdentToken => 7
      MethodNameToken => 8
      WhitespaceToken => 9
      ErrorToken => 10
      EofToken => 11
      RootNode => 12
      CallNode => 13
      NotationNode => 14
      LayerNode => 15
      AtomNode => 16
      MethodCallNode => 17
      DollarStackNode => 18
      DollarLineNode => 19
      ErrorNode => 20
    },
  )
}

///|
/// The canary AST is trivial — Phase 0 only needs the CST + diagnostics.
pub(all) enum CanaryAst {
  Parsed
} derive(Eq, Debug)

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
fn is_ident_start_char(ch : Char) -> Bool {
  let code = ch.to_int()
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch == '_'
}

///|
fn canary_step_lexer(
  source : String,
  start : Int,
) -> @core.LexStep[CanaryToken] {
  let cursor = @core.LexCursor::new(source, start)
  if cursor.is_done() {
    return Done
  }
  match cursor.view() {
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
    ['"', .. rest] => {
      cursor.set_view(rest)
      cursor.produced(Quote)
    }
    [ws, ..] if is_whitespace_char(ws) => {
      ignore(cursor.take_while(is_whitespace_char))
      cursor.produced(Whitespace)
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
fn canary_lex(source : String) -> @core.LexResult[CanaryToken] {
  let buffer = @core.TokenBuffer::new_from_steps(
    source,
    @core.PrefixLexer::new(lex_step=canary_step_lexer),
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
const MAX_ERRORS : Int = 32

///|
pub let canary_spec : @core.LanguageSpec[CanaryToken, CanarySyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  incomplete_kind=ErrorNode,
  parse_root~,
  reuse_size_threshold=1,
)

///|
fn parse_root(ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind]) -> Unit {
  if ctx.peek() == DollarColon {
    parse_dollar_program(ctx)
  } else {
    parse_expr(ctx)
  }
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after mini notation")
    let _ = ctx.skip_until(fn(token) { token == EOF })
  }
}

///|
fn parse_dollar_program(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  ctx.node(DollarStackNode, fn() {
    parse_dollar_line(ctx)
    while ctx.peek() == DollarColon && ctx.error_count < MAX_ERRORS {
      parse_dollar_line(ctx)
    }
  })
}

///|
fn parse_dollar_line(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  ctx.node(DollarLineNode, fn() {
    expect(ctx, DollarColon, DollarColonToken) |> ignore
    parse_expr(ctx)
  })
}

///|
fn parse_expr(ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind]) -> Unit {
  parse_primary(ctx)
  while ctx.peek() == Dot && ctx.error_count < MAX_ERRORS {
    parse_method_call(ctx)
  }
}

///|
fn parse_primary(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  match ctx.peek() {
    SKeyword => parse_s_call(ctx)
    _ => {
      ctx.error("Expected 's('")
      ctx.bump_error()
    }
  }
}

///|
fn parse_s_call(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  ctx.node(CallNode, fn() {
    expect(ctx, SKeyword, SKeywordToken) |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_notation(ctx)
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_notation(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  ctx.node(NotationNode, fn() {
    expect(ctx, Quote, QuoteToken) |> ignore
    parse_layer(ctx)
    expect(ctx, Quote, QuoteToken) |> ignore
  })
}

///|
fn parse_layer(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  ctx.node(LayerNode, fn() {
    while ctx.peek() != Quote &&
          ctx.peek() != EOF &&
          ctx.error_count < MAX_ERRORS {
      match ctx.peek() {
        Whitespace => ctx.emit_token(WhitespaceToken)
        Ident => ctx.node(AtomNode, fn() { ctx.emit_token(IdentToken) })
        _ => {
          ctx.error("Expected atom or whitespace inside notation")
          ctx.bump_error()
        }
      }
    }
  })
}

///|
fn parse_method_call(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  ctx.node(MethodCallNode, fn() {
    expect(ctx, Dot, DotToken) |> ignore
    expect(ctx, Ident, MethodNameToken) |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_method_args(ctx)
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_method_args(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  if ctx.peek() == RParen {
    return
  }
  parse_method_arg(ctx)
  while ctx.peek() == Comma && ctx.error_count < MAX_ERRORS {
    expect(ctx, Comma, CommaToken) |> ignore
    parse_method_arg(ctx)
  }
}

///|
fn parse_method_arg(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
) -> Unit {
  match ctx.peek() {
    Ident => {
      // Callback form: bare `rev` or `f(...)`.
      ctx.emit_token(MethodNameToken)
      if ctx.peek() == LParen {
        expect(ctx, LParen, LParenToken) |> ignore
        parse_method_args(ctx)
        expect(ctx, RParen, RParenToken) |> ignore
      }
    }
    _ => {
      ctx.error("Expected callback identifier as method argument")
      ctx.bump_error()
    }
  }
}

///|
fn expect(
  ctx : @core.ParserContext[CanaryToken, CanarySyntaxKind],
  expected : CanaryToken,
  kind : CanarySyntaxKind,
) -> Bool {
  if ctx.peek() == expected {
    ctx.emit_token(kind)
    true
  } else {
    ctx.error("Expected " + expected.to_string())
    false
  }
}

///|
fn canary_fold_node(
  _node : @seam.SyntaxNode,
  _fold_child : (@seam.SyntaxNode) -> CanaryAst,
) -> CanaryAst {
  Parsed
}

///|
pub let canary_grammar : @loom.Grammar[CanaryToken, CanarySyntaxKind, CanaryAst] = @loom.Grammar::new(
  spec=canary_spec,
  lex=canary_lex,
  fold_node=canary_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=None,
)

// ----------------------------------------------------------------------------
// Probe entry points — these are what the tests drive to exercise the surface.
// ----------------------------------------------------------------------------

///|
/// Build a unified, incr-integrated parser over the canary grammar. This is the
/// single sanctioned entry point (`@loom.new_parser`); it owns the engine and
/// publishes reactive views, exactly as a production parser path would.
pub fn probe_parser(source : String) -> @loom.Parser[CanaryAst] {
  @loom.new_parser(source, canary_grammar)
}

///|
/// Count `AtomNode`s in the parser's current syntax tree. Exercises the
/// reactive `syntax_tree()` view plus seam `SyntaxNode` navigation.
pub fn probe_atom_count(parser : @loom.Parser[CanaryAst]) -> Int {
  let root = parser.syntax_tree().read_or_abort()
  count_atoms(root)
}

///|
fn count_atoms(node : @seam.SyntaxNode) -> Int {
  let mut total = if node.kind() == AtomNode.to_raw() { 1 } else { 0 }
  for child in node.children() {
    total += count_atoms(child)
  }
  total
}

///|
/// Advance the parser incrementally through the text_change edit path. Computes
/// the edit from old→new source via `text_to_delta`/`to_edits` (the
/// `dowdiness/text_change`-backed helpers) and applies the first resulting edit.
/// Returns the atom count after the edit. Exercises `apply_edit` + text_change.
pub fn probe_apply_edit(
  parser : @loom.Parser[CanaryAst],
  old_source : String,
  new_source : String,
) -> Int {
  let edits = @loom.to_edits(@loom.text_to_delta(old_source, new_source))
  match edits {
    [first, ..] => parser.apply_edit(first, new_source)
    [] => parser.set_source(new_source)
  }
  probe_atom_count(parser)
}

///|
/// Extract projection leaves (one per atom ident token) and advance a
/// projection-identity baseline, allocating stable string IDs. Exercises the
/// `ProjectionIdentityBaseline` / `ProjectionLeaf` surface that the production
/// PatternDoc stable-ID path will depend on. Returns the number of stable
/// leaves carried by the advanced baseline.
pub fn probe_projection_identity(
  parser : @loom.Parser[CanaryAst],
  source : String,
) -> Int {
  let root = parser.syntax_tree().read_or_abort()
  let leaves : Array[@loom.ProjectionLeaf] = []
  collect_leaves(root, leaves)
  let baseline : @loom.ProjectionIdentityBaseline[String] = @loom.ProjectionIdentityBaseline::new(
    "",
    [],
  )
  let advanced = baseline.advance(source, leaves, fn(leaf) { leaf.key })
  advanced.leaves().length()
}

///|
fn collect_leaves(
  node : @seam.SyntaxNode,
  out : Array[@loom.ProjectionLeaf],
) -> Unit {
  if node.kind() == AtomNode.to_raw() {
    match node.find_token(IdentToken.to_raw()) {
      Some(token) =>
        out.push(
          @loom.ProjectionLeaf::new(token.start(), token.end(), token.text()),
        )
      None => ()
    }
  }
  for child in node.children() {
    collect_leaves(child, out)
  }
}
