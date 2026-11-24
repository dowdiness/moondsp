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
  /// The resolved body, which playback admission assesses.
  syntax : ResolvedMiniExpr
  body : Score
  name_span : MiniSpan
}

///|
priv struct ResolvedMiniExpr {
  span : MiniSpan
  node : ResolvedMiniExprNode
}

///|
priv enum ResolvedMiniExprNode {
  Sounds(NotationSyntax[SoundName])
  Notes(NotationSyntax[Pitch])
  Chords(NotationSyntax[ChordName])
  Silence
  Stack(Array[ResolvedMiniExpr])
  Reference(String, MiniDefinition)
  Apply(ResolvedMiniExpr, MiniTransform[ControlValue])
  /// The instruments of `.s`, and where its argument is written.
  Instruments(ResolvedMiniExpr, NotationSyntax[VoiceName], Int32)
}

///|
/// A control argument as read: its quoted notation parsed, and every value in
/// its control's domain.
type ControlValue = MiniValue[NotationSyntax[ControlNumber]]

///|
/// What an author reads when a control value is outside its domain.
fn control_domain_message(key : @control.Control) -> String {
  match key {
    Attack | Hold | Release =>
      "\{key}() expects seconds between 0 and \{@control.MAX_SECONDS}"
    Room => "room() expects a send between 0 and 1"
    Begin | End => "\{key}() expects a fraction between 0 and 1"
    Speed => "speed() expects a finite number"
    LpfResonance => "lpf() expects finite resonance above 0"
    HpfResonance => "hpf() expects finite resonance above 0"
    Note | Gain | Pan | Lpf | Hpf | Decay | Sustain | SampleNumber =>
      "\{key}() expects a number"
  }
}

///|
/// Reads the argument as a value of `key`. A signal stays between its two
/// range endpoints.
fn ControlArgument::read(
  self : ControlArgument,
  key : @control.Control,
) -> ControlValue raise SourceProblem {
  let (value, admitted) : (ControlValue, Bool) = match self.value {
    Number(number) => (Number(number), key.admits(number))
    Signal(signal) =>
      (Signal(signal), key.admits(signal.low) && key.admits(signal.high))
    Steps(quoted) => {
      let notation = quoted.parse(control_numbers(key))
      let mut admitted = true
      notation.each_word((number, _) => {
        admitted = admitted && key.admits(number.value)
      })
      (Steps(notation), admitted)
    }
  }
  guard admitted else {
    raise Mistake(self.method_at, control_domain_message(key))
  }
  value
}

///|
fn read_transform_controls(
  transform : MiniTransform[ControlArgument],
) -> MiniTransform[ControlValue] raise SourceProblem {
  match transform {
    Fast(n) => Fast(n)
    Slow(n) => Slow(n)
    Gate(n) => Gate(n)
    Rev => Rev
    Degrade(p) => Degrade(p)
    Control(key, argument) => Control(key, argument.read(key))
    Filter(kind, frequency_hz, resonance) => {
      let frequency_hz = frequency_hz.read(kind.control_key())
      let resonance = match resonance {
        Some(q) => Some(q.read(kind.resonance_control_key()))
        None => None
      }
      Filter(kind, frequency_hz, resonance)
    }
    Every(n, callback) => Every(n, callback)
    Jux(callback) => Jux(callback)
  }
}

///|
fn[W] QuotedNotation::parse(
  self : QuotedNotation,
  vocabulary : NotationVocabulary[W],
) -> NotationSyntax[W] raise SourceProblem {
  NotationSyntax::parse(self.text, vocabulary, at=self.at)
}

///|
/// Reads the expression's notation and control values and binds its names,
/// in source order.
fn resolve_mini_expr(
  expr : MiniExpr,
  definitions : Map[String, MiniDefinition],
) -> ResolvedMiniExpr raise SourceProblem {
  let node : ResolvedMiniExprNode = match expr.node {
    Literal(Sound, quoted) => Sounds(quoted.parse(sound_names()))
    Literal(Note, quoted) => Notes(quoted.parse(pitches()))
    Literal(Chord, quoted) => Chords(quoted.parse(chord_names()))
    Silence => Silence
    Stack(children) =>
      Stack(children.map(child => resolve_mini_expr(child, definitions)))
    Apply(child, transform) => {
      let child = resolve_mini_expr(child, definitions)
      Apply(child, read_transform_controls(transform))
    }
    Instruments(child, quoted) => {
      let child = resolve_mini_expr(child, definitions)
      Instruments(child, quoted.parse(voice_names()), quoted.at)
    }
    Reference(name) =>
      match unique_definition(definitions.get(name).iter(), false) {
        Ok(definition) => Reference(name, definition)
        Err(_) =>
          raise Mistake(
            expr.span.start,
            "undefined pattern '\{name}'; define it before use",
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
fn compile_score(
  expr : ResolvedMiniExpr,
  builder : MiniDocBuilder,
) -> Score raise SourceProblem {
  match expr.node {
    Sounds(notation) =>
      Hits(builder.literal_doc(notation, MiniDocBuilder::sound_name_doc))
    Notes(notation) =>
      Notes(NoteDoc(builder.literal_doc(notation, MiniDocBuilder::pitch_doc)))
    Chords(notation) =>
      Notes(
        NoteDoc(builder.literal_doc(notation, MiniDocBuilder::chord_name_doc)),
      )
    Silence => {
      let id = builder.atom_id_at(
        "silence",
        "~",
        expr.span.start,
        expr.span.end,
      )
      Silent(builder.rest_doc(id))
    }
    Stack(children) =>
      Score::stack(
        builder,
        children.map(child => compile_score(child, builder)),
      )
    Reference(name, definition) => {
      let id = builder.atom_id_at(
        "binding",
        name,
        expr.span.start,
        expr.span.end,
      )
      definition.body.map(body => {
        builder.reference_doc(
          id,
          expr.span.start,
          expr.span.end,
          definition.name_span,
          body,
        )
      })
    }
    Instruments(child, notation, at) => {
      guard compile_score(child, builder).notes() is Some(notes) else {
        raise Mistake(
          at, ".s(\"...\") chooses the instrument of notes, and drums have none",
        )
      }
      let instruments = builder.notation_doc(
        notation,
        MiniDocBuilder::instrument_doc,
      )
      Notes(notes.on(builder, instruments))
    }
    Apply(child, transform) => {
      let score = compile_score(child, builder)
      match transform {
        Fast(n) => score.map(doc => builder.fast_doc(doc, n))
        Slow(n) => score.map(doc => builder.slow_doc(doc, n))
        Gate(factor) => score.map(doc => builder.gate_doc(doc, factor))
        Rev => score.map(doc => builder.rev_doc(doc))
        Degrade(p) => score.map(doc => builder.degrade_doc(doc, p))
        Control(key, value) =>
          score.map(doc => builder.control_value_doc(doc, key, value))
        Filter(kind, frequency_hz, resonance) =>
          score.map(doc => {
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
          })
        Every(n, callback) =>
          score.map(doc => builder.every_doc(doc, n, callback.operation()))
        Jux(callback) =>
          score.map(doc => builder.jux_doc(doc, callback.operation()))
      }
    }
  }
}
