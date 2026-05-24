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
  parse_expr(ctx)
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after mini notation")
    let _ = ctx.skip_until(fn(token) { token == EOF })
  }
}

///|
/// Parse a full expression: `primary ( "." method )*`. Production mini
/// grammar (cf. `mini/parser.mbt:5`) lets `stack` args be full
/// expressions, so this extracted helper is reused inside
/// `parse_stack_call` for parity.
fn parse_expr(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  parse_primary_call(ctx)
  while ctx.peek() == Dot && ctx.error_count < MAX_ERRORS {
    parse_method_call(ctx)
  }
}

///|
fn parse_method_call(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
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
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
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
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  match ctx.peek() {
    Number => ctx.emit_token(NumberToken)
    Ident => {
      // Callback form: bare `rev` or `fast(N)` / `slow(N)` / `rev()`
      ctx.emit_token(MethodNameToken)
      if ctx.peek() == LParen {
        expect(ctx, LParen, LParenToken) |> ignore
        parse_method_args(ctx)
        expect(ctx, RParen, RParenToken) |> ignore
      }
    }
    _ => {
      ctx.error("Expected number or callback identifier as method argument")
      ctx.bump_error()
    }
  }
}

///|
fn parse_primary_call(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  match ctx.peek() {
    SKeyword => parse_s_call(ctx)
    NoteKeyword => parse_note_call(ctx)
    StackKeyword => parse_stack_call(ctx)
    _ => {
      ctx.error("Expected 's(', 'note(', or 'stack('")
      ctx.bump_error()
    }
  }
}

///|
fn parse_s_call(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(CallNode, fn() {
    expect(ctx, SKeyword, SKeywordToken) |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_notation(ctx)
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_note_call(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(NoteCallNode, fn() {
    expect(ctx, NoteKeyword, NoteKeywordToken) |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_notation(ctx)
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_stack_call(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(StackCallNode, fn() {
    expect(ctx, StackKeyword, StackKeywordToken) |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_expr(ctx)
    while ctx.peek() == Comma && ctx.error_count < MAX_ERRORS {
      expect(ctx, Comma, CommaToken) |> ignore
      parse_expr(ctx)
    }
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_notation(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(NotationNode, fn() {
    expect(ctx, Quote, QuoteToken) |> ignore
    parse_notation_body(ctx, stop_token=Quote)
    expect(ctx, Quote, QuoteToken) |> ignore
  })
}

///|
fn parse_notation_body(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
  stop_token~ : MiniToken,
) -> Unit {
  parse_layer(ctx, stop_token~)
  while ctx.peek() == Comma && ctx.error_count < MAX_ERRORS {
    expect(ctx, Comma, CommaToken) |> ignore
    parse_layer(ctx, stop_token~)
  }
}

///|
fn parse_layer(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
  stop_token~ : MiniToken,
) -> Unit {
  ctx.node(LayerNode, fn() {
    while ctx.peek() != stop_token &&
          ctx.peek() != Comma &&
          ctx.peek() != EOF &&
          ctx.error_count < MAX_ERRORS {
      match ctx.peek() {
        Whitespace => ctx.emit_token(WhitespaceToken)
        LBracket => parse_sub_notation(ctx)
        Ident => parse_atom_with_postfix(ctx, IdentToken)
        Number => parse_atom_with_postfix(ctx, NumberToken)
        _ => {
          ctx.error("Expected atom, number, or sub-notation")
          ctx.bump_error()
        }
      }
    }
  })
}

///|
fn parse_atom_with_postfix(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
  atom_kind : MiniSyntaxKind,
) -> Unit {
  ctx.node(AtomNode, fn() {
    ctx.emit_token(atom_kind)
    parse_postfix_loop(ctx)
  })
}

///|
fn parse_sub_notation(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SubNotationNode, fn() {
    expect(ctx, LBracket, LBracketToken) |> ignore
    parse_notation_body(ctx, stop_token=RBracket)
    expect(ctx, RBracket, RBracketToken) |> ignore
    parse_postfix_loop(ctx)
  })
}

///|
fn parse_postfix_loop(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  while is_postfix_start(ctx.peek()) && ctx.error_count < MAX_ERRORS {
    parse_postfix(ctx)
  }
}

///|
fn is_postfix_start(t : MiniToken) -> Bool {
  match t {
    Star | Slash | Question | LParen => true
    _ => false
  }
}

///|
fn parse_postfix(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(PostfixNode, fn() {
    match ctx.peek() {
      Star => {
        ctx.emit_token(StarToken)
        if ctx.peek() == Number {
          ctx.emit_token(NumberToken)
        } else {
          ctx.error("Expected number after '*'")
          ctx.bump_error()
        }
      }
      Slash => {
        ctx.emit_token(SlashToken)
        if ctx.peek() == Number {
          ctx.emit_token(NumberToken)
        } else {
          ctx.error("Expected number after '/'")
          ctx.bump_error()
        }
      }
      Question => ctx.emit_token(QuestionToken)
      LParen => parse_euclid(ctx)
      _ => {
        ctx.error("Expected postfix '*', '/', '?', or '('")
        ctx.bump_error()
      }
    }
  })
}

///|
fn parse_euclid(ctx : @core.ParserContext[MiniToken, MiniSyntaxKind]) -> Unit {
  ctx.node(EuclidNode, fn() {
    expect(ctx, LParen, LParenToken) |> ignore
    expect(ctx, Number, NumberToken) |> ignore
    expect(ctx, Comma, CommaToken) |> ignore
    expect(ctx, Number, NumberToken) |> ignore
    if ctx.peek() == Comma {
      expect(ctx, Comma, CommaToken) |> ignore
      expect(ctx, Number, NumberToken) |> ignore
    }
    expect(ctx, RParen, RParenToken) |> ignore
  })
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
