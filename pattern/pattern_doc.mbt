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
priv enum PatternDocNode {
  Runtime(Pat[ControlMap])
  /// A continuous control as both its query form and its allocation-free
  /// time function `(cycles) -> value` for one key.
  Continuous(Pat[ControlMap], @control.Control, (Double) -> Double)
  Reference(PatternDoc, ReferenceBinding?)
  Silence
  Pure(ControlMap)
  /// A pure value; the pattern carries its content signature. Without a
  /// source atom it has no exact origin.
  Atom(Pat[ControlMap], ControlMap, @identity.SourceAtomId?, Double)
  Fast(@identity.PatternNodeId, Rational)
  Slow(@identity.PatternNodeId, Rational)
  Gate(@identity.PatternNodeId, Rational)
  Rev(@identity.PatternNodeId)
  FilterMap(@identity.PatternNodeId, (ControlMap) -> ControlMap?)
  Euclid(@identity.PatternNodeId, Int32, Int32, Int32)
  DegradeBy(@identity.PatternNodeId, Double, Int32)
  Every(@identity.PatternNodeId, Int32, TimeTransform)
  Jux(@identity.PatternNodeId, TimeTransform)
  /// The right-hand controls merge into each left-hand event, as buses.
  MergeControl(@identity.PatternNodeId, @identity.PatternNodeId)
  Sequence(Array[@identity.PatternNodeId])
  WeightedSequence(Array[@identity.PatternNodeId], Array[Int32])
  Stack(Array[@identity.PatternNodeId])
}

///|
priv struct PatternDocEntry {
  generation : Int64
  revision : @identity.Revision
  node : PatternDocNode
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
fn PatternDocNode::snapshot(self : PatternDocNode) -> PatternDocNode {
  match self {
    Runtime(pat) => Runtime(pat)
    Continuous(pat, key, f) => Continuous(pat, key, f)
    Reference(definition, binding) => Reference(definition, binding)
    Silence => Silence
    Pure(value) => Pure(value)
    Atom(pat, value, atom, pitch) => Atom(pat, value, atom, pitch)
    Fast(child, factor) => Fast(child, factor)
    Slow(child, factor) => Slow(child, factor)
    Gate(child, factor) => Gate(child, factor)
    Rev(child) => Rev(child)
    FilterMap(child, f) => FilterMap(child, f)
    Euclid(child, k, n, rotation) => Euclid(child, k, n, rotation)
    DegradeBy(child, p, seed) => DegradeBy(child, p, seed)
    Every(child, n, f) => Every(child, n, f)
    Jux(child, transform) => Jux(child, transform)
    MergeControl(left, right) => MergeControl(left, right)
    Sequence(children) => Sequence(children.copy())
    WeightedSequence(children, weights) =>
      WeightedSequence(children.copy(), weights.copy())
    Stack(children) => Stack(children.copy())
  }
}

///|
fn PatternDocEntry::snapshot(self : PatternDocEntry) -> PatternDocEntry {
  {
    generation: self.generation,
    revision: self.revision,
    node: self.node.snapshot(),
    source_frame: self.source_frame,
  }
}

///|
fn copy_pattern_nodes(
  nodes : Map[String, PatternDocEntry],
) -> Map[String, PatternDocEntry] {
  let result : Map[String, PatternDocEntry] = Map([])
  nodes.each(fn(id, entry) { result[id] = entry.snapshot() })
  result
}

///|
fn singleton_pattern_nodes(
  id : @identity.PatternNodeId,
  node : PatternDocNode,
) -> Map[String, PatternDocEntry] {
  let nodes : Map[String, PatternDocEntry] = Map([])
  nodes[id.value()] = {
    generation: next_pattern_node_generation(),
    revision: @identity.Revision::zero(),
    node: node.snapshot(),
    source_frame: None,
  }
  nodes
}

///|
fn insert_pattern_node(
  nodes : Map[String, PatternDocEntry],
  id : @identity.PatternNodeId,
  node : PatternDocNode,
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
fn merge_pattern_nodes(
  target : Map[String, PatternDocEntry],
  source : Map[String, PatternDocEntry],
) -> Unit raise PatternDocError {
  source.each((id, entry) => {
    if target.contains(id) {
      raise DuplicateNodeId(id)
    }
    target[id] = entry.snapshot()
  })
}

///|
fn aggregate_pattern_revision(docs : Array[PatternDoc]) -> @identity.Revision {
  let mut revision = @identity.Revision::zero()
  for doc in docs {
    revision = revision.combine(doc.revision)
  }
  revision.next()
}

///|
fn replace_pattern_node(
  nodes : Map[String, PatternDocEntry],
  id : @identity.PatternNodeId,
  node : PatternDocNode,
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
fn pattern_node_cache_token_memoized(
  nodes : Map[String, PatternDocEntry],
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
            | Continuous(_, _, _)
            | Silence
            | Pure(_)
            | Atom(_, _, _, _) => ()
            Fast(child, _)
            | Slow(child, _)
            | Gate(child, _)
            | Rev(child)
            | FilterMap(child, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _) =>
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
                pattern_node_cache_token_memoized(nodes, right, memo),
              )
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
fn pattern_node_revision(
  nodes : Map[String, PatternDocEntry],
  id : @identity.PatternNodeId,
) -> @identity.Revision raise PatternDocError {
  let memo : Map[String, @identity.Revision] = Map([])
  pattern_node_revision_memoized(nodes, id, memo)
}

///|
fn copy_reachable_pattern_nodes(
  source : Map[String, PatternDocEntry],
  id : @identity.PatternNodeId,
  target : Map[String, PatternDocEntry],
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
        | Continuous(_, _, _)
        | Silence
        | Pure(_)
        | Atom(_, _, _, _) => ()
        Fast(child, _)
        | Slow(child, _)
        | Gate(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _) => copy_reachable_pattern_nodes(source, child, target)
        MergeControl(left, right) => {
          copy_reachable_pattern_nodes(source, left, target)
          copy_reachable_pattern_nodes(source, right, target)
        }
        Sequence(children) | Stack(children) | WeightedSequence(children, _) =>
          for child in children {
            copy_reachable_pattern_nodes(source, child, target)
          }
      }
    }
  }
}

///|
fn pattern_node_revision_memoized(
  nodes : Map[String, PatternDocEntry],
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
            | Continuous(_, _, _)
            | Silence
            | Pure(_)
            | Atom(_, _, _, _) => ()
            Fast(child, _)
            | Slow(child, _)
            | Gate(child, _)
            | Rev(child)
            | FilterMap(child, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _) =>
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, child, memo),
              )
            MergeControl(left, right) => {
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, left, memo),
              )
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, right, memo),
              )
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
pub struct PatternSnapshotEvent {
  priv event : Event[ControlMap]
  priv path : PatternNodePath
  priv controls : Controls
}

///|
fn PatternSnapshotEvent::PatternSnapshotEvent(
  event~ : Event[ControlMap],
  path~ : PatternNodePath,
  controls~ : Controls,
) -> PatternSnapshotEvent {
  { event, path, controls, }
}

///|
/// This event's controls: its values at the onset and the buses they follow
/// while it sounds.
pub fn PatternSnapshotEvent::controls(self : PatternSnapshotEvent) -> Controls {
  self.controls
}

///|
pub fn PatternSnapshotEvent::event(
  self : PatternSnapshotEvent,
) -> Event[ControlMap] {
  self.event
}

///|
pub fn PatternSnapshotEvent::pattern_nodes(
  self : PatternSnapshotEvent,
) -> Array[@identity.PatternNodeId] {
  self.path.nodes()
}

///|
pub fn PatternSnapshotEvent::pattern_node_path(
  self : PatternSnapshotEvent,
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
pub struct ResolvedReference {
  priv definition : PatternDoc
  priv binding : ReferenceBinding
}

///|
pub fn ResolvedReference::ResolvedReference(
  definition~ : PatternDoc,
  definition_id~ : @identity.DefinitionId,
  reference~ : @identity.ReferenceId,
  binding~ : @identity.ReferenceBindingId,
) -> ResolvedReference raise @identity.StableIdError {
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
priv struct ScopedValue[O] {
  value : ControlMap
  scope : PatternNodePath
  origin : O
  mut source_frame : @identity.SourceFrameId?
  mut source_start : Double
  source_pitch : Double
  bindings : FixedArray[BusBinding]
}

///|
fn[O] ScopedValue::ScopedValue(
  value : ControlMap,
  scope : PatternNodePath,
  origin : O,
  source_frame~ : @identity.SourceFrameId? = None,
  source_start~ : Double = -1.0,
  source_pitch~ : Double = @double.not_a_number,
  bindings~ : FixedArray[BusBinding] = no_bus_bindings,
) -> ScopedValue[O] {
  { value, scope, origin, source_frame, source_start, source_pitch, bindings, }
}

///|
fn[O] ScopedValue::remap(
  self : ScopedValue[O],
  value : ControlMap,
  scope : PatternNodePath,
  bindings~ : FixedArray[BusBinding] = self.bindings,
) -> ScopedValue[O] {
  ScopedValue(
    value,
    scope,
    self.origin,
    source_frame=self.source_frame,
    source_start=self.source_start,
    source_pitch=self.source_pitch,
    bindings~,
  )
}

///|
fn[O] Pat::shift_buses(
  self : Pat[ScopedValue[O]],
  offset : Int32,
) -> Pat[ScopedValue[O]] {
  self.map_payload(value => {
    ..value,
    bindings: shift_bus_bindings(value.bindings, offset),
  })
}

///|
fn[O] ScopedValue::prepend(
  self : ScopedValue[O],
  id : @identity.PatternNodeId,
) -> ScopedValue[O] {
  self.remap(self.value, self.scope.prepend(id))
}

///|
/// Pair each event's payload with its projection at the start of the event's
/// fragment (`project_controls`). `buses` must be on this pattern's clock;
/// child bodies share it.
fn[O] Pat::with_projected_controls(
  self : Pat[ScopedValue[O]],
  buses : Array[ControlBus],
) -> Pat[(ControlMap, ScopedValue[O])] {
  self.map_events((value, time) => {
    (project_controls(value.value, value.bindings, buses, time), value)
  })
}

///|
/// The payloads as controls leave lowering, at the start of each fragment.
fn[O] Pat::project_controls(
  self : Pat[ScopedValue[O]],
  buses : Array[ControlBus],
) -> Pat[ControlMap] {
  self.map_events((value, time) => {
    project_controls(value.value, value.bindings, buses, time)
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
fn[O] Pat::capture_source_frame(
  self : Pat[ScopedValue[O]],
  frame : @identity.SourceFrameId?,
  span : Double,
) -> Pat[ScopedValue[O]] {
  let body : PatBody[ScopedValue[O]] = match self.body {
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
fn[O] scoped_event(
  event : Event[ScopedValue[O]],
  buses : Array[ControlBus],
  table : Array[BusSignal],
) -> PatternSnapshotEvent {
  let value = event.value
  let controls = Controls::lowered(
    value.value,
    value.bindings,
    buses,
    table,
    event.part.begin,
  )
  PatternSnapshotEvent(
    event={ whole: event.whole, part: event.part, value: controls.values(), },
    path=value.scope,
    controls~,
  )
}

///|
pub struct EventWithOrigin {
  priv event : Event[ControlMap]
  priv origin : EventOrigin
  priv scope : PatternNodePath
  priv source_frame : @identity.SourceFrameId?
  priv source_start : Double
  priv source_pitch : Double
  priv controls : Controls
}

///|
fn EventWithOrigin::EventWithOrigin(
  event : Event[ScopedValue[EventOrigin]],
  buses : Array[ControlBus],
  table : Array[BusSignal],
) -> EventWithOrigin {
  let value = event.value
  let controls = Controls::lowered(
    value.value,
    value.bindings,
    buses,
    table,
    event.part.begin,
  )
  {
    event: { whole: event.whole, part: event.part, value: controls.values(), },
    origin: event.value.origin,
    scope: event.value.scope,
    source_frame: event.value.source_frame,
    source_start: event.value.source_start,
    source_pitch: event.value.source_pitch,
    controls,
  }
}

///|
/// This event's controls: its values at the onset and the buses they follow
/// while it sounds.
pub fn EventWithOrigin::controls(self : EventWithOrigin) -> Controls {
  self.controls
}

///|
pub fn EventWithOrigin::event(self : EventWithOrigin) -> Event[ControlMap] {
  self.event
}

///|
pub fn EventWithOrigin::origin(self : EventWithOrigin) -> EventOrigin {
  self.origin
}

///|
pub fn EventWithOrigin::source_frame(
  self : EventWithOrigin,
) -> @identity.SourceFrameId? {
  self.source_frame
}

///|
pub fn EventWithOrigin::source_start(self : EventWithOrigin) -> Double {
  self.source_start
}

///|
pub fn EventWithOrigin::source_pitch(self : EventWithOrigin) -> Double {
  self.source_pitch
}

///|
pub fn EventWithOrigin::pattern_node_path(
  self : EventWithOrigin,
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
fn append_reachable_pattern_source_ids(
  nodes : Map[String, PatternDocEntry],
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
        | Continuous(_, _, _)
        | Silence
        | Pure(_)
        | Atom(_, _, _, _) => ()
        Fast(child, _)
        | Slow(child, _)
        | Gate(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _) =>
          append_reachable_pattern_source_ids(nodes, child, result, seen)
        MergeControl(left, right) => {
          append_reachable_pattern_source_ids(nodes, left, result, seen)
          append_reachable_pattern_source_ids(nodes, right, result, seen)
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
fn pattern_source_path_for_opaque_children(
  nodes : Map[String, PatternDocEntry],
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
priv struct CompiledEntry[O] {
  key : String
  source : Pat[ScopedValue[O]]
}

///|
fn[O] CompiledEntry::CompiledEntry(
  key : String,
  source : Pat[ScopedValue[O]],
) -> CompiledEntry[O] {
  { key, source, }
}

///|
/// One execution kernel; raw events and scoped/origin views are projections.
/// `buses` are in this subtree's local time; event bindings index into them.
priv struct CompiledPattern[O] {
  pat : Pat[ScopedValue[O]]
  entries : Array[CompiledEntry[O]]
  buses : Array[ControlBus]
}

///|
fn[O] CompiledPattern::CompiledPattern(
  pat : Pat[ScopedValue[O]],
  entries : Array[CompiledEntry[O]],
  buses~ : Array[ControlBus] = [],
) -> CompiledPattern[O] {
  { pat, entries, buses, }
}

///|
/// Apply an enclosing node's time transform to every bus.
fn[O] CompiledPattern::map_buses(
  self : CompiledPattern[O],
  f : (BusSignal) -> BusSignal,
) -> CompiledPattern[O] {
  { ..self, buses: self.buses.map(bus => bus.map_signal(f)), }
}

///|
/// Renumber this child's bindings after `offset` earlier sibling buses.
fn[O] CompiledPattern::shift_buses(
  self : CompiledPattern[O],
  offset : Int32,
) -> CompiledPattern[O] {
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
fn[O] concat_child_buses(
  children : Array[CompiledPattern[O]],
  wrap : (Int32, BusSignal) -> BusSignal,
) -> (Array[CompiledPattern[O]], Array[ControlBus]) {
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
fn[O] CompiledPattern::single_material(
  pat : Pat[ScopedValue[O]],
  id : @identity.PatternNodeId,
) -> CompiledPattern[O] {
  CompiledPattern(
    pat,
    pat
    .entries()
    .map(_ => CompiledEntry("\{id.value().length()}:\{id.value()}", pat)),
  )
}

///|
fn[O] CompiledPattern::transform(
  self : CompiledPattern[O],
  f : (Pat[ScopedValue[O]]) -> Pat[ScopedValue[O]],
) -> CompiledPattern[O] {
  CompiledPattern(
    f(self.pat),
    self.entries.map(entry => CompiledEntry(entry.key, f(entry.source))),
    buses=self.buses,
  )
}

///|
fn[O] opaque_compiled_entries(
  pat : Pat[ScopedValue[O]],
  id : @identity.PatternNodeId,
) -> Array[CompiledEntry[O]] {
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
fn[O : DocumentOrigin] lower_pattern_node_cached(
  nodes : Map[String, PatternDocEntry],
  id : @identity.PatternNodeId,
  cache : CompiledCache[O],
  controls : CompiledCache[Unit],
  token_memo : Map[String, Array[Int64]],
  context : OriginBindings,
) -> CompiledPattern[O] raise PatternDocError {
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
fn[O : DocumentOrigin] compile_pattern_node(
  nodes : Map[String, PatternDocEntry],
  id : @identity.PatternNodeId,
  cache : CompiledCache[O],
  controls : CompiledCache[Unit],
  token_memo : Map[String, Array[Int64]],
  context : OriginBindings,
) -> CompiledPattern[O] raise PatternDocError {
  guard nodes.get(id.value()) is Some(entry) else {
    raise MissingNode(id.value())
  }
  fn lower(
    child : @identity.PatternNodeId,
  ) -> CompiledPattern[O] raise PatternDocError {
    lower_pattern_node_cached(
      nodes, child, cache, controls, token_memo, context,
    )
  }
  fn prepend(pat : Pat[ScopedValue[O]]) -> Pat[ScopedValue[O]] {
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
    Runtime(pat) | Continuous(pat, _, _) => {
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
    Atom(pat, _, atom, pitch) => {
      let origin : O = O::make_origin(id, atom, context)
      let path = PatternNodePath(id)
      let source = pat.map_payload(value => {
        ScopedValue(value, path, origin, source_pitch=pitch)
      })
      CompiledPattern(source, opaque_compiled_entries(source, id))
    }
    Fast(child, factor) => {
      let child = lower(child)
      let result = child
        .transform(pat => prepend(pat.fast(factor)))
        .map_buses(signal => Fast(factor.num, factor.den, signal))
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
        .map_buses(signal => Fast(factor.den, factor.num, signal))
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
      .map_buses(signal => Rev(signal))
    // The map sees the child's controls with their bus values, on the
    // child's clock. Returning them unchanged keeps the own values and their
    // buses; a replaced value becomes the event's own values and follows no
    // bus, since a bus would undo the mapping.
    FilterMap(child, f) => {
      let child = lower(child)
      child.transform(pat => {
        pat
        .with_projected_controls(child.buses)
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
        fn(p : Pat[ScopedValue[O]]) {
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
            Every(n.to_int64(), signal, signal.transformed(transform))
          })
        })
      }
      CompiledPattern(pat, entries, buses~)
    }
    // The transformed branch reads its own copy of each bus. The fixed pan
    // overrides a pan bus.
    Jux(child_id, transform) => {
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
            value.value.merge(pan),
            value.scope,
            bindings=unbind_keys(value.bindings, pan),
          )
        },
        transform.signature(),
      ).map_payload(value => value.remap(value.value, scope))
      let buses = child.buses.copy()
      for bus in child.buses {
        buses.push(bus.map_signal(signal => signal.transformed(transform)))
      }
      CompiledPattern(pat, opaque_compiled_entries(pat, id), buses~)
    }
    // One new bus per key the provider sets, after the left side's buses,
    // plus one per inner bus of that key that combines with it: nested
    // `gain` multiplies, and other keys take the outer value where it has one. The merged
    // values come from the buses at the snapshot root, on its clock, so the
    // provider is never queried.
    MergeControl(left_id, right_id) => {
      let left = lower(left_id)
      let keys = []
      control_keys(nodes, right_id, keys)
      let buses = left.buses.copy()
      let provided : Array[(@control.Control, Int32)] = []
      let chained : Map[Int32, Int32] = Map([])
      for key in keys {
        let signal = compile_signal(nodes, right_id, Some(key))
        provided.push((key, buses.length()))
        buses.push({ key, signal, })
        for inner, bus in left.buses {
          if bus.key == key {
            chained[inner] = buses.length()
            buses.push({
              key,
              signal: nested_signal(key.nesting(), bus.signal, signal),
            })
          }
        }
      }
      // Control providers need no primary source atom or reference binding;
      // lowering one only gives the merge's content signature.
      let right : CompiledPattern[Unit] = lower_pattern_node_cached(
        nodes,
        right_id,
        controls,
        controls,
        token_memo,
        End,
      )
      let scope = pattern_source_path_for_opaque_children(nodes, id, [
        left_id, right_id,
      ])
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
    // A child's bus is silent outside that child's slot.
    Sequence(children) => {
      let count = children.length()
      let (children, buses) = concat_child_buses(children.map(lower), (
        index,
        signal,
      ) => Sequence(slot_signals(count, index, signal)))
      let pats = children.map(child => child.pat)
      {
        ..CompiledPattern::single_material(prepend(sequence(pats)), id),
        buses,
      }
    }
    WeightedSequence(children, weights) => {
      let count = children.length()
      let bounds = weight_bounds(weights)
      let (children, buses) = concat_child_buses(children.map(lower), (
        index,
        signal,
      ) => Weighted(slot_signals(count, index, signal), bounds))
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
priv struct CompiledCacheEntry[O] {
  token : Array[Int64]
  context : OriginBindings
  compiled : CompiledPattern[O]
}

///|
/// Keep the common single-variant case free of a secondary hash table.
priv struct CompiledCacheVariants[O] {
  first : CompiledCacheEntry[O]
  mut others : Map[Int32, Array[CompiledCacheEntry[O]]]?
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
priv struct CompiledCache[O] {
  entries : Map[String, CompiledCacheVariants[O]]
  mut hits : Int32
  mut misses : Int32
}

///|
fn[O] CompiledCache::new() -> CompiledCache[O] {
  { entries: {}, hits: 0, misses: 0, }
}

///|
fn[O] CompiledCache::lookup(
  self : CompiledCache[O],
  id : @identity.PatternNodeId,
  token : Array[Int64],
  context : OriginBindings,
) -> CompiledPattern[O]? {
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
fn[O] CompiledCache::store(
  self : CompiledCache[O],
  id : @identity.PatternNodeId,
  token : Array[Int64],
  context : OriginBindings,
  compiled : CompiledPattern[O],
) -> Unit {
  let key = id.value()
  let entry = { token: token.copy(), context, compiled, }
  match self.entries.get(key) {
    None => self.entries[key] = { first: entry, others: None, }
    Some(variants) => {
      let buckets = match variants.others {
        Some(buckets) => buckets
        None => {
          let buckets : Map[Int32, Array[CompiledCacheEntry[O]]] = Map([])
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
fn[O] CompiledCache::hit_count(self : CompiledCache[O]) -> Int32 {
  self.hits
}

///|
fn[O] CompiledCache::miss_count(self : CompiledCache[O]) -> Int32 {
  self.misses
}

///|
fn[O] CompiledCache::entry_count(self : CompiledCache[O]) -> Int32 {
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
fn[O] CompiledCache::reset_stats(self : CompiledCache[O]) -> Unit {
  self.hits = 0
  self.misses = 0
}

///|
fn[O] CompiledCache::clear(self : CompiledCache[O]) -> Unit {
  self.entries.clear()
  self.reset_stats()
}

///|
/// Exact and general specializations never exchange cached payloads.
pub struct PatternLoweringCache {
  priv general : CompiledCache[Unit]
  priv exact : CompiledCache[EventOrigin]
}

///|
pub fn PatternLoweringCache::new() -> PatternLoweringCache {
  { general: CompiledCache::new(), exact: CompiledCache::new(), }
}

///|
pub fn PatternLoweringCache::hit_count(self : PatternLoweringCache) -> Int32 {
  self.general.hit_count() + self.exact.hit_count()
}

///|
pub fn PatternLoweringCache::miss_count(self : PatternLoweringCache) -> Int32 {
  self.general.miss_count() + self.exact.miss_count()
}

///|
pub fn PatternLoweringCache::entry_count(self : PatternLoweringCache) -> Int32 {
  self.general.entry_count() + self.exact.entry_count()
}

///|
pub fn PatternLoweringCache::reset_stats(self : PatternLoweringCache) -> Unit {
  self.general.reset_stats()
  self.exact.reset_stats()
}

///|
pub fn PatternLoweringCache::clear(self : PatternLoweringCache) -> Unit {
  self.general.clear()
  self.exact.clear()
}

///|
/// Lowered pattern snapshot for scheduler/runtime consumers.
pub struct PatternSnapshot {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv pat : Pat[ControlMap]
  priv sourced : Pat[ScopedValue[Unit]]
  priv entry_sourced : Array[CompiledEntry[Unit]]
  /// The root's buses, which project payloads as controls leave lowering.
  priv buses : Array[ControlBus]
  priv table : Array[BusSignal]
}

///|
pub fn PatternSnapshot::root(self : PatternSnapshot) -> @identity.PatternNodeId {
  self.root
}

///|
pub fn PatternSnapshot::revision(self : PatternSnapshot) -> @identity.Revision {
  self.revision
}

///|
pub fn PatternSnapshot::pat(self : PatternSnapshot) -> Pat[ControlMap] {
  self.pat
}

///|
pub fn PatternSnapshot::query(
  self : PatternSnapshot,
  arc : TimeSpan,
) -> Array[Event[ControlMap]] {
  self.pat.query(arc)
}

///|
pub fn PatternSnapshot::query_sourced_events(
  self : PatternSnapshot,
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent] {
  self.sourced
  .query(arc)
  .map(event => scoped_event(event, self.buses, self.table))
}

///|
/// Query one canonical `Pat::entries()` member with authored provenance.
/// `source_index` is the member index retained by playback entry state.
/// Invalid indexes return an empty result.
pub fn PatternSnapshot::query_sourced_events_for_entry(
  self : PatternSnapshot,
  source_index : Int32,
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent] {
  match self.entry_sourced.get(source_index) {
    Some(entry) =>
      entry.source
      .query(arc)
      .map(event => scoped_event(event, self.buses, self.table))
    None => []
  }
}

///|
/// A compiled pattern whose every emitted event carries an exact source origin.
pub struct PatternSnapshotWithOrigins {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv pat : Pat[ControlMap]
  priv sourced : Pat[ScopedValue[EventOrigin]]
  priv entry_sourced : Array[CompiledEntry[EventOrigin]]
  /// The root's buses, which project payloads as controls leave lowering.
  priv buses : Array[ControlBus]
  priv table : Array[BusSignal]
}

///|
pub fn PatternSnapshotWithOrigins::root(
  self : PatternSnapshotWithOrigins,
) -> @identity.PatternNodeId {
  self.root
}

///|
pub fn PatternSnapshotWithOrigins::revision(
  self : PatternSnapshotWithOrigins,
) -> @identity.Revision {
  self.revision
}

///|
pub fn PatternSnapshotWithOrigins::pat(
  self : PatternSnapshotWithOrigins,
) -> Pat[ControlMap] {
  self.pat
}

///|
pub fn PatternSnapshotWithOrigins::query(
  self : PatternSnapshotWithOrigins,
  arc : TimeSpan,
) -> Array[EventWithOrigin] {
  self.sourced
  .query(arc)
  .map(event => EventWithOrigin(event, self.buses, self.table))
}

///|
/// Query a canonical material member; invalid indexes produce no events.
pub fn PatternSnapshotWithOrigins::query_for_entry(
  self : PatternSnapshotWithOrigins,
  index : Int32,
  arc : TimeSpan,
) -> Array[EventWithOrigin] {
  match self.entry_sourced.get(index) {
    None => []
    Some(entry) =>
      entry.source
      .query(arc)
      .map(event => EventWithOrigin(event, self.buses, self.table))
  }
}

///|
/// Erase only origin capability, without compiling or interpreting time again.
pub fn PatternSnapshotWithOrigins::as_snapshot(
  self : PatternSnapshotWithOrigins,
) -> PatternSnapshot {
  fn erase_origin(value : ScopedValue[EventOrigin]) -> ScopedValue[Unit] {
    ScopedValue(
      value.value,
      value.scope,
      (),
      source_frame=value.source_frame,
      source_start=value.source_start,
      source_pitch=value.source_pitch,
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
pub fn PatternDoc::lower_with_origins(
  self : PatternDoc,
  cache~ : PatternLoweringCache = PatternLoweringCache::new(),
) -> PatternSnapshotWithOrigins raise PatternDocError {
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
/// Generic values have unknown musical content, just like Pat::pure.
pub fn PatternDoc::atom(
  id~ : @identity.PatternNodeId,
  source_atom~ : @identity.SourceAtomId,
  value~ : ControlMap,
) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(
      id,
      Atom(Pat::pure(value), value, Some(source_atom), @double.not_a_number),
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
) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(
      id,
      Atom(
        control(key, value),
        ControlMap::single(key, value),
        source_atom,
        if key == Note {
          value
        } else {
          @double.not_a_number
        },
      ),
    ),
  )
}

///|
pub fn PatternDoc::reference_with_binding(
  id~ : @identity.PatternNodeId,
  resolved_reference~ : ResolvedReference,
) -> PatternDoc {
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
/// `PatternDoc` is an immutable authoring layer above the runtime `Pat`
/// closure model. Node storage is private so future incremental lowering can
/// cache by stable node identity and revision without exposing storage shape.
pub struct PatternDoc {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv incr_revision : @types.Revision
  priv nodes : Map[String, PatternDocEntry]
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
fn PatternDoc::PatternDoc(
  root~ : @identity.PatternNodeId,
  revision~ : @identity.Revision,
  nodes~ : Map[String, PatternDocEntry],
) -> PatternDoc {
  { root, revision, incr_revision: next_pattern_doc_incr_revision(), nodes, }
}

///|
pub fn PatternDoc::from_pattern(
  id~ : @identity.PatternNodeId,
  pat~ : Pat[ControlMap],
) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Runtime(pat)),
  )
}

///|
/// A continuous control `key = f(cycles)`, sampled at each query arc's start
/// when queried as a pattern; its bus evaluates `f` at exact time.
pub fn PatternDoc::continuous(
  id~ : @identity.PatternNodeId,
  key~ : @control.Control,
  f~ : (Double) -> Double,
) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Continuous(continuous(key, f), key, f)),
  )
}

///|
pub fn PatternDoc::silence(id~ : @identity.PatternNodeId) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Silence),
  )
}

///|
pub fn PatternDoc::pure(
  id~ : @identity.PatternNodeId,
  value~ : ControlMap,
) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Pure(value)),
  )
}

///|
pub fn PatternDoc::root(self : PatternDoc) -> @identity.PatternNodeId {
  self.root
}

///|
pub fn PatternDoc::revision(self : PatternDoc) -> @identity.Revision {
  self.revision
}

///|
/// `PatternDoc` participates in incr's backdate-aware acceptance
/// (`@incr.AcceptedDerived::accepted_memo`) through its
/// `@identity.Revision` content stamp. `PatternDoc` is not `Eq` (it carries
/// closure fields), so `backdate_equal` below compares that full stamp.
///
/// incr's closed `Revision` is an independent monotonic creation stamp.
/// Semantic equality remains governed by `backdate_equal`, so reparsing an
/// unchanged document can backdate to the previously accepted value.
pub impl @types.HasChangedAt for PatternDoc with fn changed_at(self) -> @types.Revision {
  self.incr_revision
}

///|
/// Compare the full 2-D `@identity.Revision` (`value` AND `fingerprint`) via
/// its derived `Eq`, so two content-distinct docs that happen to collide on
/// `value` are still treated as changed. This is the load-bearing acceptance
/// predicate used by `accepted_memo`.
pub impl @types.BackdateEq for PatternDoc with fn backdate_equal(self, other) -> Bool {
  self.revision == other.revision
}

///|
pub fn PatternDoc::node_count(self : PatternDoc) -> Int32 {
  self.nodes.length()
}

///|
pub fn PatternDoc::contains_node(
  self : PatternDoc,
  id : @identity.PatternNodeId,
) -> Bool {
  self.nodes.contains(id.value())
}

///|
pub fn PatternDoc::subdoc(
  self : PatternDoc,
  root~ : @identity.PatternNodeId,
) -> PatternDoc raise PatternDocError {
  let nodes : Map[String, PatternDocEntry] = Map([])
  copy_reachable_pattern_nodes(self.nodes, root, nodes)
  PatternDoc(root~, revision=pattern_node_revision(nodes, root), nodes~)
}

///|
pub fn PatternDoc::node_revision(
  self : PatternDoc,
  id : @identity.PatternNodeId,
) -> @identity.Revision raise PatternDocError {
  pattern_node_revision(self.nodes, id)
}

///|
pub fn PatternDoc::lower(
  self : PatternDoc,
) -> PatternSnapshot raise PatternDocError {
  self.lower_with_cache(PatternLoweringCache::new())
}

///|
pub fn PatternDoc::lower_with_cache(
  self : PatternDoc,
  cache : PatternLoweringCache,
) -> PatternSnapshot raise PatternDocError {
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
pub fn PatternDoc::with_root(
  self : PatternDoc,
  root~ : @identity.PatternNodeId,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::replace_with_pattern(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  pat~ : Pat[ControlMap],
) -> PatternDoc raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Runtime(pat))
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
pub fn PatternDoc::replace_with_silence(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
) -> PatternDoc raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Silence)
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
pub fn PatternDoc::replace_with_pure(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  value~ : ControlMap,
) -> PatternDoc raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Pure(value))
  PatternDoc(root=self.root, revision=self.revision.next(), nodes~)
}

///|
/// Capture source-local coordinates before enclosing musical transformations.
/// This does not change the pattern's timing, material keys, or musical values.
pub fn PatternDoc::with_source_frame(
  self : PatternDoc,
  frame~ : @identity.SourceFrameId,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::fast(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::slow(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::gate(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::rev(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
) -> PatternDoc raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Rev(self.root), revision=self.revision.next())
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn PatternDoc::filter_map(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  f~ : (ControlMap) -> ControlMap?,
) -> PatternDoc raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    FilterMap(self.root, f),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn PatternDoc::euclid(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  k~ : Int32,
  n~ : Int32,
  rotation~ : Int32 = 0,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::degrade_by(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  p~ : Double,
  seed~ : Int32 = 42,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::every(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  n~ : Int32,
  transform~ : TimeTransform,
) -> PatternDoc raise PatternDocError {
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
pub fn PatternDoc::jux(
  self : PatternDoc,
  id~ : @identity.PatternNodeId,
  transform~ : TimeTransform,
) -> PatternDoc raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Jux(self.root, transform),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn PatternDoc::merge_control(
  id~ : @identity.PatternNodeId,
  left~ : PatternDoc,
  right~ : PatternDoc,
) -> PatternDoc raise PatternDocError {
  let docs = [left, right]
  let nodes : Map[String, PatternDocEntry] = Map([])
  merge_pattern_nodes(nodes, left.nodes)
  merge_pattern_nodes(nodes, right.nodes)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(nodes, id, MergeControl(left.root, right.root), revision~)
  PatternDoc(root=id, revision~, nodes~)
}

///|
pub fn PatternDoc::sequence(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc],
) -> PatternDoc raise PatternDocError {
  if docs.is_empty() {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocEntry] = Map([])
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
  }
  let children = docs.map(doc => doc.root)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(nodes, id, Sequence(children), revision~)
  PatternDoc(root=id, revision~, nodes~)
}

///|
pub fn PatternDoc::sequence_weighted(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc],
  weights~ : Array[Int32],
) -> PatternDoc raise PatternDocError {
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
  let nodes : Map[String, PatternDocEntry] = Map([])
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
pub fn PatternDoc::stack(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc],
) -> PatternDoc raise PatternDocError {
  if docs.is_empty() {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocEntry] = Map([])
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
pub fn PatternDoc::reference(
  id~ : @identity.PatternNodeId,
  definition~ : PatternDoc,
) -> PatternDoc {
  PatternDoc(
    root=id,
    revision=definition.revision,
    nodes=singleton_pattern_nodes(id, Reference(definition, None)),
  )
}

///|
/// Inspect the definition at a reference use site without losing its structure.
pub fn PatternDoc::referenced_definition(
  self : PatternDoc,
  id : @identity.PatternNodeId,
) -> PatternDoc? {
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
