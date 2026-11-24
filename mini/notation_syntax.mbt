///|
/// A MIDI number or note name as written, as in `note("60 e4")`.
priv struct Pitch {
  text : String
  midi : Double
}

///|
/// A chord name or brace pitch set as written, as in `chord("C G7")`.
priv struct ChordName {
  name : String
  notes : Array[Int32]
}

///|
/// A number of a control pattern as written, as in `.gain("0.5 1")`.
priv struct ControlNumber {
  text : String
  value : Double
}

///|
/// Whether a notation may drop its events at random with `?`.
priv enum RandomDrop {
  Allowed
  /// A control pattern keeps every value, so `?` is a mistake there.
  Refused(@control.Control)
}

///|
/// The words a notation's atoms are made of.
priv struct NotationVocabulary[W] {
  /// Reads one word at the cursor, which is not at a rest.
  read_word : (NotationCursor) -> W raise SourceProblem
  random_drop : RandomDrop
}

///|
/// A name `s("…")` accepts: a drum or a sample (ADR-0026 Decision 3).
priv enum SoundName {
  Drum(@score.Drum)
  Sample(@score.Sample)
}

///|
fn SoundName::name(self : SoundName) -> String {
  match self {
    Drum(drum) => drum.name()
    Sample(sample) => sample.name()
  }
}

///|
/// What the name plays: a drum hit, or the sample at its root pitch.
fn SoundName::sound(self : SoundName) -> @score.Sound {
  match self {
    Drum(drum) => Hit(drum)
    Sample(sample) => Play(sample, pitch=sample.root_pitch())
  }
}

///|
fn SoundName::parse(name : String) -> SoundName? {
  match @score.Drum::parse(name) {
    Some(drum) => Some(Drum(drum))
    None => @score.Sample::parse(name).map(sample => Sample(sample))
  }
}

///|
/// A name `.s("…")` accepts: an instrument or a sample.
priv enum VoiceName {
  Instrument(@score.Instrument)
  Sample(@score.Sample)
}

///|
fn VoiceName::name(self : VoiceName) -> String {
  match self {
    Instrument(instrument) => instrument.name()
    Sample(sample) => sample.name()
  }
}

///|
fn sound_names() -> NotationVocabulary[SoundName] {
  { read_word: NotationCursor::read_sound_name, random_drop: Allowed, }
}

///|
fn voice_names() -> NotationVocabulary[VoiceName] {
  { read_word: NotationCursor::read_voice_name, random_drop: Allowed, }
}

///|
fn pitches() -> NotationVocabulary[Pitch] {
  { read_word: NotationCursor::read_pitch, random_drop: Allowed, }
}

///|
fn chord_names() -> NotationVocabulary[ChordName] {
  { read_word: NotationCursor::read_chord_name, random_drop: Allowed, }
}

///|
fn control_numbers(key : @control.Control) -> NotationVocabulary[ControlNumber] {
  { read_word: NotationCursor::read_control_number, random_drop: Refused(key), }
}

///|
/// What `(pulses,steps[,rotation])` plays, read as `Pat::euclid` reads it.
priv enum EuclidRhythm {
  /// No pulses or no steps: the step is silent.
  Silent
  /// `pulses` of `steps` play, rotated left by `rotation`, with
  /// 1 ≤ pulses ≤ steps and 0 ≤ rotation < steps.
  Pulses(pulses~ : Int32, steps~ : Int32, rotation~ : Int32)
}

///|
fn EuclidRhythm::from_written(
  pulses : Int32,
  steps : Int32,
  rotation : Int32,
) -> EuclidRhythm {
  guard pulses > 0 && steps > 0 else { return Silent }
  Pulses(
    pulses=pulses.min(steps),
    steps~,
    rotation=(rotation % steps + steps) % steps,
  )
}

///|
/// The numbers of `(pulses,steps[,rotation])` as written.
priv struct EuclidArguments {
  pulses : Int32
  steps : Int32
  rotation : Int32
}

///|
/// A change to what a step plays, applied to what the changes before it made.
priv enum NotationModifierKind {
  /// `(pulses,steps[,rotation])`
  Euclid(EuclidRhythm, written~ : EuclidArguments)
  /// `*n`: the step plays n times in its slot.
  Repeat(Int32)
  /// `/n`: the step stretches over n cycles of its slot.
  Slow(Int32)
  /// `?`: each event drops at random. `draw` numbers the `?` of one
  /// notation in source order, so each drops independently of the others.
  Degrade(draw~ : Int32)
}

///|
priv struct NotationModifier {
  kind : NotationModifierKind
  span : MiniSpan
}

///|
/// `@n`: the step takes n slots of its layer.
priv struct NotationWeight {
  slots : Int32
  span : MiniSpan
}

///|
/// What a step plays before its modifiers. Spans are whole-source.
priv enum NotationBody[W] {
  /// `~`
  Rest(MiniSpan)
  Word(W, MiniSpan)
  /// `[ ... ]`: layers in one step, and the span of the brackets.
  Group(Array[NotationLayer[W]], MiniSpan)
}

///|
/// One element of a layer.
priv struct NotationStep[W] {
  body : NotationBody[W]
  /// In written order.
  modifiers : Array[NotationModifier]
  /// Written `@n`; a step without one takes one slot.
  weight : NotationWeight?
}

///|
fn[W] NotationStep::slots(self : NotationStep[W]) -> Int32 {
  match self.weight {
    Some(weight) => weight.slots
    None => 1
  }
}

///|
/// How a layer divides its cycle among its steps.
priv enum LayerTiming {
  /// Every step takes one slot.
  EqualSlots
  /// Some step takes other than one slot; each takes its `slots()`.
  RelativeDurations
}

///|
/// Space-separated steps sharing one cycle.
priv struct NotationLayer[W] {
  steps : Array[NotationStep[W]]
  timing : LayerTiming
  /// From the first step through any spaces after the last.
  span : MiniSpan
}

///|
/// Quoted notation as written, with words of one vocabulary. Every rule of
/// the notation language holds in it, so readers turn it into a document,
/// query work, a projection, or source facts without checking it again.
/// Parsing refuses a rule broken as a `Mistake`, and nesting deeper than its
/// own recursion bound as `OverLimit(Nesting)`; what playback can afford is
/// left to playback admission.
priv struct NotationSyntax[W] {
  /// Whole-source span of the quoted content.
  content : MiniSpan
  /// Comma-separated layers played together.
  layers : Array[NotationLayer[W]]
}

///|
/// Calls `visit` with every word and its span, in source order.
fn[W] NotationSyntax::each_word(
  self : NotationSyntax[W],
  visit : (W, MiniSpan) -> Unit,
) -> Unit {
  fn walk(layers : Array[NotationLayer[W]]) -> Unit {
    for layer in layers {
      for step in layer.steps {
        match step.body {
          Rest(_) => ()
          Word(word, span) => visit(word, span)
          Group(inner, _) => walk(inner)
        }
      }
    }
  }

  walk(self.layers)
}

///|
/// What reading quoted notation finds.
priv enum NotationReading[W] {
  Parsed(NotationSyntax[W])
  /// The notation breaks a rule. The spans of the words completed before the
  /// problem are still source facts, so an edit in progress keeps them.
  Damaged(complete_words~ : Array[MiniSpan], problem~ : SourceProblem)
}

///|
fn[W] NotationSyntax::read(
  content : String,
  vocabulary : NotationVocabulary[W],
  at~ : Int32,
) -> NotationReading[W] {
  let parser = NotationParser::{
    cursor: { input: content, offset: at, pos: 0, },
    vocabulary,
    depth: 0,
    degrade_draws: 0,
    complete_words: [],
  }
  try parser.parse() catch {
    problem => Damaged(complete_words=parser.complete_words, problem~)
  } noraise {
    syntax => Parsed(syntax)
  }
}

///|
fn[W] NotationSyntax::parse(
  content : String,
  vocabulary : NotationVocabulary[W],
  at~ : Int32,
) -> NotationSyntax[W] raise SourceProblem {
  match NotationSyntax::read(content, vocabulary, at~) {
    Parsed(syntax) => syntax
    Damaged(problem~, ..) => raise problem
  }
}

///|
/// A position in the quoted content of one notation.
priv struct NotationCursor {
  input : String
  /// Whole-source position of the content's first code unit.
  offset : Int32
  mut pos : Int32
}

///|
/// Notation positions count from the quoted content; mistakes report the whole source.
fn NotationCursor::mistake(
  self : NotationCursor,
  at : Int32,
  message : String,
) -> SourceProblem {
  Mistake(self.offset + at, message)
}

///|
/// Whole-source span from `start` in the content to the current position.
fn NotationCursor::span_from(self : NotationCursor, start : Int32) -> MiniSpan {
  { start: self.offset + start, end: self.offset + self.pos, }
}

///|
fn NotationCursor::at_end(self : NotationCursor) -> Bool {
  self.pos >= self.input.length()
}

///|
fn NotationCursor::next_is(self : NotationCursor, unit : UInt16) -> Bool {
  !self.at_end() && self.input[self.pos] == unit
}

///|
fn NotationCursor::skip_spaces(self : NotationCursor) -> Unit {
  while !self.at_end() && mini_is_space(self.input[self.pos]) {
    self.pos += 1
  }
}

///|
/// Whether the word just read is complete: what follows can only end it, as
/// a separator or a modifier does, and not continue it.
fn NotationCursor::ends_word(self : NotationCursor) -> Bool {
  self.at_end() ||
  mini_is_space(self.input[self.pos]) ||
  (match self.input[self.pos] {
    ',' | ']' | '(' | '*' | '/' | '?' | '@' => true
    _ => false
  })
}

///|
/// Reads the structure of one notation; its vocabulary reads the words.
priv struct NotationParser[W] {
  cursor : NotationCursor
  vocabulary : NotationVocabulary[W]
  mut depth : Int32
  /// `?` read so far.
  mut degrade_draws : Int32
  /// Spans of the complete words read so far, in source order.
  complete_words : Array[MiniSpan]
}

///|
fn[W] NotationParser::parse(
  self : NotationParser[W],
) -> NotationSyntax[W] raise SourceProblem {
  let cursor = self.cursor
  guard !cursor.input.is_empty() else {
    raise cursor.mistake(0, "empty notation")
  }
  let layers = self.parse_layers()
  guard cursor.at_end() else {
    raise cursor.mistake(cursor.pos, "unexpected ']' without a matching '['")
  }
  {
    content: {
      start: cursor.offset,
      end: cursor.offset + cursor.input.length(),
    },
    layers,
  }
}

///|
/// layer ( "," layer )*
fn[W] NotationParser::parse_layers(
  self : NotationParser[W],
) -> Array[NotationLayer[W]] raise SourceProblem {
  let layers = [self.parse_layer()]
  while self.cursor.next_is(',') {
    self.cursor.pos += 1
    layers.push(self.parse_layer())
  }
  layers
}

///|
/// The most slots one layer's relative durations may add up to.
const RELATIVE_DURATION_SUM_LIMIT : Int32 = 256

///|
/// Space-separated steps up to a `,`, a `]`, or the end.
fn[W] NotationParser::parse_layer(
  self : NotationParser[W],
) -> NotationLayer[W] raise SourceProblem {
  let cursor = self.cursor
  cursor.skip_spaces()
  let start = cursor.pos
  let steps : Array[NotationStep[W]] = []
  let mut total_slots = 0
  let mut timing = EqualSlots
  while !cursor.at_end() && !cursor.next_is(',') && !cursor.next_is(']') {
    let step_start = cursor.pos
    let step = self.parse_step()
    total_slots += step.slots()
    if step.slots() != 1 {
      timing = RelativeDurations
    }
    guard timing is EqualSlots || total_slots <= RELATIVE_DURATION_SUM_LIMIT else {
      raise cursor.mistake(
        step_start,
        "relative durations in one layer must add up to at most \{RELATIVE_DURATION_SUM_LIMIT}",
      )
    }
    steps.push(step)
    cursor.require_step_boundary()
    cursor.skip_spaces()
  }
  guard !steps.is_empty() else {
    raise cursor.mistake(cursor.pos, "expected at least one element in layer")
  }
  { steps, timing, span: cursor.span_from(start), }
}

///|
const NOTATION_NESTING_LIMIT : Int32 = 32

///|
fn[W] NotationParser::parse_step(
  self : NotationParser[W],
) -> NotationStep[W] raise SourceProblem {
  guard self.depth < NOTATION_NESTING_LIMIT else {
    raise OverLimit(Nesting(NOTATION_NESTING_LIMIT))
  }
  let cursor = self.cursor
  let start = cursor.pos
  let body : NotationBody[W] = if cursor.next_is('[') {
    cursor.pos += 1
    self.depth += 1
    let layers = self.parse_layers()
    self.depth -= 1
    guard cursor.next_is(']') else {
      raise cursor.mistake(cursor.pos, "expected ']'")
    }
    cursor.pos += 1
    Group(layers, cursor.span_from(start))
  } else if cursor.next_is('~') {
    cursor.pos += 1
    Rest(cursor.span_from(start))
  } else {
    let word = (self.vocabulary.read_word)(cursor)
    let span = cursor.span_from(start)
    if cursor.ends_word() {
      self.complete_words.push(span)
    }
    Word(word, span)
  }
  let modifiers : Array[NotationModifier] = []
  let mut weight : NotationWeight? = None
  while !cursor.at_end() {
    let modifier_start = cursor.pos
    let kind : NotationModifierKind = match cursor.input[cursor.pos] {
      '(' => {
        let written = cursor.read_euclid_arguments()
        Euclid(
          EuclidRhythm::from_written(
            written.pulses,
            written.steps,
            written.rotation,
          ),
          written~,
        )
      }
      '*' => Repeat(cursor.read_positive_count())
      '/' => Slow(cursor.read_positive_count())
      '?' => {
        if self.vocabulary.random_drop is Refused(key) {
          raise cursor.mistake(
            cursor.pos,
            "random drop ? is not supported in \{key} patterns",
          )
        }
        cursor.pos += 1
        let draw = self.degrade_draws
        self.degrade_draws += 1
        Degrade(draw~)
      }
      '@' => {
        guard weight is None else {
          raise cursor.mistake(cursor.pos, "a step takes at most one '@'")
        }
        let slots = cursor.read_relative_duration()
        weight = Some({ slots, span: cursor.span_from(modifier_start), })
        continue
      }
      _ => break
    }
    modifiers.push({ kind, span: cursor.span_from(modifier_start), })
  }
  { body, modifiers, weight, }
}

///|
fn NotationCursor::require_step_boundary(
  self : NotationCursor,
) -> Unit raise SourceProblem {
  if self.at_end() {
    return
  }
  let c = self.input[self.pos]
  if mini_is_space(c) || c == ',' || c == ']' {
    return
  }
  raise self.mistake(self.pos, "expected separator between elements")
}

///|
/// `(k,n[,r])`
fn NotationCursor::read_euclid_arguments(
  self : NotationCursor,
) -> EuclidArguments raise SourceProblem {
  let euclid_start = self.pos
  self.pos += 1 // consume '('
  self.skip_spaces()
  let pulses = self.read_int_signed(euclid_start)
  self.skip_spaces()
  guard self.next_is(',') else {
    raise self.mistake(self.pos, "expected ',' in euclid (k,n)")
  }
  self.pos += 1 // consume ','
  self.skip_spaces()
  let steps = self.read_int_signed(euclid_start)
  self.skip_spaces()
  let mut rotation = 0
  if self.next_is(',') {
    self.pos += 1 // consume ','
    self.skip_spaces()
    rotation = self.read_int_signed(euclid_start)
    self.skip_spaces()
  }
  guard self.next_is(')') else {
    raise self.mistake(self.pos, "expected ')' to close euclid")
  }
  self.pos += 1 // consume ')'
  { pulses, steps, rotation, }
}

///|
fn NotationCursor::read_sound_name(
  self : NotationCursor,
) -> SoundName raise SourceProblem {
  let start = self.pos
  let name = self.read_ident()
  guard !name.is_empty() else {
    raise self.mistake(start, "expected sound name")
  }
  match SoundName::parse(name) {
    Some(sound) => sound
    None => raise self.mistake(start, "unknown drum or sample name '\{name}'")
  }
}

///|
fn NotationCursor::read_voice_name(
  self : NotationCursor,
) -> VoiceName raise SourceProblem {
  let start = self.pos
  let name = self.read_ident()
  guard !name.is_empty() else {
    raise self.mistake(start, "expected instrument name")
  }
  match @score.Instrument::parse(name) {
    Some(instrument) => Instrument(instrument)
    None =>
      match @score.Sample::parse(name) {
        Some(sample) => Sample(sample)
        None =>
          raise self.mistake(
            start,
            "unknown instrument or sample name '\{name}'",
          )
      }
  }
}

///|
/// A MIDI number, or a note name such as `C4`, `F#3` or `Bb5`.
fn NotationCursor::read_pitch(
  self : NotationCursor,
) -> Pitch raise SourceProblem {
  let start = self.pos
  try self.read_number() catch {
    _ => {
      let name = self.read_note_name_text()
      guard !name.is_empty() else {
        raise self.mistake(start, "expected note name or number")
      }
      match @pattern.note_name_to_midi(name) {
        Some(midi) => { text: name, midi, }
        None => raise self.mistake(start, "unknown note name '\{name}'")
      }
    }
  } noraise {
    midi => { text: self.input[start:self.pos].to_owned(), midi, }
  }
}

///|
fn NotationCursor::read_chord_name(
  self : NotationCursor,
) -> ChordName raise SourceProblem {
  let start = self.pos
  let name = self.read_chord_name_text()
  guard !name.is_empty() else {
    raise self.mistake(start, "expected chord name")
  }
  match @pattern.parse_chord(name) {
    Some(notes) => { name, notes, }
    None => raise self.mistake(start, "unknown chord '\{name}'")
  }
}

///|
fn NotationCursor::read_control_number(
  self : NotationCursor,
) -> ControlNumber raise SourceProblem {
  let start = self.pos
  let value = self.read_number()
  { text: self.input[start:self.pos].to_owned(), value, }
}

///|
/// `*n` or `/n`, with n positive.
fn NotationCursor::read_positive_count(
  self : NotationCursor,
) -> Int32 raise SourceProblem {
  let operator_at = self.pos
  let operator = self.input[operator_at:operator_at + 1].to_owned()
  self.pos += 1
  let n = self.read_int_signed(operator_at)
  guard n > 0 else {
    raise self.mistake(
      operator_at,
      "'\{operator}' requires a positive integer, got \{n}",
    )
  }
  n
}

///|
const RELATIVE_DURATION_WEIGHT_LIMIT : Int32 = 16

///|
fn NotationCursor::read_relative_duration(
  self : NotationCursor,
) -> Int32 raise SourceProblem {
  let at_pos = self.pos
  self.pos += 1
  let digits_start = self.pos
  let mut weight = 0
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    weight = if weight > RELATIVE_DURATION_WEIGHT_LIMIT {
      weight
    } else {
      weight * 10 + self.input[self.pos].to_int() - '0'.to_int()
    }
    self.pos += 1
  }
  guard self.pos > digits_start &&
    weight > 0 &&
    weight <= RELATIVE_DURATION_WEIGHT_LIMIT else {
    raise self.mistake(at_pos, "'@' requires a positive integer from 1 to 16")
  }
  weight
}

///|
/// Read a signed integer at current position (no decimal point allowed).
fn NotationCursor::read_int_signed(
  self : NotationCursor,
  err_pos : Int32,
) -> Int32 raise SourceProblem {
  let start = self.pos
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  let digits_start = self.pos
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    self.pos += 1
  }
  guard self.pos > digits_start else {
    self.pos = start
    raise self.mistake(err_pos, "expected integer")
  }
  let mut value = 0
  for i in digits_start..<self.pos {
    value = value * 10 + (self.input[i].to_int() - '0'.to_int())
  }
  if digits_start > start {
    -value
  } else {
    value
  }
}

///|
/// Read through a closing brace so malformed contents are rejected as one atom.
fn NotationCursor::read_explicit_chord_text(self : NotationCursor) -> String {
  let start = self.pos
  while !self.at_end() && self.input[self.pos] != '}' {
    self.pos += 1
  }
  if !self.at_end() {
    self.pos += 1
  }
  self.input[start:self.pos].to_owned()
}

///|
/// Read a note name text: letter (A-G) + optional accidental (#/s/b/f) + optional signed octave digits.
/// Unlike read_ident(), this includes accidentals which are not alphanumeric.
fn NotationCursor::read_note_name_text(self : NotationCursor) -> String {
  let start = self.pos
  // Read root note letter (must start with A-G)
  if !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'g') || (c >= 'A' && c <= 'G') {
      self.pos += 1
    } else {
      return self.input[start:self.pos].to_owned()
    }
  }
  // Read optional accidental(s)
  while !self.at_end() {
    let c = self.input[self.pos]
    if c == '#' || c == 's' || c == 'b' || c == 'f' {
      self.pos += 1
    } else {
      break
    }
  }
  // Read optional signed octave digits
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  while !self.at_end() {
    let c = self.input[self.pos]
    if c >= '0' && c <= '9' {
      self.pos += 1
    } else {
      break
    }
  }
  self.input[start:self.pos].to_owned()
}

///|
/// Read a named chord or a complete brace-delimited MIDI pitch set.
fn NotationCursor::read_chord_name_text(self : NotationCursor) -> String {
  if !self.at_end() && self.input[self.pos] == '{' {
    return self.read_explicit_chord_text()
  }
  let start = self.pos
  // Read root note letter (must start with A-G)
  if !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'g') || (c >= 'A' && c <= 'G') {
      self.pos += 1
    } else {
      return self.input[start:self.pos].to_owned()
    }
  }
  // Read optional accidental(s)
  while !self.at_end() {
    let c = self.input[self.pos]
    if c == '#' || c == 's' || c == 'b' || c == 'f' {
      self.pos += 1
    } else {
      break
    }
  }
  // Read quality suffix and octave
  while !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '+' ||
      c == 'ø' {
      self.pos += 1
    } else {
      break
    }
  }
  self.input[start:self.pos].to_owned()
}

///|
fn NotationCursor::read_ident(self : NotationCursor) -> String {
  let start = self.pos
  while !self.at_end() {
    let c = self.input[self.pos]
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      (c >= '0' && c <= '9' && self.pos > start) {
      self.pos += 1
    } else {
      break
    }
  }
  self.input[start:self.pos].to_owned()
}

///|
/// A decimal number such as `60`, `-1` or `0.5`; the position is unchanged
/// when there is none.
fn NotationCursor::read_number(
  self : NotationCursor,
) -> Double raise SourceProblem {
  let start = self.pos
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
    self.pos = start
    raise self.mistake(start, "expected number")
  }
  parse_double_manual(self.input, start, self.pos)
}
