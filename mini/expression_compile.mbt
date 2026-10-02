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
priv struct MiniDefinition[A] {
  body : A
  name_span : MiniSpan
}

///|
fn[A] MiniDefinition::MiniDefinition(
  body : A,
  name_span : MiniSpan,
) -> MiniDefinition[A] {
  { body, name_span, }
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
  Reference(String, MiniDefinition[A])
  Apply(ResolvedMiniExpr[A], MiniTransform)
}

///|
fn[A] resolve_mini_expr(
  expr : MiniExpr,
  definitions : Map[String, MiniDefinition[A]],
) -> ResolvedMiniExpr[A] raise ParseError {
  let node : ResolvedMiniExprNode[A] = match expr.node {
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
        Silence => @pattern.Pat::silence()
      }
      pat.material()
    }
    Stack(children) => {
      let pats = children.map(child => compile_mini_pattern(child))
      @pattern.stack(pats)
    }
    Reference(name, definition) => definition.body.named_entry(name)
    Apply(child, transform) => {
      let pat = compile_mini_pattern(child)
      match transform {
        Fast(n) => pat.fast(n)
        Slow(n) => pat.slow(n)
        Gate(factor) => pat.gate(factor)
        Rev => pat.rev()
        Degrade(p, seed) => pat.degrade_by(p, seed=seed.unwrap_or(42))
        Transpose(semitones) => pat.transpose(semitones)
        Steps(scale, steps) => pat.steps(scale, steps)
        Lowest => pat.lowest()
        Voicing(low, high, count) =>
          match count {
            Some(n) => pat.voicing(low, high, count=n)
            None => pat.voicing(low, high)
          }
        Mask(mask) => pat.mask(mask)
        Tail(cycles, kind, content, _) => {
          guard cycles <= pat.entry_period() else {
            raise ParseError(
              "tail() duration exceeds the pattern entry period; specify a shorter duration",
            )
          }
          let replacement = match kind {
            Sound => parse_sound_notation(content)
            Note => parse_note_notation(content)
            Chord => parse_chord_notation(content)
            Silence => @pattern.Pat::silence()
          }
          pat.tail(replacement, cycles~) catch {
            _ => raise ParseError("tail() duration must be positive")
          }
        }
        PhaseTranspose(from, to, semitones) =>
          pat.phase_transpose(semitones, from, to~)
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
        Silence => {
          let id = builder.atom_id_at("silence", "~", offset, offset + 9)
          @pattern.PatternDoc::silence(id~)
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
        Degrade(p, seed) =>
          builder.degrade_doc(
            doc,
            p,
            seed.unwrap_or(stable_seed(doc.root().value())),
          )
        Transpose(semitones) =>
          builder.composition_doc(
            doc,
            "transpose:\{semitones}",
            @pattern.CompositionOp::Transpose(semitones),
          )
        Steps(scale, steps) =>
          builder.composition_doc(
            doc,
            "steps:\{mini_scale_signature(scale)}:\{steps}",
            @pattern.CompositionOp::Steps(scale, steps),
          )
        Lowest =>
          builder.composition_doc(doc, "lowest", @pattern.CompositionOp::Lowest)
        Voicing(low, high, count) =>
          builder.composition_doc(
            doc,
            "voicing:\{low}:\{high}:\{count.unwrap_or(-1)}",
            @pattern.CompositionOp::Voicing(low, high, count),
          )
        Mask(mask) =>
          builder.composition_doc(
            doc,
            "mask:\{mini_rhythm_signature(mask)}",
            @pattern.CompositionOp::Mask(mask),
          )
        Tail(cycles, kind, content, source_offset) => {
          let replacement = match kind {
            Sound => parse_sound_doc_notation(content, builder, source_offset~)
            Note => parse_note_doc_notation(content, builder, source_offset~)
            Chord => parse_chord_doc_notation(content, builder, source_offset~)
            Silence =>
              @pattern.PatternDoc::silence(
                id=builder.atom_id_at(
                  "silence",
                  "~",
                  source_offset,
                  source_offset + 1,
                ),
              )
          }
          let snapshot = doc.lower() catch {
            _ => raise ParseError("tail() input could not be lowered")
          }
          guard cycles <= snapshot.pat().entry_period() else {
            raise ParseError(
              "tail() duration exceeds the pattern entry period; specify a shorter duration",
            )
          }
          let id = builder.node_id(
            "tail",
            "\{doc.root().value()}:\{replacement.root().value()}:\{cycles.num}:\{cycles.den}",
          )
          match builder.reuse_doc(id, inputs=[doc, replacement]) {
            Some(reused) => reused
            None =>
              doc.tail(id~, replacement~, cycles~) catch {
                _ => raise ParseError("tail() duration or source is invalid")
              }
          }
        }
        PhaseTranspose(from, to, semitones) =>
          builder.composition_doc(
            doc,
            "phase_transpose:\{from.num}:\{from.den}:\{to.num}:\{to.den}:\{semitones}",
            @pattern.CompositionOp::PhaseTranspose(semitones, from, to),
          )
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
