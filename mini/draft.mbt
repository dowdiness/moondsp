///|
const DRAFT_SOURCE_LIMIT : Int = 8192

///|
const DRAFT_IDENTITY_MAX : Int64 = 9007199254740991L

///|
let draft_epoch_counter : Ref[Int64] = Ref(0L)

///|
/// An opaque document epoch and revision. Only Draft issues versions.
pub struct DraftVersion {
  priv epoch : @identity.SourceEpoch
  priv revision : Int64
} derive(Eq, Debug)

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
pub struct SourceRange {
  priv first : Int
  priv last : Int
} derive(Eq, Debug)

///|
fn SourceRange::SourceRange(span : MiniSpan) -> SourceRange {
  { first: span.start, last: span.end, }
}

///|
pub fn SourceRange::start(self : SourceRange) -> Int {
  self.first
}

///|
pub fn SourceRange::end(self : SourceRange) -> Int {
  self.last
}

///|
pub extend SourceRange with Eq::{equal, not_equal}

///|
pub extend SourceRange with Debug::{to_repr}

///|
/// A replacement in the transaction's old document, not an intermediate text.
pub struct TextEdit {
  priv from : Int
  priv to : Int
  priv inserted : String
}

///|
pub fn TextEdit::TextEdit(
  from~ : Int,
  to~ : Int,
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
pub(all) suberror DraftEditError {
  WrongBase
  InvalidEdit(String)
  IdentityExhausted
  Disposed
} derive(Eq, Debug)

///|
pub extend DraftEditError with Eq::{equal, not_equal}

///|
pub extend DraftEditError with Debug::{to_repr}

///|
pub(all) enum DraftTracking {
  Pattern
  Song
  TrackingUnavailable
  Disposed
} derive(Eq, Debug)

///|
pub extend DraftTracking with Eq::{equal, not_equal}

///|
pub extend DraftTracking with Debug::{to_repr}

///|
pub(all) enum DraftDiagnosticKind {
  Syntax
  TrackingUnavailable
  CompilerContract
  Disposed
} derive(Eq, Debug)

///|
pub extend DraftDiagnosticKind with Eq::{equal, not_equal}

///|
pub extend DraftDiagnosticKind with Debug::{to_repr}

///|
pub struct DraftDiagnostic {
  priv at : DraftVersion
  priv category : DraftDiagnosticKind
  priv detail : String
} derive(Eq, Debug)

///|
pub extend DraftDiagnostic with Eq::{equal, not_equal}

///|
pub extend DraftDiagnostic with Debug::{to_repr}

///|
fn DraftDiagnostic::DraftDiagnostic(
  at : DraftVersion,
  category : DraftDiagnosticKind,
  detail : String,
) -> DraftDiagnostic {
  { at, category, detail, }
}

///|
pub fn DraftDiagnostic::version(self : DraftDiagnostic) -> DraftVersion {
  self.at
}

///|
pub fn DraftDiagnostic::kind(self : DraftDiagnostic) -> DraftDiagnosticKind {
  self.category
}

///|
pub fn DraftDiagnostic::message(self : DraftDiagnostic) -> String {
  self.detail
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
pub(all) enum OriginUnavailable {
  SourceReset
  AtomRetired
  BrokenReference
} derive(Eq, Debug)

///|
pub extend OriginUnavailable with Eq::{equal, not_equal}

///|
pub extend OriginUnavailable with Debug::{to_repr}

///|
pub(all) enum OriginLocation {
  Located(SourceRange, Array[SourceRange])
  Unavailable(OriginUnavailable)
} derive(Eq, Debug)

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
priv struct LiveDefinition {
  id : @identity.DefinitionId
  name : String
  span : MiniSpan
  visible_after : Int
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
  definitions : Array[LiveDefinition]
  references : Array[LiveReference]
}

///|
fn SourceMap::SourceMap(
  epoch : @identity.SourceEpoch,
  serial : Int64,
  atoms : Array[LiveAtom],
  definitions : Array[LiveDefinition],
  references : Array[LiveReference],
) -> SourceMap {
  { epoch, serial, atoms, definitions, references, }
}

///|
fn SourceMap::empty(epoch : @identity.SourceEpoch) -> SourceMap {
  SourceMap(epoch, 0L, [], [], [])
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
fn SourceMap::advance(
  self : SourceMap,
  facts : SourceRecognition,
  edits : Array[TextEdit],
) -> SourceMap raise DraftEditError {
  let old_atoms : Map[String, LiveAtom] = Map([])
  let old_definitions : Map[String, LiveDefinition] = Map([])
  let old_references : Map[String, LiveReference] = Map([])
  for atom in self.atoms {
    if draft_map_untouched(atom.span, edits) is Some(span) {
      old_atoms[draft_span_key(atom.kind, span)] = atom
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
  SourceMap(self.epoch, counter.val, atoms, definitions, references)
}

///|
fn SourceMap::atom_at(
  self : SourceMap,
  kind : String,
  start : Int,
  end : Int,
) -> @identity.SourceAtomId? {
  for atom in self.atoms {
    if atom.kind == kind && atom.span.start == start && atom.span.end == end {
      return Some(atom.id)
    }
  }
  None
}

///|
fn SourceMap::resolve_reference(
  self : SourceMap,
  start : Int,
  end : Int,
  definition_span : MiniSpan,
  definition : @pattern.PatternDoc[@pattern.ControlMap],
) -> @pattern.ResolvedReference[@pattern.ControlMap] raise ParseError {
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
          raise ParseError("exact reference at \{start}: \{message}")
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
            _ => raise ParseError("exact reference epoch mismatch at \{start}")
          }
        }
      }
    }
  }
  raise ParseError("missing exact reference witness at \{start}")
}

///|
priv enum PlaybackPayload {
  Pattern(DraftVersion, SourceMap)
  Song(DraftVersion)
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
    Pattern(version, _) | Song(version) => Some(version)
    Text => None
  }
}

///|
/// Exact patterns and explicitly untracked runtime sources are distinct capabilities.
pub(all) enum PreparedPlayback {
  Pattern(@pattern.PatternSnapshotWithOrigins[@pattern.ControlMap], Double)
  Runtime(PlaySource)
}

///|
/// Compile this frozen input, independently of any subsequent Draft edits.
/// A failed exact compilation never falls back to runtime-only playback.
pub fn PlaybackInput::compile(
  self : PlaybackInput,
  previous? : @pattern.PatternDoc[@pattern.ControlMap]? = None,
  max_query_span? : @pattern.Rational? = None,
) -> Result[PreparedPlayback, String] {
  match self.payload {
    Text =>
      parse_play_source(self.input, previous~, max_query_span~).map(source => {
        Runtime(source)
      })
    Song(_) => {
      let source = match
        parse_play_source_with_origins(
          self.input,
          previous,
          max_query_span,
          syntax_depth_limit=Some(32),
        ) {
        Ok(source) => source
        Err(message) => return Err(message)
      }
      guard source.body() is Arrangement(_, _) else {
        return Err("song input changed source mode")
      }
      Ok(Runtime(source))
    }
    Pattern(_, origins) => {
      let source = match
        parse_play_source_with_origins(
          self.input,
          None,
          max_query_span,
          origins=Some(origins),
          syntax_depth_limit=Some(32),
        ) {
        Ok(source) => source
        Err(message) => return Err(message)
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
    InvalidTailDuration => "exact compilation: invalid tail duration"
    MissingAtomOrigin(id) =>
      "exact compilation: missing atom origin \{id.value()}"
    MissingReferenceBinding(id) =>
      "exact compilation: missing reference binding \{id.value()}"
  }
}

///|
/// Single owner of current text, causal source lifetimes and bounded parse state.
/// Playback acceptance and run eligibility belong to the caller, not this owner.
pub struct Draft {
  priv mut current : DraftState
  priv mut sources : SourceMap
  priv mut parsed : Result[PlaySource, String]
  priv mut last_valid_doc : @pattern.PatternDoc[@pattern.ControlMap]?
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
fn draft_parse(
  input : String,
  mode : DraftTracking,
  sources : SourceMap,
  previous : @pattern.PatternDoc[@pattern.ControlMap]?,
) -> Result[PlaySource, String] {
  match mode {
    TrackingUnavailable => Err("source tracking exceeds 8192 UTF-16 code units")
    Disposed => Err("Draft is disposed")
    Pattern =>
      parse_play_source_with_origins(
        input,
        previous,
        None,
        origins=Some(sources),
        syntax_depth_limit=Some(32),
      )
    Song =>
      parse_play_source_with_origins(
        input,
        previous,
        None,
        syntax_depth_limit=Some(32),
      )
  }
}

///|
fn draft_diagnostic(
  version : DraftVersion,
  mode : DraftTracking,
  parsed : Result[PlaySource, String],
) -> DraftDiagnostic? {
  match parsed {
    Ok(_) => None
    Err(message) =>
      Some(
        DraftDiagnostic(
          version,
          match mode {
            TrackingUnavailable => TrackingUnavailable
            Disposed => Disposed
            _ => Syntax
          },
          message,
        ),
      )
  }
}

///|
pub fn Draft::new(input : String) -> Draft raise DraftEditError {
  let epoch = next_draft_epoch()
  let facts = draft_recognize(input)
  let mode = draft_tracking(facts, Pattern)
  let empty = SourceMap::empty(epoch)
  let sources = match facts {
    Some(facts) if mode == Pattern => empty.advance(facts, [])
    _ => empty
  }
  let version = DraftVersion(epoch, 0L)
  let parsed = draft_parse(input, mode, sources, None)
  let last_valid_doc = match parsed {
    Ok(source) =>
      match source.body() {
        Pattern(doc) => Some(doc)
        _ => None
      }
    _ => None
  }
  {
    current: DraftState(
      input,
      version,
      mode,
      draft_diagnostic(version, mode, parsed),
    ),
    sources,
    parsed,
    last_valid_doc,
  }
}

///|
pub fn Draft::state(self : Draft) -> DraftState {
  self.current
}

///|
fn draft_utf16_boundary(text : String, offset : Int) -> Bool {
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
  guard self.current.mode != Disposed else { raise Disposed }
  guard tx.base == self.current.at else { raise WrongBase }
  let edits = draft_validate_edits(self.current.input, tx.edits)
  guard !edits.is_empty() else { return self.current }
  guard self.current.at.revision < DRAFT_IDENTITY_MAX else {
    raise IdentityExhausted
  }
  let input = draft_apply_edits(self.current.input, edits)
  let facts = draft_recognize(input)
  let mode = draft_tracking(facts, self.current.mode)
  let baseline = if mode == self.current.mode {
    self.sources
  } else {
    SourceMap::empty(next_draft_epoch())
  }
  let sources = match facts {
    Some(facts) if mode == Pattern => baseline.advance(facts, edits)
    _ => baseline
  }
  let version = DraftVersion(
    self.current.at.epoch,
    self.current.at.revision + 1L,
  )
  let parsed = draft_parse(input, mode, sources, self.last_valid_doc)
  let state = DraftState(
    input,
    version,
    mode,
    draft_diagnostic(version, mode, parsed),
  )
  // Commit only after all validation and checked identity allocation succeeded.
  self.sources = sources
  self.parsed = parsed
  self.current = state
  if parsed is Ok(source) {
    if source.body() is Pattern(doc) {
      self.last_valid_doc = Some(doc)
    }
  }
  state
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
  guard self.current.mode != Disposed else { return Err(Disposed) }
  try Draft::new(input) catch {
    error => Err(error)
  } noraise {
    fresh => {
      self.current = fresh.current
      self.sources = fresh.sources
      self.parsed = fresh.parsed
      self.last_valid_doc = fresh.last_valid_doc
      Ok(self.current)
    }
  }
}

///|
pub fn Draft::prepare_playback(
  self : Draft,
) -> Result[PlaybackInput, DraftDiagnostic] {
  if self.current.error is Some(error) {
    return Err(error)
  }
  let payload = match self.current.mode {
    Pattern => PlaybackPayload::Pattern(self.current.at, self.sources)
    Song => PlaybackPayload::Song(self.current.at)
    TrackingUnavailable =>
      return Err(
        DraftDiagnostic(
          self.current.at,
          TrackingUnavailable,
          "source tracking is unavailable",
        ),
      )
    Disposed =>
      return Err(
        DraftDiagnostic(self.current.at, Disposed, "Draft is disposed"),
      )
  }
  match self.parsed {
    Ok(source) =>
      if source.body() is Pattern(doc) {
        try doc.lower_with_origins() catch {
          error => {
            let diagnostic = DraftDiagnostic(
              self.current.at,
              CompilerContract,
              draft_origin_error(error),
            )
            self.current = DraftState(
              self.current.input,
              self.current.at,
              self.current.mode,
              Some(diagnostic),
            )
            return Err(diagnostic)
          }
        } noraise {
          _ => ()
        }
      }
    Err(message) =>
      return Err(DraftDiagnostic(self.current.at, Syntax, message))
  }
  Ok(PlaybackInput(self.current.input, payload))
}

///|
/// Locate every immutable binding in an origin's path, never a partial path.
pub fn Draft::locate_origin(
  self : Draft,
  origin : @pattern.EventOrigin,
) -> OriginLocation {
  guard self.current.mode == Pattern &&
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
pub fn Draft::dispose(self : Draft) -> Unit {
  self.current = DraftState(
    self.current.input,
    self.current.at,
    Disposed,
    Some(DraftDiagnostic(self.current.at, Disposed, "Draft is disposed")),
  )
  self.sources = SourceMap::empty(self.sources.epoch)
  self.parsed = Err("Draft is disposed")
  self.last_valid_doc = None
}
