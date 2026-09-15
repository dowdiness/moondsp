///|
fn MiniCallback::runtime(self : MiniCallback) -> Callback {
  let operation = self.operation()
  fn(pat) { operation.apply(pat) }
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
fn MiniCallback::operation(self : MiniCallback) -> @pattern.TimeTransform {
  match self {
    Fast(n) => @pattern.TimeTransform::Fast(@pattern.Rational::from_int(n))
    Slow(n) => @pattern.TimeTransform::Slow(@pattern.Rational::from_int(n))
    Rev => @pattern.TimeTransform::Reverse
  }
}

///|
priv struct ResolvedMiniExpr[A] {
  span : MiniSpan
  node : ResolvedMiniExprNode[A]
}

///|
priv enum ResolvedMiniExprNode[A] {
  Literal(MiniLiteral, String, Int)
  Stack(Array[ResolvedMiniExpr[A]])
  Reference(String, A)
  Apply(ResolvedMiniExpr[A], MiniTransform)
}

///|
/// Resolve only previously compiled declarations. References retain their values
/// and use-site spans, so compilation needs no name table or definition bodies.
fn[A] resolve_mini_expr(
  expr : MiniExpr,
  definitions : Map[String, A],
) -> ResolvedMiniExpr[A] raise ParseError {
  let node : ResolvedMiniExprNode[A] = match expr.node {
    Literal(kind, content, offset) => Literal(kind, content, offset)
    Stack(children) =>
      Stack(children.map(child => resolve_mini_expr(child, definitions)))
    Apply(child, transform) =>
      Apply(resolve_mini_expr(child, definitions), transform)
    Reference(name) =>
      match definitions.get(name) {
        Some(definition) => Reference(name, definition)
        None =>
          raise ParseError(
            "position \{expr.span.start}: undefined pattern '\{name}'; define it before use",
          )
      }
  }
  ResolvedMiniExpr(expr.span, node)
}

///|
fn[A] ResolvedMiniExpr::ResolvedMiniExpr(
  span : MiniSpan,
  node : ResolvedMiniExprNode[A],
) -> ResolvedMiniExpr[A] {
  { span, node, }
}

///|
fn compile_mini_pattern(
  expr : ResolvedMiniExpr[@pattern.Pat[@pattern.ControlMap]],
) -> @pattern.Pat[@pattern.ControlMap] raise ParseError {
  match expr.node {
    Literal(kind, content, _) => {
      let pat = match kind {
        Sound => parse_sound_notation(content)
        Note => parse_note_notation(content)
        Chord => parse_chord_notation(content)
      }
      pat.material()
    }
    Stack(children) => {
      let pats = children.map(child => compile_mini_pattern(child))
      @pattern.stack(pats)
    }
    Reference(name, pat) => pat.named_entry(name)
    Apply(child, transform) => {
      let pat = compile_mini_pattern(child)
      match transform {
        Fast(n) => pat.fast(n)
        Slow(n) => pat.slow(n)
        Gate(factor) => pat.gate(factor)
        Rev => pat.rev()
        Degrade(p) => pat.degrade_by(p)
        Control(key, value) =>
          @pattern.merge_control(pat, @pattern.control(key, value))
        Filter(kind, frequency_hz, resonance) => {
          let filtered = @pattern.merge_control(
            pat,
            @pattern.control(kind.control_key(), frequency_hz),
          )
          match resonance {
            None => filtered
            Some(q) =>
              @pattern.merge_control(
                filtered,
                @pattern.control(kind.resonance_control_key(), q),
              )
          }
        }
        Every(n, callback) => callback.operation().every(n, pat)
        Jux(callback) => callback.operation().jux(pat)
      }
    }
  }
}

///|
fn compile_mini_doc(
  expr : ResolvedMiniExpr[@pattern.PatternDoc[@pattern.ControlMap]],
  builder : MiniDocBuilder,
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
      builder.stack_doc(children.map(child => compile_mini_doc(child, builder)))
    Reference(name, doc) => {
      let id = builder.atom_id_at(
        "binding",
        name,
        expr.span.start,
        expr.span.end,
      )
      @pattern.PatternDoc::reference(id~, definition=doc)
    }
    Apply(child, transform) => {
      let doc = compile_mini_doc(child, builder)
      match transform {
        Fast(n) => builder.fast_doc(doc, n)
        Slow(n) => builder.slow_doc(doc, n)
        Gate(factor) => builder.gate_doc(doc, factor)
        Rev => builder.rev_doc(doc)
        Degrade(p) =>
          builder.degrade_doc(doc, p, stable_seed(doc.root().value()))
        Control(key, value) => builder.scalar_control_doc(doc, key, value)
        Filter(kind, frequency_hz, resonance) => {
          let filtered = builder.scalar_control_doc(
            doc,
            kind.control_key(),
            frequency_hz,
          )
          match resonance {
            None => filtered
            Some(q) =>
              builder.scalar_control_doc(
                filtered,
                kind.resonance_control_key(),
                q,
              )
          }
        }
        Every(n, callback) => builder.every_doc(doc, n, callback)
        Jux(callback) => builder.jux_doc(doc, callback)
      }
    }
  }
}
