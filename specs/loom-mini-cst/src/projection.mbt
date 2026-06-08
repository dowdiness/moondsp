///|
priv enum LoomMiniAtomKind {
  SoundAtom
  NoteAtom
}

///|
priv enum LoomMiniAtomPostfix {
  StarPostfix(Int)
  SlowPostfix(Int)
  DegradePostfix
  EuclidPostfix(Int, Int, Int)
}

///|
priv struct LoomMiniRawAtom {
  kind : LoomMiniAtomKind
  text : String
  start : Int
  end : Int
  postfixes : Array[LoomMiniAtomPostfix]
}

///|
priv struct LoomMiniProjectedAtom {
  kind : LoomMiniAtomKind
  text : String
  id : String
}

///|
priv enum LoomMiniNotationElement {
  AtomElement(LoomMiniRawAtom)
  SubNotationElement(
    Array[Array[LoomMiniNotationElement]],
    Array[LoomMiniAtomPostfix],
  )
}

///|
priv struct LoomMiniRawNotation {
  layers : Array[Array[LoomMiniNotationElement]]
  atoms : Array[LoomMiniRawAtom]
}

///|
priv struct LoomMiniSubNotationProjection {
  layers : Array[Array[LoomMiniNotationElement]]
  atoms : Array[LoomMiniRawAtom]
  postfixes : Array[LoomMiniAtomPostfix]
}

///|
priv enum LoomMiniMethodCallback {
  FastCallback(Int)
  SlowCallback(Int)
  RevCallback
}

///|
priv enum LoomMiniMethodCall {
  FastMethod(Int)
  SlowMethod(Int)
  RevMethod
  ControlMethod(String, Double)
  JuxMethod(LoomMiniMethodCallback)
  EveryMethod(Int, LoomMiniMethodCallback)
}

///|
type LoomMiniPatternCallback = (@pattern.Pat[@pattern.ControlMap]) -> @pattern.Pat[
  @pattern.ControlMap,
]

///|
priv enum LoomMiniExpr {
  NotationExpr(Array[Array[LoomMiniNotationElement]])
  StackExpr(Array[LoomMiniExpr])
  MethodChainExpr(LoomMiniExpr, Array[LoomMiniMethodCall])
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
  priv source_before_edit : @incr.Signal[String?]
  priv observer : @incr.Observer[
    Result[@pattern.PatternDoc[@pattern.ControlMap], String],
  ]
  priv accepted : @incr.AcceptedDerived[
    @pattern.PatternDoc[@pattern.ControlMap],
    String,
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
  let source_before_edit : @incr.Signal[String?] = @incr.Signal::new(
    rt,
    None,
    label="loom-mini-atom-projection.source-before-edit",
  )
  let mut previous_doc : @pattern.PatternDoc[@pattern.ControlMap]? = None
  let identity_tracker : @loom.ProjectionIdentityTracker[String] = @loom.ProjectionIdentityTracker::new()
  let projected = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      let current_edit = edit.get()
      let edit_source = source_before_edit.get()
      let current_source = parser.source().get_or_abort()
      let diagnostics = parser.diagnostics().get_or_abort()
      if diagnostics.length() > 0 {
        identity_tracker.record_failed_input_with_optional_edit(
          current_source,
          edit_source,
          current_edit,
        )
        return Err("loom mini syntax has diagnostics")
      }
      let raw_projection = match
        loom_mini_collect_raw_projection(parser.syntax_tree().get_or_abort()) {
        Ok(projection) => projection
        Err(msg) => {
          identity_tracker.record_failed_input_with_optional_edit(
            current_source,
            edit_source,
            current_edit,
          )
          return Err(msg)
        }
      }
      let leaves = loom_mini_raw_atom_projection_leaves(raw_projection.atoms)
      let allocate = loom_mini_atom_id_allocator(identity_tracker)
      let stable = identity_tracker.realign_success_with_optional_edit(
        current_source,
        leaves,
        allocate,
        current_edit,
      )
      let atoms = loom_mini_projected_atoms_from_stable(
        raw_projection.atoms,
        stable,
      )
      let builder = @mini.MiniDocBuilder::with_previous(previous_doc)
      match
        loom_mini_build_projected_doc(
          builder,
          previous_doc,
          raw_projection.expr,
          atoms,
        ) {
        Ok(doc) => {
          previous_doc = Some(doc)
          identity_tracker.commit_success(current_source, stable)
          Ok(doc)
        }
        Err(msg) => {
          identity_tracker.record_failed_input_with_optional_edit(
            current_source,
            edit_source,
            current_edit,
          )
          Err(msg)
        }
      }
    },
    label="loom-mini-atom-projection.doc",
  )
  scope.add_cell_ids([projected.id()])
  let observer = scope.add_observer(projected.observe())
  let accepted = scope.accepted_memo(
    () => projected.get(),
    label="loom-mini-atom-projection.accepted",
  )
  { parser, scope, edit, source_before_edit, observer, accepted }
}

///|
/// The last successfully projected doc, retained across parse errors. Returns
/// `None` until the first successful parse.
pub fn LoomMiniAtomProjection::accepted_doc(
  self : LoomMiniAtomProjection,
) -> @pattern.PatternDoc[@pattern.ControlMap]? {
  self.accepted.accepted_or_abort()
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
  self.source_before_edit.set(Some(self.parser.source().read_or_abort()))
  self.edit.set(Some(edit))
  self.parser.apply_edit(edit, new_source)
}

///|
pub fn LoomMiniAtomProjection::set_source(
  self : LoomMiniAtomProjection,
  source : String,
) -> Unit {
  self.source_before_edit.set(None)
  self.edit.set(None)
  self.parser.set_source(source)
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
  match root.direct_children_of_kind(DollarStackNode.to_raw()) {
    [dollar_stack, ..] => loom_mini_collect_dollar_stack_expr(dollar_stack)
    [] =>
      match root.direct_children_of_kind(StackCallNode.to_raw()) {
        [stack_call, ..] => loom_mini_collect_stack_expr(stack_call)
        [] => {
          let (kind, call) = match
            root.direct_children_of_kind(CallNode.to_raw()) {
            [call, ..] => (SoundAtom, call)
            [] =>
              match
                root.direct_children_of_kind(NoteCallNode.to_raw()) {
                [call, ..] => (NoteAtom, call)
                [] =>
                  return Err(
                    "loom atom projection only supports s(...), note(...), stack(...), or $: lines",
                  )
              }
          }
          loom_mini_collect_atom_group_expr(call, kind)
        }
      }
  }
}

///|
fn loom_mini_collect_dollar_stack_expr(
  dollar_stack : @seam.SyntaxNode,
) -> Result[LoomMiniRawProjection, String] {
  let initial_children : Array[LoomMiniExpr] = []
  let initial_atoms : Array[LoomMiniRawAtom] = []
  let (children, atoms) = for child in dollar_stack.children();
                              children = initial_children,
                              atoms = initial_atoms {
    if child.kind() != DollarLineNode.to_raw() {
      continue children, atoms
    }
    let projection = match loom_mini_collect_raw_projection(child) {
      Ok(projection) => projection
      Err(msg) => return Err(msg)
    }
    let next_children = children.copy()
    let next_atoms = atoms.copy()
    next_children.push(projection.expr)
    for atom in projection.atoms {
      next_atoms.push(atom)
    }
    continue next_children, next_atoms
  } nobreak {
    (children, atoms)
  }
  if children.length() == 0 {
    return Err("loom atom projection expected dollar stack lines")
  }
  Ok({ expr: StackExpr(children), atoms })
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
  let notation = match loom_mini_collect_call_notation(call, kind) {
    Ok(notation) => notation
    Err(msg) => return Err(msg)
  }
  Ok({ expr: NotationExpr(notation.layers), atoms: notation.atoms })
}

///|
fn loom_mini_apply_method_expr(
  root : @seam.SyntaxNode,
  base : LoomMiniExpr,
) -> Result[LoomMiniExpr, String] {
  let method_nodes = root.direct_children_of_kind(MethodCallNode.to_raw())
  if method_nodes.length() == 0 {
    return Ok(base)
  }
  let methods : Array[LoomMiniMethodCall] = []
  for call in method_nodes {
    match loom_mini_collect_method_call(call) {
      Ok(call_ir) => methods.push(call_ir)
      Err(msg) => return Err(msg)
    }
  }
  Ok(MethodChainExpr(base, methods))
}

///|
fn loom_mini_collect_method_call(
  call : @seam.SyntaxNode,
) -> Result[LoomMiniMethodCall, String] {
  let names = call.direct_tokens_of_kind(MethodNameToken.to_raw())
  let name = match names {
    [] => return Err("loom atom projection expected method name")
    [token, ..] => token.text()
  }
  let commas = call.direct_tokens_of_kind(CommaToken.to_raw())
  let numbers = call.direct_tokens_of_kind(NumberToken.to_raw())
  if name == "fast" || name == "slow" {
    loom_mini_collect_rate_method_call(name, names, numbers, commas)
  } else if name == "rev" {
    loom_mini_collect_rev_method_call(names, numbers, commas)
  } else if name == "cutoff" || name == "gain" || name == "pan" {
    loom_mini_collect_control_method_call(name, names, numbers, commas)
  } else if name == "jux" {
    loom_mini_collect_jux_method_call(names, numbers, commas)
  } else if name == "every" {
    loom_mini_collect_every_method_call(names, numbers, commas)
  } else {
    Err(loom_mini_supported_method_error())
  }
}

///|
fn loom_mini_collect_rate_method_call(
  name : String,
  names : Array[@seam.SyntaxToken],
  numbers : Array[@seam.SyntaxToken],
  commas : Array[@seam.SyntaxToken],
) -> Result[LoomMiniMethodCall, String] {
  if commas.length() > 0 {
    return Err(loom_mini_supported_method_error())
  }
  if names.length() != 1 {
    return Err("loom atom projection expected numeric method argument")
  }
  let number = match numbers {
    [token] => token.text()
    _ => return Err("loom atom projection expected method argument")
  }
  let factor = match loom_mini_parse_positive_int(number) {
    Ok(n) => n
    Err(msg) => return Err(msg)
  }
  if name == "fast" {
    Ok(FastMethod(factor))
  } else {
    Ok(SlowMethod(factor))
  }
}

///|
fn loom_mini_collect_rev_method_call(
  names : Array[@seam.SyntaxToken],
  numbers : Array[@seam.SyntaxToken],
  commas : Array[@seam.SyntaxToken],
) -> Result[LoomMiniMethodCall, String] {
  if names.length() != 1 || numbers.length() != 0 || commas.length() != 0 {
    return Err("loom atom projection expected .rev() with no arguments")
  }
  Ok(RevMethod)
}

///|
fn loom_mini_collect_control_method_call(
  name : String,
  names : Array[@seam.SyntaxToken],
  numbers : Array[@seam.SyntaxToken],
  commas : Array[@seam.SyntaxToken],
) -> Result[LoomMiniMethodCall, String] {
  if commas.length() > 0 {
    return Err(loom_mini_supported_method_error())
  }
  if names.length() != 1 {
    return Err("loom atom projection expected numeric method argument")
  }
  let number = match numbers {
    [token] => token.text()
    _ => return Err("loom atom projection expected method argument")
  }
  let value = match loom_mini_parse_double(number) {
    Ok(value) => value
    Err(msg) => return Err(msg)
  }
  Ok(ControlMethod(name, value))
}

///|
fn loom_mini_collect_jux_method_call(
  names : Array[@seam.SyntaxToken],
  numbers : Array[@seam.SyntaxToken],
  commas : Array[@seam.SyntaxToken],
) -> Result[LoomMiniMethodCall, String] {
  if names.length() != 2 || commas.length() != 0 {
    return Err("loom atom projection expected jux(callback)")
  }
  let callback = match
    loom_mini_collect_method_callback(names[1].text(), numbers, "jux") {
    Ok(callback) => callback
    Err(msg) => return Err(msg)
  }
  Ok(JuxMethod(callback))
}

///|
fn loom_mini_collect_every_method_call(
  names : Array[@seam.SyntaxToken],
  numbers : Array[@seam.SyntaxToken],
  commas : Array[@seam.SyntaxToken],
) -> Result[LoomMiniMethodCall, String] {
  if commas.length() != 1 {
    return Err("loom atom projection expected every(n, callback)")
  }
  let comma_start = commas[0].start()
  if names.length() != 2 || names[1].start() <= comma_start {
    return Err("loom atom projection expected every(n, callback)")
  }
  let n_numbers = numbers.filter(fn(token) { token.start() < comma_start })
  let callback_numbers = numbers.filter(fn(token) {
    token.start() > comma_start
  })
  let n_text = match n_numbers {
    [token] => token.text()
    _ => return Err("loom atom projection expected every(n, callback)")
  }
  let n = match loom_mini_parse_positive_int(n_text) {
    Ok(n) => n
    Err(msg) => return Err(msg)
  }
  let callback = match
    loom_mini_collect_method_callback(
      names[1].text(),
      callback_numbers,
      "every",
    ) {
    Ok(callback) => callback
    Err(msg) => return Err(msg)
  }
  Ok(EveryMethod(n, callback))
}

///|
fn loom_mini_collect_method_callback(
  name : String,
  numbers : Array[@seam.SyntaxToken],
  calling_method : String,
) -> Result[LoomMiniMethodCallback, String] {
  if name == "fast" || name == "slow" {
    let number = match numbers {
      [token] => token.text()
      _ =>
        return Err(
          "loom atom projection expected \{calling_method}(\{name}(N)) callback argument",
        )
    }
    let factor = match loom_mini_parse_positive_int(number) {
      Ok(n) => n
      Err(msg) => return Err(msg)
    }
    if name == "fast" {
      Ok(FastCallback(factor))
    } else {
      Ok(SlowCallback(factor))
    }
  } else if name == "rev" {
    if numbers.length() != 0 {
      return Err(
        "loom atom projection expected \{calling_method}(rev) callback with no arguments",
      )
    }
    Ok(RevCallback)
  } else {
    Err(
      "loom atom projection \{calling_method}() callback must be fast(N), slow(N), or rev",
    )
  }
}

///|
fn loom_mini_supported_method_error() -> String {
  "loom atom projection only supports .fast(N), .slow(N), .rev(), .cutoff(N), .gain(N), .pan(N), .jux(...), or .every(...) methods"
}

///|
fn loom_mini_parse_positive_int(text : String) -> Result[Int, String] {
  let result = match loom_mini_parse_int(text) {
    Ok(n) => n
    Err(_) => return Err("loom atom projection expected positive integer")
  }
  if result <= 0 {
    Err("loom atom projection expected positive integer")
  } else {
    Ok(result)
  }
}

///|
fn loom_mini_parse_int(text : String) -> Result[Int, String] {
  let mut index = 0
  let negative = text.length() > 0 && text[0] == '-'
  if negative {
    index = 1
  }
  if index >= text.length() {
    return Err("loom atom projection expected integer")
  }
  let mut result = 0
  while index < text.length() {
    let ch = text[index]
    if ch < '0' || ch > '9' {
      return Err("loom atom projection expected integer")
    }
    result = result * 10 + (ch.to_int() - '0'.to_int())
    index += 1
  }
  if negative {
    Ok(-result)
  } else {
    Ok(result)
  }
}

///|
fn loom_mini_parse_double(text : String) -> Result[Double, String] {
  let mut index = 0
  let negative = text.length() > 0 && text[0] == '-'
  if negative {
    index = 1
  }
  let mut has_digit = false
  let mut result = 0.0
  while index < text.length() && text[index] >= '0' && text[index] <= '9' {
    result = result * 10.0 + (text[index].to_int() - '0'.to_int()).to_double()
    index += 1
    has_digit = true
  }
  if index < text.length() && text[index] == '.' {
    index += 1
    let mut frac = 0.1
    while index < text.length() && text[index] >= '0' && text[index] <= '9' {
      result += (text[index].to_int() - '0'.to_int()).to_double() * frac
      frac *= 0.1
      index += 1
      has_digit = true
    }
  }
  if !has_digit || index != text.length() {
    return Err("loom atom projection expected number")
  }
  if negative {
    Ok(-result)
  } else {
    Ok(result)
  }
}

///|
fn loom_mini_collect_call_notation(
  call : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[LoomMiniRawNotation, String] {
  let notation = match call.direct_children_of_kind(NotationNode.to_raw()) {
    [notation, ..] => notation
    [] => return Err("loom atom projection expected notation")
  }
  loom_mini_collect_notation(notation, kind)
}

///|
fn loom_mini_collect_notation(
  notation : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[LoomMiniRawNotation, String] {
  let layer_nodes = notation.direct_children_of_kind(LayerNode.to_raw())
  if layer_nodes.length() == 0 {
    return Err("loom atom projection expected at least one atom")
  }
  let layers : Array[Array[LoomMiniNotationElement]] = []
  let atoms : Array[LoomMiniRawAtom] = []
  for layer in layer_nodes {
    let collected = match loom_mini_collect_layer(layer, kind) {
      Ok(collected) => collected
      Err(msg) => return Err(msg)
    }
    layers.push(collected.layers[0])
    for atom in collected.atoms {
      atoms.push(atom)
    }
  }
  if atoms.length() == 0 {
    Err("loom atom projection expected at least one atom")
  } else {
    Ok({ layers, atoms })
  }
}

///|
fn loom_mini_collect_layer(
  layer : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[LoomMiniRawNotation, String] {
  let elements : Array[LoomMiniNotationElement] = []
  let atoms : Array[LoomMiniRawAtom] = []
  for child in layer.children() {
    if child.kind() == AtomNode.to_raw() {
      match loom_mini_collect_raw_atom(child, kind) {
        Ok(Some(atom)) => {
          elements.push(AtomElement(atom))
          atoms.push(atom)
        }
        Ok(None) => ()
        Err(msg) => return Err(msg)
      }
    } else if child.kind() == SubNotationNode.to_raw() {
      let collected = match loom_mini_collect_sub_notation(child, kind) {
        Ok(collected) => collected
        Err(msg) => return Err(msg)
      }
      elements.push(SubNotationElement(collected.layers, collected.postfixes))
      for atom in collected.atoms {
        atoms.push(atom)
      }
    }
  }
  if elements.length() == 0 {
    Err("loom atom projection expected at least one atom")
  } else {
    Ok({ layers: [elements], atoms })
  }
}

///|
fn loom_mini_collect_sub_notation(
  sub_notation : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[LoomMiniSubNotationProjection, String] {
  let notation = match loom_mini_collect_notation(sub_notation, kind) {
    Ok(notation) => notation
    Err(msg) => return Err(msg)
  }
  let postfixes = match loom_mini_collect_atom_postfixes(sub_notation) {
    Ok(postfixes) => postfixes
    Err(msg) => return Err(msg)
  }
  Ok({ layers: notation.layers, atoms: notation.atoms, postfixes })
}

///|
fn loom_mini_collect_raw_atom(
  atom : @seam.SyntaxNode,
  kind : LoomMiniAtomKind,
) -> Result[LoomMiniRawAtom?, String] {
  let token = match kind {
    SoundAtom => atom.direct_token_of_kind(IdentToken.to_raw())
    NoteAtom => atom.direct_token_of_kind(NumberToken.to_raw())
  }
  match token {
    Some(token) => {
      let postfixes = match loom_mini_collect_atom_postfixes(atom) {
        Ok(postfixes) => postfixes
        Err(msg) => return Err(msg)
      }
      Ok(Some({
        kind,
        text: token.text(),
        start: token.start(),
        end: token.end(),
        postfixes,
      }))
    }
    None =>
      match kind {
        SoundAtom => {
          let has_number = atom.direct_token_of_kind(NumberToken.to_raw()) is Some(_)
          if has_number {
            Err("loom atom projection expected sound name")
          } else {
            Ok(None)
          }
        }
        NoteAtom => {
          let has_ident = atom.direct_token_of_kind(IdentToken.to_raw()) is Some(_)
          if has_ident {
            Err("loom atom projection expected note number")
          } else {
            Ok(None)
          }
        }
      }
  }
}

///|
fn loom_mini_collect_atom_postfixes(
  atom : @seam.SyntaxNode,
) -> Result[Array[LoomMiniAtomPostfix], String] {
  let postfixes : Array[LoomMiniAtomPostfix] = []
  for child in atom.children() {
    if child.kind() == PostfixNode.to_raw() {
      match loom_mini_collect_atom_postfix(child) {
        Ok(postfix) => postfixes.push(postfix)
        Err(msg) => return Err(msg)
      }
    }
  }
  Ok(postfixes)
}

///|
fn loom_mini_collect_atom_postfix(
  postfix : @seam.SyntaxNode,
) -> Result[LoomMiniAtomPostfix, String] {
  let euclids = postfix.direct_children_of_kind(EuclidNode.to_raw())
  match euclids {
    [euclid] => return loom_mini_collect_euclid_atom_postfix(euclid)
    [_, _, ..] => return Err("loom atom projection expected one euclid postfix")
    [] => ()
  }
  let has_question = postfix.direct_token_of_kind(QuestionToken.to_raw()) is Some(_)
  if has_question {
    if postfix.direct_token_of_kind(StarToken.to_raw()) is Some(_) ||
      postfix.direct_token_of_kind(SlashToken.to_raw()) is Some(_) {
      return Err("loom atom projection expected one atom postfix operator")
    }
    return Ok(DegradePostfix)
  }
  loom_mini_collect_numeric_atom_postfix(postfix)
}

///|
fn loom_mini_collect_euclid_atom_postfix(
  euclid : @seam.SyntaxNode,
) -> Result[LoomMiniAtomPostfix, String] {
  let numbers = euclid.direct_tokens_of_kind(NumberToken.to_raw())
  if numbers.length() != 2 && numbers.length() != 3 {
    return Err("loom atom projection expected euclid (k,n[,rotation])")
  }
  let k = match loom_mini_parse_int(numbers[0].text()) {
    Ok(n) => n
    Err(msg) => return Err(msg)
  }
  let n = match loom_mini_parse_int(numbers[1].text()) {
    Ok(n) => n
    Err(msg) => return Err(msg)
  }
  let rotation = if numbers.length() == 3 {
    match loom_mini_parse_int(numbers[2].text()) {
      Ok(n) => n
      Err(msg) => return Err(msg)
    }
  } else {
    0
  }
  Ok(EuclidPostfix(k, n, rotation))
}

///|
fn loom_mini_collect_numeric_atom_postfix(
  postfix : @seam.SyntaxNode,
) -> Result[LoomMiniAtomPostfix, String] {
  let has_star = postfix.direct_token_of_kind(StarToken.to_raw()) is Some(_)
  let has_slash = postfix.direct_token_of_kind(SlashToken.to_raw()) is Some(_)
  if !has_star && !has_slash {
    return Err(
      "loom atom projection only supports '*', '/', '?', or euclid postfix atoms",
    )
  }
  if has_star && has_slash {
    return Err("loom atom projection expected one atom postfix operator")
  }
  let number = match postfix.direct_token_of_kind(NumberToken.to_raw()) {
    Some(token) => token.text()
    None => return Err("loom atom projection expected atom postfix argument")
  }
  let factor = match loom_mini_parse_positive_int(number) {
    Ok(n) => n
    Err(msg) => return Err(msg)
  }
  if has_star {
    Ok(StarPostfix(factor))
  } else {
    Ok(SlowPostfix(factor))
  }
}

///|
fn loom_mini_atom_id_allocator(
  tracker : @loom.ProjectionIdentityTracker[String],
) -> (@loom.ProjectionLeaf) -> String {
  let allocator = match tracker.baseline() {
    None => @loom.ProjectionStringIdAllocator::new(loom_mini_atom_id)
    Some(baseline) =>
      @loom.ProjectionStringIdAllocator::from_baseline(
        baseline, loom_mini_atom_id,
      )
  }
  fn(leaf : @loom.ProjectionLeaf) -> String { allocator.allocate(leaf) }
}

///|
fn loom_mini_raw_atom_projection_leaves(
  raw_atoms : Array[LoomMiniRawAtom],
) -> Array[@loom.ProjectionLeaf] {
  raw_atoms.map(fn(atom) { loom_mini_raw_atom_projection_leaf(atom) })
}

///|
fn loom_mini_raw_atom_projection_leaf(
  atom : LoomMiniRawAtom,
) -> @loom.ProjectionLeaf {
  @loom.ProjectionLeaf::new(
    atom.start,
    atom.end,
    loom_mini_atom_identity_key(atom.kind, atom.text),
  )
}

///|
fn loom_mini_projected_atoms_from_stable(
  raw_atoms : Array[LoomMiniRawAtom],
  stable : Array[@loom.StableProjectionLeaf[String]],
) -> Array[LoomMiniProjectedAtom] {
  let atoms : Array[LoomMiniProjectedAtom] = []
  for index in 0..<raw_atoms.length() {
    let raw = raw_atoms[index]
    atoms.push({ kind: raw.kind, text: raw.text, id: stable[index].id })
  }
  atoms
}

///|
fn loom_mini_atom_identity_key(
  kind : LoomMiniAtomKind,
  text : String,
) -> String {
  "\{loom_mini_atom_kind_label(kind)}:\{text}"
}

///|
fn loom_mini_atom_id(key : String, occurrence : Int) -> String {
  "mini:\{key}:\{occurrence}"
}

///|
fn loom_mini_atom_kind_label(kind : LoomMiniAtomKind) -> String {
  match kind {
    SoundAtom => "sound"
    NoteAtom => "note"
  }
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
  previous_doc : @pattern.PatternDoc[@pattern.ControlMap]?,
  expr : LoomMiniExpr,
  atoms : Array[LoomMiniProjectedAtom],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let cursor = LoomMiniProjectedCursor::new(atoms)
  let doc = match loom_mini_lower_expr(builder, previous_doc, expr, cursor) {
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
  previous_doc : @pattern.PatternDoc[@pattern.ControlMap]?,
  expr : LoomMiniExpr,
  cursor : LoomMiniProjectedCursor,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  match expr {
    NotationExpr(layers) => loom_mini_lower_notation(builder, layers, cursor)
    StackExpr(children) => {
      let docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
      for child in children {
        match loom_mini_lower_expr(builder, previous_doc, child, cursor) {
          Ok(doc) => docs.push(doc)
          Err(msg) => return Err(msg)
        }
      }
      builder.stack(docs)
    }
    MethodChainExpr(inner, methods) => {
      let base_doc = match
        loom_mini_lower_expr(builder, previous_doc, inner, cursor) {
        Ok(doc) => doc
        Err(msg) => return Err(msg)
      }
      loom_mini_apply_method_chain(builder, previous_doc, base_doc, methods)
    }
  }
}

///|
fn loom_mini_apply_method_chain(
  builder : @mini.MiniDocBuilder,
  previous_doc : @pattern.PatternDoc[@pattern.ControlMap]?,
  base_doc : @pattern.PatternDoc[@pattern.ControlMap],
  methods : Array[LoomMiniMethodCall],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = for call_ir in methods; doc = base_doc {
    match call_ir {
      FastMethod(factor) =>
        match builder.fast(doc, @pattern.Rational::from_int(factor)) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      SlowMethod(factor) =>
        match builder.slow(doc, @pattern.Rational::from_int(factor)) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      RevMethod =>
        match builder.rev(doc) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      ControlMethod(key, value) =>
        match loom_mini_apply_control_method(previous_doc, doc, key, value) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      JuxMethod(callback) =>
        match loom_mini_apply_jux_method(doc, callback) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      EveryMethod(n, callback) =>
        match loom_mini_apply_every_method(doc, n, callback) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
    }
  } nobreak {
    doc
  }
  Ok(doc)
}

///|
fn loom_mini_apply_control_method(
  previous_doc : @pattern.PatternDoc[@pattern.ControlMap]?,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  key : String,
  value : Double,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let control_id = match
    loom_mini_pattern_node_id(
      "mini:control:\{doc.root().value()}:\{key}:\{value}",
    ) {
    Ok(id) => id
    Err(msg) => return Err(msg)
  }
  let id = match
    loom_mini_pattern_node_id(
      "mini:merge_control:\{doc.root().value()}:\{key}:\{value}",
    ) {
    Ok(id) => id
    Err(msg) => return Err(msg)
  }
  match loom_mini_reuse_previous_doc(previous_doc, id) {
    Ok(Some(doc)) => return Ok(doc)
    Ok(None) => ()
    Err(msg) => return Err(msg)
  }
  let control_doc = match loom_mini_reuse_previous_doc(previous_doc, control_id) {
    Ok(Some(doc)) => doc
    Ok(None) =>
      @pattern.PatternDoc::pure(
        id=control_id,
        value=@pattern.ControlMap::single(key, value),
      )
    Err(msg) => return Err(msg)
  }
  let result = try? @pattern.PatternDoc::merge_control(
    id~,
    left=doc,
    right=control_doc,
  )
  match result {
    Ok(next) => Ok(next)
    Err(_) => Err("internal loom mini PatternDoc construction failed")
  }
}

///|
fn loom_mini_reuse_previous_doc(
  previous_doc : @pattern.PatternDoc[@pattern.ControlMap]?,
  id : @identity.PatternNodeId,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap]?, String] {
  match previous_doc {
    None => Ok(None)
    Some(previous) =>
      if previous.contains_node(id) {
        let result = try? previous.subdoc(root=id)
        match result {
          Ok(doc) => Ok(Some(doc))
          Err(_) =>
            Err("internal loom mini id could not be reused: \{id.value()}")
        }
      } else {
        Ok(None)
      }
  }
}

///|
fn loom_mini_apply_jux_method(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  callback : LoomMiniMethodCallback,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let signature = loom_mini_callback_signature(callback)
  let id = match
    loom_mini_pattern_node_id("mini:jux:\{doc.root().value()}:\{signature}") {
    Ok(id) => id
    Err(msg) => return Err(msg)
  }
  let f = loom_mini_callback_function(callback)
  let result = try? doc.jux(id~, f~)
  match result {
    Ok(next) => Ok(next)
    Err(_) => Err("internal loom mini PatternDoc construction failed")
  }
}

///|
fn loom_mini_apply_every_method(
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  n : Int,
  callback : LoomMiniMethodCallback,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let signature = loom_mini_callback_signature(callback)
  let id = match
    loom_mini_pattern_node_id(
      "mini:every:\{doc.root().value()}:\{n}:\{signature}",
    ) {
    Ok(id) => id
    Err(msg) => return Err(msg)
  }
  let f = loom_mini_callback_function(callback)
  let result = try? doc.every(id~, n~, f~)
  match result {
    Ok(next) => Ok(next)
    Err(_) => Err("internal loom mini PatternDoc construction failed")
  }
}

///|
fn loom_mini_callback_signature(callback : LoomMiniMethodCallback) -> String {
  match callback {
    FastCallback(factor) => "fast:\{factor}"
    SlowCallback(factor) => "slow:\{factor}"
    RevCallback => "rev"
  }
}

///|
fn loom_mini_callback_function(
  callback : LoomMiniMethodCallback,
) -> LoomMiniPatternCallback {
  match callback {
    FastCallback(factor) =>
      fn(p) { p.fast(@pattern.Rational::from_int(factor)) }
    SlowCallback(factor) =>
      fn(p) { p.slow(@pattern.Rational::from_int(factor)) }
    RevCallback => fn(p) { p.rev() }
  }
}

///|
fn loom_mini_lower_notation(
  builder : @mini.MiniDocBuilder,
  layers : Array[Array[LoomMiniNotationElement]],
  cursor : LoomMiniProjectedCursor,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  for layer in layers {
    match loom_mini_lower_layer(builder, layer, cursor) {
      Ok(doc) => docs.push(doc)
      Err(msg) => return Err(msg)
    }
  }
  builder.stack(docs)
}

///|
fn loom_mini_lower_layer(
  builder : @mini.MiniDocBuilder,
  elements : Array[LoomMiniNotationElement],
  cursor : LoomMiniProjectedCursor,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  for element in elements {
    match loom_mini_lower_element(builder, element, cursor) {
      Ok(doc) => docs.push(doc)
      Err(msg) => return Err(msg)
    }
  }
  builder.sequence(docs)
}

///|
fn loom_mini_lower_element(
  builder : @mini.MiniDocBuilder,
  element : LoomMiniNotationElement,
  cursor : LoomMiniProjectedCursor,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  match element {
    AtomElement(raw) => {
      if cursor.offset >= cursor.atoms.length() {
        return Err("internal loom mini atom grouping mismatch")
      }
      let atom_doc = match
        loom_mini_atom_doc(builder, cursor.atoms[cursor.offset]) {
        Ok(doc) => doc
        Err(msg) => return Err(msg)
      }
      cursor.offset += 1
      loom_mini_apply_postfixes(builder, atom_doc, raw.postfixes)
    }
    SubNotationElement(layers, postfixes) => {
      let doc = match loom_mini_lower_notation(builder, layers, cursor) {
        Ok(doc) => doc
        Err(msg) => return Err(msg)
      }
      loom_mini_apply_postfixes(builder, doc, postfixes)
    }
  }
}

///|
fn loom_mini_apply_postfixes(
  builder : @mini.MiniDocBuilder,
  base_doc : @pattern.PatternDoc[@pattern.ControlMap],
  postfixes : Array[LoomMiniAtomPostfix],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = for postfix in postfixes; doc = base_doc {
    match postfix {
      StarPostfix(factor) =>
        match builder.fast(doc, @pattern.Rational::from_int(factor)) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      SlowPostfix(factor) =>
        match builder.slow(doc, @pattern.Rational::from_int(factor)) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      DegradePostfix =>
        match builder.degrade(doc, 0.5) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
      EuclidPostfix(k, n, rotation) =>
        match builder.euclid(doc, k, n, rotation) {
          Ok(next) => continue next
          Err(msg) => return Err(msg)
        }
    }
  } nobreak {
    doc
  }
  Ok(doc)
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
