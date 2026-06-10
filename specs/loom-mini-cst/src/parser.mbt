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
  if ctx.peek() == DollarColon {
    parse_dollar_stack_program(ctx)
  } else {
    parse_expr(ctx)
  }
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after mini notation")
    let _ = ctx.skip_until(fn(token) { token == EOF })
  }
}

///|
fn parse_dollar_stack_program(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(DollarStackNode, fn() {
    parse_dollar_stack_line(ctx)
    while ctx.peek() == DollarColon &&
          dollar_colon_starts_new_line(ctx) &&
          ctx.error_count < MAX_ERRORS {
      parse_dollar_stack_line(ctx)
    }
  })
}

///|
fn dollar_colon_starts_new_line(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Bool {
  let mut pos = ctx.position
  let mut saw_newline = false
  while pos < ctx.token_count {
    let token = (ctx.get_token)(pos)
    if token.is_trivia() {
      let text = ctx.token_text_at(pos)
      for ch in text {
        if ch == '\n' || ch == '\r' {
          saw_newline = true
        }
      }
      pos += 1
    } else {
      return token == DollarColon && saw_newline
    }
  }
  false
}

///|
fn parse_dollar_stack_line(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(DollarLineNode, fn() {
    expect(ctx, DollarColon, DollarColonToken) |> ignore
    parse_expr(ctx)
  })
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

// -- Song-level grammar (Phase 2 Piece 2) ------------------------------------
//
// A SEPARATE top-level grammar for `song(...)` wrapper forms, sharing the same
// lexer and the same `parse_expr` pattern grammar for section bodies (mirroring
// the oracle `mini/song_parser.mbt`, which reuses `parse_expr` under `parse`).
// Outer keywords (`song`, `section`, `bpm`, `part`, `part_id`, `fill`) lex as
// `Ident` + `LParen` — the `['s', '(']` keyword rule never matches `so…` — so
// item dispatch keys on the ident text, and each item is wrapped in a distinct
// node so projection disambiguates by node kind rather than keyword token.

///|
pub let song_spec : @core.LanguageSpec[MiniToken, MiniSyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  incomplete_kind=ErrorNode,
  parse_root=parse_song_root,
  reuse_size_threshold=1,
)

///|
pub let song_grammar : @loom.Grammar[MiniToken, MiniSyntaxKind, MiniAst] = @loom.Grammar::new(
  spec=song_spec,
  lex~,
  fold_node=mini_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=None,
)

///|
fn parse_song_root(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongNode, fn() {
    expect_song_keyword(ctx, "song") |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    if ctx.peek() == RParen {
      ctx.error("song() requires at least one item")
    } else {
      parse_song_item(ctx)
      while ctx.peek() == Comma && ctx.error_count < MAX_ERRORS {
        expect(ctx, Comma, CommaToken) |> ignore
        parse_song_item(ctx)
      }
    }
    expect(ctx, RParen, RParenToken) |> ignore
  })
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after song notation")
    let _ = ctx.skip_until(fn(token) { token == EOF })
  }
}

///|
fn parse_song_item(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  if ctx.peek() != Ident {
    ctx.error("Expected song item: section(...), bpm(...), part(...), part_id(...), or fill(...)")
    ctx.bump_error()
    return
  }
  match ctx.current_token_text().to_string() {
    "section" => parse_song_section_item(ctx)
    "bpm" => parse_song_bpm_item(ctx)
    "part_id" => parse_song_part_id_item(ctx)
    "part" => parse_song_part_item(ctx)
    "fill" => parse_song_fill_item(ctx)
    _ => {
      ctx.error("Expected song item: section(...), bpm(...), part(...), part_id(...), or fill(...)")
      ctx.bump_error()
    }
  }
}

///|
fn parse_song_section_item(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongSectionNode, fn() {
    expect_song_keyword(ctx, "section") |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_song_string(ctx)
    expect(ctx, Comma, CommaToken) |> ignore
    parse_song_rational(ctx)
    expect(ctx, Comma, CommaToken) |> ignore
    ctx.node(SongSectionBodyNode, fn() { parse_expr(ctx) })
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_song_bpm_item(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongBpmNode, fn() {
    expect_song_keyword(ctx, "bpm") |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    expect(ctx, Number, NumberToken) |> ignore
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_song_part_item(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongPartNode, fn() {
    expect_song_keyword(ctx, "part") |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_song_string(ctx)
    expect(ctx, Comma, CommaToken) |> ignore
    parse_song_string(ctx)
    if ctx.peek() == Comma {
      expect(ctx, Comma, CommaToken) |> ignore
      parse_song_rational(ctx)
    }
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_song_part_id_item(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongPartIdNode, fn() {
    expect_song_keyword(ctx, "part_id") |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_song_string(ctx)
    expect(ctx, Comma, CommaToken) |> ignore
    parse_song_string(ctx)
    expect(ctx, Comma, CommaToken) |> ignore
    parse_song_string(ctx)
    if ctx.peek() == Comma {
      expect(ctx, Comma, CommaToken) |> ignore
      parse_song_rational(ctx)
    }
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
fn parse_song_fill_item(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongFillNode, fn() {
    expect_song_keyword(ctx, "fill") |> ignore
    expect(ctx, LParen, LParenToken) |> ignore
    parse_song_string(ctx)
    expect(ctx, Comma, CommaToken) |> ignore
    parse_song_string(ctx)
    expect(ctx, RParen, RParenToken) |> ignore
  })
}

///|
/// A quoted literal string (section/part/id/fill name). Unlike `s("…")`
/// notation, the interior is an opaque string (may contain `:` and spaces),
/// so every interior token is captured as `StringContentToken` and the value
/// is reconstructed from the source span between the quotes at projection time.
fn parse_song_string(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongStringNode, fn() {
    expect(ctx, Quote, QuoteToken) |> ignore
    while ctx.peek() != Quote &&
          ctx.peek() != EOF &&
          ctx.error_count < MAX_ERRORS {
      ctx.emit_token(StringContentToken)
    }
    expect(ctx, Quote, QuoteToken) |> ignore
  })
}

///|
/// An integer or `num/den` rational (section length, optional part start).
/// A leading `-` is part of the `Number` token, so negatives lower to a
/// non-positive length and reject downstream, matching the oracle.
fn parse_song_rational(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
) -> Unit {
  ctx.node(SongRationalNode, fn() {
    expect(ctx, Number, NumberToken) |> ignore
    if ctx.peek() == Slash {
      expect(ctx, Slash, SlashToken) |> ignore
      expect(ctx, Number, NumberToken) |> ignore
    }
  })
}

///|
fn expect_song_keyword(
  ctx : @core.ParserContext[MiniToken, MiniSyntaxKind],
  word : String,
) -> Bool {
  if ctx.peek() == Ident && ctx.current_token_text().to_string() == word {
    // The oracle matches `keyword(` as one contiguous literal, so it rejects a
    // space before the paren. Reproduce that: require `(` immediately adjacent
    // to the keyword (no intervening trivia) before consuming.
    ctx.emit_token(IdentToken)
    if ctx.at_adjacent(LParen) {
      true
    } else {
      ctx.error("Expected '" + word + "('")
      false
    }
  } else {
    ctx.error("Expected '" + word + "'")
    false
  }
}

///|
pub fn parse_song_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  song_grammar.parse_cst(source)
}
