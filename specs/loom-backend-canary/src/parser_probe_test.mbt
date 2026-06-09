// Phase 0 representative parser slice: exactly ONE input per production
// entrypoint shape, driven through the full consumed loom surface. This is
// deliberately MINIMAL — its job is to make Check #1 (multi-target build) and
// Check #2 (dependency scan) meaningful, NOT to assert grammar parity (Phase 2).

///|
/// Runtime `parse` shape: a basic `s("...")` notation. Mirrors the production
/// `@mini.parse("bd sd hh sd")`-style runtime entrypoint.
test "representative: runtime s(...) notation parses cleanly" {
  let source = "s(\"bd sd hh sd\")"
  // Clean parse → Ok carrying the atom count (bd, sd, hh, sd).
  inspect(adapt_parse(source) is Ok(4), content="true")
  let parser = probe_parser(source)
  inspect(probe_atom_count(parser), content="4")
}

///|
/// Authoring `parse_doc` shape: a method chain exercising the PatternDoc /
/// stable-ID projection path (`s("bd sd").jux(rev)`).
test "representative: authoring method-chain parses + projects stable IDs" {
  let source = "s(\"bd sd\").jux(rev)"
  inspect(adapt_parse(source) is Ok(2), content="true")
  let parser = probe_parser(source)
  inspect(probe_atom_count(parser), content="2")
  // Projection identity allocates one stable leaf per atom ident.
  inspect(probe_projection_identity(parser, source), content="2")
}

///|
/// Song shape: a `$:`-stack top-level form, the minimal stand-in for the
/// `@mini.parse_song_with_bpm` entrypoint's distinct top-level grammar.
test "representative: $:-stack song form parses cleanly" {
  let source = "$: s(\"bd\")"
  inspect(adapt_parse(source) is Ok(1), content="true")
  let parser = probe_parser(source)
  inspect(probe_atom_count(parser), content="1")
}

///|
/// Incremental edit through the `text_change`-backed edit path: extend the
/// notation and confirm the parser re-derives the new atom count. Exercises
/// `apply_edit` + `text_to_delta`/`to_edits`.
test "incremental: apply_edit advances atom count via text_change" {
  let old_source = "s(\"bd sd\")"
  let new_source = "s(\"bd sd hh sd\")"
  let parser = probe_parser(old_source)
  inspect(probe_atom_count(parser), content="2")
  let after = probe_apply_edit(parser, old_source, new_source)
  inspect(after, content="4")
}
