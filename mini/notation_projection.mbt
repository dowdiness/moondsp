///|
fn projection_modifier_json(modifier : NotationProjectionModifier) -> Json {
  {
    "kind": modifier.kind.to_json(),
    "from": modifier.from.to_json(),
    "to": modifier.to.to_json(),
    "value": modifier.value.to_json(),
    "args": Json::array(modifier.args.map(value => value.to_json())),
  }
}

///|
fn projection_node_json(node : NotationProjectionNode) -> Json {
  {
    "kind": node.kind.to_json(),
    "from": node.from.to_json(),
    "baseTo": node.base_to.to_json(),
    "end": node.end.to_json(),
    "value": node.value.to_json(),
    "parent": match node.parent {
      Some(parent) => parent.to_json()
      None => Json::null()
    },
    "children": Json::array(node.children.map(child => child.to_json())),
    "weight": node.weight.to_json(),
    "modifiers": Json::array(node.modifiers.map(projection_modifier_json)),
  }
}

///|
/// Parse notation with the production grammar while collecting its source tree.
pub fn project_notation_nodes(
  kind : String,
  content : String,
) -> Result[Json, String] {
  guard content.length() <= 8192 else {
    return Err("notation exceeds 8192 UTF-16 code units")
  }
  let sound = kind == "drum"
  let chord = kind == "chord"
  guard sound || chord || kind == "note" else {
    return Err("kind must be note, drum, or chord")
  }
  if content.is_empty() {
    return Err("position 0: empty notation")
  }
  let parser = NotationParser::new(content, sound~, chord~)
  parser.projection_nodes = Some([])
  let pattern = parser.parse_notation() catch {
    ParseError(message) => return Err(message)
  }
  guard parser.at_end() else {
    return Err("position \{parser.pos}: unexpected trailing notation")
  }
  let nodes = parser.projection_nodes.unwrap()
  let roots = match parser.projection_root {
    Some(root) => [root]
    None => []
  }
  guard !roots.is_empty() else {
    return Err("notation parser produced no source root")
  }
  // A reduced p/q period repeats on the integer-cycle grid after p cycles.
  // Ceil(p/q) is not a repeat span (e.g. 3/2 needs 3 cycles, not 2).
  let span = pattern.entry_period().num.to_double().max(1.0)
  guard span <= 16.0 else {
    return Err("notation entry period exceeds 16 cycles")
  }
  // Projection queries start at zero and cover whole cycles. Reuse the source
  // admission model with that alignment, rather than an arbitrary runtime arc.
  let assessment = NotationParser::new(content, sound~, chord~, assess=true)
  let _ = assessment.parse_notation() catch {
    ParseError(message) => return Err(message)
  }
  guard assessment.query_work.unwrap().estimate(span, aligned=true).allowed() else {
    return Err("notation projection exceeds the bounded query budget")
  }
  Ok({
    "roots": Json::array(roots.map(root => root.to_json())),
    "nodes": Json::array(nodes.map(projection_node_json)),
    "span": span.to_json(),
  })
}
