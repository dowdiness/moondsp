///|
priv enum LoomMiniAtomKind {
  SoundAtom
  NoteAtom
}

///|
priv struct LoomMiniRawAtom {
  kind : LoomMiniAtomKind
  text : String
  start : Int
  end : Int
}

///|
priv struct LoomMiniProjectedAtom {
  kind : LoomMiniAtomKind
  text : String
  start : Int
  end : Int
  id : String
}

///|
priv enum LoomMiniExpr {
  AtomGroupExpr(Array[LoomMiniRawAtom])
  StackExpr(Array[LoomMiniExpr])
  FastExpr(LoomMiniExpr, Int)
  SlowExpr(LoomMiniExpr, Int)
}

///|
priv struct LoomMiniRawProjection {
  expr : LoomMiniExpr
  atoms : Array[LoomMiniRawAtom]
}

///|
priv struct LoomMiniProjectedCursor {
  atoms : Array[LoomMiniProjectedAtom]
  mut offset : Int
}

///|
pub struct LoomMiniAtomProjection {
  priv parser : @loom.Parser[MiniAst]
  priv scope : @incr.Scope
  priv edit : @incr.Signal[@core.Edit?]
  priv observer : @incr.Observer[
    Result[@pattern.PatternDoc[@pattern.ControlMap], String],
  ]
}

///|
pub fn LoomMiniAtomProjection::new(input : String) -> LoomMiniAtomProjection {
  let parser = @loom.new_parser(input, mini_grammar)
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let edit : @incr.Signal[@core.Edit?] = @incr.Signal::new(
    rt,
    None,
    label="loom-mini-atom-projection.edit",
  )
  let mut previous_doc : @pattern.PatternDoc[@pattern.ControlMap]? = None
  let mut previous_atoms : Array[LoomMiniProjectedAtom] = []
  let projected = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      let diagnostics = parser.diagnostics().get_or_abort()
      if diagnostics.length() > 0 {
        return Err("loom mini syntax has diagnostics")
      }
      let raw_projection = match
        loom_mini_collect_raw_projection(parser.syntax_tree().get_or_abort()) {
        Ok(projection) => projection
        Err(msg) => return Err(msg)
      }
      let atoms = match edit.get() {
        Some(edit) =>
          loom_mini_realign_projected_atoms(
            previous_atoms,
            raw_projection.atoms,
            edit,
          )
        None => loom_mini_assign_projected_atoms(raw_projection.atoms)
      }
      let builder = @mini.MiniDocBuilder::with_previous(previous_doc)
      match
        loom_mini_build_projected_doc(
          builder,
          raw_projection.expr,
          atoms,
        ) {
        Ok(doc) => {
          previous_doc = Some(doc)
          previous_atoms = atoms
          Ok(doc)
        }
        Err(msg) => Err(msg)
      }
    },
    label="loom-mini-atom-projection.doc",
  )
  scope.add_cell_ids([projected.id()])
  let observer = scope.add_observer(projected.observe())
  { parser, scope, edit, observer }
}

///|
pub fn LoomMiniAtomProjection::parse_doc(
  self : LoomMiniAtomProjection,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  self.observer.get()
}

///|
pub fn LoomMiniAtomProjection::apply_edit(
  self : LoomMiniAtomProjection,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  self.edit.set(Some(edit))
  self.parser.apply_edit(edit, new_source)
}

///|
pub fn LoomMiniAtomProjection::dispose(self : LoomMiniAtomProjection) -> Unit {
  self.scope.dispose()
}

///|
fn loom_mini_collect_raw_projection(
  root : @seam.SyntaxNode,
) -> Result[LoomMiniRawProjection, String] {
  let base = match loom_mini_collect_base_expr(root) {
    Ok(projection) => projection
    Err(msg) => return Err(msg)
  }
  let expr = match loom_mini_apply_method_expr(root, base.expr) {
    Ok(expr) => expr
    Err(msg) => return Err(msg)
  }
  Ok({ expr, atoms: base.atoms })
}

///|
fn loom_mini_collect_base_expr(
  root : @seam.SyntaxNode,
) -> Result[LoomMiniRawProjection, String] {
  match root.child_of_kind(StackCallNode.to_raw()) {
    Some(stack_call) => loom_mini_collect_stack_expr(stack_call)
    None => {
      let (kind, call) = match root.child_of_kind(CallNode.to_raw()) {
        Some(call) => (SoundAtom, call)
        None =>
          match root.child_of_kind(NoteCallNode.to_raw()) {
            Some(call) => (NoteAtom, call)
            None =>
              return Err(
                "loom atom projection only supports s(...), note(...), or stack(...)",
              )
          }
      }
      loom_mini_collect_atom_group_expr(call, kind)
    }
  }
}

///|
fn loom_mini_collect_stack_expr(
  stack_call : @seam.SyntaxNode,
) -> Result[LoomMiniRawProjection, String] {
  let children : Array[LoomMiniExpr] = []
  let atoms : Array[LoomMiniRawAtom] = []
  for child in stack_call.children() {
    let projection = if child.kind() == CallNode.to_raw() {
      loom_mini_collect_atom_group_expr(child, SoundAtom)
    } else if child.kind() == NoteCallNode.to_raw() {
      loom_mini_collect_atom_group_expr(child, NoteAtom)
    } else {
      return Err("loom atom projection only supports plain stack arguments")
    }
    match projection {
      Ok(projection) => {
        children.push(projection.expr)
        for atom in projection.atoms {
          atoms.push(atom)
        }
      }
      Err(msg) => return Err(msg)
    }
  }
  if children.length() == 0 {
    return Err("loom atom projection expected stack arguments")
  }
  Ok({ expr: StackExpr(children), atoms })
}

///|
fn loom_mini_collect_atom_group_expr(
  call : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[LoomMiniRawProjection, String] {
  let atoms = match loom_mini_collect_plain_call_atoms(call, kind) {
    Ok(atoms) => atoms
    Err(msg) => return Err(msg)
  }
  Ok({ expr: AtomGroupExpr(atoms), atoms })
}

///|
fn loom_mini_apply_method_expr(
  root : @seam.SyntaxNode,
  base : LoomMiniExpr,
) -> Result[LoomMiniExpr, String] {
  let methods : Array[@seam.SyntaxNode] = []
  for child in root.children() {
    if child.kind() == MethodCallNode.to_raw() {
      methods.push(child)
    }
  }
  match methods {
    [] => Ok(base)
    [call] => {
      let name = match call.find_token(MethodNameToken.to_raw()) {
        Some(token) => token.text()
        None => return Err("loom atom projection expected method name")
      }
      if name != "fast" && name != "slow" {
        return Err("loom atom projection only supports .fast(N) or .slow(N) methods")
      }
      if call.find_token(CommaToken.to_raw()) is Some(_) {
        return Err("loom atom projection only supports .fast(N) or .slow(N) methods")
      }
      let number = match call.find_token(NumberToken.to_raw()) {
        Some(token) => token.text()
        None => return Err("loom atom projection expected method argument")
      }
      let factor = match loom_mini_parse_positive_int(number) {
        Ok(n) => n
        Err(msg) => return Err(msg)
      }
      if name == "fast" {
        Ok(FastExpr(base, factor))
      } else {
        Ok(SlowExpr(base, factor))
      }
    }
    _ => Err("loom atom projection only supports one method")
  }
}

///|
fn loom_mini_parse_positive_int(text : String) -> Result[Int, String] {
  let mut result = 0
  if text.length() == 0 {
    return Err("loom atom projection expected positive integer")
  }
  for ch in text {
    if ch < '0' || ch > '9' {
      return Err("loom atom projection expected positive integer")
    }
    result = result * 10 + (ch.to_int() - '0'.to_int())
  }
  if result <= 0 {
    Err("loom atom projection expected positive integer")
  } else {
    Ok(result)
  }
}

///|
fn loom_mini_collect_plain_call_atoms(
  call : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[Array[LoomMiniRawAtom], String] {
  let notation = match call.child_of_kind(NotationNode.to_raw()) {
    Some(notation) => notation
    None => return Err("loom atom projection expected notation")
  }
  if loom_mini_direct_layer_count(notation) != 1 ||
    loom_mini_contains_node_kind(notation, SubNotationNode.to_raw()) ||
    loom_mini_contains_node_kind(notation, PostfixNode.to_raw()) ||
    loom_mini_contains_node_kind(notation, EuclidNode.to_raw()) {
    return Err("loom atom projection only supports one plain atom layer")
  }
  let atoms : Array[LoomMiniRawAtom] = []
  fn visit(node : @seam.SyntaxNode) -> Unit {
    if node.kind() == AtomNode.to_raw() {
      let token = match kind {
        SoundAtom => node.find_token(IdentToken.to_raw())
        NoteAtom => node.find_token(NumberToken.to_raw())
      }
      match token {
        Some(token) =>
          atoms.push({
            kind,
            text: token.text(),
            start: token.start(),
            end: token.end(),
          })
        None => ()
      }
    }
    for child in node.children() {
      visit(child)
    }
  }
  visit(notation)
  if atoms.length() == 0 {
    Err("loom atom projection expected at least one atom")
  } else {
    Ok(atoms)
  }
}

///|
fn loom_mini_contains_node_kind(
  node : @seam.SyntaxNode,
  kind : @seam.RawKind,
) -> Bool {
  if node.kind() == kind {
    return true
  }
  for child in node.children() {
    if loom_mini_contains_node_kind(child, kind) {
      return true
    }
  }
  false
}

///|
fn loom_mini_direct_layer_count(node : @seam.SyntaxNode) -> Int {
  let mut count = 0
  for child in node.children() {
    if child.kind() == LayerNode.to_raw() {
      count += 1
    }
  }
  count
}

///|
fn loom_mini_assign_projected_atoms(
  raw_atoms : Array[LoomMiniRawAtom],
) -> Array[LoomMiniProjectedAtom] {
  let counters : Map[String, Int] = {}
  raw_atoms.map(fn(atom) {
    let occurrence = loom_mini_next_atom_occurrence(
      counters,
      atom.kind,
      atom.text,
    )
    {
      kind: atom.kind,
      text: atom.text,
      start: atom.start,
      end: atom.end,
      id: loom_mini_atom_id(atom.kind, atom.text, occurrence),
    }
  })
}

///|
fn loom_mini_realign_projected_atoms(
  old_atoms : Array[LoomMiniProjectedAtom],
  raw_atoms : Array[LoomMiniRawAtom],
  edit : @core.Edit,
) -> Array[LoomMiniProjectedAtom] {
  if old_atoms.length() == 0 {
    return loom_mini_assign_projected_atoms(raw_atoms)
  }
  let edit_start = edit.new_end() - edit.inserted_length()
  let span = loom_mini_atom_edit_span_from_source(
    old_atoms,
    raw_atoms,
    old_start=edit_start,
    old_end=edit.old_end(),
    new_end=edit.new_end(),
  )
  let used : Map[String, Bool] = {}
  for atom in old_atoms {
    used[atom.id] = true
  }
  let counters : Map[String, Int] = {}
  let aligned : Array[LoomMiniProjectedAtom] = []
  for index in 0..<raw_atoms.length() {
    let raw = raw_atoms[index]
    let id = if index < span.old_start && index < span.new_start {
      old_atoms[index].id
    } else if index >= span.new_end {
      old_atoms[span.old_end + index - span.new_end].id
    } else {
      loom_mini_allocate_atom_id(counters, used, raw.kind, raw.text)
    }
    aligned.push({
      kind: raw.kind,
      text: raw.text,
      start: raw.start,
      end: raw.end,
      id,
    })
  }
  aligned
}

///|
fn loom_mini_next_atom_occurrence(
  counters : Map[String, Int],
  kind : LoomMiniAtomKind,
  text : String,
) -> Int {
  let key = loom_mini_atom_counter_key(kind, text)
  let occurrence = match counters.get(key) {
    Some(value) => value
    None => 0
  }
  counters[key] = occurrence + 1
  occurrence
}

///|
fn loom_mini_allocate_atom_id(
  counters : Map[String, Int],
  used : Map[String, Bool],
  kind : LoomMiniAtomKind,
  text : String,
) -> String {
  let key = loom_mini_atom_counter_key(kind, text)
  let mut occurrence = match counters.get(key) {
    Some(value) => value
    None => 0
  }
  let mut id = loom_mini_atom_id(kind, text, occurrence)
  while used.contains(id) {
    occurrence += 1
    id = loom_mini_atom_id(kind, text, occurrence)
  }
  counters[key] = occurrence + 1
  used[id] = true
  id
}

///|
fn loom_mini_atom_counter_key(kind : LoomMiniAtomKind, text : String) -> String {
  "\{loom_mini_atom_kind_label(kind)}:\{text}"
}

///|
fn loom_mini_atom_id(
  kind : LoomMiniAtomKind,
  text : String,
  occurrence : Int,
) -> String {
  "mini:\{loom_mini_atom_kind_label(kind)}:\{text}:\{occurrence}"
}

///|
fn loom_mini_atom_kind_label(kind : LoomMiniAtomKind) -> String {
  match kind {
    SoundAtom => "sound"
    NoteAtom => "note"
  }
}

///|
priv struct LoomMiniAtomEditSpan {
  old_start : Int
  old_end : Int
  new_start : Int
  new_end : Int
}

///|
fn loom_mini_atom_edit_span_from_source(
  old_atoms : Array[LoomMiniProjectedAtom],
  raw_atoms : Array[LoomMiniRawAtom],
  old_start~ : Int,
  old_end~ : Int,
  new_end~ : Int,
) -> LoomMiniAtomEditSpan {
  {
    old_start: loom_mini_first_projected_atom_ending_after(old_atoms, old_start),
    old_end: loom_mini_first_projected_atom_starting_at_or_after(
      old_atoms, old_end,
    ),
    new_start: loom_mini_first_raw_atom_ending_after(raw_atoms, old_start),
    new_end: loom_mini_first_raw_atom_starting_at_or_after(raw_atoms, new_end),
  }
}

///|
fn loom_mini_first_projected_atom_ending_after(
  atoms : Array[LoomMiniProjectedAtom],
  offset : Int,
) -> Int {
  let mut index = 0
  while index < atoms.length() && atoms[index].end <= offset {
    index += 1
  }
  index
}

///|
fn loom_mini_first_projected_atom_starting_at_or_after(
  atoms : Array[LoomMiniProjectedAtom],
  offset : Int,
) -> Int {
  let mut index = 0
  while index < atoms.length() && atoms[index].start < offset {
    index += 1
  }
  index
}

///|
fn loom_mini_first_raw_atom_ending_after(
  atoms : Array[LoomMiniRawAtom],
  offset : Int,
) -> Int {
  let mut index = 0
  while index < atoms.length() && atoms[index].end <= offset {
    index += 1
  }
  index
}

///|
fn loom_mini_first_raw_atom_starting_at_or_after(
  atoms : Array[LoomMiniRawAtom],
  offset : Int,
) -> Int {
  let mut index = 0
  while index < atoms.length() && atoms[index].start < offset {
    index += 1
  }
  index
}

///|
fn LoomMiniProjectedCursor::new(
  atoms : Array[LoomMiniProjectedAtom],
) -> LoomMiniProjectedCursor {
  { atoms, offset: 0 }
}

///|
fn loom_mini_build_projected_doc(
  builder : @mini.MiniDocBuilder,
  expr : LoomMiniExpr,
  atoms : Array[LoomMiniProjectedAtom],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let cursor = LoomMiniProjectedCursor::new(atoms)
  let doc = match loom_mini_lower_expr(builder, expr, cursor) {
    Ok(doc) => doc
    Err(msg) => return Err(msg)
  }
  if cursor.offset != atoms.length() {
    return Err("internal loom mini atom grouping mismatch")
  }
  Ok(doc)
}

///|
fn loom_mini_lower_expr(
  builder : @mini.MiniDocBuilder,
  expr : LoomMiniExpr,
  cursor : LoomMiniProjectedCursor,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  match expr {
    AtomGroupExpr(raw_atoms) =>
      loom_mini_lower_atom_group(builder, raw_atoms, cursor)
    StackExpr(children) => {
      let docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
      for child in children {
        match loom_mini_lower_expr(builder, child, cursor) {
          Ok(doc) => docs.push(doc)
          Err(msg) => return Err(msg)
        }
      }
      builder.stack(docs)
    }
    FastExpr(inner, factor) =>
      match loom_mini_lower_expr(builder, inner, cursor) {
        Ok(doc) => builder.fast(doc, @pattern.Rational::from_int(factor))
        Err(msg) => Err(msg)
      }
    SlowExpr(inner, factor) =>
      match loom_mini_lower_expr(builder, inner, cursor) {
        Ok(doc) => builder.slow(doc, @pattern.Rational::from_int(factor))
        Err(msg) => Err(msg)
      }
  }
}

///|
fn loom_mini_lower_atom_group(
  builder : @mini.MiniDocBuilder,
  raw_atoms : Array[LoomMiniRawAtom],
  cursor : LoomMiniProjectedCursor,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  for _ in raw_atoms {
    if cursor.offset >= cursor.atoms.length() {
      return Err("internal loom mini atom grouping mismatch")
    }
    match loom_mini_atom_doc(builder, cursor.atoms[cursor.offset]) {
      Ok(doc) => docs.push(doc)
      Err(msg) => return Err(msg)
    }
    cursor.offset += 1
  }
  builder.sequence(docs)
}

///|
fn loom_mini_atom_doc(
  builder : @mini.MiniDocBuilder,
  atom : LoomMiniProjectedAtom,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let id = match loom_mini_pattern_node_id(atom.id) {
    Ok(id) => id
    Err(msg) => return Err(msg)
  }
  match atom.kind {
    SoundAtom => builder.sound_atom(id, atom.text)
    NoteAtom => builder.note_atom(id, atom.text)
  }
}

///|
fn loom_mini_pattern_node_id(
  value : String,
) -> Result[@identity.PatternNodeId, String] {
  let result = try? @identity.PatternNodeId::from_string(value)
  match result {
    Ok(id) => Ok(id)
    Err(_) => Err("internal loom mini id was invalid: \{value}")
  }
}
