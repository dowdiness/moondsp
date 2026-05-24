///|
pub(all) enum MiniAst {
  Parsed
} derive(Eq, Debug)

///|
const MAX_ERRORS : Int = 32

///|
pub let mini_spec : @core.LanguageSpec[MiniToken, MiniSyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  incomplete_kind=ErrorNode,
  parse_root~,
  reuse_size_threshold=1,
)

///|
fn parse_root(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  parse_call(ctx)
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after mini notation")
    let _ = ctx.skip_until(fn(token) { token == EOF })
  }
}

///|
fn parse_call(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(CallNode, fn() {
    expect(ctx, SKeyword, SKeywordToken) |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_notation(ctx)
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_notation(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(NotationNode, fn() {
    expect(ctx, Quote, QuoteToken) |> ignore
    while ctx.peek() != Quote &&
          ctx.peek() != EOF &&
          ctx.error_count < MAX_ERRORS {
      match ctx.peek() {
        Ident => parse_atom(ctx)
        Whitespace => ctx.emit_token(WhitespaceToken)
        _ => {
          ctx.error("Expected sound atom")
          ctx.bump_error()
        }
      }
    }
    expect(ctx, Quote, QuoteToken) |> ignore
  })
}

///|
fn parse_atom(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(AtomNode, fn() { expect(ctx, Ident, IdentToken) |> ignore })
}

///|
fn expect(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
  expected : MiniToken,
  kind : MiniSyntaxKind,
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
pub fn mini_fold_node(
  _node : @seam.SyntaxNode,
  _fold_child : (@seam.SyntaxNode) -> MiniAst,
) -> MiniAst {
  Parsed
}

///|
pub let mini_grammar : @loom.Grammar[MiniToken, MiniSyntaxKind, MiniAst] = @loom.Grammar::new(
  spec=mini_spec,
  lex~,
  fold_node=mini_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=None,
)

///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  mini_grammar.parse_cst(source)
}

///|
pub fn ident_token_spans(source : String) -> Array[String] raise @core.LexError {
  let (cst, _diagnostics) = parse_cst(source)
  ident_token_spans_from_syntax(@seam.SyntaxNode::from_cst(cst))
}

///|
pub fn ident_token_spans_from_syntax(root : @seam.SyntaxNode) -> Array[String] {
  let spans : Array[String] = []
  fn visit(node : @seam.SyntaxNode) -> Unit {
    if node.kind() == AtomNode.to_raw() {
      match node.find_token(IdentToken.to_raw()) {
        Some(token) =>
          spans.push("\{token.text()}@[\{token.start()},\{token.end()})")
        None => ()
      }
    }
    for child in node.children() {
      visit(child)
    }
  }
  visit(root)
  spans
}

///|
pub fn parser_ident_token_spans(
  parser : @loom.Parser[MiniAst],
) -> Array[String] {
  let root = parser.syntax_tree().read_or_abort()
  ident_token_spans_from_syntax(root)
}
