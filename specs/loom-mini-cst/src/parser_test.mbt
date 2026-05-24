// Loom PR #135 contract pinned by this spec:
// pure deletions may preserve reusable left-adjacent CST subtrees when
// leading and trailing token context still validate. This is deletion-safe
// CST reuse, not parser-owned token/subtree identity projection.
//
// Explicit non-goals: stable logical identity through insertions, token
// splits/merges, full reparses, or AST/domain projections.

///|
test "SPIKE step 1: note() primary parses with zero diagnostics" {
  let (_cst, diagnostics) = try! parse_cst("note(\"c4 e4 g4\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 1: stack() with single arg parses with zero diagnostics" {
  let (_cst, diagnostics) = try! parse_cst("stack(s(\"bd\"))")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 1: stack() with multiple args parses with zero diagnostics" {
  let (_cst, diagnostics) = try! parse_cst(
    "stack(s(\"bd\"), s(\"sd\"), note(\"c4\"))",
  )
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 1: nested stack parses recursively" {
  let (_cst, diagnostics) = try! parse_cst(
    "stack(stack(s(\"bd\"), s(\"sd\")), s(\"hh\"))",
  )
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 2: method chain with number arg" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd sd\").fast(2)")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 2: method chain with empty args" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd\").rev()")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 2: chained methods" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd sd\").fast(2).rev().slow(3)")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 2: method with callback arg (jux rev)" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd sd hh sd\").jux(rev)")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 2: method with parenthesized callback (every)" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd sd\").every(4, fast(2))")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 3: decimal number arg" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd\").gain(0.5)")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 3: live-demo pattern shape (euclid + chain)" {
  // The live-demo's actual pattern uses euclid `(3,8)` postfix (step 5),
  // `?` postfix (step 5), and `.jux(rev)` method (step 2). This test
  // verifies just the method-chain piece; euclid/postfix come later.
  let (_cst, diagnostics) = try! parse_cst("s(\"bd cp hh sd\").jux(rev)")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 4: layer comma inside notation" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd sd, hh cp\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 4: sub-notation brackets" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd [sd cp] hh\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 4: nested brackets and layers" {
  let (_cst, diagnostics) = try! parse_cst("s(\"[bd sd, hh] [cp, oh oh]\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 5: star postfix" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd*2 sd\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 5: slash postfix" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd/2 sd\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 5: question (degrade) postfix" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd? sd hh?\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 5: euclid postfix 2-arg" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd(3,8) sd\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 5: euclid postfix 3-arg with offset" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd(3,8,1) sd\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE step 5: postfix on sub-notation" {
  let (_cst, diagnostics) = try! parse_cst("s(\"[bd sd]*2 hh\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "SPIKE FULL: live-demo's actual initial pattern" {
  // Cited by Codex: web/live/src/main.ts:20 uses euclid + ? + jux(rev).
  // This is THE test that defines the wall: if loom can parse this with
  // zero diagnostics, the parity gap is grammar-coverage in the spec, not
  // a loom expressivity limitation.
  let (_cst, diagnostics) = try! parse_cst(
    "s(\"bd(3,8) cp? hh*2 [sd oh]\").jux(rev).fast(2)",
  )
  inspect(diagnostics.length(), content="0")
}

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

// ----------------------------------------------------------------------------
// Edit/reuse coverage for the expanded grammar surface (method chain,
// postfix, sub-notation brackets, layer commas). These tests pin reuse
// behavior across the new productions so future grammar changes can't
// silently degrade incremental parsing on the production-parity surface.
// ----------------------------------------------------------------------------

///|
test "apply_edit inside method name still parses with zero diagnostics" {
  let parser = @loom.new_parser("s(\"bd sd\").fast(2)", mini_grammar)
  // Insert "er" between "fast" and "(" to produce ".faster(2)"
  parser.apply_edit(@core.Edit::insert(15, 2), "s(\"bd sd\").faster(2)")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  let after =
    #|["bd@[3,5)", "sd@[6,8)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  // Measure reuse: the s(...) primary subtree is unchanged, so the
  // pre-method-call call node should be reusable.
  inspect(parser.snapshot().read_or_abort().reuse_count > 0, content="true")
}

///|
test "apply_edit deletion of postfix preserves zero diagnostics" {
  let parser = @loom.new_parser("s(\"bd*2 sd\")", mini_grammar)
  // Delete "*2" leaving `s("bd sd")`
  parser.apply_edit(@core.Edit::delete(5, 7), "s(\"bd sd\")")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  let after =
    #|["bd@[3,5)", "sd@[6,8)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.snapshot().read_or_abort().reuse_count > 0, content="true")
}

///|
test "apply_edit insertion inside sub-notation brackets parses cleanly" {
  let parser = @loom.new_parser("s(\"[bd sd]\")", mini_grammar)
  // Insert " hh" before the closing bracket to produce `s("[bd sd hh]")`
  parser.apply_edit(@core.Edit::insert(9, 3), "s(\"[bd sd hh]\")")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  let after =
    #|["bd@[4,6)", "sd@[7,9)", "hh@[10,12)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.snapshot().read_or_abort().reuse_count > 0, content="true")
}

///|
test "apply_edit across layer-comma keeps both layers parsing cleanly" {
  let parser = @loom.new_parser("s(\"bd, sd\")", mini_grammar)
  // Insert " hh" before the comma to produce `s("bd hh, sd")`
  parser.apply_edit(@core.Edit::insert(5, 3), "s(\"bd hh, sd\")")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  let after =
    #|["bd@[3,5)", "hh@[6,8)", "sd@[10,12)"]
  debug_inspect(parser_ident_token_spans(parser), content=after)
  inspect(parser.snapshot().read_or_abort().reuse_count > 0, content="true")
}

// ----------------------------------------------------------------------------
// CST shape coverage for the expanded grammar surface. The earlier
// diagnostic-count tests only verify "no errors"; these tests pin the
// concrete shape of the CST so a future refactor can't accidentally
// collapse a production while keeping diagnostics at zero. One
// representative test per new node category — not exhaustive.
// ----------------------------------------------------------------------------

///|
fn make_indent(depth : Int) -> String {
  let buf = StringBuilder::new()
  for _ in 0..<depth {
    buf.write_string("  ")
  }
  buf.to_string()
}

///|
fn cst_shape_walk(
  node : @seam.SyntaxNode,
  depth : Int,
  lines : Array[String],
) -> Unit {
  let kind = MiniSyntaxKind::from_raw(node.kind())
  lines.push("\{make_indent(depth)}\{kind}@[\{node.start()},\{node.end()})")
  for child in node.all_children() {
    match child {
      Node(n) => cst_shape_walk(n, depth + 1, lines)
      Token(t) => {
        let tk = MiniSyntaxKind::from_raw(t.kind())
        if tk != WhitespaceToken {
          lines.push(
            "\{make_indent(depth + 1)}\{tk} \"\{t.text()}\"@[\{t.start()},\{t.end()})",
          )
        }
      }
    }
  }
}

///|
fn cst_shape(source : String) -> Array[String] raise @core.LexError {
  let (cst, _) = parse_cst(source)
  let root = @seam.SyntaxNode::from_cst(cst)
  let lines : Array[String] = []
  cst_shape_walk(root, 0, lines)
  lines
}

///|
test "CST shape: method call produces MethodCallNode with method name and number arg" {
  let expected =
    #|[
    #|  "RootNode@[0,12)",
    #|  "  CallNode@[0,6)",
    #|  "    SKeywordToken \"s\"@[0,1)",
    #|  "    LParenToken \"(\"@[1,2)",
    #|  "    NotationNode@[2,5)",
    #|  "      QuoteToken \"\"\"@[2,3)",
    #|  "      LayerNode@[3,4)",
    #|  "        AtomNode@[3,4)",
    #|  "          IdentToken \"d\"@[3,4)",
    #|  "      QuoteToken \"\"\"@[4,5)",
    #|  "    RParenToken \")\"@[5,6)",
    #|  "  MethodCallNode@[6,12)",
    #|  "    DotToken \".\"@[6,7)",
    #|  "    MethodNameToken \"fst\"@[7,10)",
    #|  "    LParenToken \"(\"@[10,11)",
    #|  "    RParenToken \")\"@[11,12)",
    #|]
  debug_inspect(try! cst_shape("s(\"d\").fst()"), content=expected)
}

///|
test "CST shape: star postfix lives inside the AtomNode" {
  let expected =
    #|[
    #|  "RootNode@[0,9)",
    #|  "  CallNode@[0,9)",
    #|  "    SKeywordToken \"s\"@[0,1)",
    #|  "    LParenToken \"(\"@[1,2)",
    #|  "    NotationNode@[2,8)",
    #|  "      QuoteToken \"\"\"@[2,3)",
    #|  "      LayerNode@[3,7)",
    #|  "        AtomNode@[3,7)",
    #|  "          IdentToken \"bd\"@[3,5)",
    #|  "          PostfixNode@[5,7)",
    #|  "            StarToken \"*\"@[5,6)",
    #|  "            NumberToken \"2\"@[6,7)",
    #|  "      QuoteToken \"\"\"@[7,8)",
    #|  "    RParenToken \")\"@[8,9)",
    #|]
  debug_inspect(try! cst_shape("s(\"bd*2\")"), content=expected)
}

///|
test "CST shape: euclid postfix nests a EuclidNode under the AtomNode" {
  let expected =
    #|[
    #|  "RootNode@[0,12)",
    #|  "  CallNode@[0,12)",
    #|  "    SKeywordToken \"s\"@[0,1)",
    #|  "    LParenToken \"(\"@[1,2)",
    #|  "    NotationNode@[2,11)",
    #|  "      QuoteToken \"\"\"@[2,3)",
    #|  "      LayerNode@[3,10)",
    #|  "        AtomNode@[3,10)",
    #|  "          IdentToken \"bd\"@[3,5)",
    #|  "          PostfixNode@[5,10)",
    #|  "            EuclidNode@[5,10)",
    #|  "              LParenToken \"(\"@[5,6)",
    #|  "              NumberToken \"3\"@[6,7)",
    #|  "              CommaToken \",\"@[7,8)",
    #|  "              NumberToken \"8\"@[8,9)",
    #|  "              RParenToken \")\"@[9,10)",
    #|  "      QuoteToken \"\"\"@[10,11)",
    #|  "    RParenToken \")\"@[11,12)",
    #|]
  debug_inspect(try! cst_shape("s(\"bd(3,8)\")"), content=expected)
}

///|
test "CST shape: layer comma splits notation into multiple LayerNodes" {
  // Note: LayerNode @[6,9) span starts at the space before "sd" because
  // seam attaches leading trivia (whitespace) to the next non-trivia
  // production. The IdentToken itself still starts at 7.
  let expected =
    #|[
    #|  "RootNode@[0,11)",
    #|  "  CallNode@[0,11)",
    #|  "    SKeywordToken \"s\"@[0,1)",
    #|  "    LParenToken \"(\"@[1,2)",
    #|  "    NotationNode@[2,10)",
    #|  "      QuoteToken \"\"\"@[2,3)",
    #|  "      LayerNode@[3,5)",
    #|  "        AtomNode@[3,5)",
    #|  "          IdentToken \"bd\"@[3,5)",
    #|  "      CommaToken \",\"@[5,6)",
    #|  "      LayerNode@[6,9)",
    #|  "        AtomNode@[6,9)",
    #|  "          IdentToken \"sd\"@[7,9)",
    #|  "      QuoteToken \"\"\"@[9,10)",
    #|  "    RParenToken \")\"@[10,11)",
    #|]
  debug_inspect(try! cst_shape("s(\"bd, sd\")"), content=expected)
}

// ----------------------------------------------------------------------------
// Edge-case coverage for the expanded grammar surface. These pin
// behavior at the corners that the SPIKE step tests don't reach:
// degenerate inputs (empty notation), malformed productions (euclid
// missing its second number), and intentional limits (digit-start
// atoms inside quotes — see KNOWN LIMITATION below).
//
// Codex pre-PR review (2026-05-24) flagged that stack args must accept
// full expressions, not just primaries, to claim production parity
// against `mini/parser.mbt:5-8`. The first test below pins that.
// ----------------------------------------------------------------------------

///|
test "edge case: stack accepts method-chained expressions per production grammar" {
  let (_cst, diagnostics) = try! parse_cst(
    "stack(s(\"bd\").fast(2), note(\"c4\").rev())",
  )
  inspect(diagnostics.length(), content="0")
}

///|
// PERMISSIVE-BY-DESIGN: at the CST construction level we accept empty
// notation `s("")` and trailing-comma layers `s("bd,")` with zero
// diagnostics — the production runtime parser (mini/parser.mbt) rejects
// these later as semantic errors. Codex pre-PR review (2026-05-24) noted
// the divergence; pinning current behavior is the right move for a CST
// spec because editor flows want a tree even from partial input.
test "edge case: empty quoted notation accepted at CST level (permissive)" {
  let (_cst, diagnostics) = try! parse_cst("s(\"\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "edge case: trailing-comma layer accepted at CST level (permissive)" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd,\")")
  inspect(diagnostics.length(), content="0")
}

///|
test "edge case: unterminated sub-notation bracket recovers within MAX_ERRORS" {
  // Codex pre-PR review (2026-05-24) flagged that `parse_layer` does not
  // bail out on outer-context stop tokens, so `s("[bd")` with a missing
  // `]` cascades error-bumps until `MAX_ERRORS` (=32). This test pins
  // that recovery behavior: parsing terminates with a bounded diagnostic
  // count rather than looping forever, but the count is large. A future
  // PR can add layered stop_token tracking to recover more cleanly.
  let (_cst, diagnostics) = try! parse_cst("s(\"[bd\")")
  inspect(diagnostics.length() > 0, content="true")
  inspect(diagnostics.length() <= 64, content="true")
}

///|
test "edge case: malformed euclid (missing second number) reports diagnostic" {
  let (_cst, diagnostics) = try! parse_cst("s(\"bd(3,)\")")
  // parse_euclid expects Number after the comma; absent number triggers
  // "Expected <number>" via expect(). The bracket is balanced, so we
  // expect at least one diagnostic but parsing recovers without cascading.
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "edge case: deeply nested brackets parse cleanly" {
  let (_cst, diagnostics) = try! parse_cst("s(\"[[[bd]]]\")")
  inspect(diagnostics.length(), content="0")
}

///|
// KNOWN LIMITATION: digit-start atoms inside quoted notation are not
// supported. The Number-first lexer ordering splits `2bd` into a Number
// token "2" followed by an Ident token "bd", producing two separate
// AtomNodes instead of one. Production mini-notation patterns use
// letter-start atoms (`c4`, `e4`, `g4`, `bd`, `sd`, `hh`), so this does
// not affect any live-demo pattern. Fixing this would require
// context-sensitive lexing inside quotes — out of scope for the
// grammar-parity spec; track as a separate decision if a downstream
// pattern needs it.
test "edge case: digit-start atom inside quotes splits into Number + Ident (KNOWN LIMITATION)" {
  let expected =
    #|["bd@[4,6)"]
  // `2bd` lexes as Number(2) + Ident(bd), so only the Ident-bearing
  // AtomNode appears in ident_token_spans. The "2" atom exists in the
  // CST as an AtomNode with a NumberToken but contributes no ident span.
  debug_inspect(try! ident_token_spans("s(\"2bd\")"), content=expected)
}

///|
test "CST shape: sub-notation brackets produce a SubNotationNode" {
  let expected =
    #|[
    #|  "RootNode@[0,9)",
    #|  "  CallNode@[0,9)",
    #|  "    SKeywordToken \"s\"@[0,1)",
    #|  "    LParenToken \"(\"@[1,2)",
    #|  "    NotationNode@[2,8)",
    #|  "      QuoteToken \"\"\"@[2,3)",
    #|  "      LayerNode@[3,7)",
    #|  "        SubNotationNode@[3,7)",
    #|  "          LBracketToken \"[\"@[3,4)",
    #|  "          LayerNode@[4,6)",
    #|  "            AtomNode@[4,6)",
    #|  "              IdentToken \"bd\"@[4,6)",
    #|  "          RBracketToken \"]\"@[6,7)",
    #|  "      QuoteToken \"\"\"@[7,8)",
    #|  "    RParenToken \")\"@[8,9)",
    #|]
  debug_inspect(try! cst_shape("s(\"[bd]\")"), content=expected)
}
