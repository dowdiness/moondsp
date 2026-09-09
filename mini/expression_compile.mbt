///|
priv struct MiniDefinition {
  id : String
  body : ResolvedMiniExpr
}

///|
priv struct ResolvedMiniExpr {
  span : MiniSpan
  node : ResolvedMiniExprNode
}

///|
priv enum ResolvedMiniExprNode {
  Literal(MiniLiteral, String, Int)
  Stack(Array[ResolvedMiniExpr])
  Reference(MiniDefinition)
  Apply(ResolvedMiniExpr, MiniTransform)
}

///|
/// Pure name resolution. A definition sees only previously accepted definitions,
/// so forward/self/mutual references cannot enter the validated expression graph.
fn resolve_mini_expr(
  expr : MiniExpr,
  definitions : Map[String, MiniDefinition],
) -> ResolvedMiniExpr raise ParseError {
  let node : ResolvedMiniExprNode = match expr.node {
    Literal(kind, content, offset) => Literal(kind, content, offset)
    Stack(children) =>
      Stack(children.map(child => resolve_mini_expr(child, definitions)))
    Apply(child, transform) =>
      Apply(resolve_mini_expr(child, definitions), transform)
    Reference(name) =>
      match definitions.get(name) {
        Some(definition) => Reference(definition)
        None =>
          raise ParseError(
            "position \{expr.span.start}: undefined pattern '\{name}'; define it before use",
          )
      }
  }
  { span: expr.span, node, }
}

///|
fn MiniCallback::runtime(self : MiniCallback) -> Callback {
  match self {
    Fast(n) => make_fast(@pattern.Rational::from_int(n))
    Slow(n) => make_slow(@pattern.Rational::from_int(n))
    Rev => make_rev()
  }
}

///|
fn MiniCallback::signature(self : MiniCallback) -> String {
  match self {
    Fast(n) => "fast:\{n}"
    Slow(n) => "slow:\{n}"
    Rev => "rev"
  }
}

///|
fn compile_mini_pattern(
  expr : ResolvedMiniExpr,
  definitions : Map[String, @pattern.Pat[@pattern.ControlMap]],
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  match expr.node {
    Literal(kind, content, _) => {
      let pat = match kind {
        Sound => parse_sound_notation(content)
        Note => parse_note_notation(content)
        Chord => parse_chord_notation(content)
      }
      let tag = match kind {
        Sound => "s"
        Note => "n"
        Chord => "c"
      }
      pat.material("literal:\{content.length()}:\{content}:" + tag)
    }
    Stack(children) => {
      let pats = children.map(child => compile_mini_pattern(child, definitions))
      @pattern.stack(pats)
    }
    Reference(definition) =>
      match definitions.get(definition.id) {
        Some(pat) => pat.named_entry(definition.id)
        None => {
          let pat = compile_mini_pattern(definition.body, definitions)
          definitions[definition.id] = pat
          pat.named_entry(definition.id)
        }
      }
    Apply(child, transform) => {
      let pat = compile_mini_pattern(child, definitions)
      let transformed = match transform {
        Fast(n) => pat.fast(n)
        Slow(n) => pat.slow(n)
        Rev => pat.rev()
        Degrade(p) => pat.degrade_by(p)
        Control(key, value) =>
          @pattern.merge_control(
            pat,
            @pattern.Pat::pure(@pattern.ControlMap::single(key, value)),
          )
        Every(n, callback) => @pattern.every(n, callback.runtime(), pat)
        Jux(callback) => pat.jux(callback.runtime())
      }
      transformed.entry_transform(transform.entry_signature())
    }
  }
}

///|
fn compile_mini_doc(
  expr : ResolvedMiniExpr,
  builder : MiniDocBuilder,
  definitions : Map[String, @pattern.PatternDoc[@pattern.ControlMap]],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  match expr.node {
    Literal(kind, content, offset) =>
      match kind {
        Sound =>
          parse_sound_doc_notation(content, builder, source_offset=offset)
        Note => parse_note_doc_notation(content, builder, source_offset=offset)
        Chord =>
          parse_chord_doc_notation(content, builder, source_offset=offset)
      }
    Stack(children) =>
      builder.stack_doc(
        children.map(child => compile_mini_doc(child, builder, definitions)),
      )
    Reference(definition) => {
      let doc = match definitions.get(definition.id) {
        Some(doc) => doc
        None => {
          let doc = compile_mini_doc(definition.body, builder, definitions)
          definitions[definition.id] = doc
          doc
        }
      }
      let id = builder.atom_id_at(
        "binding",
        "\{definition.id}:\{doc.root().value()}",
        expr.span.start,
        expr.span.end,
      )
      @pattern.PatternDoc::reference(id~, definition=doc)
    }
    Apply(child, transform) => {
      let doc = compile_mini_doc(child, builder, definitions)
      match transform {
        Fast(n) => builder.fast_doc(doc, n)
        Slow(n) => builder.slow_doc(doc, n)
        Rev => builder.rev_doc(doc)
        Degrade(p) =>
          builder.degrade_doc(doc, p, stable_seed(doc.root().value()))
        Control(key, value) => builder.scalar_control_doc(doc, key, value)
        Every(n, callback) =>
          builder.every_doc(doc, n, callback.runtime(), callback.signature())
        Jux(callback) =>
          builder.jux_doc(doc, callback.runtime(), callback.signature())
      }
    }
  }
}

///|
fn MiniTransform::entry_signature(self : MiniTransform) -> String {
  match self {
    Fast(n) => "/fast:\{n.num}:\{n.den}"
    Slow(n) => "/slow:\{n.num}:\{n.den}"
    Rev => "/rev"
    Degrade(p) => "/degrade:\{p}"
    Control(key, value) => "/control:\{key}:\{value}"
    Every(n, callback) => "/every:\{n}:" + callback.signature()
    Jux(callback) => "/jux:" + callback.signature()
  }
}
