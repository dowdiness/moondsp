///|
test "lexer exposes duplicate mini atoms as separate tokens" {
  let expected =
    #|[
    #|  "s@[0,1)",
    #|  "(@[1,2)",
    #|  "\"@[2,3)",
    #|  "<ident>@[3,5)",
    #|  " @[5,6)",
    #|  "<ident>@[6,8)",
    #|  " @[8,9)",
    #|  "<ident>@[9,11)",
    #|  "\"@[11,12)",
    #|  ")@[12,13)",
    #|  "EOF@[13,13)",
    #|]
  debug_inspect(token_debug("s(\"bd sd bd\")"), content=expected)
}

///|
test "cst keeps duplicate sound atom spans separate" {
  let expected =
    #|["bd@[3,5)", "sd@[6,8)", "bd@[9,11)"]
  debug_inspect(try! ident_token_spans("s(\"bd sd bd\")"), content=expected)
}

///|
test "cst diagnostics survive malformed notation" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd sd")
  inspect(diagnostics.length(), content="2")
}

///|
test "apply_edit insertion updates duplicate atom spans through parser CST" {
  let parser = @loom.new_parser("s(\"bd sd bd\")", mini_grammar)
  let before =
    #|["bd@[3,5)", "sd@[6,8)", "bd@[9,11)"]
  debug_inspect(parser_ident_token_spans(parser), content=before)
  parser.apply_edit(@core.Edit::insert(8, 3), "s(\"bd sd cp bd\")")
  let after =
    #|["bd@[3,5)", "sd@[6,8)", "cp@[9,11)", "bd@[12,14)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.runtime().read(parser.diagnostics()).length(), content="0")
  inspect(
    parser.runtime().read(parser.snapshot()).reuse_count > 0,
    content="true",
  )
}

///|
test "apply_edit deletion updates duplicate atom spans and reuses unchanged nodes" {
  let parser = @loom.new_parser("s(\"bd sd bd\")", mini_grammar)
  parser.apply_edit(@core.Edit::delete(5, 8), "s(\"bd bd\")")
  let after =
    #|["bd@[3,5)", "bd@[6,8)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.runtime().read(parser.diagnostics()).length(), content="0")
  inspect(parser.runtime().read(parser.snapshot()).reuse_count > 0, content="true")
}

test "parse_tokens_indexed reproduces mini deletion without parser wrapper reuse" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"bd bd\")"
  let edit = @core.Edit::delete(5, 8)
  let (old_tree, old_diagnostics) = parse_cst(old_source)
  inspect(old_diagnostics.length(), content="0")
  let new_tokens = tokenize(new_source)
  let new_starts = @core.build_starts(new_tokens)
  let cache = @core.OldTokenCache::empty()
  cache.apply_source_edit(edit)
  let cursor = @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_source.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_tokens[i].len,
      )
    },
    mini_spec,
    old_token_cache=cache,
  )
  let (_, _new_diagnostics, reuse_count) = @core.parse_tokens_indexed(
    new_source,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_tokens[i].len },
    mini_spec,
    cursor=Some(cursor),
  )
  inspect(reuse_count > 0, content="true")
}

test "parse_tokens_indexed reproduces mini prefix deletion reuse" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"sd bd\")"
  let edit = @core.Edit::delete(3, 6)
  let (old_tree, old_diagnostics) = parse_cst(old_source)
  inspect(old_diagnostics.length(), content="0")
  let new_tokens = tokenize(new_source)
  let new_starts = @core.build_starts(new_tokens)
  let cache = @core.OldTokenCache::empty()
  cache.apply_source_edit(edit)
  let cursor = @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_source.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_tokens[i].len,
      )
    },
    mini_spec,
    old_token_cache=cache,
  )
  let (_, _new_diagnostics, reuse_count) = @core.parse_tokens_indexed(
    new_source,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_tokens[i].len },
    mini_spec,
    cursor=Some(cursor),
  )
  inspect(reuse_count > 0, content="true")
}

test "parse_tokens_indexed reproduces mini suffix deletion reuse" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"bd sd\")"
  let edit = @core.Edit::delete(8, 11)
  let (old_tree, old_diagnostics) = parse_cst(old_source)
  inspect(old_diagnostics.length(), content="0")
  let new_tokens = tokenize(new_source)
  let new_starts = @core.build_starts(new_tokens)
  let cache = @core.OldTokenCache::empty()
  cache.apply_source_edit(edit)
  let cursor = @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_source.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_tokens[i].len,
      )
    },
    mini_spec,
    old_token_cache=cache,
  )
  let (_, _new_diagnostics, reuse_count) = @core.parse_tokens_indexed(
    new_source,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_tokens[i].len },
    mini_spec,
    cursor=Some(cursor),
  )
  inspect(reuse_count > 0, content="true")
}

test "parser apply_edit path uses direct parse_tokens_indexed-like cursor inputs" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"bd bd\")"
  let parser = @loom.new_parser(old_source, mini_grammar)
  let before = parser.runtime().read(parser.snapshot())
  let edit = @core.Edit::delete(5, 8)
  parser.apply_edit(edit, new_source)
  let after = parser.runtime().read(parser.snapshot())
  let new_tokens = tokenize(new_source)
  let new_starts = @core.build_starts(new_tokens)
  let cache = @core.OldTokenCache::empty()
  cache.apply_source_edit(edit)
  let cursor = @core.ReuseCursor::new_with_edit(
    before.syntax.cst_node(),
    edit,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) {
      new_source.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_tokens[i].len,
      )
    },
    mini_spec,
    old_token_cache=cache,
  )
  let (_, _, direct_reuse_count) = @core.parse_tokens_indexed(
    new_source,
    new_tokens.length(),
    fn(i) { new_tokens[i].token },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + new_tokens[i].len },
    mini_spec,
    cursor=Some(cursor),
  )
  inspect(direct_reuse_count > 0, content="true")
  inspect(after.reuse_count > 0, content="true")
}

test "parser reuse count compares against direct TokenBuffer parse path" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"bd bd\")"
  let edit = @core.Edit::delete(5, 8)
  let parser = @loom.new_parser(old_source, mini_grammar)
  parser.apply_edit(edit, new_source)
  let after = parser.runtime().read(parser.snapshot())

  let buffer = @core.TokenBuffer::new_from_lex(
    new_source,
    lex_fn=lex,
    eof_token=EOF,
    incremental_relex_enabled = false,
  )
  buffer.update(edit, new_source) catch {
    @core.LexError(_) => abort("unexpected lexer failure")
  }
  let new_starts = buffer.get_starts()
  let cache = @core.OldTokenCache::empty()
  cache.apply_source_edit(edit)
  let cursor = @core.ReuseCursor::new_with_edit(
    parse_cst(old_source).0,
    edit,
    buffer.token_count(),
    fn(i) { buffer.get_token(i) },
    fn(i) { new_starts[i] },
    fn(i) { buffer.get_view(i) },
    mini_spec,
    old_token_cache=cache,
  )
  let (_, _, direct_reuse_count) = @core.parse_tokens_indexed(
    new_source,
    buffer.token_count(),
    fn(i) { buffer.get_token(i) },
    fn(i) { new_starts[i] },
    fn(i) { new_starts[i] + buffer.get_tokens()[i].len },
    mini_spec,
    cursor=Some(cursor),
  )

  let direct_reuse = direct_reuse_count > 0
  let parser_reuse = after.reuse_count > 0
  inspect(direct_reuse, content="true")
  inspect(parser_reuse, content="true")
}

test "imperative parser reuse path matches direct deletion expectations" {
  let parser = @loom.new_imperative_parser("s(\"bd sd bd\")", mini_grammar)
  let _ = parser.parse()
  ignore(parser.edit(@core.Edit::delete(5, 8), "s(\"bd bd\")"))
  inspect(parser.get_last_reuse_count() > 0, content="true")
}
