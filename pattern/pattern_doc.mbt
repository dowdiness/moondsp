///|
#derive(Eq, Debug)
pub(all) suberror PatternDocError {
  MissingNode(String)
  DuplicateNodeId(String)
  EmptyPatternDocs
  InvalidSequenceWeights
  MissingAtomOrigin(@identity.PatternNodeId)
  MissingReferenceBinding(@identity.PatternNodeId)
  /// A control provider outside the bus signal set (ADR-0019): an opaque
  /// runtime pattern, or event selection inside the provider.
  UnsupportedControl(@identity.PatternNodeId)
}

///|
priv enum PatternDocNode[A] {
  Runtime(Pat[A])
  /// A continuous control as both its query form and its allocation-free
  /// bus signal for one key, and the authored signal it compiles.
  Continuous(Pat[A], @control.Control, BusSignal, @identity.SourceAtomId?)
  Reference(PatternDoc[A], ReferenceBinding?)
  Silence
  Pure(A)
  /// A pure value; the pattern carries its content signature. Without a
  /// source atom it has no exact origin.
  Atom(Pat[A], A, @identity.SourceAtomId?)
  Fast(@identity.PatternNodeId, Rational)
  Slow(@identity.PatternNodeId, Rational)
  Gate(@identity.PatternNodeId, Rational)
  Rev(@identity.PatternNodeId)
  /// The map sees each event's controls, read and written through the
  /// access its constructor captured.
  FilterMap(@identity.PatternNodeId, (A) -> A?, ControlAccess[A])
  Euclid(@identity.PatternNodeId, Int32, Int32, Int32)
  DegradeBy(@identity.PatternNodeId, Double, Int32)
  Every(@identity.PatternNodeId, Int32, TimeTransform)
  Jux(@identity.PatternNodeId, TimeTransform, ControlAccess[A])
  /// The right-hand controls merge into each left-hand event, as buses.
  /// The provider is a document of its own, as a reference keeps its
  /// definition: it sets controls and sounds nothing (ADR-0022).
  MergeControl(@identity.PatternNodeId, PatternDoc[ControlMap])
  /// Each left-hand event takes the right-hand value at its onset; the value
  /// does not change while the event sounds, so it derives no bus.
  MergeValues(@identity.PatternNodeId, ProvidedValues[A])
  Sequence(Array[@identity.PatternNodeId])
  WeightedSequence(Array[@identity.PatternNodeId], Array[Int32])
  Stack(Array[@identity.PatternNodeId])
}

///|
/// The right side of `merge_values`, lowered once: the change each value
/// makes, and what the merge records of the provider document.
priv struct ProvidedValues[A] {
  changes : Pat[(A) -> A]
  /// Every provider node, for the merged events' paths (ADR-0018).
  nodes : Array[@identity.PatternNodeId]
  revision : @identity.Revision
  cache_token : Array[Int64]
}

///|
priv struct PatternDocEntry[A] {
  generation : Int64
  revision : @identity.Revision
  node : PatternDocNode[A]
  source_frame : @identity.SourceFrameId?
}

///|
let pattern_node_generation_counter : Ref[Int64] = Ref(0L)

///|
fn next_pattern_node_generation() -> Int64 {
  pattern_node_generation_counter.val = pattern_node_generation_counter.val + 1L
  pattern_node_generation_counter.val
}

///|
fn[A] PatternDocNode::snapshot(self : PatternDocNode[A]) -> PatternDocNode[A] {
  match self {
    Runtime(pat) => Runtime(pat)
    Continuous(pat, key, signal, source) => Continuous(pat, key, signal, source)
    Reference(definition, binding) => Reference(definition, binding)
    Silence => Silence
    Pure(value) => Pure(value)
    Atom(pat, value, atom) => Atom(pat, value, atom)
    Fast(child, factor) => Fast(child, factor)
    Slow(child, factor) => Slow(child, factor)
    Gate(child, factor) => Gate(child, factor)
    Rev(child) => Rev(child)
    FilterMap(child, f, access) => FilterMap(child, f, access)
    Euclid(child, k, n, rotation) => Euclid(child, k, n, rotation)
    DegradeBy(child, p, seed) => DegradeBy(child, p, seed)
    Every(child, n, f) => Every(child, n, f)
    Jux(child, transform, access) => Jux(child, transform, access)
    MergeControl(left, right) => MergeControl(left, right)
    MergeValues(left, provided) => MergeValues(left, provided)
    Sequence(children) => Sequence(children.copy())
    WeightedSequence(children, weights) =>
      WeightedSequence(children.copy(), weights.copy())
    Stack(children) => Stack(children.copy())
  }
}

///|
fn[A] PatternDocEntry::snapshot(
  self : PatternDocEntry[A],
) -> PatternDocEntry[A] {
  {
    generation: self.generation,
    revision: self.revision,
    node: self.node.snapshot(),
    source_frame: self.source_frame,
  }
}

///|
fn[A] copy_pattern_nodes(
  nodes : Map[String, PatternDocEntry[A]],
) -> Map[String, PatternDocEntry[A]] {
  let result : Map[String, PatternDocEntry[A]] = Map([])
  nodes.each(fn(id, entry) { result[id] = entry.snapshot() })
  result
}

///|
fn[A] singleton_pattern_nodes(
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
) -> Map[String, PatternDocEntry[A]] {
  let nodes : Map[String, PatternDocEntry[A]] = Map([])
  nodes[id.value()] = {
    generation: next_pattern_node_generation(),
    revision: @identity.Revision::zero(),
    node: node.snapshot(),
    source_frame: None,
  }
  nodes
}

///|
fn[A] insert_pattern_node(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
  revision~ : @identity.Revision,
) -> Unit raise PatternDocError {
  let key = id.value()
  if nodes.contains(key) {
    raise DuplicateNodeId(key)
  }
  nodes[key] = {
    generation: next_pattern_node_generation(),
    revision,
    node: node.snapshot(),
    source_frame: None,
  }
}

///|
fn[A] merge_pattern_nodes(
  target : Map[String, PatternDocEntry[A]],
  source : Map[String, PatternDocEntry[A]],
) -> Unit raise PatternDocError {
  source.each((id, entry) => {
    if target.contains(id) {
      raise DuplicateNodeId(id)
    }
    target[id] = entry.snapshot()
  })
}

///|
fn[A] aggregate_pattern_revision(
  docs : Array[PatternDoc[A]],
) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for doc in docs {
    revision = revision.combine(doc.revision)
  }
  revision.next()
}

///|
fn[A] replace_pattern_node(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
) -> Unit raise PatternDocError {
  let key = id.value()
  match nodes.get(key) {
    None => raise MissingNode(key)
    Some(entry) =>
      nodes[key] = {
        generation: next_pattern_node_generation(),
        revision: entry.revision.next(),
        node: node.snapshot(),
        source_frame: None,
      }
  }
}

///|
fn append_pattern_cache_token(
  target : Array[Int64],
  source : Array[Int64],
) -> Unit {
  for value in source {
    target.push(value)
  }
}

///|
fn pattern_cache_token_equal(left : Array[Int64], right : Array[Int64]) -> Bool {
  guard left.length() == right.length() else { return false }
  for index in 0..<left.length() {
    guard left[index] == right[index] else { return false }
  }
  true
}

///|
fn[A] pattern_node_cache_token_memoized(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  memo : Map[String, Array[Int64]],
) -> Array[Int64] raise PatternDocError {
  let key = id.value()
  match memo.get(key) {
    Some(token) => token
    None =>
      match nodes.get(key) {
        None => raise MissingNode(id.value())
        Some(entry) => {
          let token : Array[Int64] = [entry.generation]
          match entry.node {
            Reference(definition, _) =>
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(
                  definition.nodes,
                  definition.root,
                  {},
                ),
              )
            Runtime(_)
            | Continuous(_, _, _, _)
            | Silence
            | Pure(_)
            | Atom(_, _, _) => ()
            Fast(child, _)
            | Slow(child, _)
            | Gate(child, _)
            | Rev(child)
            | FilterMap(child, _, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _, _) =>
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(nodes, child, memo),
              )
            MergeControl(left, right) => {
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(nodes, left, memo),
              )
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(
                  right.nodes,
                  right.root,
                  Map([]),
                ),
              )
            }
            MergeValues(left, provided) => {
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(nodes, left, memo),
              )
              append_pattern_cache_token(token, provided.cache_token)
            }
            Sequence(children) | Stack(children) =>
              for child in children {
                append_pattern_cache_token(
                  token,
                  pattern_node_cache_token_memoized(nodes, child, memo),
                )
              }
            WeightedSequence(children, weights) => {
              for weight in weights {
                token.push(weight.to_int64())
              }
              for child in children {
                append_pattern_cache_token(
                  token,
                  pattern_node_cache_token_memoized(nodes, child, memo),
                )
              }
            }
          }
          memo[key] = token
          token
        }
      }
  }
}

///|
fn[A] pattern_node_revision(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
) -> @identity.Revision raise PatternDocError {
  let memo : Map[String, @identity.Revision] = Map([])
  pattern_node_revision_memoized(nodes, id, memo)
}

///|
fn[A] copy_reachable_pattern_nodes(
  source : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  target : Map[String, PatternDocEntry[A]],
) -> Unit raise PatternDocError {
  let key = id.value()
  if target.contains(key) {
    return
  }
  match source.get(key) {
    None => raise MissingNode(key)
    Some(entry) => {
      target[key] = entry.snapshot()
      match entry.node {
        Reference(_, _) => ()
        Runtime(_)
        | Continuous(_, _, _, _)
        | Silence
        | Pure(_)
        | Atom(_, _, _) => ()
        Fast(child, _)
        | Slow(child, _)
        | Gate(child, _)
        | Rev(child)
        | FilterMap(child, _, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _, _) =>
          copy_reachable_pattern_nodes(source, child, target)
        MergeControl(left, _) | MergeValues(left, _) =>
          copy_reachable_pattern_nodes(source, left, target)
        Sequence(children) | Stack(children) | WeightedSequence(children, _) =>
          for child in children {
            copy_reachable_pattern_nodes(source, child, target)
          }
      }
    }
  }
}

///|
fn[A] pattern_node_revision_memoized(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  memo : Map[String, @identity.Revision],
) -> @identity.Revision raise PatternDocError {
  let key = id.value()
  match memo.get(key) {
    Some(revision) => revision
    None =>
      match nodes.get(key) {
        None => raise MissingNode(id.value())
        Some(entry) => {
          let mut revision = entry.revision
          match entry.node {
            Reference(definition, _) =>
              revision = revision.combine(definition.revision)
            Runtime(_)
            | Continuous(_, _, _, _)
            | Silence
            | Pure(_)
            | Atom(_, _, _) => ()
            Fast(child, _)
            | Slow(child, _)
            | Gate(child, _)
            | Rev(child)
            | FilterMap(child, _, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _, _) =>
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, child, memo),
              )
            MergeControl(left, right) => {
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, left, memo),
              )
              revision = revision.combine(right.revision)
            }
            MergeValues(left, provided) => {
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, left, memo),
              )
              revision = revision.combine(provided.revision)
            }
            Sequence(children)
            | Stack(children)
            | WeightedSequence(children, _) =>
              for child in children {
                revision = revision.combine(
                  pattern_node_revision_memoized(nodes, child, memo),
                )
              }
          }
          memo[key] = revision
          revision
        }
      }
  }
}

///|
#derive(Eq)
priv enum PatternNodePathLink {
  PathEnd
  PathLink(@identity.PatternNodeId, PatternNodePathLink)
}

///|
#derive(Eq, Debug)
pub struct PatternNodePath {
  priv root : @identity.PatternNodeId
  priv descendants : PatternNodePathLink
}

///|
impl Debug for PatternNodePathLink with fn to_repr(self) -> @debug.Repr {
  match self {
    PathEnd => {
      let nodes : Array[@identity.PatternNodeId] = []
      @debug.Repr(nodes)
    }
    PathLink(first, rest) => {
      let mut length = 1
      let mut next = rest
      while next is PathLink(_, tail) {
        length += 1
        next = tail
      }
      let nodes = Array::make(length, first)
      let mut index = 1
      next = rest
      while next is PathLink(id, tail) {
        nodes[index] = id
        index += 1
        next = tail
      }
      @debug.Repr(nodes)
    }
  }
}

///|
fn PatternNodePath::PatternNodePath(
  root : @identity.PatternNodeId,
  descendants~ : Array[@identity.PatternNodeId] = [],
) -> PatternNodePath {
  let mut linked = PathEnd
  for index = descendants.length() - 1; index >= 0; index = index - 1 {
    linked = PathLink(descendants[index], linked)
  }
  { root, descendants: linked, }
}

///|
pub fn PatternNodePath::leaf(self : PatternNodePath) -> @identity.PatternNodeId {
  let mut next = self.descendants
  let mut leaf = self.root
  while next is PathLink(id, rest) {
    leaf = id
    next = rest
  }
  leaf
}

///|
pub fn PatternNodePath::nodes(
  self : PatternNodePath,
) -> Array[@identity.PatternNodeId] {
  let mut length = 1
  let mut next = self.descendants
  while next is PathLink(_, rest) {
    length += 1
    next = rest
  }
  let nodes = Array::make(length, self.root)
  let mut index = 1
  next = self.descendants
  while next is PathLink(id, rest) {
    nodes[index] = id
    index += 1
    next = rest
  }
  nodes
}

///|
fn PatternNodePath::prepend(
  self : PatternNodePath,
  parent : @identity.PatternNodeId,
) -> PatternNodePath {
  { root: parent, descendants: PathLink(self.root, self.descendants), }
}

///|
pub struct PatternSnapshotEvent[A] {
  priv event : Event[A]
  priv path : PatternNodePath
  priv controls : Controls
}

///|
fn[A] PatternSnapshotEvent::PatternSnapshotEvent(
  event~ : Event[A],
  path~ : PatternNodePath,
  controls~ : Controls,
) -> PatternSnapshotEvent[A] {
  { event, path, controls, }
}

///|
/// This event's controls: its values at the onset and the buses they follow
/// while it sounds.
pub fn[A] PatternSnapshotEvent::controls(
  self : PatternSnapshotEvent[A],
) -> Controls {
  self.controls
}

///|
pub fn[A] PatternSnapshotEvent::event(
  self : PatternSnapshotEvent[A],
) -> Event[A] {
  self.event
}

///|
pub fn[A] PatternSnapshotEvent::pattern_nodes(
  self : PatternSnapshotEvent[A],
) -> Array[@identity.PatternNodeId] {
  self.path.nodes()
}

///|
pub fn[A] PatternSnapshotEvent::pattern_node_path(
  self : PatternSnapshotEvent[A],
) -> PatternNodePath {
  self.path
}

///|
/// One resolved name-use edge, distinct from graph/voice identity.
#derive(Eq, Debug)
pub struct ReferenceBinding {
  priv id : @identity.ReferenceBindingId
  priv reference : @identity.ReferenceId
  priv definition : @identity.DefinitionId
}

///|
fn ReferenceBinding::ReferenceBinding(
  id : @identity.ReferenceBindingId,
  reference : @identity.ReferenceId,
  definition : @identity.DefinitionId,
) -> ReferenceBinding {
  { id, reference, definition, }
}

///|
pub fn ReferenceBinding::id(
  self : ReferenceBinding,
) -> @identity.ReferenceBindingId {
  self.id
}

///|
pub fn ReferenceBinding::reference(
  self : ReferenceBinding,
) -> @identity.ReferenceId {
  self.reference
}

///|
pub fn ReferenceBinding::definition(
  self : ReferenceBinding,
) -> @identity.DefinitionId {
  self.definition
}

///|
#derive(Eq, Debug)
priv enum OriginBindings {
  End
  Link(ReferenceBinding, OriginBindings)
}

///|
/// Exact source identity. Bindings run from outer use site to inner definition.
#derive(Eq, Debug)
pub struct EventOrigin {
  priv atom : @identity.SourceAtomId
  priv bindings : OriginBindings
}

///|
fn EventOrigin::EventOrigin(
  atom : @identity.SourceAtomId,
  bindings~ : OriginBindings = End,
) -> EventOrigin {
  { atom, bindings, }
}

///|
pub fn EventOrigin::atom(self : EventOrigin) -> @identity.SourceAtomId {
  self.atom
}

///|
pub fn EventOrigin::bindings(self : EventOrigin) -> Array[ReferenceBinding] {
  let result = []
  for remaining = self.bindings {
    match remaining {
      End => break
      Link(binding, rest) => {
        result.push(binding)
        continue rest
      }
    }
  }
  result
}

///|
/// Write reference/binding/definition serial triples into caller-owned storage.
/// Returns the number of links, or -1 without modifying storage if the complete
/// path does not fit or cannot be represented exactly as JavaScript numbers.
/// Validation and copying are linear in path length; neither allocates.
pub fn EventOrigin::write_binding_serials(
  self : EventOrigin,
  target : Array[Double],
  offset : Int32,
  limit : Int32,
) -> Int32 {
  guard offset >= 0 && offset <= target.length() && limit >= 0 else {
    return -1
  }
  let available = (target.length() - offset) / 3
  let epoch = self.atom.epoch()
  let mut count = 0
  let mut remaining = self.bindings
  while remaining is Link(binding, rest) {
    if count == limit ||
      count == available ||
      binding.reference.epoch() != epoch ||
      binding.id.epoch() != epoch ||
      binding.definition.epoch() != epoch ||
      binding.reference.serial() > 9007199254740991L ||
      binding.id.serial() > 9007199254740991L ||
      binding.definition.serial() > 9007199254740991L {
      return -1
    }
    count += 1
    remaining = rest
  }
  remaining = self.bindings
  let mut cursor = offset
  while remaining is Link(binding, rest) {
    target[cursor] = binding.reference.serial().to_double()
    target[cursor + 1] = binding.id.serial().to_double()
    target[cursor + 2] = binding.definition.serial().to_double()
    cursor += 3
    remaining = rest
  }
  count
}

///|
/// Name resolution supplies this witness; lowering never guesses from spelling.
pub struct ResolvedReference[A] {
  priv definition : PatternDoc[A]
  priv binding : ReferenceBinding
}

///|
pub fn[A] ResolvedReference::ResolvedReference(
  definition~ : PatternDoc[A],
  definition_id~ : @identity.DefinitionId,
  reference~ : @identity.ReferenceId,
  binding~ : @identity.ReferenceBindingId,
) -> ResolvedReference[A] raise @identity.StableIdError {
  guard definition_id.epoch() == reference.epoch() &&
    reference.epoch() == binding.epoch() else {
    raise @identity.InvalidId("reference binding spans source epochs")
  }
  { definition, binding: ReferenceBinding(binding, reference, definition_id), }
}

///|
/// Cold compilation policy. Contexts accumulate inner-to-outer while descending.
/// Query callbacks only carry the completed origin; they never extend it.
priv trait DocumentOrigin {
  fn make_origin(
    @identity.PatternNodeId,
    @identity.SourceAtomId?,
    OriginBindings,
  ) -> Self raise PatternDocError
  fn bind_context(@identity.PatternNodeId, ReferenceBinding?, OriginBindings) -> OriginBindings raise PatternDocError
  fn carries_origins() -> Bool
}

///|
impl DocumentOrigin for Unit with fn make_origin(_, _, _) {
  ()
}

///|
impl DocumentOrigin for Unit with fn bind_context(_, _, _) {
  End
}

///|
impl DocumentOrigin for Unit with fn carries_origins() {
  false
}

///|
impl DocumentOrigin for EventOrigin with fn carries_origins() {
  true
}

///|
impl DocumentOrigin for EventOrigin with fn make_origin(node, atom, context) {
  guard atom is Some(atom) else { raise MissingAtomOrigin(node) }
  let mut bindings = End
  for remaining = context {
    match remaining {
      End => break
      Link(binding, rest) => {
        bindings = Link(binding, bindings)
        continue rest
      }
    }
  }
  EventOrigin(atom, bindings~)
}

///|
impl DocumentOrigin for EventOrigin with fn bind_context(node, binding, context) {
  guard binding is Some(binding) else { raise MissingReferenceBinding(node) }
  Link(binding, context)
}

///|
priv struct ScopedValue[A, O] {
  value : A
  scope : PatternNodePath
  origin : O
  mut source_frame : @identity.SourceFrameId?
  mut source_start : Double
  bindings : FixedArray[BusBinding]
}

///|
fn[A, O] ScopedValue::ScopedValue(
  value : A,
  scope : PatternNodePath,
  origin : O,
  source_frame~ : @identity.SourceFrameId? = None,
  source_start~ : Double = -1.0,
  bindings~ : FixedArray[BusBinding] = no_bus_bindings,
) -> ScopedValue[A, O] {
  { value, scope, origin, source_frame, source_start, bindings, }
}

///|
fn[A, O] ScopedValue::remap(
  self : ScopedValue[A, O],
  value : A,
  scope : PatternNodePath,
  bindings~ : FixedArray[BusBinding] = self.bindings,
) -> ScopedValue[A, O] {
  ScopedValue(
    value,
    scope,
    self.origin,
    source_frame=self.source_frame,
    source_start=self.source_start,
    bindings~,
  )
}

///|
fn[A, O] Pat::shift_buses(
  self : Pat[ScopedValue[A, O]],
  offset : Int32,
) -> Pat[ScopedValue[A, O]] {
  self.map_payload(value => {
    ..value,
    bindings: shift_bus_bindings(value.bindings, offset),
  })
}

///|
fn[A, O] ScopedValue::prepend(
  self : ScopedValue[A, O],
  id : @identity.PatternNodeId,
) -> ScopedValue[A, O] {
  self.remap(self.value, self.scope.prepend(id))
}

///|
/// Pair each event's payload with its projection at the start of the event's
/// fragment (`project_controls`). `buses` must be on this pattern's clock;
/// child bodies share it.
fn[A, O] Pat::with_projected_controls(
  self : Pat[ScopedValue[A, O]],
  buses : Array[ControlBus],
  access : ControlAccess[A],
) -> Pat[(A, ScopedValue[A, O])] {
  self.map_events((value, time) => {
    (
      (access.with_controls)(
        value.value,
        project_controls(
          (access.controls)(value.value),
          value.bindings,
          buses,
          time,
        ),
      ),
      value,
    )
  })
}

///|
/// The payloads as controls leave lowering, at the start of each fragment.
fn[A : WithControls, O] Pat::project_controls(
  self : Pat[ScopedValue[A, O]],
  buses : Array[ControlBus],
) -> Pat[A] {
  self.map_events((value, time) => {
    value.value.with_controls(
      project_controls(value.value.controls(), value.bindings, buses, time),
    )
  })
}

///|
/// Map each payload with its fragment's start time, keeping the pattern's
/// shape and content.
fn[A, B] Pat::map_events(self : Pat[A], f : (A, Rational) -> B) -> Pat[B] {
  let body : PatBody[B] = match self.body {
    Silence => Silence
    Opaque(children) => Opaque(children.map(child => child.map_events(f)))
    Overlay(children) => Overlay(children.map(child => child.map_events(f)))
  }
  make_pat(
    fn(arc) {
      self
      .query(arc)
      .map(event => {
        whole: event.whole,
        part: event.part,
        value: f(event.value, event.part.begin),
      })
    },
    self.metadata.period,
    body,
    self.metadata.scope,
    self.metadata.content,
  )
}

///|
/// Exact lowering creates a fresh ScopedValue for every queried atom, and each
/// transform remaps it. Pure/Runtime cannot enter that lowering. Capture on those
/// owned query values without another array, event, origin, or option allocation.
/// General lowering skips this operation because Pure may share a cold payload.
fn[A, O] Pat::capture_source_frame(
  self : Pat[ScopedValue[A, O]],
  frame : @identity.SourceFrameId?,
  span : Double,
) -> Pat[ScopedValue[A, O]] {
  let body : PatBody[ScopedValue[A, O]] = match self.body {
    Silence => Silence
    Opaque(children) =>
      Opaque(children.map(child => child.capture_source_frame(frame, span)))
    Overlay(children) =>
      Overlay(children.map(child => child.capture_source_frame(frame, span)))
  }
  make_pat(
    fn(arc) {
      let events = self.query(arc)
      for event in events {
        event.value.source_frame = frame
        event.value.source_start = match event.whole {
          Some(whole) => {
            let start = whole.begin.to_double()
            start - (start / span).floor() * span
          }
          None => -1.0
        }
      }
      events
    },
    self.metadata.period,
    body,
    self.metadata.scope,
    self.metadata.content,
  )
}

///|
fn[A : WithControls, O] scoped_event(
  event : Event[ScopedValue[A, O]],
  buses : Array[ControlBus],
  table : Array[BusSignal],
) -> PatternSnapshotEvent[A] {
  let value = event.value
  let controls = Controls::lowered(
    value.value.controls(),
    value.bindings,
    buses,
    table,
    event.part.begin,
  )
  PatternSnapshotEvent(
    event={
      whole: event.whole,
      part: event.part,
      value: value.value.with_controls(controls.values()),
    },
    path=value.scope,
    controls~,
  )
}

///|
pub struct EventWithOrigin[A] {
  priv event : Event[A]
  priv origin : EventOrigin
  priv scope : PatternNodePath
  priv source_frame : @identity.SourceFrameId?
  priv source_start : Double
  priv controls : Controls
}

///|
fn[A : WithControls] EventWithOrigin::EventWithOrigin(
  event : Event[ScopedValue[A, EventOrigin]],
  buses : Array[ControlBus],
  table : Array[BusSignal],
) -> EventWithOrigin[A] {
  let value = event.value
  let controls = Controls::lowered(
    value.value.controls(),
    value.bindings,
    buses,
    table,
    event.part.begin,
  )
  {
    event: {
      whole: event.whole,
      part: event.part,
      value: value.value.with_controls(controls.values()),
    },
    origin: event.value.origin,
    scope: event.value.scope,
    source_frame: event.value.source_frame,
    source_start: event.value.source_start,
    controls,
  }
}

///|
/// This event's controls: its values at the onset and the buses they follow
/// while it sounds.
pub fn[A] EventWithOrigin::controls(self : EventWithOrigin[A]) -> Controls {
  self.controls
}

///|
pub fn[A] EventWithOrigin::event(self : EventWithOrigin[A]) -> Event[A] {
  self.event
}

///|
pub fn[A] EventWithOrigin::origin(self : EventWithOrigin[A]) -> EventOrigin {
  self.origin
}

///|
pub fn[A] EventWithOrigin::source_frame(
  self : EventWithOrigin[A],
) -> @identity.SourceFrameId? {
  self.source_frame
}

///|
pub fn[A] EventWithOrigin::source_start(self : EventWithOrigin[A]) -> Double {
  self.source_start
}

///|
pub fn[A] EventWithOrigin::pattern_node_path(
  self : EventWithOrigin[A],
) -> PatternNodePath {
  self.scope
}

///|
pub extend EventOrigin with Eq::{equal, not_equal}

///|
pub extend EventOrigin with Debug::{to_repr}

///|
pub extend ReferenceBinding with Eq::{equal, not_equal}

///|
pub extend ReferenceBinding with Debug::{to_repr}

///|
fn[A] append_reachable_pattern_source_ids(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  result : Array[@identity.PatternNodeId],
  seen : Map[String, Bool],
) -> Unit raise PatternDocError {
  let key = id.value()
  if seen.contains(key) {
    return
  }
  match nodes.get(key) {
    None => raise MissingNode(key)
    Some(entry) => {
      seen[key] = true
      result.push(id)
      match entry.node {
        Reference(definition, _) =>
          append_reachable_pattern_source_ids(
            definition.nodes,
            definition.root,
            result,
            {},
          )
        Runtime(_)
        | Continuous(_, _, _, _)
        | Silence
        | Pure(_)
        | Atom(_, _, _) => ()
        Fast(child, _)
        | Slow(child, _)
        | Gate(child, _)
        | Rev(child)
        | FilterMap(child, _, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _, _) =>
          append_reachable_pattern_source_ids(nodes, child, result, seen)
        MergeControl(left, right) => {
          append_reachable_pattern_source_ids(nodes, left, result, seen)
          append_reachable_pattern_source_ids(
            right.nodes,
            right.root,
            result,
            seen,
          )
        }
        MergeValues(left, provided) => {
          append_reachable_pattern_source_ids(nodes, left, result, seen)
          for provider_node in provided.nodes {
            if !seen.contains(provider_node.value()) {
              seen[provider_node.value()] = true
              result.push(provider_node)
            }
          }
        }
        Sequence(children) | Stack(children) | WeightedSequence(children, _) =>
          for child in children {
            append_reachable_pattern_source_ids(nodes, child, result, seen)
          }
      }
    }
  }
}

///|
fn[A] pattern_source_path_for_opaque_children(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  children : Array[@identity.PatternNodeId],
) -> PatternNodePath raise PatternDocError {
  let descendants : Array[@identity.PatternNodeId] = []
  let seen : Map[String, Bool] = Map([])
  seen[id.value()] = true
  for child in children {
    append_reachable_pattern_source_ids(nodes, child, descendants, seen)
  }
  PatternNodePath(id, descendants~)
}

///|
priv struct CompiledEntry[A, O] {
  key : String
  source : Pat[ScopedValue[A, O]]
}

///|
fn[A, O] CompiledEntry::CompiledEntry(
  key : String,
  source : Pat[ScopedValue[A, O]],
) -> CompiledEntry[A, O] {
  { key, source, }
}

///|
/// One execution kernel; raw events and scoped/origin views are projections.
/// `buses` are in this subtree's local time; event bindings index into them.
priv struct CompiledPattern[A, O] {
  pat : Pat[ScopedValue[A, O]]
  entries : Array[CompiledEntry[A, O]]
  buses : Array[ControlBus]
}

///|
fn[A, O] CompiledPattern::CompiledPattern(
  pat : Pat[ScopedValue[A, O]],
  entries : Array[CompiledEntry[A, O]],
  buses~ : Array[ControlBus] = [],
) -> CompiledPattern[A, O] {
  { pat, entries, buses, }
}

///|
/// Apply an enclosing node's time transform to every bus.
fn[A, O] CompiledPattern::map_buses(
  self : CompiledPattern[A, O],
  f : (BusSignal) -> BusSignal,
) -> CompiledPattern[A, O] {
  { ..self, buses: self.buses.map(bus => bus.map_signal(f)), }
}

///|
/// Renumber this child's bindings after `offset` earlier sibling buses.
fn[A, O] CompiledPattern::shift_buses(
  self : CompiledPattern[A, O],
  offset : Int32,
) -> CompiledPattern[A, O] {
  if offset == 0 || self.buses.is_empty() {
    return self
  }
  CompiledPattern(
    self.pat.shift_buses(offset),
    self.entries.map(entry => {
      CompiledEntry(entry.key, entry.source.shift_buses(offset))
    }),
    buses=self.buses,
  )
}

///|
/// Concatenate sibling buses; `wrap(index, signal)` applies the parent's
/// time partition for that child. Returns children with renumbered bindings.
fn[A, O] concat_child_buses(
  children : Array[CompiledPattern[A, O]],
  wrap : (Int32, BusSignal) -> BusSignal,
) -> (Array[CompiledPattern[A, O]], Array[ControlBus]) {
  let buses : Array[ControlBus] = []
  let shifted = children.mapi((index, child) => {
    let offset = buses.length()
    for bus in child.buses {
      buses.push(bus.map_signal(signal => wrap(index, signal)))
    }
    child.shift_buses(offset)
  })
  (shifted, buses)
}

///|
fn[A, O] CompiledPattern::single_material(
  pat : Pat[ScopedValue[A, O]],
  id : @identity.PatternNodeId,
) -> CompiledPattern[A, O] {
  CompiledPattern(
    pat,
    pat
    .entries()
    .map(_ => CompiledEntry("\{id.value().length()}:\{id.value()}", pat)),
  )
}

///|
fn[A, O] CompiledPattern::transform(
  self : CompiledPattern[A, O],
  f : (Pat[ScopedValue[A, O]]) -> Pat[ScopedValue[A, O]],
) -> CompiledPattern[A, O] {
  CompiledPattern(
    f(self.pat),
    self.entries.map(entry => CompiledEntry(entry.key, f(entry.source))),
    buses=self.buses,
  )
}

///|
fn[A, O] opaque_compiled_entries(
  pat : Pat[ScopedValue[A, O]],
  id : @identity.PatternNodeId,
) -> Array[CompiledEntry[A, O]] {
  pat
  .entries()
  .map(entry => {
    CompiledEntry(
      "\{id.value().length()}:\{id.value()}/\{entry.entry_key()}",
      entry,
    )
  })
}

///|
fn[A, O : DocumentOrigin] lower_pattern_node_cached(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  cache : CompiledCache[A, O],
  controls : CompiledCache[A, Unit],
  token_memo : Map[String, Array[Int64]],
  context : OriginBindings,
) -> CompiledPattern[A, O] raise PatternDocError {
  let token = pattern_node_cache_token_memoized(nodes, id, token_memo)
  match cache.lookup(id, token, context) {
    Some(compiled) => compiled
    None => {
      let compiled = compile_pattern_node(
        nodes, id, cache, controls, token_memo, context,
      )
      cache.store(id, token, context, compiled)
      compiled
    }
  }
}

///|
fn[A, O : DocumentOrigin] compile_pattern_node(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  cache : CompiledCache[A, O],
  controls : CompiledCache[A, Unit],
  token_memo : Map[String, Array[Int64]],
  context : OriginBindings,
) -> CompiledPattern[A, O] raise PatternDocError {
  guard nodes.get(id.value()) is Some(entry) else {
    raise MissingNode(id.value())
  }
  fn lower(
    child : @identity.PatternNodeId,
  ) -> CompiledPattern[A, O] raise PatternDocError {
    lower_pattern_node_cached(
      nodes, child, cache, controls, token_memo, context,
    )
  }
  fn prepend(pat : Pat[ScopedValue[A, O]]) -> Pat[ScopedValue[A, O]] {
    pat.map_payload(value => value.prepend(id))
  }
  let compiled = match entry.node {
    Reference(definition, binding) => {
      let bound_context = O::bind_context(id, binding, context)
      let target = lower_pattern_node_cached(
        definition.nodes,
        definition.root,
        cache,
        controls,
        {},
        bound_context,
      )
      CompiledPattern(
        prepend(target.pat),
        Array::makei(target.entries.length(), index => {
          CompiledEntry(
            "\{id.value().length()}:\{id.value()}/member:\{index}",
            prepend(target.entries[index].source),
          )
        }),
        buses=target.buses,
      )
    }
    Runtime(pat) | Continuous(pat, _, _, _) => {
      let origin : O = O::make_origin(id, None, context)
      let path = PatternNodePath(id)
      let source = pat.map_payload(value => ScopedValue(value, path, origin))
      CompiledPattern(source, opaque_compiled_entries(source, id))
    }
    Silence => CompiledPattern::single_material(Pat::silence(), id)
    Pure(value) => {
      let origin : O = O::make_origin(id, None, context)
      let path = PatternNodePath(id)
      CompiledPattern::single_material(
        Pat::pure(ScopedValue(value, path, origin)),
        id,
      )
    }
    Atom(pat, _, atom) => {
      let origin : O = O::make_origin(id, atom, context)
      let path = PatternNodePath(id)
      let source = pat.map_payload(value => ScopedValue(value, path, origin))
      CompiledPattern(source, opaque_compiled_entries(source, id))
    }
    Fast(child, factor) => {
      let child = lower(child)
      let result = child
        .transform(pat => prepend(pat.fast(factor)))
        .map_buses(signal => {
          signal.through(TimeTransform::Fast(factor).time_map())
        })
      if factor.num <= 0L {
        CompiledPattern(result.pat, [], buses=result.buses)
      } else {
        result
      }
    }
    Slow(child, factor) => {
      let child = lower(child)
      let result = child
        .transform(pat => prepend(pat.slow(factor)))
        .map_buses(signal => {
          signal.through(TimeTransform::Slow(factor).time_map())
        })
      if factor.num <= 0L {
        CompiledPattern(result.pat, [], buses=result.buses)
      } else {
        result
      }
    }
    Gate(child, factor) =>
      lower(child).transform(pat => prepend(pat.gate(factor)))
    Rev(child) =>
      lower(child)
      .transform(pat => prepend(pat.rev()))
      .map_buses(signal => signal.through(Some(MirrorCycles)))
    // The map sees the child's controls with their bus values, on the
    // child's clock. Returning them unchanged keeps the own values and their
    // buses; a replaced value becomes the event's own values and follows no
    // bus, since a bus would undo the mapping.
    FilterMap(child, f, access) => {
      let child = lower(child)
      child.transform(pat => {
        pat
        .with_projected_controls(child.buses, access)
        .filter_map_payload(
          pair => {
            let (projected, value) = pair
            f(projected).map(mapped => {
              if physical_equal(mapped, projected) {
                value.prepend(id)
              } else {
                value.remap(
                  mapped,
                  value.scope.prepend(id),
                  bindings=no_bus_bindings,
                )
              }
            })
          },
          "",
        )
      })
    }
    Euclid(child, k, n, rotation) => {
      let child = lower(child)
      let compiled = CompiledPattern::single_material(
        prepend(child.pat.euclid(k, n, rotation~)),
        id,
      )
      { ..compiled, buses: child.buses, }.map_buses(signal => {
        euclid_slots(k, n, rotation, signal)
      })
    }
    DegradeBy(child, p, seed) =>
      lower(child).transform(pat => prepend(pat.degrade_by(p, seed~)))
    Every(child_id, n, transform) => {
      let child = lower(child_id)
      let scope = pattern_source_path_for_opaque_children(nodes, id, [child_id])
      let base = prepend(child.pat)
      let pat = every_known(
        n,
        fn(p : Pat[ScopedValue[A, O]]) {
          transform
          .apply(p)
          .map_payload(value => value.remap(value.value, scope))
        },
        base,
        transform.signature(),
      )
      // `every_known` returns these unchanged, so they keep the child's entries.
      let unchanged = n <= 0 || base.body is Silence
      let entries = if unchanged {
        child.entries.map(entry => {
          CompiledEntry(entry.key, prepend(entry.source))
        })
      } else {
        [CompiledEntry("\{id.value().length()}:\{id.value()}", pat)]
      }
      let buses = if unchanged {
        child.buses
      } else {
        child.buses.map(bus => {
          bus.map_signal(signal => {
            Every(n.to_int64(), signal, signal.through(transform.time_map()))
          })
        })
      }
      CompiledPattern(pat, entries, buses~)
    }
    // The transformed branch reads its own copy of each bus. The fixed pan
    // overrides a pan bus.
    Jux(child_id, transform, access) => {
      let child = lower(child_id)
      let scope = pattern_source_path_for_opaque_children(nodes, id, [child_id])
      let offset = child.buses.length()
      let pat = jux_kernel(
        child.pat,
        p => {
          transform.apply(if offset == 0 { p } else { p.shift_buses(offset) })
        },
        (value, pan) => {
          value.remap(
            (access.with_controls)(value.value, pan),
            value.scope,
            bindings=unbind_keys(value.bindings, pan),
          )
        },
        transform.signature(),
      ).map_payload(value => value.remap(value.value, scope))
      let buses = child.buses.copy()
      for bus in child.buses {
        buses.push(
          bus.map_signal(signal => signal.through(transform.time_map())),
        )
      }
      CompiledPattern(pat, opaque_compiled_entries(pat, id), buses~)
    }
    // One new bus per key the provider sets, after the left side's buses,
    // plus one per inner bus of that key that combines with it: nested
    // `gain` multiplies, and other keys take the outer value where it has one. The merged
    // values come from the buses at the snapshot root, on its clock, so the
    // provider is never queried.
    MergeControl(left_id, provider) => {
      let left = lower(left_id)
      let keys = []
      control_keys(provider.nodes, provider.root, keys)
      let buses = left.buses.copy()
      let provided : Array[(@control.Control, Int32)] = []
      let chained : Map[Int32, Int32] = Map([])
      for key in keys {
        let signal = compile_signal(provider.nodes, provider.root, Some(key))
        let source = signal_source(provider.nodes, provider.root)
        provided.push((key, buses.length()))
        buses.push({ key, signal, source, })
        for inner, bus in left.buses {
          if bus.key == key {
            chained[inner] = buses.length()
            buses.push({
              key,
              signal: nested_signal(key.nesting(), bus.signal, signal),
              source,
            })
          }
        }
      }
      // Control providers need no primary source atom or reference binding;
      // lowering one only gives the merge's content signature.
      let right : CompiledPattern[ControlMap, Unit] = lower_pattern_node_cached(
        provider.nodes,
        provider.root,
        CompiledCache::new(),
        CompiledCache::new(),
        Map([]),
        End,
      )
      // The path names the merge, its left side, and every provider node.
      let descendants : Array[@identity.PatternNodeId] = []
      let seen : Map[String, Bool] = Map([(id.value(), true)])
      append_reachable_pattern_source_ids(nodes, left_id, descendants, seen)
      append_reachable_pattern_source_ids(
        provider.nodes,
        provider.root,
        descendants,
        seen,
      )
      let scope = PatternNodePath(id, descendants~)
      // Events of one atom share their bindings, so reuse the last result.
      let mut last_in = no_bus_bindings
      let mut last_out = bind_buses(no_bus_bindings, provided, chained)
      let pat = bind_control_kernel(left.pat, right.pat.entry_signature(), value => {
        if !physical_equal(value.bindings, last_in) {
          last_in = value.bindings
          last_out = bind_buses(value.bindings, provided, chained)
        }
        value.remap(value.value, scope, bindings=last_out)
      })
      let entries = pat.entries()
      CompiledPattern(
        pat,
        Array::makei(entries.length(), index => {
          CompiledEntry(left.entries[index].key, entries[index])
        }),
        buses~,
      )
    }
    // The left side's buses are unchanged: a value sampled at the onset
    // does not change while the event sounds.
    MergeValues(left_id, provided) => {
      let left = lower(left_id)
      let descendants : Array[@identity.PatternNodeId] = []
      let seen : Map[String, Bool] = Map([(id.value(), true)])
      append_reachable_pattern_source_ids(nodes, left_id, descendants, seen)
      for provider_node in provided.nodes {
        if !seen.contains(provider_node.value()) {
          seen[provider_node.value()] = true
          descendants.push(provider_node)
        }
      }
      let scope = PatternNodePath(id, descendants~)
      let pat = merge_at_onset_kernel(left.pat, provided.changes, (
        value,
        change,
      ) => value.remap(change(value.value), scope))
      let entries = pat.entries()
      CompiledPattern(
        pat,
        Array::makei(entries.length(), index => {
          CompiledEntry(left.entries[index].key, entries[index])
        }),
        buses=left.buses,
      )
    }
    // A child's bus is silent outside that child's slot.
    Sequence(children) => {
      let count = children.length()
      let (children, buses) = concat_child_buses(children.map(lower), (
        index,
        signal,
      ) => Mapped(TimeMap::sequence(count), slot_signals(count, index, signal)))
      let pats = children.map(child => child.pat)
      {
        ..CompiledPattern::single_material(prepend(sequence(pats)), id),
        buses,
      }
    }
    WeightedSequence(children, weights) => {
      let count = children.length()
      let (children, buses) = concat_child_buses(children.map(lower), (
        index,
        signal,
      ) => {
        Mapped(TimeMap::weighted(weights), slot_signals(count, index, signal))
      })
      let pats = children.map(child => child.pat)
      let compiled = CompiledPattern::single_material(
        prepend(sequence_weighted(pats, weights)),
        id,
      )
      { ..compiled, buses, }
    }
    Stack(children) => {
      let (children, buses) = concat_child_buses(children.map(lower), (
        _,
        signal,
      ) => signal)
      let entries = children
        .iter()
        .flat_map(child => {
          child.entries
          .iter()
          .map(entry => CompiledEntry(entry.key, prepend(entry.source)))
        })
        .collect()
      CompiledPattern(
        prepend(stack(children.map(child => child.pat))),
        entries,
        buses~,
      )
    }
  }
  if O::carries_origins() && entry.source_frame is Some(_) {
    let span = compiled.pat.entry_period().num.to_double().max(1.0)
    compiled.transform(pat => pat.capture_source_frame(entry.source_frame, span))
  } else {
    compiled
  }
}

///|
priv struct CompiledCacheEntry[A, O] {
  token : Array[Int64]
  context : OriginBindings
  compiled : CompiledPattern[A, O]
}

///|
/// Keep the common single-variant case free of a secondary hash table.
priv struct CompiledCacheVariants[A, O] {
  first : CompiledCacheEntry[A, O]
  mut others : Map[Int32, Array[CompiledCacheEntry[A, O]]]?
}

///|
/// This fingerprint selects a bucket, never establishes origin identity.
/// Lookup still compares the full context, including epochs and binding witnesses.
fn OriginBindings::cache_hash(self : OriginBindings) -> Int32 {
  if self is End {
    return 0
  }
  let hasher = Hasher()
  for remaining = self {
    match remaining {
      End => break
      Link(binding, rest) => {
        hasher.combine_int64(binding.id.serial())
        continue rest
      }
    }
  }
  hasher.finalize()
}

///|
/// Cache for compiled playback and provenance of pattern subtrees.
///
/// Entries are keyed by stable `PatternNodeId`, a recursive private subtree
/// token, and the immutable reference context. The context prevents a definition
/// compiled for one reference use from supplying origins to another use.
/// The subtree token prevents stale hits
/// when callers rebuild unrelated docs or fork divergent edits from the same
/// base with identical stable IDs and revision counters. Every replacement gets
/// a fresh generation, and the token includes every dependency generation.
/// Revision is an editing API value; it adds no discrimination to this key.
priv struct CompiledCache[A, O] {
  entries : Map[String, CompiledCacheVariants[A, O]]
  mut hits : Int32
  mut misses : Int32
}

///|
fn[A, O] CompiledCache::new() -> CompiledCache[A, O] {
  { entries: {}, hits: 0, misses: 0, }
}

///|
fn[A, O] CompiledCache::lookup(
  self : CompiledCache[A, O],
  id : @identity.PatternNodeId,
  token : Array[Int64],
  context : OriginBindings,
) -> CompiledPattern[A, O]? {
  match self.entries.get(id.value()) {
    None => {
      self.misses += 1
      None
    }
    Some(variants) => {
      let first = variants.first
      if first.context == context &&
        pattern_cache_token_equal(first.token, token) {
        self.hits += 1
        return Some(first.compiled)
      }
      if variants.others is Some(buckets) {
        if buckets.get(context.cache_hash()) is Some(entries) {
          for entry in entries {
            if entry.context == context &&
              pattern_cache_token_equal(entry.token, token) {
              self.hits += 1
              return Some(entry.compiled)
            }
          }
        }
      }
      self.misses += 1
      None
    }
  }
}

///|
/// Called only after a cache miss; the immutable dependency key is absent.
fn[A, O] CompiledCache::store(
  self : CompiledCache[A, O],
  id : @identity.PatternNodeId,
  token : Array[Int64],
  context : OriginBindings,
  compiled : CompiledPattern[A, O],
) -> Unit {
  let key = id.value()
  let entry = { token: token.copy(), context, compiled, }
  match self.entries.get(key) {
    None => self.entries[key] = { first: entry, others: None, }
    Some(variants) => {
      let buckets = match variants.others {
        Some(buckets) => buckets
        None => {
          let buckets : Map[Int32, Array[CompiledCacheEntry[A, O]]] = Map([])
          variants.others = Some(buckets)
          buckets
        }
      }
      let hash = context.cache_hash()
      match buckets.get(hash) {
        None => buckets[hash] = [entry]
        Some(entries) => entries.push(entry)
      }
    }
  }
}

///|
fn[A, O] CompiledCache::hit_count(self : CompiledCache[A, O]) -> Int32 {
  self.hits
}

///|
fn[A, O] CompiledCache::miss_count(self : CompiledCache[A, O]) -> Int32 {
  self.misses
}

///|
fn[A, O] CompiledCache::entry_count(self : CompiledCache[A, O]) -> Int32 {
  let mut count = 0
  self.entries.each(fn(_, variants) {
    count += 1
    if variants.others is Some(buckets) {
      buckets.each(fn(_, entries) { count += entries.length() })
    }
  })
  count
}

///|
fn[A, O] CompiledCache::reset_stats(self : CompiledCache[A, O]) -> Unit {
  self.hits = 0
  self.misses = 0
}

///|
fn[A, O] CompiledCache::clear(self : CompiledCache[A, O]) -> Unit {
  self.entries.clear()
  self.reset_stats()
}

///|
/// Exact and general specializations never exchange cached payloads.
pub struct PatternLoweringCache[A] {
  priv general : CompiledCache[A, Unit]
  priv exact : CompiledCache[A, EventOrigin]
}

///|
pub fn[A] PatternLoweringCache::new() -> PatternLoweringCache[A] {
  { general: CompiledCache::new(), exact: CompiledCache::new(), }
}

///|
pub fn[A] PatternLoweringCache::hit_count(
  self : PatternLoweringCache[A],
) -> Int32 {
  self.general.hit_count() + self.exact.hit_count()
}

///|
pub fn[A] PatternLoweringCache::miss_count(
  self : PatternLoweringCache[A],
) -> Int32 {
  self.general.miss_count() + self.exact.miss_count()
}

///|
pub fn[A] PatternLoweringCache::entry_count(
  self : PatternLoweringCache[A],
) -> Int32 {
  self.general.entry_count() + self.exact.entry_count()
}

///|
pub fn[A] PatternLoweringCache::reset_stats(
  self : PatternLoweringCache[A],
) -> Unit {
  self.general.reset_stats()
  self.exact.reset_stats()
}

///|
pub fn[A] PatternLoweringCache::clear(self : PatternLoweringCache[A]) -> Unit {
  self.general.clear()
  self.exact.clear()
}

///|
/// Lowered pattern snapshot for scheduler/runtime consumers.
pub struct PatternSnapshot[A] {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv pat : Pat[A]
  priv sourced : Pat[ScopedValue[A, Unit]]
  priv entry_sourced : Array[CompiledEntry[A, Unit]]
  /// The root's buses, which project payloads as controls leave lowering.
  priv buses : Array[ControlBus]
  priv table : Array[BusSignal]
}

///|
pub fn[A] PatternSnapshot::root(
  self : PatternSnapshot[A],
) -> @identity.PatternNodeId {
  self.root
}

///|
pub fn[A] PatternSnapshot::revision(
  self : PatternSnapshot[A],
) -> @identity.Revision {
  self.revision
}

///|
pub fn[A] PatternSnapshot::pat(self : PatternSnapshot[A]) -> Pat[A] {
  self.pat
}

///|
pub fn[A] PatternSnapshot::query(
  self : PatternSnapshot[A],
  arc : TimeSpan,
) -> Array[Event[A]] {
  self.pat.query(arc)
}

///|
pub fn[A : WithControls] PatternSnapshot::query_sourced_events(
  self : PatternSnapshot[A],
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  self.sourced
  .query(arc)
  .map(event => scoped_event(event, self.buses, self.table))
}

///|
/// Query one canonical `Pat::entries()` member with authored provenance.
/// `source_index` is the member index retained by playback entry state.
/// Invalid indexes return an empty result.
pub fn[A : WithControls] PatternSnapshot::query_sourced_events_for_entry(
  self : PatternSnapshot[A],
  source_index : Int32,
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  match self.entry_sourced.get(source_index) {
    Some(entry) =>
      entry.source
      .query(arc)
      .map(event => scoped_event(event, self.buses, self.table))
    None => []
  }
}

///|
/// This snapshot for material that entered `delay` after its origin: its
/// one-shot signals start `delay` later (ADR-0025), on the payloads and the
/// buses alike. `delay` must be a whole number of the pattern's periods.
pub fn[A : WithControls] PatternSnapshot::entered(
  self : PatternSnapshot[A],
  delay : Rational,
) -> PatternSnapshot[A] {
  guard delayed_buses(self.buses, delay) is Some(buses) else { return self }
  {
    ..self,
    pat: self.sourced
    .project_controls(buses)
    .address_entries(self.entry_sourced.map(entry => entry.key)),
    buses,
    table: buses.map(bus => bus.signal),
  }
}

///|
/// `buses` with their one-shot signals `delay` later; `None` when that
/// changes nothing.
fn delayed_buses(
  buses : Array[ControlBus],
  delay : Rational,
) -> Array[ControlBus]? {
  guard delay.num != 0L && buses.iter().any(bus => bus.signal.has_once()) else {
    return None
  }
  Some(buses.map(bus => bus.map_signal(signal => signal.delayed(delay))))
}

///|
/// A compiled pattern whose every emitted event carries an exact source origin.
pub struct PatternSnapshotWithOrigins[A] {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv pat : Pat[A]
  priv sourced : Pat[ScopedValue[A, EventOrigin]]
  priv entry_sourced : Array[CompiledEntry[A, EventOrigin]]
  /// The root's buses, which project payloads as controls leave lowering.
  priv buses : Array[ControlBus]
  priv table : Array[BusSignal]
}

///|
pub fn[A] PatternSnapshotWithOrigins::root(
  self : PatternSnapshotWithOrigins[A],
) -> @identity.PatternNodeId {
  self.root
}

///|
pub fn[A] PatternSnapshotWithOrigins::revision(
  self : PatternSnapshotWithOrigins[A],
) -> @identity.Revision {
  self.revision
}

///|
/// The control signals the authored signal `source` gives this snapshot, one
/// per bus that follows it: the curves the voices it controls follow, in root
/// time. A reused binding or `jux` gives several.
pub fn[A] PatternSnapshotWithOrigins::control_traces(
  self : PatternSnapshotWithOrigins[A],
  source : @identity.SourceAtomId,
) -> Array[ControlTrace] {
  self.buses.filter_map(bus => {
    if bus.source == Some(source) {
      Some(ControlTrace(bus.signal))
    } else {
      None
    }
  })
}

///|
pub fn[A] PatternSnapshotWithOrigins::pat(
  self : PatternSnapshotWithOrigins[A],
) -> Pat[A] {
  self.pat
}

///|
pub fn[A : WithControls] PatternSnapshotWithOrigins::query(
  self : PatternSnapshotWithOrigins[A],
  arc : TimeSpan,
) -> Array[EventWithOrigin[A]] {
  self.sourced
  .query(arc)
  .map(event => EventWithOrigin(event, self.buses, self.table))
}

///|
/// Query a canonical material member; invalid indexes produce no events.
pub fn[A : WithControls] PatternSnapshotWithOrigins::query_for_entry(
  self : PatternSnapshotWithOrigins[A],
  index : Int32,
  arc : TimeSpan,
) -> Array[EventWithOrigin[A]] {
  match self.entry_sourced.get(index) {
    None => []
    Some(entry) =>
      entry.source
      .query(arc)
      .map(event => EventWithOrigin(event, self.buses, self.table))
  }
}

///|
/// `PatternSnapshot::entered` with origins.
pub fn[A : WithControls] PatternSnapshotWithOrigins::entered(
  self : PatternSnapshotWithOrigins[A],
  delay : Rational,
) -> PatternSnapshotWithOrigins[A] {
  guard delayed_buses(self.buses, delay) is Some(buses) else { return self }
  {
    ..self,
    pat: self.sourced
    .project_controls(buses)
    .address_entries(self.entry_sourced.map(entry => entry.key)),
    buses,
    table: buses.map(bus => bus.signal),
  }
}

///|
/// Erase only origin capability, without compiling or interpreting time again.
pub fn[A] PatternSnapshotWithOrigins::as_snapshot(
  self : PatternSnapshotWithOrigins[A],
) -> PatternSnapshot[A] {
  fn erase_origin(value : ScopedValue[A, EventOrigin]) -> ScopedValue[A, Unit] {
    ScopedValue(
      value.value,
      value.scope,
      (),
      source_frame=value.source_frame,
      source_start=value.source_start,
      bindings=value.bindings,
    )
  }
  {
    root: self.root,
    revision: self.revision,
    pat: self.pat,
    sourced: self.sourced.map_payload(erase_origin),
    entry_sourced: self.entry_sourced.map(entry => {
      CompiledEntry(entry.key, entry.source.map_payload(erase_origin))
    }),
    buses: self.buses,
    table: self.table,
  }
}

///|
pub fn[A : WithControls] PatternDoc::lower_with_origins(
  self : PatternDoc[A],
  cache~ : PatternLoweringCache[A] = PatternLoweringCache::new(),
) -> PatternSnapshotWithOrigins[A] raise PatternDocError {
  let compiled = lower_pattern_node_cached(
    self.nodes,
    self.root,
    cache.exact,
    cache.general,
    {},
    End,
  )
  {
    root: self.root,
    revision: self.revision,
    pat: compiled.pat
    .project_controls(compiled.buses)
    .address_entries(compiled.entries.map(entry => entry.key)),
    sourced: compiled.pat,
    entry_sourced: compiled.entries,
    buses: compiled.buses,
    table: compiled.buses.map(bus => bus.signal),
  }
}

///|
/// A value written once in the source. `content` describes it, as for
/// `Pat::pure`. Without `source_atom` the value has no exact origin.
pub fn[A] PatternDoc::atom(
  id~ : @identity.PatternNodeId,
  source_atom? : @identity.SourceAtomId,
  value~ : A,
  content~ : String = "",
) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(
      id,
      Atom(Pat::pure(value, content~), value, source_atom),
    ),
  )
}

///|
/// Use the canonical control constructor's signature; source IDs never enter it.
/// Without `source_atom` the control has no exact origin.
pub fn PatternDoc::control_atom(
  id~ : @identity.PatternNodeId,
  source_atom? : @identity.SourceAtomId,
  key~ : @control.Control,
  value~ : Double,
) -> PatternDoc[ControlMap] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(
      id,
      Atom(control(key, value), ControlMap::single(key, value), source_atom),
    ),
  )
}

///|
pub fn[A] PatternDoc::reference_with_binding(
  id~ : @identity.PatternNodeId,
  resolved_reference~ : ResolvedReference[A],
) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=resolved_reference.definition.revision,
    nodes=singleton_pattern_nodes(
      id,
      Reference(resolved_reference.definition, Some(resolved_reference.binding)),
    ),
  )
}

///|
/// Identity-bearing pattern authoring document.
///
/// `PatternDoc[A]` is an immutable authoring layer above the runtime `Pat`
/// closure model. Node storage is private so future incremental lowering can
/// cache by stable node identity and revision without exposing storage shape.
pub struct PatternDoc[A] {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv incr_revision : @types.Revision
  priv nodes : Map[String, PatternDocEntry[A]]
}

///|
let pattern_doc_incr_revision : Ref[@types.Revision] = Ref(
  @types.Revision::initial(),
)

///|
fn next_pattern_doc_incr_revision() -> @types.Revision {
  let next = pattern_doc_incr_revision.val.next()
  pattern_doc_incr_revision.val = next
  next
}

///|
fn[A] PatternDoc::PatternDoc(
  root~ : @identity.PatternNodeId,
  revision~ : @identity.Revision,
  nodes~ : Map[String, PatternDocEntry[A]],
) -> PatternDoc[A] {
  { root, revision, incr_revision: next_pattern_doc_incr_revision(), nodes, }
}

///|
pub fn[A] PatternDoc::from_pattern(
  id~ : @identity.PatternNodeId,
  pat~ : Pat[A],
) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Runtime(pat)),
  )
}

///|
/// A continuous control `key = f(cycles, before)`: the value at `cycles`, or
/// with `before`, its limit from below, which differs only where `f` jumps.
/// Queried as a pattern, it is sampled at each query arc's start; its bus
/// evaluates `f` at exact time, and `rev` reads limits from below. `period` is
/// the cycles after which `f` repeats, when it does; `ControlTrace::period`
/// reads it. `source` is the authored signal it compiles, by which
/// `PatternSnapshotWithOrigins::control_traces` finds the buses it provides.
/// `signature` names `f`: two signals with the same key and signature must
/// compute the same function. A live edit keeps a material whose content,
/// signatures included, is unchanged.
pub fn PatternDoc::continuous(
  id~ : @identity.PatternNodeId,
  key~ : @control.Control,
  f~ : (Double, Bool) -> Double,
  signature~ : String,
  period~ : Rational? = None,
  source~ : @identity.SourceAtomId? = None,
) -> PatternDoc[ControlMap] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(
      id,
      Continuous(
        signal_pattern(key, t => f(t, false), "continuous", signature),
        key,
        Continuous(f, period),
        source,
      ),
    ),
  )
}

///|
/// `continuous(key, f)` with content `kind` and `signature`.
fn signal_pattern(
  key : @control.Control,
  f : (Double) -> Double,
  kind : String,
  signature : String,
) -> Pat[ControlMap] {
  let pat = continuous(key, f)
  let name = key.name()
  make_pat(
    pat.query,
    pat.metadata.period,
    pat.body,
    pat.metadata.scope,
    transformed_signature("\{kind}:\{name.length()}:\{name}", signature),
  )
}

///|
/// A one-shot control `key = f(cycles since its material entered)`. A live
/// edit's replacement and a newly added material start it at their entry
/// (ADR-0025); a song section starts it at the section's start. Queried as
/// a pattern, it samples `f` at each query arc's start; `f` takes `before`
/// as `PatternDoc::continuous`'s does.
/// `signature` and `source` are as for `PatternDoc::continuous`.
pub fn PatternDoc::once(
  id~ : @identity.PatternNodeId,
  key~ : @control.Control,
  f~ : (Double, Bool) -> Double,
  signature~ : String,
  source~ : @identity.SourceAtomId? = None,
) -> PatternDoc[ControlMap] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(
      id,
      Continuous(
        signal_pattern(key, t => f(t, false), "once", signature),
        key,
        Once(f, 0.0),
        source,
      ),
    ),
  )
}

///|
pub fn[A] PatternDoc::silence(id~ : @identity.PatternNodeId) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Silence),
  )
}

///|
pub fn[A] PatternDoc::pure(
  id~ : @identity.PatternNodeId,
  value~ : A,
) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Pure(value)),
  )
}

///|
pub fn[A] PatternDoc::root(self : PatternDoc[A]) -> @identity.PatternNodeId {
  self.root
}

///|
pub fn[A] PatternDoc::revision(self : PatternDoc[A]) -> @identity.Revision {
  self.revision
}

///|
/// `PatternDoc[A]` participates in incr's backdate-aware acceptance
/// (`@incr.AcceptedDerived::accepted_memo`) through its
/// `@identity.Revision` content stamp. `PatternDoc[A]` is not `Eq` (it carries
/// closure fields), so `backdate_equal` below compares that full stamp.
///
/// incr's closed `Revision` is an independent monotonic creation stamp.
/// Semantic equality remains governed by `backdate_equal`, so reparsing an
/// unchanged document can backdate to the previously accepted value.
pub impl[A] @types.HasChangedAt for PatternDoc[A] with fn changed_at(self) -> @types.Revision {
  self.incr_revision
}

///|
/// Compare the full 2-D `@identity.Revision` (`value` AND `fingerprint`) via
/// its derived `Eq`, so two content-distinct docs that happen to collide on
/// `value` are still treated as changed. This is the load-bearing acceptance
/// predicate used by `accepted_memo`.
pub impl[A] @types.BackdateEq for PatternDoc[A] with fn backdate_equal(
  self,
  other,
) -> Bool {
  self.revision == other.revision
}

///|
pub fn[A] PatternDoc::node_count(self : PatternDoc[A]) -> Int32 {
  self.nodes.length()
}

///|
pub fn[A] PatternDoc::contains_node(
  self : PatternDoc[A],
  id : @identity.PatternNodeId,
) -> Bool {
  self.nodes.contains(id.value())
}

///|
pub fn[A] PatternDoc::subdoc(
  self : PatternDoc[A],
  root~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes : Map[String, PatternDocEntry[A]] = Map([])
  copy_reachable_pattern_nodes(self.nodes, root, nodes)
  PatternDoc(root~, revision=pattern_node_revision(nodes, root), nodes~)
}

///|
pub fn[A] PatternDoc::node_revision(
  self : PatternDoc[A],
  id : @identity.PatternNodeId,
) -> @identity.Revision raise PatternDocError {
  pattern_node_revision(self.nodes, id)
}

///|
pub fn[A : WithControls] PatternDoc::lower(
  self : PatternDoc[A],
) -> PatternSnapshot[A] raise PatternDocError {
  self.lower_with_cache(PatternLoweringCache::new())
}

///|
/// The document's values in time, without origins or controls: lowering
/// before `lower` projects controls into payloads.
fn[A] PatternDoc::values(self : PatternDoc[A]) -> Pat[A] raise PatternDocError {
  let compiled : CompiledPattern[A, Unit] = lower_pattern_node_cached(
    self.nodes,
    self.root,
    CompiledCache::new(),
    CompiledCache::new(),
    {},
    End,
  )
  compiled.pat.map_payload(value => value.value)
}

///|
pub fn[A : WithControls] PatternDoc::lower_with_cache(
  self : PatternDoc[A],
  cache : PatternLoweringCache[A],
) -> PatternSnapshot[A] raise PatternDocError {
  let compiled = lower_pattern_node_cached(
    self.nodes,
    self.root,
    cache.general,
    cache.general,
    {},
    End,
  )
  {
    root: self.root,
    revision: self.revision,
    pat: compiled.pat
    .project_controls(compiled.buses)
    .address_entries(compiled.entries.map(entry => entry.key)),
    sourced: compiled.pat,
    entry_sourced: compiled.entries,
    buses: compiled.buses,
    table: compiled.buses.map(bus => bus.signal),
  }
}

///|
pub fn[A] PatternDoc::with_root(
  self : PatternDoc[A],
  root~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  if !self.nodes.contains(root.value()) {
    raise MissingNode(root.value())
  }
  PatternDoc(
    root~,
    revision=self.revision.next(),
    nodes=copy_pattern_nodes(self.nodes),
  )
}

///|
pub fn[A] PatternDoc::replace_with_pattern(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  pat~ : Pat[A],
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Runtime(pat))
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::replace_with_silence(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Silence)
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::replace_with_pure(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  value~ : A,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Pure(value))
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
/// Capture source-local coordinates before enclosing musical transformations.
/// This does not change the pattern's timing, material keys, or musical values.
pub fn[A] PatternDoc::with_source_frame(
  self : PatternDoc[A],
  frame~ : @identity.SourceFrameId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  guard nodes.get(self.root.value()) is Some(entry) else {
    raise MissingNode(self.root.value())
  }
  nodes[self.root.value()] = {
    generation: next_pattern_node_generation(),
    revision: entry.revision.next(),
    node: entry.node,
    source_frame: Some(frame),
  }
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::fast(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Fast(self.root, factor),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::slow(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Slow(self.root, factor),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::gate(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Gate(self.root, factor),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::rev(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Rev(self.root), revision=self.revision.next())
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A : WithControls] PatternDoc::filter_map(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  f~ : (A) -> A?,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    FilterMap(self.root, f, ControlAccess::of()),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::euclid(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  k~ : Int32,
  n~ : Int32,
  rotation~ : Int32 = 0,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Euclid(self.root, k, n, rotation),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::degrade_by(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  p~ : Double,
  seed~ : Int32 = 42,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    DegradeBy(self.root, p, seed),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::every(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  n~ : Int32,
  transform~ : TimeTransform,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Every(self.root, n, transform),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A : WithControls] PatternDoc::jux(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  transform~ : TimeTransform,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Jux(self.root, transform, ControlAccess::of()),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
/// Merge each control `right` sets into the overlapping events of `left`.
/// The controls follow `right` while a note sounds (ADR-0019).
pub fn[A] PatternDoc::merge_control(
  id~ : @identity.PatternNodeId,
  left~ : PatternDoc[A],
  right~ : PatternDoc[ControlMap],
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(left.nodes)
  let revision = left.revision.combine(right.revision).next()
  insert_pattern_node(nodes, id, MergeControl(left.root, right), revision~)
  PatternDoc(root=id, revision~, nodes~)
}

///|
/// Give each event of `left` the value `right` has at its onset, through
/// `apply`. The value holds while the event sounds: it derives no bus.
pub fn[A, B] PatternDoc::merge_values(
  id~ : @identity.PatternNodeId,
  left~ : PatternDoc[A],
  right~ : PatternDoc[B],
  apply~ : (A, B) -> A,
) -> PatternDoc[A] raise PatternDocError {
  let provider_nodes = []
  append_reachable_pattern_source_ids(right.nodes, right.root, provider_nodes, {})
  let provided = {
    changes: right.values().map_payload(value => (a : A) => apply(a, value)),
    nodes: provider_nodes,
    revision: right.revision,
    cache_token: pattern_node_cache_token_memoized(right.nodes, right.root, {}),
  }
  let nodes = copy_pattern_nodes(left.nodes)
  let revision = left.revision.combine(right.revision).next()
  insert_pattern_node(nodes, id, MergeValues(left.root, provided), revision~)
  PatternDoc(root=id, revision~, nodes~)
}

///|
pub fn[A] PatternDoc::sequence(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
) -> PatternDoc[A] raise PatternDocError {
  if docs.is_empty() {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocEntry[A]] = Map([])
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
  }
  let children = docs.map(doc => doc.root)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(nodes, id, Sequence(children), revision~)
  PatternDoc(root=id, revision~, nodes~)
}

///|
pub fn[A] PatternDoc::sequence_weighted(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
  weights~ : Array[Int32],
) -> PatternDoc[A] raise PatternDocError {
  if docs.is_empty() {
    raise EmptyPatternDocs
  }
  if weights.length() != docs.length() {
    raise InvalidSequenceWeights
  }
  let mut total = 0
  for weight in weights {
    if weight <= 0 || weight > 16 {
      raise InvalidSequenceWeights
    }
    total += weight
    if total > 256 {
      raise InvalidSequenceWeights
    }
  }
  let nodes : Map[String, PatternDocEntry[A]] = Map([])
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
  }
  let children = docs.map(doc => doc.root)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(
    nodes,
    id,
    WeightedSequence(children, weights.copy()),
    revision~,
  )
  PatternDoc(root=id, revision~, nodes~)
}

///|
pub fn[A] PatternDoc::stack(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
) -> PatternDoc[A] raise PatternDocError {
  if docs.is_empty() {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocEntry[A]] = Map([])
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
  }
  let children = docs.map(doc => doc.root)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(nodes, id, Stack(children), revision~)
  PatternDoc(root=id, revision~, nodes~)
}

///|
/// A use-site node referencing an immutable definition document. The definition
/// keeps its own node identities; combining uses does not duplicate its nodes.
/// References cannot form cycles because construction only accepts existing
/// immutable documents. Runtime closures remain an explicit, separate API.
pub fn[A] PatternDoc::reference(
  id~ : @identity.PatternNodeId,
  definition~ : PatternDoc[A],
) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=definition.revision,
    nodes=singleton_pattern_nodes(id, Reference(definition, None)),
  )
}

///|
/// Inspect the definition at a reference use site without losing its structure.
pub fn[A] PatternDoc::referenced_definition(
  self : PatternDoc[A],
  id : @identity.PatternNodeId,
) -> PatternDoc[A]? {
  match self.nodes.get(id.value()) {
    Some({ node: Reference(definition, _), .. }) => Some(definition)
    _ => None
  }
}

///|
pub extend PatternDoc with @types.BackdateEq::{backdate_equal}

///|
pub extend PatternDoc with @types.HasChangedAt::{changed_at}

///|
pub extend PatternDocError with Debug::{to_repr}

///|
pub extend PatternDocError with Eq::{not_equal, equal}

///|
pub extend PatternNodePath with Debug::{to_repr}

///|
pub extend PatternNodePath with Eq::{not_equal, equal}
