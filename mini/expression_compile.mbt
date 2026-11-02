///|
fn MiniCallback::operation(self : MiniCallback) -> @pattern.TimeTransform {
  match self {
    Fast(n) => @pattern.TimeTransform::Fast(@pattern.Rational::from_int(n))
    Slow(n) => @pattern.TimeTransform::Slow(@pattern.Rational::from_int(n))
    Rev => @pattern.TimeTransform::Reverse
  }
}

///|
priv struct MiniDefinition {
  body : @pattern.PatternDoc[@pattern.ControlMap]
  name_span : MiniSpan
}

///|
fn MiniDefinition::MiniDefinition(
  body : @pattern.PatternDoc[@pattern.ControlMap],
  name_span : MiniSpan,
) -> MiniDefinition {
  { body, name_span, }
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
  Reference(String, MiniDefinition)
  Apply(ResolvedMiniExpr, MiniTransform)
}

///|
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
      match unique_definition(definitions.get(name).iter(), false) {
        Ok(definition) => Reference(name, definition)
        Err(_) =>
          raise ParseError(
            "position \{expr.span.start}: undefined pattern '\{name}'; define it before use",
          )
      }
  }
  ResolvedMiniExpr(expr.span, node)
}

///|
fn ResolvedMiniExpr::ResolvedMiniExpr(
  span : MiniSpan,
  node : ResolvedMiniExprNode,
) -> ResolvedMiniExpr {
  { span, node, }
}

///|
fn compile_mini_doc(
  expr : ResolvedMiniExpr,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  match expr.node {
    Literal(kind, content, offset) => {
      let doc = match kind {
        Sound =>
          parse_sound_doc_notation(content, builder, source_offset=offset)
        Note => parse_note_doc_notation(content, builder, source_offset=offset)
        Chord =>
          parse_chord_doc_notation(content, builder, source_offset=offset)
        Silence => {
          let id = builder.atom_id_at("silence", "~", offset, offset + 9)
          builder.rest_doc(id)
        }
      }
      match builder.source_frame_at(offset, offset + content.length()) {
        Some(frame) =>
          doc.with_source_frame(frame~) catch {
            _ => raise ParseError("internal source-frame construction failed")
          }
        None => {
          if builder.origins is Some(_) && !(kind is Silence) {
            raise ParseError(
              "position \{offset}: missing source-frame identity",
            )
          }
          doc
        }
      }
    }
    Stack(children) =>
      builder.stack_doc(children.map(child => compile_mini_doc(child, builder)))
    Reference(name, definition) => {
      let id = builder.atom_id_at(
        "binding",
        name,
        expr.span.start,
        expr.span.end,
      )
      builder.reference_doc(
        id,
        expr.span.start,
        expr.span.end,
        definition.name_span,
        definition.body,
      )
    }
    Apply(child, transform) => {
      let doc = compile_mini_doc(child, builder)
      match transform {
        Fast(n) => builder.fast_doc(doc, n)
        Slow(n) => builder.slow_doc(doc, n)
        Gate(factor) => builder.gate_doc(doc, factor)
        Rev => builder.rev_doc(doc)
        Degrade(p) => builder.degrade_doc(doc, p)
        Control(key, value) => builder.control_value_doc(doc, key, value)
        Filter(kind, frequency_hz, resonance) => {
          let filtered = builder.control_value_doc(
            doc,
            kind.control_key(),
            frequency_hz,
          )
          match resonance {
            None => filtered
            Some(q) =>
              builder.control_value_doc(
                filtered,
                kind.resonance_control_key(),
                q,
              )
          }
        }
        Every(n, callback) => builder.every_doc(doc, n, callback.operation())
        Jux(callback) => builder.jux_doc(doc, callback.operation())
      }
    }
  }
}
