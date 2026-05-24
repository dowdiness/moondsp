// Loom PR #135 contract pinned by this spec:
// pure deletions may preserve reusable left-adjacent CST subtrees when
// leading and trailing token context still validate. This is deletion-safe
// CST reuse, not parser-owned token/subtree identity projection.
//
// Explicit non-goals: stable logical identity through insertions, token
// splits/merges, full reparses, or AST/domain projections.

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
fn find_first_atom_node(root : @seam.SyntaxNode) -> @seam.SyntaxNode? {
  if root.kind() == mini_atom_node_raw_kind() {
    Some(root)
  } else {
    for child in root.children() {
      match find_first_atom_node(child) {
        Some(node) => break Some(node)
        None => ()
      }
    } nobreak {
      None
    }
  }
}

///|
fn first_atom_node_or_abort(root : @seam.SyntaxNode) -> @seam.SyntaxNode {
  match find_first_atom_node(root) {
    Some(node) => node
    None => abort("expected AtomNode")
  }
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
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  inspect(parser.snapshot().read_or_abort().reuse_count > 0, content="true")
}

///|
test "apply_edit deletion updates duplicate atom spans and reuses unchanged nodes" {
  let parser = @loom.new_parser("s(\"bd sd bd\")", mini_grammar)
  parser.apply_edit(@core.Edit::delete(5, 8), "s(\"bd bd\")")
  let after =
    #|["bd@[3,5)", "bd@[6,8)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  inspect(parser.snapshot().read_or_abort().reuse_count > 0, content="true")
}

///|
test "parser pure deletion preserves left-adjacent mini atom reuse" {
  let parser = @loom.new_parser("s(\"bd \")", mini_grammar)
  parser.apply_edit(@core.Edit::delete(5, 6), "s(\"bd\")")
  let after_snapshot = parser.snapshot().read_or_abort()
  let after =
    #|["bd@[3,5)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  inspect(after_snapshot.reuse_count > 0, content="true")
}

///|
test "parser adjacent insertion does not claim deletion-style mini atom reuse" {
  let parser = @loom.new_parser("s(\"bd\")", mini_grammar)
  parser.apply_edit(@core.Edit::insert(5, 1), "s(\"bd \")")
  let after_snapshot = parser.snapshot().read_or_abort()
  let after =
    #|["bd@[3,5)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  inspect(after_snapshot.reuse_count, content="0")
}

///|
test "parser deletion that merges mini atoms stays conservative" {
  let parser = @loom.new_parser("s(\"bd sd\")", mini_grammar)
  parser.apply_edit(@core.Edit::delete(5, 6), "s(\"bdsd\")")
  let after_snapshot = parser.snapshot().read_or_abort()
  let after =
    #|["bdsd@[3,7)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  inspect(after_snapshot.reuse_count, content="0")
}

///|
test "reuse cursor can opt into safe left-adjacent mini deletion" {
  let old_source = "s(\"bd \")"
  let new_source = "s(\"bd\")"
  let edit = @core.Edit::delete(5, 6)
  let (old_tree, old_diagnostics) = parse_cst(old_source)
  inspect(old_diagnostics.length(), content="0")
  let old_atom = first_atom_node_or_abort(@seam.SyntaxNode::from_cst(old_tree))
  let new_tokens = tokenize(new_source)
  let new_starts = @core.build_starts(new_tokens)

  let strict_cache = @core.OldTokenCache::empty()
  strict_cache.apply_source_edit(edit)
  let strict_cursor = @core.ReuseCursor::new_with_edit(
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
    old_token_cache=strict_cache,
  )
  let atom_raw = mini_atom_node_raw_kind()
  inspect(strict_cursor.try_reuse(atom_raw, 3, 3) is None, content="true")

  let relaxed_cache = @core.OldTokenCache::empty()
  relaxed_cache.apply_source_edit(edit)
  let relaxed_cursor = @core.ReuseCursor::new_with_edit(
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
    old_token_cache=relaxed_cache,
    allow_left_adjacent_reuse=true,
  )
  let reused_atom = relaxed_cursor.try_reuse(atom_raw, 3, 3)
  inspect(reused_atom is Some(_), content="true")
  match reused_atom {
    Some(node) =>
      // This physical equality is meaningful because ReuseCursor returns a
      // subtree selected from old_tree, before any new tree interning happens.
      inspect(physical_equal(old_atom.cst_node(), node), content="true")
    None => abort("expected left-adjacent atom reuse")
  }
}

///|
test "reuse cursor rejects mini token merge with deletion opt-in" {
  let old_source = "s(\"bd sd\")"
  let new_source = "s(\"bdsd\")"
  let edit = @core.Edit::delete(5, 6)
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
    allow_left_adjacent_reuse=true,
  )
  inspect(
    cursor.try_reuse(mini_atom_node_raw_kind(), 3, 3) is None,
    content="true",
  )
}

///|
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

///|
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

///|
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

///|
test "parser apply_edit path uses direct parse_tokens_indexed-like cursor inputs" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"bd bd\")"
  let parser = @loom.new_parser(old_source, mini_grammar)
  let before = parser.snapshot().read_or_abort()
  let edit = @core.Edit::delete(5, 8)
  parser.apply_edit(edit, new_source)
  let after = parser.snapshot().read_or_abort()
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

///|
test "parser reuse count compares against direct TokenBuffer parse path" {
  let old_source = "s(\"bd sd bd\")"
  let new_source = "s(\"bd bd\")"
  let edit = @core.Edit::delete(5, 8)
  let parser = @loom.new_parser(old_source, mini_grammar)
  parser.apply_edit(edit, new_source)
  let after = parser.snapshot().read_or_abort()

  let buffer = @core.TokenBuffer::new_from_lex(
    new_source,
    lex_fn=lex,
    eof_token=EOF,
    incremental_relex_enabled=false,
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

///|
test "imperative parser reuse path matches direct deletion expectations" {
  let parser = @loom.new_imperative_parser("s(\"bd sd bd\")", mini_grammar)
  let _ = parser.parse()
  ignore(parser.edit(@core.Edit::delete(5, 8), "s(\"bd bd\")"))
  inspect(parser.get_last_reuse_count() > 0, content="true")
}
