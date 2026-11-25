///|
priv struct NotationProjectionModifier {
  kind : String
  from : Int32
  to : Int32
  value : Double
  args : Array[Int32]
}

///|
priv struct NotationProjectionNode {
  kind : String
  from : Int32
  base_to : Int32
  mut end : Int32
  value : String
  mut parent : Int32?
  children : Array[Int32]
  mut weight : Int32
  modifiers : Array[NotationProjectionModifier]
}

///|
const NOTATION_PROJECTION_NODE_LIMIT : Int32 = 256

///|
/// The source tree the editor draws, children before their parents.
priv struct NotationProjection {
  /// The projected notation, whose spans count from its first code unit.
  content : String
  nodes : Array[NotationProjectionNode]
}

///|
fn NotationProjection::node(
  self : NotationProjection,
  kind : String,
  span : MiniSpan,
  value : String,
  children : Array[Int32],
) -> Int32 raise SourceProblem {
  guard self.nodes.length() < NOTATION_PROJECTION_NODE_LIMIT else {
    raise OverLimit(NotationNodes)
  }
  let index = self.nodes.length()
  for child in children {
    self.nodes[child].parent = Some(index)
  }
  self.nodes.push({
    kind,
    from: span.start,
    base_to: span.end,
    end: span.end,
    value,
    parent: None,
    children,
    weight: 1,
    modifiers: [],
  })
  index
}

///|
/// The node standing for these layers: the only layer, or a parallel node.
fn[W] NotationProjection::layers(
  self : NotationProjection,
  layers : Array[NotationLayer[W]],
) -> Int32 raise SourceProblem {
  let roots = layers.map(layer => self.layer(layer))
  guard roots.length() > 1 else { return roots[0] }
  self.node(
    "parallel",
    { start: layers[0].span.start, end: layers[layers.length() - 1].span.end, },
    "",
    roots,
  )
}

///|
/// The node standing for a layer: its only step, or a sequence node.
fn[W] NotationProjection::layer(
  self : NotationProjection,
  layer : NotationLayer[W],
) -> Int32 raise SourceProblem {
  let children = layer.steps.map(step => self.step(step))
  for index, step in layer.steps {
    self.nodes[children[index]].weight = step.slots()
  }
  guard children.length() > 1 || layer.timing is RelativeDurations else {
    return children[0]
  }
  self.node("sequence", layer.span, "", children)
}

///|
fn[W] NotationProjection::step(
  self : NotationProjection,
  step : NotationStep[W],
) -> Int32 raise SourceProblem {
  let index = match step.body {
    Rest(span) => self.node("atom", span, "~", [])
    Word(_, span) => self.node("atom", span, self.word_text(span), [])
    Group(layers, span) => self.node("group", span, "", [self.layers(layers)])
  }
  let modifiers : Array[NotationProjectionModifier] = step.modifiers.map(modifier => {
    let (kind, value, args) = match modifier.kind {
      Euclid(_, written~) =>
        (
          "euclid",
          written.pulses.to_double(),
          [written.pulses, written.steps, written.rotation],
        )
      Repeat(n) => ("repeat", n.to_double(), [])
      Slow(n) => ("slow", n.to_double(), [])
      Degrade(..) => ("degrade", 0.5, [])
    }
    { kind, from: modifier.span.start, to: modifier.span.end, value, args, }
  })
  if step.weight is Some(weight) {
    modifiers.push({
      kind: "weight",
      from: weight.span.start,
      to: weight.span.end,
      value: weight.slots.to_double(),
      args: [],
    })
  }
  // The editor reads modifiers in written order.
  modifiers.sort_by_key(modifier => modifier.from)
  let node = self.nodes[index]
  for modifier in modifiers {
    node.modifiers.push(modifier)
    node.end = modifier.to
  }
  index
}

///|
fn NotationProjection::word_text(
  self : NotationProjection,
  span : MiniSpan,
) -> String {
  self.content[span.start:span.end].to_owned()
}

///|
fn projection_modifier_json(modifier : NotationProjectionModifier) -> Json {
  {
    "kind": Json(modifier.kind),
    "from": Json(modifier.from),
    "to": Json(modifier.to),
    "value": Json(modifier.value),
    "args": Json::array(modifier.args.map(value => Json(value))),
  }
}

///|
fn projection_node_json(node : NotationProjectionNode) -> Json {
  {
    "kind": Json(node.kind),
    "from": Json(node.from),
    "baseTo": Json(node.base_to),
    "end": Json(node.end),
    "value": Json(node.value),
    "parent": match node.parent {
      Some(parent) => Json(parent)
      None => Json::null()
    },
    "children": Json::array(node.children.map(child => Json(child))),
    "weight": Json(node.weight),
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
  match kind {
    "drum" =>
      project_notation(content, sound_names(), MiniDocBuilder::sound_name_doc, _ => {
        Atom
      })
    "note" =>
      project_notation(content, pitches(), MiniDocBuilder::pitch_doc, _ => Atom)
    "chord" =>
      project_notation(
        content,
        chord_names(),
        MiniDocBuilder::chord_name_doc,
        ChordName::query_work,
      )
    _ => Err("kind must be note, drum, or chord")
  }
}

///|
fn[W] project_notation(
  content : String,
  vocabulary : NotationVocabulary[W],
  word_doc : (MiniDocBuilder, W, MiniSpan) -> ScoreDoc raise SourceProblem,
  word_work : (W) -> MiniQueryWork,
) -> Result[Json, String] {
  let syntax = NotationSyntax::parse(content, vocabulary, at=0) catch {
    problem => return Err(problem.to_string())
  }
  let projection = NotationProjection::{ content, nodes: [], }
  let root = projection.layers(syntax.layers) catch {
    problem => return Err(problem.to_string())
  }
  // A reduced p/q period repeats on the integer-cycle grid after p cycles.
  // Ceil(p/q) is not a repeat span (e.g. 3/2 needs 3 cycles, not 2).
  let pattern = MiniDocBuilder().notation_doc(syntax, word_doc).lower().pat() catch {
      _ => return Err("internal mini PatternDoc lowering failed")
    }
  let span = pattern.entry_period().num.to_double().max(1.0)
  guard span <= 16.0 else {
    return Err("notation entry period exceeds 16 cycles")
  }
  // Projection queries start at zero and cover whole cycles. Reuse the source
  // admission model with that alignment, rather than an arbitrary runtime arc.
  let work = syntax.query_work(word_work~) catch {
    problem => return Err(problem.to_string())
  }
  guard work.estimate(span, aligned=true).allowed() else {
    return Err("notation projection exceeds the bounded query budget")
  }
  Ok({
    "roots": Json::array([Json(root)]),
    "nodes": Json::array(projection.nodes.map(projection_node_json)),
    "span": Json(span),
  })
}
