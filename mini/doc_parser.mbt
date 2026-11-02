///|
pub struct MiniDocBuilder {
  priv previous : @pattern.PatternDoc[@pattern.ControlMap]?
  priv counters : Map[String, Int]
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
  previous~ : @pattern.PatternDoc[@pattern.ControlMap]?,
  origins? : SourceMap? = None,
) -> MiniDocBuilder {
  {
    previous,
    counters: Map([]),
    origins,
    source_atom_by_graph_id: Map([]),
    contents: Map([]),
  }
}

///|
fn MiniDocBuilder::source_frame_at(
  self : MiniDocBuilder,
  content_from : Int,
  content_to : Int,
) -> @identity.SourceFrameId? {
  match self.origins {
    Some(origins) => origins.frame_at(content_from, content_to)
    None => None
  }
}

///|
/// Create a reusable mini `PatternDoc` semantic builder for external
/// frontends. Pass the last successful document to preserve subtree reuse.
pub fn MiniDocBuilder::with_previous(
  previous : @pattern.PatternDoc[@pattern.ControlMap]?,
) -> MiniDocBuilder {
  MiniDocBuilder(previous~)
}

///|
/// Build a sound atom with a caller-supplied stable node ID.
pub fn MiniDocBuilder::sound_atom(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  name : String,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = match drum_midi(name) {
    Some(midi) =>
      self.control_doc(id, "sound", midi.to_double()) catch {
        ParseError(msg) => return Err(msg)
      }
    None => return Err("unknown drum name '\{name}'")
  }
  Ok(doc)
}

///|
/// Build a note atom with a caller-supplied stable node ID.
pub fn MiniDocBuilder::note_atom(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  text : String,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let note = match parse_mini_doc_builder_note_text(text) {
    Ok(note) => note
    Err(msg) => return Err(msg)
  }
  let doc = self.control_doc(id, "note", note) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
fn MiniDocBuilder::chord_tone_id(
  self : MiniDocBuilder,
  chord_id : @identity.PatternNodeId,
  tone_index : Int,
  midi : Int,
) -> @identity.PatternNodeId raise ParseError {
  self.id("mini:chord-tone:\{chord_id.value()}:\{tone_index}:\{midi}")
}

///|
fn MiniDocBuilder::chord_doc_from_notes(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  notes : Array[Int],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.contents[id.value()] = "chord:\{notes.map(note => "\{note}").join(":")}"
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => {
      let note_docs : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
      let mut tone_index = 0
      for midi in notes {
        let note_id = self.chord_tone_id(id, tone_index, midi)
        match self.source_atom_by_graph_id.get(id.value()) {
          Some(source_atom) =>
            self.source_atom_by_graph_id[note_id.value()] = source_atom
          None => ()
        }
        note_docs.push(self.control_doc(note_id, "note", midi.to_double()))
        tone_index += 1
      }
      @pattern.PatternDoc::stack(id~, docs=note_docs) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
    }
  }
}

///|
/// Build a chord atom with a caller-supplied stable node ID.
/// Expands the chord name into a stack of note docs.
pub fn MiniDocBuilder::chord_atom(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  name : String,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  match @pattern.parse_chord(name) {
    Some(notes) => {
      let doc = self.chord_doc_from_notes(id, notes) catch {
        ParseError(msg) => return Err(msg)
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
/// Build a mini fast transform using production root-ID and reuse rules.
pub fn MiniDocBuilder::fast(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.fast_doc(doc, factor) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Build a mini slow transform using production root-ID and reuse rules.
pub fn MiniDocBuilder::slow(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.slow_doc(doc, factor) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Build a mini rev transform using production root-ID and reuse rules.
pub fn MiniDocBuilder::rev(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.rev_doc(doc) catch { ParseError(msg) => return Err(msg) }
  Ok(doc)
}

///|
/// Build a mini euclid transform using production root-ID and reuse rules.
pub fn MiniDocBuilder::euclid(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  k : Int,
  n : Int,
  rotation : Int,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.euclid_doc(doc, k, n, rotation) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Build a mini degrade transform using production root-ID, seed, and reuse rules.
/// A notation `?` passes its `step`, the count of earlier `?` in its string.
pub fn MiniDocBuilder::degrade(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  p : Double,
  step? : Int,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.degrade_doc(doc, p, step?) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Merge `key = value` into `doc` using production root-ID and reuse rules.
pub fn MiniDocBuilder::control(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  key : String,
  value : Double,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.scalar_control_doc(doc, key, value) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Build a mini every transform using production root-ID and reuse rules.
pub fn MiniDocBuilder::every(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  n : Int,
  transform : @pattern.TimeTransform,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.every_doc(doc, n, transform) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Build a mini jux transform using production root-ID and reuse rules.
pub fn MiniDocBuilder::jux(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  transform : @pattern.TimeTransform,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.jux_doc(doc, transform) catch {
    ParseError(msg) => return Err(msg)
  }
  Ok(doc)
}

///|
/// Build a mini sequence document using production root-ID and reuse rules.
pub fn MiniDocBuilder::sequence(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.sequence_doc(docs) catch { ParseError(msg) => return Err(msg) }
  Ok(doc)
}

///|
/// Build a mini stack document using production root-ID and reuse rules.
pub fn MiniDocBuilder::stack(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let doc = self.stack_doc(docs) catch { ParseError(msg) => return Err(msg) }
  Ok(doc)
}

///|
fn MiniDocBuilder::id(
  self : MiniDocBuilder,
  value : String,
) -> @identity.PatternNodeId raise ParseError {
  ignore(self)
  @identity.PatternNodeId::from_string(value) catch {
    _ => raise ParseError("internal mini id was invalid: \{value}")
  }
}

///|
fn MiniDocBuilder::next_occurrence(self : MiniDocBuilder, key : String) -> Int {
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
) -> @identity.PatternNodeId raise ParseError {
  let key = "\{kind}:\{value}"
  let occurrence = self.next_occurrence(key)
  self.id("mini:\{kind}:\{mini_doc_id_fragment(value)}:\{occurrence}")
}

///|
fn MiniDocBuilder::atom_id_at(
  self : MiniDocBuilder,
  kind : String,
  value : String,
  start : Int,
  end : Int,
) -> @identity.PatternNodeId raise ParseError {
  let id = self.atom_id(kind, value)
  if self.origins is Some(origins) &&
    (kind == "sound" || kind == "note" || kind == "chord") {
    guard origins.atom_at(kind, start, end) is Some(source_atom) else {
      raise ParseError(
        "position \{start}: source atom witness missing for \{kind}",
      )
    }
    self.source_atom_by_graph_id[id.value()] = source_atom
  }
  id
}

///|
fn MiniDocBuilder::node_id(
  self : MiniDocBuilder,
  kind : String,
  inputs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
  params : String,
) -> @identity.PatternNodeId raise ParseError {
  let parts = inputs.map(input => input.root().value())
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
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> String {
  match self.contents.get(doc.root().value()) {
    Some(content) => content
    None => "doc:\{doc.root().value()}"
  }
}

///|
fn MiniDocBuilder::reuse_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  inputs? : Array[@pattern.PatternDoc[@pattern.ControlMap]] = [],
) -> @pattern.PatternDoc[@pattern.ControlMap]? raise ParseError {
  guard self.origins is None else { return None }
  match self.previous {
    None => None
    Some(previous) =>
      if previous.contains_node(id) {
        for input in inputs {
          guard previous.contains_node(input.root()) else { return None }
          let old_input = previous.subdoc(root=input.root()) catch {
            _ => raise ParseError("internal mini input could not be reused")
          }
          guard old_input.revision() == input.revision() else { return None }
        }
        let doc = previous.subdoc(root=id) catch {
          _ =>
            raise ParseError(
              "internal mini id could not be reused: \{id.value()}",
            )
        }
        Some(doc)
      } else {
        None
      }
  }
}

///|
fn MiniDocBuilder::rest_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.contents[id.value()] = "silence"
  match self.reuse_doc(id) {
    Some(doc) => doc
    None => @pattern.PatternDoc::silence(id~)
  }
}

///|
fn MiniDocBuilder::control_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  key : String,
  value : Double,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.contents[id.value()] = "control:\{key}:\{value}"
  match self.reuse_doc(id) {
    Some(doc) => doc
    None =>
      @pattern.PatternDoc::control_atom(
        id~,
        source_atom?=self.source_atom_by_graph_id.get(id.value()),
        key~,
        value~,
      )
  }
}

///|
fn MiniDocBuilder::reference_doc(
  self : MiniDocBuilder,
  id : @identity.PatternNodeId,
  start : Int,
  end : Int,
  definition_span : MiniSpan,
  definition : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.contents[id.value()] = self.content(definition)
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
fn MiniDocBuilder::sequence_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  if docs.length() == 1 {
    return docs[0]
  }
  let id = self.node_id("seq", docs, "")
  match self.reuse_doc(id, inputs=docs) {
    Some(doc) => doc
    None =>
      @pattern.PatternDoc::sequence(id~, docs~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::weighted_sequence_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
  weights : Array[Int],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id(
    "weighted_seq",
    docs,
    weights.map(weight => "\{weight}").join(":"),
  )
  match self.reuse_doc(id, inputs=docs) {
    Some(doc) => doc
    None =>
      @pattern.PatternDoc::sequence_weighted(id~, docs~, weights~) catch {
        _ => raise ParseError("invalid relative duration sequence")
      }
  }
}

///|
fn MiniDocBuilder::stack_doc(
  self : MiniDocBuilder,
  docs : Array[@pattern.PatternDoc[@pattern.ControlMap]],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  if docs.length() == 1 {
    return docs[0]
  }
  let id = self.node_id("stack", docs, "")
  match self.reuse_doc(id, inputs=docs) {
    Some(doc) => doc
    None =>
      @pattern.PatternDoc::stack(id~, docs~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::fast_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("fast", [doc], "\{factor.num}:\{factor.den}")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.fast(id~, factor~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::slow_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("slow", [doc], "\{factor.num}:\{factor.den}")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.slow(id~, factor~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::gate_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  factor : @pattern.Rational,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("gate", [doc], "\{factor.num}:\{factor.den}")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.gate(id~, factor~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::rev_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("rev", [doc], "")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.rev(id~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::euclid_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  k : Int,
  n : Int,
  rotation : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("euclid", [doc], "\{k}:\{n}:\{rotation}")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.euclid(id~, k~, n~, rotation~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::degrade_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  p : Double,
  step? : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  // Seed by content so a named pattern drops the events its inline form does.
  // Like Strudel, each `?` of a notation string draws its own seed; the seed
  // never depends on `p`, so a higher probability drops a superset.
  let salt = match step {
    None => ""
    Some(step) => ":step:\{step}"
  }
  let seed = stable_seed(self.content(doc) + salt)
  let id = self.node_id("degrade", [doc], "\{p}\{salt}")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.degrade_by(id~, p~, seed~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::every_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  n : Int,
  transform : @pattern.TimeTransform,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let signature = time_transform_signature(transform)
  let id = self.node_id("every", [doc], "\{n}:\{signature}")
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.every(id~, n~, transform~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn MiniDocBuilder::jux_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  transform : @pattern.TimeTransform,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let id = self.node_id("jux", [doc], time_transform_signature(transform))
  match self.reuse_doc(id, inputs=[doc]) {
    Some(doc) => doc
    None =>
      doc.jux(id~, transform~) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
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
fn MiniDocBuilder::scalar_control_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  key : String,
  value : Double,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let control_id = self.id("mini:control:\{doc.root().value()}:\{key}:\{value}")
  let control_doc = self.control_doc(control_id, key, value)
  let id = self.node_id("merge_control", [doc], "\{key}:\{value}")
  match self.reuse_doc(id, inputs=[doc, control_doc]) {
    Some(doc) => doc
    None =>
      @pattern.PatternDoc::merge_control(id~, left=doc, right=control_doc) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
/// Merge the control `value` gives `key` into `doc`.
fn MiniDocBuilder::control_value_doc(
  self : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
  key : String,
  value : MiniValue,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let control_doc = match value {
    Number(value) => return self.scalar_control_doc(doc, key, value)
    Steps(content, offset, _) => {
      let notation = NotationParser(
        content,
        sound=false,
        control=key,
        source_offset=offset,
      )
      notation.parse_doc_notation(self)
    }
    Signal(signal) => {
      let signature = mini_doc_id_fragment(
        "\{signal.shape.name()}:\{signal.low}:\{signal.high}:\{signal.rate.num}:\{signal.rate.den}",
      )
      let id = self.atom_id("signal", "\{key}:\{signature}")
      self.contents[id.value()] = "signal:\{key}:\{signature}"
      let shaped = match self.reuse_doc(id) {
        Some(doc) => doc
        None => @pattern.PatternDoc::continuous(id~, key~, f=signal.function())
      }
      if signal.rate == @pattern.Rational::from_int(1) {
        shaped
      } else {
        self.fast_doc(shaped, signal.rate)
      }
    }
  }
  // The provider's node and content, not its spelling, identify the merge.
  let id = self.node_id("merge_control", [doc, control_doc], key)
  match self.reuse_doc(id, inputs=[doc, control_doc]) {
    Some(doc) => doc
    None =>
      @pattern.PatternDoc::merge_control(id~, left=doc, right=control_doc) catch {
        _ => raise ParseError("internal mini PatternDoc construction failed")
      }
  }
}

///|
fn stable_seed(value : String) -> Int {
  let mut hash = 17
  for index in 0..<value.length() {
    hash = (hash * 131 + value[index].to_int()) & 0x3fffffff
  }
  hash
}

///|
fn parse_doc_internal(
  input : String,
  previous : @pattern.PatternDoc[@pattern.ControlMap]?,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  guard !input.is_empty() else { return Err("empty input") }
  let p = Parser(input)
  let builder = MiniDocBuilder(previous~)
  p.parse_bindings(builder=Some(builder)) catch {
    ParseError(msg) => return Err(msg)
  }
  match mini_collect_dollar_stack_lines(input, start=p.pos) {
    Err(msg) => return Err(msg)
    Ok(Some(lines)) =>
      return parse_doc_dollar_stack_program(input, p, builder, lines)
    Ok(None) => ()
  }
  let result = p.parse_doc_expr(builder) catch {
    ParseError(msg) => return Err(msg)
  }
  p.skip_whitespace()
  guard p.at_end() else {
    return Err(
      "position \{p.pos}: unexpected trailing input '\{input[p.pos:].to_owned()}'",
    )
  }
  Ok(result)
}

///|
fn parse_doc_dollar_stack_program(
  input : String,
  parser : Parser,
  builder : MiniDocBuilder,
  lines : Array[MiniDollarStackLine],
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  let args : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  for line in lines {
    parser.pos = line.start
    let doc = parser.parse_doc_expr(builder) catch {
      ParseError(msg) => return Err(msg)
    }
    parser.skip_inline_whitespace()
    if parser.pos != line.end {
      return Err(
        "position \{parser.pos}: unexpected trailing input '\{input[parser.pos:line.end].to_owned()}'",
      )
    }
    args.push(doc)
  }
  let doc = builder.stack_doc(args) catch { ParseError(msg) => return Err(msg) }
  Ok(doc)
}

///|
/// Parse a mini-notation string into an identity-bearing pattern document.
///
/// IDs are deterministic from the parsed structure and ignore whitespace-only
/// edits. Pass `previous=Some(prior)` to reuse unchanged subtrees from a prior
/// parsed document when their deterministic `PatternNodeId`s still appear —
/// this preserves subtree generations for lowering-cache reuse.
pub fn parse_doc(
  input : String,
  previous? : @pattern.PatternDoc[@pattern.ControlMap]? = None,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  parse_doc_internal(input, previous)
}

///|
/// Parse a mini-notation string into a lowered pattern snapshot.
///
/// Pass `previous=Some(prior)` to reuse subtree IDs from a prior parsed
/// document, mirroring `parse_doc`'s reuse semantics.
pub fn parse_snapshot(
  input : String,
  previous? : @pattern.PatternDoc[@pattern.ControlMap]? = None,
) -> Result[@pattern.PatternSnapshot[@pattern.ControlMap], String] {
  match parse_doc(input, previous~) {
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
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let syntax = self.parse_syntax_expr()
  if self.admission is Some(admission) {
    admission.roots.push(admission.expression(syntax))
    Overlay(admission.roots).check(admission.width)
  }
  let resolved = resolve_mini_expr(syntax, self.doc_bindings)
  compile_mini_doc(resolved, builder)
}

///|
fn Parser::read_quoted_string_with_start(
  self : Parser,
) -> (String, Int) raise ParseError {
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
fn parse_sound_doc_notation(
  content : String,
  builder : MiniDocBuilder,
  source_offset~ : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  guard !content.is_empty() else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser(content, sound=true, source_offset~)
  sub.parse_doc_notation(builder)
}

///|
fn parse_note_doc_notation(
  content : String,
  builder : MiniDocBuilder,
  source_offset~ : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  guard !content.is_empty() else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser(content, sound=false, source_offset~)
  sub.parse_doc_notation(builder)
}

///|
fn parse_chord_doc_notation(
  content : String,
  builder : MiniDocBuilder,
  source_offset~ : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  guard !content.is_empty() else {
    raise ParseError("position 0: empty notation")
  }
  let sub = NotationParser(content, sound=false, chord=true, source_offset~)
  sub.parse_doc_notation(builder)
}

///|
fn NotationParser::parse_doc_notation(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let first = self.parse_doc_layer(builder)
  let layers : Array[@pattern.PatternDoc[@pattern.ControlMap]] = [first]
  while !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_spaces()
    layers.push(self.parse_doc_layer(builder))
  }
  builder.stack_doc(layers)
}

///|
fn NotationParser::parse_doc_layer(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  self.skip_spaces()
  let elements : Array[@pattern.PatternDoc[@pattern.ControlMap]] = []
  let weights : Array[Int] = []
  let mut total_weight = 0
  let mut weighted = false
  while !self.at_end() &&
        self.input[self.pos] != ',' &&
        self.input[self.pos] != ']' {
    let (element, weight) = self.parse_doc_element(builder)
    elements.push(element)
    weights.push(weight)
    total_weight += weight
    weighted = weighted || weight != 1
    guard !weighted || total_weight <= 256 else {
      raise ParseError("relative duration sum must not exceed 256")
    }
    self.require_element_boundary()
    self.skip_spaces()
  }
  guard !elements.is_empty() else {
    raise ParseError(
      "position \{self.pos}: expected at least one element in layer",
    )
  }
  if !weighted {
    return builder.sequence_doc(elements)
  }
  builder.weighted_sequence_doc(elements, weights)
}

///|
fn NotationParser::parse_doc_element(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> (@pattern.PatternDoc[@pattern.ControlMap], Int) raise ParseError {
  self.skip_spaces()
  guard !self.at_end() else {
    raise ParseError("position \{self.pos}: unexpected end of notation")
  }
  let base = if self.input[self.pos] == '[' {
    self.pos += 1
    let inner = self.parse_doc_notation(builder)
    guard !self.at_end() && self.input[self.pos] == ']' else {
      raise ParseError("position \{self.pos}: expected ']'")
    }
    self.pos += 1
    inner
  } else {
    self.parse_doc_atom(builder)
  }
  let mut doc = base
  let mut weight = 1
  let mut applied = true
  while applied {
    applied = false
    if !self.at_end() {
      let c = self.input[self.pos]
      if c == '(' {
        doc = self.maybe_apply_doc_euclid(builder, doc)
        applied = true
      } else if c == '*' {
        doc = self.apply_doc_replicate(builder, doc)
        applied = true
      } else if c == '/' {
        doc = self.apply_doc_step_slow(builder, doc)
        applied = true
      } else if c == '?' {
        self.pos += 1
        doc = builder.degrade_doc(doc, 0.5, step=self.degrade_steps)
        self.degrade_steps += 1
        applied = true
      } else if c == '@' {
        weight = self.read_relative_duration()
        applied = true
      }
    }
  }
  (doc, weight)
}

///|
fn NotationParser::apply_doc_replicate(
  self : NotationParser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let op_pos = self.pos
  self.pos += 1
  let n = self.read_int_signed(op_pos)
  guard n > 0 else {
    raise ParseError(
      "position \{op_pos}: '*' requires a positive integer, got \{n}",
    )
  }
  builder.fast_doc(doc, @pattern.Rational::from_int(n))
}

///|
fn NotationParser::apply_doc_step_slow(
  self : NotationParser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let op_pos = self.pos
  self.pos += 1
  let n = self.read_int_signed(op_pos)
  guard n > 0 else {
    raise ParseError(
      "position \{op_pos}: '/' requires a positive integer, got \{n}",
    )
  }
  builder.slow_doc(doc, @pattern.Rational::from_int(n))
}

///|
fn NotationParser::maybe_apply_doc_euclid(
  self : NotationParser,
  builder : MiniDocBuilder,
  doc : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  if self.at_end() || self.input[self.pos] != '(' {
    return doc
  }
  let euclid_start = self.pos
  self.pos += 1
  self.skip_spaces()
  let k = self.read_int_signed(euclid_start)
  self.skip_spaces()
  guard !self.at_end() && self.input[self.pos] == ',' else {
    raise ParseError("position \{self.pos}: expected ',' in euclid (k,n)")
  }
  self.pos += 1
  self.skip_spaces()
  let n = self.read_int_signed(euclid_start)
  self.skip_spaces()
  let mut rotation = 0
  if !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_spaces()
    rotation = self.read_int_signed(euclid_start)
    self.skip_spaces()
  }
  guard !self.at_end() && self.input[self.pos] == ')' else {
    raise ParseError("position \{self.pos}: expected ')' to close euclid")
  }
  self.pos += 1
  builder.euclid_doc(doc, k, n, rotation)
}

///|
fn NotationParser::parse_doc_atom(
  self : NotationParser,
  builder : MiniDocBuilder,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let start = self.pos
  if self.input[self.pos] == '~' {
    self.pos += 1
    let id = builder.atom_id_at(
      "rest",
      "~",
      self.source_offset + start,
      self.source_offset + self.pos,
    )
    return builder.rest_doc(id)
  }
  if self.control is Some(key) {
    let (value, token, token_start, token_end) = self.read_control_number(start)
    let id = builder.atom_id_at(
      "control",
      "\{key}:\{token}",
      self.source_offset + token_start,
      self.source_offset + token_end,
    )
    return builder.control_doc(id, key, value)
  }
  if self.sound {
    let name = self.read_ident()
    guard !name.is_empty() else {
      raise ParseError("position \{start}: expected sound name")
    }
    match drum_midi(name) {
      Some(midi) => {
        let id = builder.atom_id_at(
          "sound",
          name,
          self.source_offset + start,
          self.source_offset + self.pos,
        )
        builder.control_doc(id, "sound", midi.to_double())
      }
      None => raise ParseError("position \{start}: unknown drum name '\{name}'")
    }
  } else if self.chord {
    // Read chord name (including accidentals like #, b) → stack of note docs
    let name_start = self.pos
    let name = self.read_chord_name_text()
    guard !name.is_empty() else {
      raise ParseError("position \{start}: expected chord name")
    }
    match @pattern.parse_chord(name) {
      Some(notes) => {
        let id = builder.atom_id_at(
          "chord",
          name,
          self.source_offset + name_start,
          self.source_offset + self.pos,
        )
        builder.chord_doc_from_notes(id, notes)
      }
      None => raise ParseError("position \{start}: unknown chord '\{name}'")
    }
  } else {
    // Try number first, then note name
    try {
      let (note, token, token_start, token_end) = self.read_note_number_value(
        start,
      )
      let id = builder.atom_id_at(
        "note",
        token,
        self.source_offset + token_start,
        self.source_offset + token_end,
      )
      builder.control_doc(id, "note", note)
    } catch {
      ParseError(_) => self.parse_doc_note_name_atom(builder, start)
    } noraise {
      doc => doc
    }
  }
}

///|
/// Parse a note name atom (e.g., "C4", "F#3") in the doc parser.
fn NotationParser::parse_doc_note_name_atom(
  self : NotationParser,
  builder : MiniDocBuilder,
  start : Int,
) -> @pattern.PatternDoc[@pattern.ControlMap] raise ParseError {
  let name_start = self.pos
  let name = self.read_note_name_text()
  guard !name.is_empty() else {
    raise ParseError("position \{start}: expected note name or number")
  }
  match @pattern.note_name_to_midi(name) {
    Some(midi) => {
      let id = builder.atom_id_at(
        "note",
        name,
        self.source_offset + name_start,
        self.source_offset + self.pos,
      )
      builder.control_doc(id, "note", midi)
    }
    None => raise ParseError("position \{start}: unknown note name '\{name}'")
  }
}

///|
fn NotationParser::read_note_number_value(
  self : NotationParser,
  start : Int,
) -> (Double, String, Int, Int) raise ParseError {
  let num_start = self.pos
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  let mut has_digit = false
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    self.pos += 1
    has_digit = true
  }
  if !self.at_end() && self.input[self.pos] == '.' {
    self.pos += 1
    while !self.at_end() &&
          self.input[self.pos] >= '0' &&
          self.input[self.pos] <= '9' {
      self.pos += 1
      has_digit = true
    }
  }
  guard has_digit else {
    self.pos = num_start
    raise ParseError("position \{start}: expected number")
  }
  let token = self.input[num_start:self.pos].to_owned()
  (
    parse_double_manual(self.input, num_start, self.pos),
    token,
    num_start,
    self.pos,
  )
}
