///|
pub struct MiniDocBuilder {
  priv counters : Map[String, Int32]
  priv origins : SourceMap?
  priv source_atom_by_graph_id : Map[String, @identity.SourceAtomId]
  /// Musical content by node ID. Unlike IDs it omits occurrences and binding
  /// names, so equal expressions get equal content wherever they are written.
  priv contents : Map[String, String]
}

///|
fn mini_doc_id_fragment_char_allowed(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '-' ||
  c == '.' ||
  c == ':'
}

///|
fn mini_doc_id_fragment(value : String) -> String {
  let mut result = ""
  for i in 0..<value.length() {
    let c = value[i]
    if mini_doc_id_fragment_char_allowed(c) {
      result = "\{result}\{value[i:i + 1].to_owned()}"
    } else {
      result = "\{result}_x\{c.to_int()}_"
    }
  }
  result
}

///|
fn MiniDocBuilder::MiniDocBuilder(
  origins~ : SourceMap? = None,
) -> MiniDocBuilder {
  {
    counters: Map([]),
    origins,
    source_atom_by_graph_id: Map([]),
    contents: Map([]),
  }
}

///|
fn MiniDocBuilder::source_frame_at(
  self : MiniDocBuilder,
  content_from : Int32,
  content_to : Int32,
) -> @identity.SourceFrameId? {
  match self.origins {
    Some(origins) => origins.frame_at(content_from, content_to)
    None => None
  }
}

///|
/// Create a mini `PatternDoc` semantic builder for external frontends.
pub fn MiniDocBuilder::new() -> MiniDocBuilder {
  MiniDocBuilder()
}

///|
/// Build a sound atom with a caller-supplied stable node ID.
pub fn MiniDocBuilder::sound_atom(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  name : String,
) -> Result[ScoreDoc, String] {
  match @score.Drum::parse(name) {
    Some(drum) => Ok(self.sound_doc(id, Hit(drum)))
    None => Err("unknown drum name '\{name}'")
  }
}

///|
/// Build a note atom with a caller-supplied stable node ID.
pub fn MiniDocBuilder::note_atom(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  text : String,
) -> Result[ScoreDoc, String] {
  parse_mini_doc_builder_note_text(text).map(pitch => {
    self.sound_doc(id, Note(@score.Instrument::default(), pitch~))
  })
}

///|
fn MiniDocBuilder::chord_tone_id(
  self : MiniDocBuilder,
  chord_id : @identity.PatternNodeId,
  tone_index : Int32,
  midi : Int32,
) -> @identity.PatternNodeId raise SourceProblem {
  self.id("mini:chord-tone:\{chord_id.value()}:\{tone_index}:\{midi}")
}

///|
fn MiniDocBuilder::chord_doc_from_notes(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  notes : Array[Int32],
) -> ScoreDoc raise SourceProblem {
  self.contents[id.value()] = "chord:\{notes.map(note => "\{note}").join(":")}"
  let note_docs : Array[ScoreDoc] = []
  for tone_index, midi in notes {
    let note_id = self.chord_tone_id(id, tone_index, midi)
    match self.source_atom_by_graph_id.get(id.value()) {
      Some(source_atom) =>
        self.source_atom_by_graph_id[note_id.value()] = source_atom
      None => ()
    }
    note_docs.push(
      self.sound_doc(
        note_id,
        Note(@score.Instrument::default(), pitch=midi.to_double()),
      ),
    )
  }
  @pattern.PatternDoc::stack(id~, docs=note_docs) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
/// Build a chord atom with a caller-supplied stable node ID.
/// Expands the chord name into a stack of note docs.
pub fn MiniDocBuilder::chord_atom(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  name : String,
) -> Result[ScoreDoc, String] {
  match @pattern.parse_chord(name) {
    Some(notes) => {
      let doc = self.chord_doc_from_notes(id, notes) catch {
        problem => return Err(problem.to_string())
      }
      Ok(doc)
    }
    None => Err("unknown chord name '\{name}'")
  }
}

///|
fn parse_mini_doc_builder_note_text(text : String) -> Result[Double, String] {
  // Try parsing as a number first
  let mut pos = 0
  if pos < text.length() && text[pos] == '-' {
    pos += 1
  }
  let mut has_digit = false
  while pos < text.length() && text[pos] >= '0' && text[pos] <= '9' {
    pos += 1
    has_digit = true
  }
  if pos < text.length() && text[pos] == '.' {
    pos += 1
    while pos < text.length() && text[pos] >= '0' && text[pos] <= '9' {
      pos += 1
      has_digit = true
    }
  }
  if has_digit && pos == text.length() {
    return Ok(parse_double_manual(text, 0, text.length()))
  }
  // Not a valid number — try note name (e.g., "C4", "F#3", "Bb")
  match @pattern.note_name_to_midi(text) {
    Some(midi) => Ok(midi)
    None => Err("invalid note: '\{text}' is not a number or note name")
  }
}

///|
/// Build a mini fast transform using production root-ID rules.
pub fn[A] MiniDocBuilder::fast(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  factor : @pattern.Rational,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.fast_doc(doc, factor) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini slow transform using production root-ID rules.
pub fn[A] MiniDocBuilder::slow(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  factor : @pattern.Rational,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.slow_doc(doc, factor) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini rev transform using production root-ID rules.
pub fn[A] MiniDocBuilder::rev(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.rev_doc(doc) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini euclid transform using production root-ID rules.
pub fn[A] MiniDocBuilder::euclid(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  k : Int32,
  n : Int32,
  rotation : Int32,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.euclid_doc(doc, k, n, rotation) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini degrade transform using production root-ID and seed rules.
/// A notation `?` passes its `step`, the count of earlier `?` in its string.
pub fn[A] MiniDocBuilder::degrade(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  p : Double,
  step? : Int32,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.degrade_doc(doc, p, step?) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Merge `key = value` into `doc` using production root-ID rules.
pub fn[A] MiniDocBuilder::control(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  key : @control.Control,
  value : Double,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.scalar_control_doc(doc, key, value) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini every transform using production root-ID rules.
pub fn[A] MiniDocBuilder::every(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  n : Int32,
  transform : @pattern.TimeTransform,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.every_doc(doc, n, transform) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini jux transform using production root-ID rules.
pub fn[A : @pattern.WithControls] MiniDocBuilder::jux(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  transform : @pattern.TimeTransform,
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.jux_doc(doc, transform) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini sequence document using production root-ID rules.
pub fn[A] MiniDocBuilder::sequence(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[A]],
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.sequence_doc(docs) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
/// Build a mini stack document using production root-ID rules.
pub fn[A] MiniDocBuilder::stack(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[A]],
) -> Result[@pattern.PatternDoc[A], String] {
  let doc = self.stack_doc(docs) catch {
    problem => return Err(problem.to_string())
  }
  Ok(doc)
}

///|
fn MiniDocBuilder::id(
  self : MiniDocBuilder,
  value : String,
) -> @identity.PatternNodeId raise SourceProblem {
  ignore(self)
  @identity.PatternNodeId::from_string(value) catch {
    _ => raise Internal("internal mini id was invalid: \{value}")
  }
}

///|
fn MiniDocBuilder::next_occurrence(
  self : MiniDocBuilder,
  key : String,
) -> Int32 {
  let index = match self.counters.get(key) {
    Some(value) => value
    None => 0
  }
  self.counters[key] = index + 1
  index
}

///|
fn MiniDocBuilder::atom_id(
  self : MiniDocBuilder,
  kind : String,
  value : String,
) -> @identity.PatternNodeId raise SourceProblem {
  let key = "\{kind}:\{value}"
  let occurrence = self.next_occurrence(key)
  self.id("mini:\{kind}:\{mini_doc_id_fragment(value)}:\{occurrence}")
}

///|
fn MiniDocBuilder::atom_id_at(
  self : MiniDocBuilder,
  kind : String,
  value : String,
  start : Int32,
  end : Int32,
) -> @identity.PatternNodeId raise SourceProblem {
  let id = self.atom_id(kind, value)
  if self.origins is Some(origins) &&
    (kind == "sound" || kind == "note" || kind == "chord") {
    guard origins.atom_at(kind, start, end) is Some(source_atom) else {
      raise Internal("source atom witness missing for \{kind} at \{start}")
    }
    self.source_atom_by_graph_id[id.value()] = source_atom
  }
  id
}

///|
fn MiniDocBuilder::node_id(
  self : MiniDocBuilder,
  kind : String,
  inputs : Array[@identity.PatternNodeId],
  params : String,
) -> @identity.PatternNodeId raise SourceProblem {
  let parts = inputs.map(input => input.value())
  let mut content = "\{kind}("
  for input in inputs {
    let input_content = self.content(input)
    content += "\{input_content.length()}:\{input_content}"
  }
  if params != "" {
    parts.push(params)
  }
  let id = self.id("mini:\{kind}:\{parts.join(":")}")
  self.contents[id.value()] = "\{content};\{params})"
  id
}

///|
/// A document another builder or parser made has no content key here, so its
/// root ID stands in: its seeds then follow that ID, as before content keys.
fn MiniDocBuilder::content(
  self : MiniDocBuilder,
  root : @identity.PatternNodeId,
) -> String {
  match self.contents.get(root.value()) {
    Some(content) => content
    None => "doc:\{root.value()}"
  }
}

///|
fn[A] MiniDocBuilder::rest_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
) -> @pattern.PatternDoc[A] {
  self.contents[id.value()] = "silence"
  @pattern.PatternDoc::silence(id~)
}

///|
fn MiniDocBuilder::control_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  key : @control.Control,
  value : Double,
) -> @pattern.PatternDoc[@pattern.ControlMap] {
  self.contents[id.value()] = "control:\{key}:\{value}"
  @pattern.PatternDoc::control_atom(
    id~,
    source_atom?=self.source_atom_by_graph_id.get(id.value()),
    key~,
    value~,
  )
}

///|
/// An atom that plays `sound`.
fn MiniDocBuilder::sound_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  sound : @score.Sound,
) -> ScoreDoc {
  let content = sound.content()
  self.contents[id.value()] = content
  @pattern.PatternDoc::atom(
    id~,
    source_atom?=self.source_atom_by_graph_id.get(id.value()),
    value=@score.ScoreEvent(sound),
    content~,
  )
}

///|
/// One instrument `.s` names. It has no source atom: highlighting follows
/// the notes it plays.
fn MiniDocBuilder::instrument_doc(
  self : MiniDocBuilder,
  instrument : @score.Instrument,
  _span : MiniSpan,
) -> @pattern.PatternDoc[@score.Instrument] raise SourceProblem {
  let id = self.atom_id("instrument", instrument.name())
  let content = "instrument:\{instrument.name()}"
  self.contents[id.value()] = content
  @pattern.PatternDoc::atom(id~, value=instrument, content~)
}

///|
fn MiniDocBuilder::reference_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  start : Int32,
  end : Int32,
  definition_span : MiniSpan,
  definition : ScoreDoc,
) -> ScoreDoc raise SourceProblem {
  self.contents[id.value()] = self.content(definition.root())
  match self.origins {
    None => @pattern.PatternDoc::reference(id~, definition~)
    Some(origins) => {
      let resolved_reference = origins.resolve_reference(
        start, end, definition_span, definition,
      )
      @pattern.PatternDoc::reference_with_binding(id~, resolved_reference~)
    }
  }
}

///|
fn[A] MiniDocBuilder::sequence_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[A]],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  if docs.length() == 1 {
    return docs[0]
  }
  let id = self.node_id("seq", docs.map(doc => doc.root()), "")
  @pattern.PatternDoc::sequence(id~, docs~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::weighted_sequence_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[A]],
  weights : Array[Int32],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id(
    "weighted_seq",
    docs.map(doc => doc.root()),
    weights.map(weight => "\{weight}").join(":"),
  )
  @pattern.PatternDoc::sequence_weighted(id~, docs~, weights~) catch {
    _ => raise Internal("invalid relative duration sequence")
  }
}

///|
fn[A] MiniDocBuilder::stack_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[A]],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  if docs.length() == 1 {
    return docs[0]
  }
  let id = self.node_id("stack", docs.map(doc => doc.root()), "")
  @pattern.PatternDoc::stack(id~, docs~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::fast_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id("fast", [doc.root()], "\{factor.num}:\{factor.den}")
  doc.fast(id~, factor~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::slow_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id("slow", [doc.root()], "\{factor.num}:\{factor.den}")
  doc.slow(id~, factor~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::gate_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id("gate", [doc.root()], "\{factor.num}:\{factor.den}")
  doc.gate(id~, factor~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::rev_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id("rev", [doc.root()], "")
  doc.rev(id~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::euclid_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  k : Int32,
  n : Int32,
  rotation : Int32,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id("euclid", [doc.root()], "\{k}:\{n}:\{rotation}")
  doc.euclid(id~, k~, n~, rotation~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::degrade_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  p : Double,
  step? : Int32,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  // Seed by content so a named pattern drops the events its inline form does.
  // Like Strudel, each `?` of a notation string draws its own seed; the seed
  // never depends on `p`, so a higher probability drops a superset.
  let salt = match step {
    None => ""
    Some(step) => ":step:\{step}"
  }
  let seed = stable_seed(self.content(doc.root()) + salt)
  let id = self.node_id("degrade", [doc.root()], "\{p}\{salt}")
  doc.degrade_by(id~, p~, seed~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A] MiniDocBuilder::every_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  n : Int32,
  transform : @pattern.TimeTransform,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let signature = time_transform_signature(transform)
  let id = self.node_id("every", [doc.root()], "\{n}:\{signature}")
  doc.every(id~, n~, transform~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn[A : @pattern.WithControls] MiniDocBuilder::jux_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  transform : @pattern.TimeTransform,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let id = self.node_id(
    "jux",
    [doc.root()],
    time_transform_signature(transform),
  )
  doc.jux(id~, transform~) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn time_transform_signature(transform : @pattern.TimeTransform) -> String {
  fn factor(name : String, r : @pattern.Rational) -> String {
    if r.den == 1L {
      "\{name}:\{r.num}"
    } else {
      "\{name}:\{r.num}/\{r.den}"
    }
  }

  match transform {
    Fast(r) => factor("fast", r)
    Slow(r) => factor("slow", r)
    Reverse => "rev"
  }
}

///|
fn[A] MiniDocBuilder::scalar_control_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  key : @control.Control,
  value : Double,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let control_id = self.id("mini:control:\{doc.root().value()}:\{key}:\{value}")
  let control_doc = self.control_doc(control_id, key, value)
  let id = self.node_id("merge_control", [doc.root()], "\{key}:\{value}")
  @pattern.PatternDoc::merge_control(id~, left=doc, right=control_doc) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
/// Merge the control `value` gives `key` into `doc`.
fn[A] MiniDocBuilder::control_value_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[A],
  key : @control.Control,
  value : ControlValue,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let control_doc = match value {
    Number(value) => return self.scalar_control_doc(doc, key, value)
    Steps(notation) =>
      self.notation_doc(notation, (builder, number, span) => {
        builder.control_number_doc(key, number, span)
      })
    Signal(signal) => {
      let signature = mini_doc_id_fragment(
        "\{signal.shape.name()}:\{signal.low}:\{signal.high}:\{signal.rate.num}:\{signal.rate.den}",
      )
      let id = self.atom_id("signal", "\{key}:\{signature}")
      self.contents[id.value()] = "signal:\{key}:\{signature}"
      let shaped = match signal.shape {
        // A ramp rises once, from when its material enters.
        Ramp =>
          @pattern.PatternDoc::once(id~, key~, f=signal.function(), signature~)
        _ =>
          @pattern.PatternDoc::continuous(
            id~,
            key~,
            f=signal.function(),
            signature~,
          )
      }
      if signal.rate == @pattern.Rational::from_int(1) {
        shaped
      } else {
        self.fast_doc(shaped, signal.rate)
      }
    }
  }
  // The provider's node and content, not its spelling, identify the merge.
  let id = self.node_id(
    "merge_control",
    [doc.root(), control_doc.root()],
    key.name(),
  )
  @pattern.PatternDoc::merge_control(id~, left=doc, right=control_doc) catch {
    _ => raise Internal("internal mini PatternDoc construction failed")
  }
}

///|
fn stable_seed(value : String) -> Int32 {
  let mut hash = 17
  for index in 0..<value.length() {
    hash = (hash * 131 + value[index].to_int()) & 0x3fffffff
  }
  hash
}

///|
fn parse_doc_internal(input : String) -> Result[ScoreDoc, String] {
  guard !input.is_empty() else { return Err("empty input") }
  let p = Parser(input)
  let builder = MiniDocBuilder()
  try parse_doc_body(input, p, builder) catch {
    problem => Err(problem.to_string())
  } noraise {
    doc => Ok(doc)
  }
}

///|
fn parse_doc_body(
  input : String,
  p : Parser,
  builder : MiniDocBuilder,
) -> ScoreDoc raise SourceProblem {
  p.parse_bindings(builder)
  if mini_collect_dollar_stack_lines(input, start=p.pos) is Some(lines) {
    return parse_doc_dollar_stack_program(input, p, builder, lines)
  }
  let result = p.parse_doc_expr(builder)
  p.skip_whitespace()
  guard p.at_end() else {
    raise Mistake(
      p.pos,
      "unexpected trailing input '\{input[p.pos:].to_owned()}'",
    )
  }
  result
}

///|
fn parse_doc_dollar_stack_program(
  input : String,
  parser : Parser,
  builder : MiniDocBuilder,
  lines : Array[MiniDollarStackLine],
) -> ScoreDoc raise SourceProblem {
  let args : Array[ScoreDoc] = []
  for line in lines {
    parser.pos = line.start
    let doc = parser.parse_doc_expr(builder)
    parser.skip_inline_whitespace()
    if parser.pos != line.end {
      raise Mistake(
        parser.pos,
        "unexpected trailing input '\{input[parser.pos:line.end].to_owned()}'",
      )
    }
    args.push(doc)
  }
  builder.stack_doc(args)
}

///|
/// Parse a mini-notation string into an identity-bearing pattern document.
///
/// IDs are deterministic from the parsed structure and ignore whitespace-only
/// edits.
pub fn parse_doc(input : String) -> Result[ScoreDoc, String] {
  parse_doc_internal(input)
}

///|
/// Parse a mini-notation string into a lowered pattern snapshot.
pub fn parse_snapshot(
  input : String,
) -> Result[@pattern.PatternSnapshot[@score.ScoreEvent], String] {
  match parse_doc(input) {
    Err(msg) => Err(msg)
    Ok(doc) => {
      let snapshot = doc.lower() catch {
        _ => return Err("internal mini PatternDoc lowering failed")
      }
      Ok(snapshot)
    }
  }
}

///|
fn Parser::parse_doc_expr(
  self : Parser,
  builder : MiniDocBuilder,
) -> ScoreDoc raise SourceProblem {
  let resolved = resolve_mini_expr(self.parse_syntax_expr(), self.bindings)
  if self.admission is Some(admission) {
    admission.roots.push(admission.expression(resolved))
    Overlay(admission.roots).check(admission.width)
  }
  compile_score(resolved, builder).doc()
}

///|
fn Parser::read_quoted_string_with_start(
  self : Parser,
) -> (String, Int32) raise SourceProblem {
  self.expect_char('"')
  let start = self.pos
  while !self.at_end() && self.input[self.pos] != '"' {
    self.pos += 1
  }
  let content = self.input[start:self.pos].to_owned()
  self.expect_char('"')
  (content, start)
}

///|
/// Builds the document of one notation; `word_doc` builds each word's.
priv struct NotationDocReader[W, A] {
  builder : MiniDocBuilder
  word_doc : (MiniDocBuilder, W, MiniSpan) -> @pattern.PatternDoc[A] raise SourceProblem
}

///|
/// The document this notation plays, building each word's with `word_doc`.
fn[W, A] MiniDocBuilder::notation_doc(
  self : MiniDocBuilder,
  syntax : NotationSyntax[W],
  word_doc : (MiniDocBuilder, W, MiniSpan) -> @pattern.PatternDoc[A] raise SourceProblem,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  NotationDocReader::{ builder: self, word_doc, }.layers(syntax.layers)
}

///|
fn[W, A] NotationDocReader::layers(
  self : NotationDocReader[W, A],
  layers : Array[NotationLayer[W]],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  self.builder.stack_doc(layers.map(layer => self.layer(layer)))
}

///|
fn[W, A] NotationDocReader::layer(
  self : NotationDocReader[W, A],
  layer : NotationLayer[W],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let steps = layer.steps.map(step => self.step(step))
  match layer.timing {
    EqualSlots => self.builder.sequence_doc(steps)
    RelativeDurations =>
      self.builder.weighted_sequence_doc(
        steps,
        layer.steps.map(step => step.slots()),
      )
  }
}

///|
fn[W, A] NotationDocReader::step(
  self : NotationDocReader[W, A],
  step : NotationStep[W],
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let builder = self.builder
  let mut doc = match step.body {
    Rest(span) =>
      builder.rest_doc(builder.atom_id_at("rest", "~", span.start, span.end))
    Word(word, span) => (self.word_doc)(builder, word, span)
    Group(layers, _) => self.layers(layers)
  }
  for modifier in step.modifiers {
    doc = match modifier.kind {
      Euclid(Pulses(pulses~, steps~, rotation~), ..) =>
        builder.euclid_doc(doc, pulses, steps, rotation)
      Euclid(Silent, ..) =>
        builder.rest_doc(
          builder.atom_id_at(
            "rest",
            "euclid",
            modifier.span.start,
            modifier.span.end,
          ),
        )
      Repeat(n) => builder.fast_doc(doc, @pattern.Rational::from_int(n))
      Slow(n) => builder.slow_doc(doc, @pattern.Rational::from_int(n))
      Degrade(draw~) => builder.degrade_doc(doc, 0.5, step=draw)
    }
  }
  doc
}

///|
/// The document of a quoted pattern literal, framed by its source literal.
fn[W, A] MiniDocBuilder::literal_doc(
  self : MiniDocBuilder,
  notation : NotationSyntax[W],
  word_doc : (MiniDocBuilder, W, MiniSpan) -> @pattern.PatternDoc[A] raise SourceProblem,
) -> @pattern.PatternDoc[A] raise SourceProblem {
  let doc = self.notation_doc(notation, word_doc)
  let { start, end, } = notation.content
  match self.source_frame_at(start, end) {
    Some(frame) =>
      doc.with_source_frame(frame~) catch {
        _ => raise Internal("internal source-frame construction failed")
      }
    None => {
      if self.origins is Some(_) {
        raise Internal("missing source-frame identity at \{start}")
      }
      doc
    }
  }
}

///|
fn MiniDocBuilder::drum_doc(
  self : MiniDocBuilder,
  drum : @score.Drum,
  span : MiniSpan,
) -> ScoreDoc raise SourceProblem {
  let id = self.atom_id_at("sound", drum.name(), span.start, span.end)
  self.sound_doc(id, Hit(drum))
}

///|
fn MiniDocBuilder::pitch_doc(
  self : MiniDocBuilder,
  pitch : Pitch,
  span : MiniSpan,
) -> ScoreDoc raise SourceProblem {
  let id = self.atom_id_at("note", pitch.text, span.start, span.end)
  self.sound_doc(id, Note(@score.Instrument::default(), pitch=pitch.midi))
}

///|
fn MiniDocBuilder::chord_name_doc(
  self : MiniDocBuilder,
  chord : ChordName,
  span : MiniSpan,
) -> ScoreDoc raise SourceProblem {
  let id = self.atom_id_at("chord", chord.name, span.start, span.end)
  self.chord_doc_from_notes(id, chord.notes)
}

///|
fn MiniDocBuilder::control_number_doc(
  self : MiniDocBuilder,
  key : @control.Control,
  number : ControlNumber,
  span : MiniSpan,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise SourceProblem {
  let id = self.atom_id_at(
    "control",
    "\{key}:\{number.text}",
    span.start,
    span.end,
  )
  self.control_doc(id, key, number.value)
}

///|
/// A document of score events, as Mini builds from a score expression.
type ScoreDoc = @pattern.PatternDoc[@score.ScoreEvent]
