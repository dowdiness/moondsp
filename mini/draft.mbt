///|
const DRAFT_SOURCE_LIMIT : Int32 = 8192

///|
const DRAFT_IDENTITY_MAX : Int64 = 9007199254740991L

///|
let draft_epoch_counter : Ref[Int64] = Ref(0L)

///|
/// An opaque document epoch and revision. Only Draft issues versions.
#derive(Eq, Debug)
pub struct DraftVersion {
  priv epoch : @identity.SourceEpoch
  priv revision : Int64
}

///|
fn DraftVersion::DraftVersion(
  epoch : @identity.SourceEpoch,
  revision : Int64,
) -> DraftVersion {
  { epoch, revision, }
}

///|
pub extend DraftVersion with Eq::{equal, not_equal}

///|
pub extend DraftVersion with Debug::{to_repr}

///|
/// Half-open UTF-16 source coordinates.
#derive(Eq, Debug)
pub struct SourceRange {
  priv first : Int32
  priv last : Int32
}

///|
fn SourceRange::SourceRange(span : MiniSpan) -> SourceRange {
  { first: span.start, last: span.end, }
}

///|
pub fn SourceRange::start(self : SourceRange) -> Int32 {
  self.first
}

///|
pub fn SourceRange::end(self : SourceRange) -> Int32 {
  self.last
}

///|
pub extend SourceRange with Eq::{equal, not_equal}

///|
pub extend SourceRange with Debug::{to_repr}

///|
/// A replacement in the transaction's old document, not an intermediate text.
pub struct TextEdit {
  priv from : Int32
  priv to : Int32
  priv inserted : String
}

///|
pub fn TextEdit::TextEdit(
  from~ : Int32,
  to~ : Int32,
  inserted~ : String,
) -> TextEdit {
  { from, to, inserted, }
}

///|
pub struct EditTransaction {
  priv base : DraftVersion
  priv edits : Array[TextEdit]
}

///|
pub fn EditTransaction::EditTransaction(
  base~ : DraftVersion,
  edits~ : Array[TextEdit],
) -> EditTransaction {
  { base, edits: edits.copy(), }
}

///|
#derive(Eq, Debug)
pub(all) suberror DraftEditError {
  WrongBase
  InvalidEdit(String)
  IdentityExhausted
}

///|
pub extend DraftEditError with Eq::{equal, not_equal}

///|
pub extend DraftEditError with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum DraftTracking {
  Pattern
  Song
  TrackingUnavailable
}

///|
pub extend DraftTracking with Eq::{equal, not_equal}

///|
pub extend DraftTracking with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub struct DraftDiagnostic {
  priv at : DraftVersion
  priv found : SourceProblem
}

///|
pub extend DraftDiagnostic with Eq::{equal, not_equal}

///|
pub extend DraftDiagnostic with Debug::{to_repr}

///|
fn DraftDiagnostic::DraftDiagnostic(
  at : DraftVersion,
  found : SourceProblem,
) -> DraftDiagnostic {
  { at, found, }
}

///|
pub fn DraftDiagnostic::version(self : DraftDiagnostic) -> DraftVersion {
  self.at
}

///|
pub fn DraftDiagnostic::problem(self : DraftDiagnostic) -> SourceProblem {
  self.found
}

///|
pub struct DraftState {
  priv input : String
  priv at : DraftVersion
  priv mode : DraftTracking
  priv error : DraftDiagnostic?
}

///|
fn DraftState::DraftState(
  input : String,
  at : DraftVersion,
  mode : DraftTracking,
  error : DraftDiagnostic?,
) -> DraftState {
  { input, at, mode, error, }
}

///|
pub fn DraftState::text(self : DraftState) -> String {
  self.input
}

///|
pub fn DraftState::version(self : DraftState) -> DraftVersion {
  self.at
}

///|
pub fn DraftState::tracking(self : DraftState) -> DraftTracking {
  self.mode
}

///|
pub fn DraftState::diagnostic(self : DraftState) -> DraftDiagnostic? {
  self.error
}

///|
#derive(Eq, Debug)
pub(all) enum OriginUnavailable {
  SourceReset
  AtomRetired
  BrokenReference
}

///|
pub extend OriginUnavailable with Eq::{equal, not_equal}

///|
pub extend OriginUnavailable with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum OriginLocation {
  Located(SourceRange, Array[SourceRange])
  Unavailable(OriginUnavailable)
}

///|
pub extend OriginLocation with Eq::{equal, not_equal}

///|
pub extend OriginLocation with Debug::{to_repr}

///|
priv struct LiveAtom {
  id : @identity.SourceAtomId
  kind : String
  span : MiniSpan
}

///|
fn LiveAtom::LiveAtom(
  id : @identity.SourceAtomId,
  kind : String,
  span : MiniSpan,
) -> LiveAtom {
  { id, kind, span, }
}

///|
priv struct LiveLiteral {
  id : @identity.SourceFrameId
  kind : String
  span : MiniSpan
}

///|
fn LiveLiteral::LiveLiteral(
  id : @identity.SourceFrameId,
  kind : String,
  span : MiniSpan,
) -> LiveLiteral {
  { id, kind, span, }
}

///|
priv struct LiveDefinition {
  id : @identity.DefinitionId
  name : String
  span : MiniSpan
  visible_after : Int32
}

///|
fn LiveDefinition::LiveDefinition(
  id : @identity.DefinitionId,
  fact : RecognizedDefinition,
) -> LiveDefinition {
  { id, name: fact.name, span: fact.span, visible_after: fact.visible_after, }
}

///|
priv enum LiveBinding {
  Bound(@identity.ReferenceBindingId, @identity.DefinitionId)
  Unresolved(ReferenceProblem)
}

///|
priv struct LiveReference {
  id : @identity.ReferenceId
  name : String
  span : MiniSpan
  binding : LiveBinding
}

///|
fn LiveReference::LiveReference(
  id : @identity.ReferenceId,
  fact : RecognizedReference,
  binding : LiveBinding,
) -> LiveReference {
  { id, name: fact.name, span: fact.span, binding, }
}

///|
/// Immutable current facts, not an edit history. Arrays never escape this package.
priv struct SourceMap {
  epoch : @identity.SourceEpoch
  serial : Int64
  atoms : Array[LiveAtom]
  literals : Array[LiveLiteral]
  definitions : Array[LiveDefinition]
  references : Array[LiveReference]
}

///|
fn SourceMap::SourceMap(
  epoch : @identity.SourceEpoch,
  serial : Int64,
  atoms : Array[LiveAtom],
  literals : Array[LiveLiteral],
  definitions : Array[LiveDefinition],
  references : Array[LiveReference],
) -> SourceMap {
  { epoch, serial, atoms, literals, definitions, references, }
}

///|
fn SourceMap::empty(epoch : @identity.SourceEpoch) -> SourceMap {
  SourceMap(epoch, 0L, [], [], [], [])
}

///|
fn next_draft_epoch() -> @identity.SourceEpoch raise DraftEditError {
  guard draft_epoch_counter.val < DRAFT_IDENTITY_MAX else {
    raise IdentityExhausted
  }
  let next = draft_epoch_counter.val + 1L
  let epoch = @identity.SourceEpoch::SourceEpoch(next) catch {
    _ => raise IdentityExhausted
  }
  draft_epoch_counter.val = next
  epoch
}

///|
fn next_draft_serial(counter : Ref[Int64]) -> Int64 raise DraftEditError {
  guard counter.val < DRAFT_IDENTITY_MAX else { raise IdentityExhausted }
  counter.val = counter.val + 1L
  counter.val
}

///|
fn draft_span_key(kind : String, span : MiniSpan) -> String {
  "\{kind}:\{span.start}:\{span.end}"
}

///|
/// Endpoint insertions map outward; the subsequent full-extent match detects
/// lexical merges. Any replacement of the token itself ends its lifetime.
fn draft_map_untouched(span : MiniSpan, edits : Array[TextEdit]) -> MiniSpan? {
  let mut delta = 0
  for edit in edits {
    if edit.from == edit.to {
      guard !(edit.from > span.start && edit.from < span.end) else {
        return None
      }
      if edit.from <= span.start {
        delta += edit.inserted.length()
      }
    } else {
      guard !(edit.from < span.end && edit.to > span.start) else { return None }
      if edit.to <= span.start {
        delta += edit.inserted.length() - (edit.to - edit.from)
      }
    }
  }
  Some({ start: span.start + delta, end: span.end + delta, })
}

///|
/// A literal frame owns its complete content. Even boundary insertions retire
/// it, unlike token mappings that intentionally survive endpoint insertion.
fn draft_map_untouched_literal(
  span : MiniSpan,
  edits : Array[TextEdit],
) -> MiniSpan? {
  let mut delta = 0
  for edit in edits {
    if edit.from == edit.to {
      guard !(edit.from >= span.start && edit.from <= span.end) else {
        return None
      }
      if edit.from < span.start {
        delta += edit.inserted.length()
      }
    } else {
      guard !(edit.from < span.end && edit.to > span.start) else { return None }
      if edit.to <= span.start {
        delta += edit.inserted.length() - (edit.to - edit.from)
      }
    }
  }
  Some({ start: span.start + delta, end: span.end + delta, })
}

///|
fn SourceMap::advance(
  self : SourceMap,
  facts : SourceRecognition,
  edits : Array[TextEdit],
) -> SourceMap raise DraftEditError {
  let old_atoms : Map[String, LiveAtom] = Map([])
  let old_literals : Map[String, LiveLiteral] = Map([])
  let old_definitions : Map[String, LiveDefinition] = Map([])
  let old_references : Map[String, LiveReference] = Map([])
  for atom in self.atoms {
    if draft_map_untouched(atom.span, edits) is Some(span) {
      old_atoms[draft_span_key(atom.kind, span)] = atom
    }
  }
  for literal in self.literals {
    if draft_map_untouched_literal(literal.span, edits) is Some(span) {
      old_literals[draft_span_key(literal.kind, span)] = literal
    }
  }
  for definition in self.definitions {
    if draft_map_untouched(definition.span, edits) is Some(span) {
      old_definitions[draft_span_key(definition.name, span)] = definition
    }
  }
  for reference in self.references {
    if draft_map_untouched(reference.span, edits) is Some(span) {
      old_references[draft_span_key(reference.name, span)] = reference
    }
  }
  let counter = Ref(self.serial)
  let atoms : Array[LiveAtom] = []
  for fact in facts.atoms {
    let id = match old_atoms.get(draft_span_key(fact.kind, fact.span)) {
      Some(old) => old.id
      None =>
        @identity.SourceAtomId::SourceAtomId(
          self.epoch,
          next_draft_serial(counter),
        ) catch {
          _ => raise IdentityExhausted
        }
    }
    atoms.push(LiveAtom(id, fact.kind, fact.span))
  }
  let literals : Array[LiveLiteral] = []
  for fact in facts.literals {
    let id = match old_literals.get(draft_span_key(fact.kind, fact.span)) {
      Some(old) => old.id
      None =>
        @identity.SourceFrameId::SourceFrameId(
          self.epoch,
          next_draft_serial(counter),
        ) catch {
          _ => raise IdentityExhausted
        }
    }
    literals.push(LiveLiteral(id, fact.kind, fact.span))
  }
  let definitions : Array[LiveDefinition] = []
  for fact in facts.definitions {
    let id = match old_definitions.get(draft_span_key(fact.name, fact.span)) {
      Some(old) => old.id
      None =>
        @identity.DefinitionId::DefinitionId(
          self.epoch,
          next_draft_serial(counter),
        ) catch {
          _ => raise IdentityExhausted
        }
    }
    definitions.push(LiveDefinition(id, fact))
  }
  let references : Array[LiveReference] = []
  for fact in facts.references {
    let old = old_references.get(draft_span_key(fact.name, fact.span))
    let id = match old {
      Some(old) => old.id
      None =>
        @identity.ReferenceId::ReferenceId(
          self.epoch,
          next_draft_serial(counter),
        ) catch {
          _ => raise IdentityExhausted
        }
    }
    let target = unique_definition(
      definitions
      .iter()
      .filter(definition => {
        definition.name == fact.name &&
        definition.visible_after <= fact.span.start
      }),
      fact.opaque_scope,
    )
    let binding = match target {
      Err(reason) => Unresolved(reason)
      Ok(target) => {
        let preserved = match old {
          Some({ binding: Bound(binding, definition), .. }) if definition ==
            target.id => Some(binding)
          _ => None
        }
        let binding = match preserved {
          Some(binding) => binding
          None =>
            @identity.ReferenceBindingId::ReferenceBindingId(
              self.epoch,
              next_draft_serial(counter),
            ) catch {
              _ => raise IdentityExhausted
            }
        }
        Bound(binding, target.id)
      }
    }
    references.push(LiveReference(id, fact, binding))
  }
  SourceMap(self.epoch, counter.val, atoms, literals, definitions, references)
}

///|
fn SourceMap::atom_at(
  self : SourceMap,
  kind : String,
  start : Int32,
  end : Int32,
) -> @identity.SourceAtomId? {
  for atom in self.atoms {
    if atom.kind == kind && atom.span.start == start && atom.span.end == end {
      return Some(atom.id)
    }
  }
  None
}

///|
fn SourceMap::frame_at(
  self : SourceMap,
  content_from : Int32,
  content_to : Int32,
) -> @identity.SourceFrameId? {
  for literal in self.literals {
    if literal.span.start == content_from && literal.span.end == content_to {
      return Some(literal.id)
    }
  }
  None
}

///|
fn SourceMap::frame_range(self : SourceMap, serial : Int64) -> SourceRange? {
  for literal in self.literals {
    if literal.id.serial() == serial {
      return Some(SourceRange(literal.span))
    }
  }
  None
}

///|
fn SourceMap::resolve_reference(
  self : SourceMap,
  start : Int32,
  end : Int32,
  definition_span : MiniSpan,
  definition : ScoreDoc,
) -> @pattern.ResolvedReference[@score.ScoreEvent] raise SourceProblem {
  for reference in self.references {
    if reference.span.start == start && reference.span.end == end {
      let (binding, target) = match reference.binding {
        Bound(binding, target) => (binding, target)
        Unresolved(reason) => {
          let message = match reason {
            UndefinedName => "undefined target"
            DuplicateName => "duplicate target"
            OpaqueScope => "opaque preceding scope"
          }
          raise Internal("exact reference at \{start}: \{message}")
        }
      }
      for declared in self.definitions {
        if declared.id == target &&
          declared.span.start == definition_span.start &&
          declared.span.end == definition_span.end {
          return @pattern.ResolvedReference::ResolvedReference(
            definition~,
            definition_id=target,
            reference=reference.id,
            binding~,
          ) catch {
            _ => raise Internal("exact reference epoch mismatch at \{start}")
          }
        }
      }
    }
  }
  raise Internal("missing exact reference witness at \{start}")
}

///|
priv enum PlaybackPayload {
  Pattern(DraftVersion, SourceMap)
  Song(DraftVersion, SourceMap)
  Text
}

///|
/// Frozen authoring input. It contains no runtime closure or serialized AST.
pub struct PlaybackInput {
  priv input : String
  priv payload : PlaybackPayload
}

///|
fn PlaybackInput::PlaybackInput(
  input : String,
  payload : PlaybackPayload,
) -> PlaybackInput {
  { input, payload, }
}

///|
/// Explicit untracked input for programmatic text playback.
pub fn PlaybackInput::text(input : String) -> PlaybackInput {
  PlaybackInput(input, Text)
}

///|
pub fn PlaybackInput::source(self : PlaybackInput) -> String {
  self.input
}

///|
pub fn PlaybackInput::version(self : PlaybackInput) -> DraftVersion? {
  match self.payload {
    Pattern(version, _) | Song(version, _) => Some(version)
    Text => None
  }
}

///|
/// Exact patterns and explicitly untracked runtime sources are distinct capabilities.
pub(all) enum PreparedPlayback {
  Pattern(@pattern.PatternSnapshotWithOrigins[@score.ScoreEvent], Double)
  Runtime(PlaySource)
}

///|
/// Compile this frozen input, independently of any subsequent Draft edits.
/// A failed exact compilation never falls back to runtime-only playback.
pub fn PlaybackInput::compile(
  self : PlaybackInput,
  query_window? : @pattern.QueryWindow,
) -> Result[PreparedPlayback, String] {
  match self.payload {
    Text =>
      parse_play_source(self.input, query_window?)
      .map(source => Runtime(source))
      .map_err(SourceProblem::to_string)
    Song(_, origins) => {
      let source = parse_play_source_with_origins(
        self.input,
        query_window,
        origins=Some(origins),
        syntax_depth_limit=Some(32),
      ) catch {
        problem => return Err(problem.to_string())
      }
      guard source.body() is ExactArrangement(_, _) else {
        return Err("song input changed source mode")
      }
      Ok(Runtime(source))
    }
    Pattern(_, origins) => {
      let source = parse_play_source_with_origins(
        self.input,
        query_window,
        origins=Some(origins),
        syntax_depth_limit=Some(32),
      ) catch {
        problem => return Err(problem.to_string())
      }
      guard source.body() is Pattern(doc) else {
        return Err("exact pattern input changed source mode")
      }
      try doc.lower_with_origins() catch {
        error => Err(draft_origin_error(error))
      } noraise {
        snapshot => Ok(Pattern(snapshot, source.bpm()))
      }
    }
  }
}

///|
fn draft_origin_error(error : @pattern.PatternDocError) -> String {
  match error {
    MissingNode(id) => "exact compilation: missing node \{id}"
    DuplicateNodeId(id) => "exact compilation: duplicate node \{id}"
    EmptyPatternDocs => "exact compilation: empty document list"
    InvalidSequenceWeights =>
      "exact compilation: invalid relative sequence weights"
    MissingAtomOrigin(id) =>
      "exact compilation: missing atom origin \{id.value()}"
    MissingReferenceBinding(id) =>
      "exact compilation: missing reference binding \{id.value()}"
    UnsupportedControl(id) =>
      "exact compilation: unsupported control provider \{id.value()}"
  }
}

///|
/// Single owner of current text, causal source lifetimes and bounded parse state.
/// Playback acceptance and run eligibility belong to the caller, not this owner.
pub struct Draft {
  priv mut input : String
  priv mut at : DraftVersion
  priv mut mode : DraftTracking
  priv mut sources : SourceMap
  /// What the current text means for playback, or why it cannot be played.
  priv mut analysis : DraftAnalysis
  /// The window of the player the text is checked for, once that is known.
  priv mut query_window : @pattern.QueryWindow?
}

///|
priv enum DraftAnalysis {
  /// It parses and fits the player's window when that is known.
  Playable(PlaySource, PlaybackPayload)
  Rejected(DraftDiagnostic)
}

///|
fn DraftAnalysis::diagnostic(self : DraftAnalysis) -> DraftDiagnostic? {
  match self {
    Playable(_, _) => None
    Rejected(diagnostic) => Some(diagnostic)
  }
}

///|
fn draft_recognize(input : String) -> SourceRecognition? {
  if input.length() > DRAFT_SOURCE_LIMIT {
    None
  } else {
    Some(recognize_mini_source(input))
  }
}

///|
fn draft_tracking(
  facts : SourceRecognition?,
  previous : DraftTracking,
) -> DraftTracking {
  match facts {
    None => TrackingUnavailable
    Some({ mode: Some(Song), .. }) => Song
    Some({ mode: Some(Pattern), .. }) => Pattern
    Some({ mode: None, .. }) => if previous == Song { Song } else { Pattern }
  }
}

///|
/// Every problem the author can cause, decided while editing so that preparing
/// playback never finds a new one. Exact lowering is not repeated here: the
/// parser already rejects every source it cannot lower, so a failure there is
/// a compiler bug that `PlaybackInput::compile` still reports.
fn draft_analysis(
  input : String,
  at : DraftVersion,
  mode : DraftTracking,
  sources : SourceMap,
  query_window : @pattern.QueryWindow?,
) -> DraftAnalysis {
  let payload = match mode {
    Pattern => PlaybackPayload::Pattern(at, sources)
    Song => PlaybackPayload::Song(at, sources)
    TrackingUnavailable =>
      return Rejected(DraftDiagnostic(at, OverLimit(Length)))
  }
  let source = parse_play_source_with_origins(
    input,
    query_window,
    origins=Some(sources),
    syntax_depth_limit=Some(32),
  ) catch {
    problem => return Rejected(DraftDiagnostic(at, problem))
  }
  Playable(source, payload)
}

///|
/// Draft checks syntax; `check_playback_within` adds the
/// player's limits once the player is known.
pub fn Draft::Draft(input : String) -> Draft raise DraftEditError {
  Draft::starting_with(input, None)
}

///|
fn Draft::starting_with(
  input : String,
  query_window : @pattern.QueryWindow?,
) -> Draft raise DraftEditError {
  let epoch = next_draft_epoch()
  let facts = draft_recognize(input)
  let mode = draft_tracking(facts, Pattern)
  let empty = SourceMap::empty(epoch)
  let sources = match facts {
    Some(facts) if mode == Pattern || mode == Song => empty.advance(facts, [])
    _ => empty
  }
  let at = DraftVersion(epoch, 0L)
  let analysis = draft_analysis(input, at, mode, sources, query_window)
  { input, at, mode, sources, analysis, query_window, }
}

///|
pub fn Draft::state(self : Draft) -> DraftState {
  DraftState(self.input, self.at, self.mode, self.analysis.diagnostic())
}

///|
/// From now on, also reject what a player querying at most `window` would
/// refuse. The text is checked again but keeps its version, as it is unchanged.
pub fn Draft::check_playback_within(
  self : Draft,
  window : @pattern.QueryWindow,
) -> DraftState {
  self.query_window = Some(window)
  self.analysis = draft_analysis(
    self.input,
    self.at,
    self.mode,
    self.sources,
    self.query_window,
  )
  self.state()
}

///|
fn draft_utf16_boundary(text : String, offset : Int32) -> Bool {
  guard offset > 0 && offset < text.length() else { return true }
  let before = text[offset - 1].to_int()
  let after = text[offset].to_int()
  !(before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF)
}

///|
fn draft_validate_edits(
  text : String,
  edits : Array[TextEdit],
) -> Array[TextEdit] raise DraftEditError {
  let active : Array[TextEdit] = []
  let mut previous_end = 0
  let mut size = text.length().to_int64()
  for edit in edits {
    guard edit.from >= previous_end &&
      edit.from <= edit.to &&
      edit.to <= text.length() else {
      raise InvalidEdit(
        "edits must be sorted, non-overlapping, in-range old-document ranges",
      )
    }
    guard draft_utf16_boundary(text, edit.from) &&
      draft_utf16_boundary(text, edit.to) else {
      raise InvalidEdit("edit boundary splits a UTF-16 surrogate pair")
    }
    previous_end = edit.to
    size = size +
      edit.inserted.length().to_int64() -
      (edit.to - edit.from).to_int64()
    if edit.from != edit.to || !edit.inserted.is_empty() {
      active.push(edit)
    }
  }
  guard size <= 2147483647L else {
    raise InvalidEdit("edited text length overflows Int")
  }
  active
}

///|
fn draft_apply_edits(text : String, edits : Array[TextEdit]) -> String {
  let output = StringBuilder()
  let mut offset = 0
  for edit in edits {
    output.write_stringview(text[offset:edit.from])
    output.write_string(edit.inserted)
    offset = edit.to
  }
  output.write_stringview(text[offset:])
  output.to_string()
}

///|
fn Draft::edit_checked(
  self : Draft,
  tx : EditTransaction,
) -> DraftState raise DraftEditError {
  guard tx.base == self.at else { raise WrongBase }
  let edits = draft_validate_edits(self.input, tx.edits)
  guard !edits.is_empty() else { return self.state() }
  guard self.at.revision < DRAFT_IDENTITY_MAX else { raise IdentityExhausted }
  let input = draft_apply_edits(self.input, edits)
  let facts = draft_recognize(input)
  let mode = draft_tracking(facts, self.mode)
  let baseline = if mode == self.mode {
    self.sources
  } else {
    SourceMap::empty(next_draft_epoch())
  }
  let sources = match facts {
    Some(facts) if mode == Pattern || mode == Song =>
      baseline.advance(facts, edits)
    _ => baseline
  }
  let at = DraftVersion(self.at.epoch, self.at.revision + 1L)
  let analysis = draft_analysis(input, at, mode, sources, self.query_window)
  // Commit only after all validation and checked identity allocation succeeded.
  self.input = input
  self.at = at
  self.mode = mode
  self.sources = sources
  self.analysis = analysis
  self.state()
}

///|
pub fn Draft::edit(
  self : Draft,
  transaction : EditTransaction,
) -> Result[DraftState, DraftEditError] {
  try self.edit_checked(transaction) catch {
    error => Err(error)
  } noraise {
    state => Ok(state)
  }
}

///|
/// A replacement document explicitly ends every prior source lifetime.
pub fn Draft::reset(
  self : Draft,
  input : String,
) -> Result[DraftState, DraftEditError] {
  try Draft::starting_with(input, self.query_window) catch {
    error => Err(error)
  } noraise {
    fresh => {
      self.input = fresh.input
      self.at = fresh.at
      self.mode = fresh.mode
      self.sources = fresh.sources
      self.analysis = fresh.analysis
      Ok(self.state())
    }
  }
}

///|
pub fn Draft::prepare_playback(
  self : Draft,
) -> Result[PlaybackInput, DraftDiagnostic] {
  match self.analysis {
    Rejected(diagnostic) => Err(diagnostic)
    Playable(_, payload) => Ok(PlaybackInput(self.input, payload))
  }
}

///|
/// Locate every immutable binding in an origin's path, never a partial path.
pub fn Draft::locate_origin(
  self : Draft,
  origin : @pattern.EventOrigin,
) -> OriginLocation {
  guard (self.mode == Pattern || self.mode == Song) &&
    origin.atom().epoch() == self.sources.epoch else {
    return Unavailable(SourceReset)
  }
  let mut atom_span : MiniSpan? = None
  for atom in self.sources.atoms {
    if atom.id == origin.atom() {
      atom_span = Some(atom.span)
      break
    }
  }
  guard atom_span is Some(span) else { return Unavailable(AtomRetired) }
  let reference_ranges : Array[SourceRange] = []
  for edge in origin.bindings() {
    let mut found = false
    for reference in self.sources.references {
      if reference.id == edge.reference() {
        if reference.binding is Bound(binding, definition) &&
          binding == edge.id() &&
          definition == edge.definition() {
          reference_ranges.push(SourceRange(reference.span))
          found = true
        }
        break
      }
    }
    guard found else { return Unavailable(BrokenReference) }
  }
  Located(SourceRange(span), reference_ranges)
}

///|
/// Checked scalar-wire lookup for authoring adapters. The path is flattened
/// as reference, binding, definition serial triples in outer-to-inner order.
pub fn Draft::locate_origin_fields(
  self : Draft,
  atom_epoch : Int64,
  atom_serial : Int64,
  path : Array[Int64],
) -> OriginLocation {
  guard (self.mode == Pattern || self.mode == Song) && path.length() % 3 == 0 else {
    return Unavailable(SourceReset)
  }
  guard atom_epoch == self.sources.epoch.serial() else {
    return Unavailable(SourceReset)
  }
  let mut atom_span : MiniSpan? = None
  for atom in self.sources.atoms {
    if atom.id.serial() == atom_serial {
      atom_span = Some(atom.span)
      break
    }
  }
  guard atom_span is Some(span) else { return Unavailable(AtomRetired) }
  let references : Array[SourceRange] = []
  for index in 0..<(path.length() / 3) {
    let reference_serial = path[index * 3]
    let binding_serial = path[index * 3 + 1]
    let definition_serial = path[index * 3 + 2]
    let mut found = false
    for reference in self.sources.references {
      if reference.id.serial() == reference_serial {
        if reference.binding is Bound(binding, definition) &&
          binding.serial() == binding_serial &&
          definition.serial() == definition_serial {
          references.push(SourceRange(reference.span))
          found = true
        }
        break
      }
    }
    guard found else { return Unavailable(BrokenReference) }
  }
  Located(SourceRange(span), references)
}

///|
/// Resolve a serialized literal-frame identity only while that exact frame is
/// still present in the current source map.
pub fn Draft::locate_frame_fields(
  self : Draft,
  frame_epoch : Int64,
  frame_serial : Int64,
) -> SourceRange? {
  guard self.mode == Pattern || self.mode == Song else { return None }
  guard frame_epoch == self.sources.epoch.serial() else { return None }
  self.sources.frame_range(frame_serial)
}

///|
/// Resolve a serialized signal identity only while that exact signal is still
/// present in the current source map; editing a signal's text retires it.
pub fn Draft::locate_signal_fields(
  self : Draft,
  epoch : Int64,
  serial : Int64,
) -> SourceRange? {
  guard (self.mode == Pattern || self.mode == Song) &&
    epoch == self.sources.epoch.serial() else {
    return None
  }
  for atom in self.sources.atoms {
    if atom.kind == "signal" && atom.id.serial() == serial {
      return Some(SourceRange(atom.span))
    }
  }
  None
}
