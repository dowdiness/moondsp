///|
pub(all) suberror PatternDocError {
  MissingNode(String)
  DuplicateNodeId(String)
  EmptyPatternDocs
  MissingAtomOrigin(@identity.PatternNodeId)
  InvalidTailDuration
  MissingReferenceBinding(@identity.PatternNodeId)
} derive(Eq, Debug)

///|
/// Authored control-map transformations whose events keep their source atoms.
pub(all) enum CompositionOp {
  Transpose(Int)
  Steps(Array[Int], Int)
  Lowest
  Voicing(Int, Int, Int?)
  Mask(Array[Bool])
  PhaseTranspose(Int, Rational, Rational)
}

///|
fn CompositionOp::snapshot(self : CompositionOp) -> CompositionOp {
  match self {
    Steps(scale, steps) => Steps(scale.copy(), steps)
    Mask(mask) => Mask(mask.copy())
    _ => self
  }
}

///|
priv enum PatternDocNode[A] {
  Runtime(Pat[A])
  Reference(PatternDoc[A], ReferenceBinding?)
  Silence
  Pure(A)
  Atom(Pat[A], @identity.SourceAtomId)
  Fast(@identity.PatternNodeId, Rational)
  Slow(@identity.PatternNodeId, Rational)
  Gate(@identity.PatternNodeId, Rational)
  Rev(@identity.PatternNodeId)
  FilterMap(@identity.PatternNodeId, (A) -> A?)
  Composition(
    @identity.PatternNodeId,
    CompositionOp,
    (A) -> Double?,
    (A, Double) -> A
  )
  Tail(@identity.PatternNodeId, @identity.PatternNodeId, Rational)
  Euclid(@identity.PatternNodeId, Int, Int, Int)
  DegradeBy(@identity.PatternNodeId, Double, Int)
  Every(@identity.PatternNodeId, Int, TimeTransform)
  Jux(@identity.PatternNodeId, TimeTransform, (A, ControlMap) -> A)
  MergeControl(@identity.PatternNodeId, @identity.PatternNodeId, (A, A) -> A)
  Sequence(Array[@identity.PatternNodeId])
  Stack(Array[@identity.PatternNodeId])
}

///|
priv struct PatternDocEntry[A] {
  generation : Int64
  revision : @identity.Revision
  node : PatternDocNode[A]
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
    Reference(definition, binding) => Reference(definition, binding)
    Silence => Silence
    Pure(value) => Pure(value)
    Atom(pat, atom) => Atom(pat, atom)
    Fast(child, factor) => Fast(child, factor)
    Slow(child, factor) => Slow(child, factor)
    Gate(child, factor) => Gate(child, factor)
    Rev(child) => Rev(child)
    FilterMap(child, f) => FilterMap(child, f)
    Composition(child, op, pitch, set_pitch) =>
      Composition(child, op.snapshot(), pitch, set_pitch)
    Tail(child, replacement, cycles) => Tail(child, replacement, cycles)
    Euclid(child, k, n, rotation) => Euclid(child, k, n, rotation)
    DegradeBy(child, p, seed) => DegradeBy(child, p, seed)
    Every(child, n, f) => Every(child, n, f)
    Jux(child, transform, merge) => Jux(child, transform, merge)
    MergeControl(left, right, f) => MergeControl(left, right, f)
    Sequence(children) => Sequence(children.copy())
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
            Runtime(_) | Silence | Pure(_) | Atom(_, _) => ()
            Fast(child, _)
            | Slow(child, _)
            | Gate(child, _)
            | Rev(child)
            | FilterMap(child, _)
            | Composition(child, _, _, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _, _) =>
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(nodes, child, memo),
              )
            Tail(left, right, _) | MergeControl(left, right, _) => {
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
        Runtime(_) | Silence | Pure(_) | Atom(_, _) => ()
        Fast(child, _)
        | Slow(child, _)
        | Gate(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Composition(child, _, _, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _, _) =>
          copy_reachable_pattern_nodes(source, child, target)
        Tail(left, right, _) | MergeControl(left, right, _) => {
          copy_reachable_pattern_nodes(source, left, target)
          copy_reachable_pattern_nodes(source, right, target)
        }
        Sequence(children) | Stack(children) =>
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
            Runtime(_) | Silence | Pure(_) | Atom(_, _) => ()
            Fast(child, _)
            | Slow(child, _)
            | Gate(child, _)
            | Rev(child)
            | FilterMap(child, _)
            | Composition(child, _, _, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _, _) =>
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, child, memo),
              )
            Tail(left, right, _) | MergeControl(left, right, _) => {
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, left, memo),
              )
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, right, memo),
              )
            }
            Sequence(children) | Stack(children) =>
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
pub struct PatternNodePath {
  priv root : @identity.PatternNodeId
  priv descendants : Array[@identity.PatternNodeId]
} derive(Eq, Debug)

///|
fn PatternNodePath::PatternNodePath(
  root : @identity.PatternNodeId,
  descendants? : Array[@identity.PatternNodeId] = [],
) -> PatternNodePath {
  { root, descendants: descendants.copy(), }
}

///|
pub fn PatternNodePath::leaf(self : PatternNodePath) -> @identity.PatternNodeId {
  match self.descendants.last() {
    Some(id) => id
    None => self.root
  }
}

///|
pub fn PatternNodePath::nodes(
  self : PatternNodePath,
) -> Array[@identity.PatternNodeId] {
  [self.root, ..self.descendants]
}

///|
fn PatternNodePath::prepend(
  self : PatternNodePath,
  parent : @identity.PatternNodeId,
) -> PatternNodePath {
  PatternNodePath(parent, descendants=self.nodes())
}

///|
pub struct PatternSnapshotEvent[A] {
  priv event : Event[A]
  priv path : PatternNodePath
}

///|
fn[A] PatternSnapshotEvent::PatternSnapshotEvent(
  event~ : Event[A],
  path~ : PatternNodePath,
) -> PatternSnapshotEvent[A] {
  { event, path, }
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
pub struct ReferenceBinding {
  priv id : @identity.ReferenceBindingId
  priv reference : @identity.ReferenceId
  priv definition : @identity.DefinitionId
} derive(Eq, Debug)

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
priv enum OriginBindings {
  End
  Link(ReferenceBinding, OriginBindings)
} derive(Eq, Debug)

///|
/// Exact source identity. Bindings run from outer use site to inner definition.
pub struct EventOrigin {
  priv atom : @identity.SourceAtomId
  priv bindings : OriginBindings
} derive(Eq, Debug)

///|
fn EventOrigin::EventOrigin(
  atom : @identity.SourceAtomId,
  bindings? : OriginBindings = End,
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
}

///|
fn[A, O] ScopedValue::ScopedValue(
  value : A,
  scope : PatternNodePath,
  origin : O,
) -> ScopedValue[A, O] {
  { value, scope, origin, }
}

///|
fn[A, O] ScopedValue::prepend(
  self : ScopedValue[A, O],
  id : @identity.PatternNodeId,
) -> ScopedValue[A, O] {
  ScopedValue(self.value, self.scope.prepend(id), self.origin)
}

///|
fn[A, O] scoped_event(
  event : Event[ScopedValue[A, O]],
) -> PatternSnapshotEvent[A] {
  PatternSnapshotEvent(
    event={ whole: event.whole, part: event.part, value: event.value.value, },
    path=event.value.scope,
  )
}

///|
fn[A, O] erase_value(event : ScopedValue[A, O]) -> A {
  event.value
}

///|
pub struct EventWithOrigin[A] {
  priv event : Event[A]
  priv origin : EventOrigin
  priv scope : PatternNodePath
}

///|
fn[A] EventWithOrigin::EventWithOrigin(
  event : Event[ScopedValue[A, EventOrigin]],
) -> EventWithOrigin[A] {
  {
    event: { whole: event.whole, part: event.part, value: event.value.value, },
    origin: event.value.origin,
    scope: event.value.scope,
  }
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
        Runtime(_) | Silence | Pure(_) | Atom(_, _) => ()
        Fast(child, _)
        | Slow(child, _)
        | Gate(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Composition(child, _, _, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _, _) =>
          append_reachable_pattern_source_ids(nodes, child, result, seen)
        Tail(left, right, _) | MergeControl(left, right, _) => {
          append_reachable_pattern_source_ids(nodes, left, result, seen)
          append_reachable_pattern_source_ids(nodes, right, result, seen)
        }
        Sequence(children) | Stack(children) =>
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
priv struct CompiledPattern[A, O] {
  pat : Pat[ScopedValue[A, O]]
  entries : Array[CompiledEntry[A, O]]
}

///|
fn[A, O] CompiledPattern::CompiledPattern(
  pat : Pat[ScopedValue[A, O]],
  entries : Array[CompiledEntry[A, O]],
) -> CompiledPattern[A, O] {
  { pat, entries, }
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
fn[A, O] apply_composition(
  pat : Pat[ScopedValue[A, O]],
  op : CompositionOp,
  pitch : (A) -> Double?,
  set_pitch : (A, Double) -> A,
) -> Pat[ScopedValue[A, O]] {
  let read = fn(value : ScopedValue[A, O]) { pitch(value.value) }
  let write = fn(value : ScopedValue[A, O], note : Double) {
    ScopedValue(set_pitch(value.value, note), value.scope, value.origin)
  }
  match op {
    Transpose(n) => pat.transpose_by(n, read, write)
    Steps(scale, steps) => pat.steps_by(scale, steps, read, write)
    Lowest => pat.lowest_by(read)
    Voicing(low, high, count) =>
      pat.voicing_by(low, high, count.unwrap_or(2147483647), read, write)
    Mask(mask) => pat.mask(mask)
    PhaseTranspose(n, from, to) =>
      pat.phase_transpose_by(n, from, to, read, write)
  }
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
  match entry.node {
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
      )
    }
    Runtime(pat) => {
      let origin : O = O::make_origin(id, None, context)
      let source = pat.map_payload(value => {
        ScopedValue(value, PatternNodePath(id), origin)
      })
      CompiledPattern(source, opaque_compiled_entries(source, id))
    }
    Silence => CompiledPattern::single_material(Pat::silence(), id)
    Pure(value) => {
      let origin : O = O::make_origin(id, None, context)
      CompiledPattern::single_material(
        Pat::pure(ScopedValue(value, PatternNodePath(id), origin)),
        id,
      )
    }
    Atom(pat, atom) => {
      let origin : O = O::make_origin(id, Some(atom), context)
      let source = pat.map_payload(value => {
        ScopedValue(value, PatternNodePath(id), origin)
      })
      CompiledPattern(source, opaque_compiled_entries(source, id))
    }
    Fast(child, factor) => {
      let child = lower(child)
      let result = child.transform(pat => prepend(pat.fast(factor)))
      if factor.num <= 0L {
        CompiledPattern(result.pat, [])
      } else {
        result
      }
    }
    Slow(child, factor) => {
      let child = lower(child)
      let result = child.transform(pat => prepend(pat.slow(factor)))
      if factor.num <= 0L {
        CompiledPattern(result.pat, [])
      } else {
        result
      }
    }
    Gate(child, factor) =>
      lower(child).transform(pat => prepend(pat.gate(factor)))
    Rev(child) => lower(child).transform(pat => prepend(pat.rev()))
    FilterMap(child, f) =>
      lower(child).transform(pat => {
        pat.filter_map_payload(
          value => {
            f(value.value).map(mapped => {
              ScopedValue(mapped, value.scope.prepend(id), value.origin)
            })
          },
          "",
        )
      })
    Composition(child_id, op, pitch, set_pitch) => {
      let child = lower(child_id)
      match op {
        Lowest | Voicing(_, _, _) if child.entries.length() > 1 => {
          // Ranking notes requires all simultaneous layers in one query.
          // An authored material scope prevents entries() from splitting it.
          let pat = prepend(apply_composition(child.pat, op, pitch, set_pitch)).material()
          CompiledPattern::single_material(pat, id)
        }
        _ =>
          child.transform(pat => {
            prepend(apply_composition(pat, op, pitch, set_pitch))
          })
      }
    }
    Tail(child_id, replacement_id, cycles) => {
      let child = lower(child_id)
      let replacement = lower(replacement_id)
      let pat = child.pat.tail(replacement.pat, cycles~) catch {
        _ => raise InvalidTailDuration
      }
      CompiledPattern::single_material(prepend(pat), id)
    }
    Euclid(child, k, n, rotation) =>
      CompiledPattern::single_material(
        prepend(lower(child).pat.euclid(k, n, rotation~)),
        id,
      )
    DegradeBy(child, p, seed) =>
      lower(child).transform(pat => prepend(pat.degrade_by(p, seed~)))
    Every(child_id, n, transform) => {
      let child = lower(child_id)
      let scope = pattern_source_path_for_opaque_children(nodes, id, [child_id])
      let base = prepend(child.pat)
      // Keep the old opaque-callback signature policy, despite the typed operation.
      let pat = every(
        n,
        p => {
          transform
          .apply(p)
          .map_payload(value => ScopedValue(value.value, scope, value.origin))
        },
        base,
      )
      let entries = if n <= 0 {
        child.entries.map(entry => {
          CompiledEntry(entry.key, prepend(entry.source))
        })
      } else {
        [CompiledEntry("\{id.value().length()}:\{id.value()}", pat)]
      }
      CompiledPattern(pat, entries)
    }
    Jux(child_id, transform, merge) => {
      let child = lower(child_id)
      let scope = pattern_source_path_for_opaque_children(nodes, id, [child_id])
      let pat = jux_kernel(
        child.pat,
        p => transform.apply(p),
        (value, pan) => {
          ScopedValue(merge(value.value, pan), value.scope, value.origin)
        },
        "",
      ).map_payload(value => ScopedValue(value.value, scope, value.origin))
      CompiledPattern(pat, opaque_compiled_entries(pat, id))
    }
    MergeControl(left_id, right_id, merge) => {
      let left = lower(left_id)
      // Control providers need no primary source atom or reference binding.
      let right : CompiledPattern[A, Unit] = lower_pattern_node_cached(
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
      let pat = merge_control_kernel(
        left.pat,
        right.pat.map_payload(erase_value),
        (value, control) => {
          ScopedValue(merge(value.value, control), value.scope, value.origin)
        },
      ).map_payload(value => ScopedValue(value.value, scope, value.origin))
      let entries = pat.entries()
      CompiledPattern(
        pat,
        Array::makei(entries.length(), index => {
          CompiledEntry(left.entries[index].key, entries[index])
        }),
      )
    }
    Sequence(children) => {
      let pats = children.map(child => lower(child).pat)
      CompiledPattern::single_material(prepend(sequence(pats)), id)
    }
    Stack(children) => {
      let children = children.map(lower)
      let entries = children
        .iter()
        .flat_map(child => {
          child.entries
          .iter()
          .map(entry => CompiledEntry(entry.key, prepend(entry.source)))
        })
        .collect()
      CompiledPattern(prepend(stack(children.map(child => child.pat))), entries)
    }
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
  mut others : Map[Int, Array[CompiledCacheEntry[A, O]]]?
}

///|
/// This fingerprint selects a bucket, never establishes origin identity.
/// Lookup still compares the full context, including epochs and binding witnesses.
fn OriginBindings::cache_hash(self : OriginBindings) -> Int {
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
  mut hits : Int
  mut misses : Int
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
          let buckets : Map[Int, Array[CompiledCacheEntry[A, O]]] = Map([])
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
fn[A, O] CompiledCache::hit_count(self : CompiledCache[A, O]) -> Int {
  self.hits
}

///|
fn[A, O] CompiledCache::miss_count(self : CompiledCache[A, O]) -> Int {
  self.misses
}

///|
fn[A, O] CompiledCache::entry_count(self : CompiledCache[A, O]) -> Int {
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
) -> Int {
  self.general.hit_count() + self.exact.hit_count()
}

///|
pub fn[A] PatternLoweringCache::miss_count(
  self : PatternLoweringCache[A],
) -> Int {
  self.general.miss_count() + self.exact.miss_count()
}

///|
pub fn[A] PatternLoweringCache::entry_count(
  self : PatternLoweringCache[A],
) -> Int {
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
/// Stable playback occurrence key, independent of overlay source ancestry.
/// Reusing a definition at distinct reference nodes produces distinct keys.
pub fn[A] PatternSnapshot::entry_key(
  self : PatternSnapshot[A],
  source_index : Int,
) -> String? {
  self.entry_sourced.get(source_index).map(entry => entry.key)
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
pub fn[A] PatternSnapshot::query_sourced_events(
  self : PatternSnapshot[A],
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  self.sourced.query(arc).map(scoped_event)
}

///|
/// Query one canonical `Pat::entries()` member with authored provenance.
/// `source_index` is the member index retained by playback entry state.
/// Invalid indexes return an empty result.
pub fn[A] PatternSnapshot::query_sourced_events_for_entry(
  self : PatternSnapshot[A],
  source_index : Int,
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  match self.entry_sourced.get(source_index) {
    Some(entry) => entry.source.query(arc).map(scoped_event)
    None => []
  }
}

///|
/// A compiled pattern whose every emitted event carries an exact source origin.
pub struct PatternSnapshotWithOrigins[A] {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv pat : Pat[A]
  priv sourced : Pat[ScopedValue[A, EventOrigin]]
  priv entry_sourced : Array[CompiledEntry[A, EventOrigin]]
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
pub fn[A] PatternSnapshotWithOrigins::pat(
  self : PatternSnapshotWithOrigins[A],
) -> Pat[A] {
  self.pat
}

///|
pub fn[A] PatternSnapshotWithOrigins::entry_key(
  self : PatternSnapshotWithOrigins[A],
  index : Int,
) -> String? {
  self.entry_sourced.get(index).map(entry => entry.key)
}

///|
pub fn[A] PatternSnapshotWithOrigins::query(
  self : PatternSnapshotWithOrigins[A],
  arc : TimeSpan,
) -> Array[EventWithOrigin[A]] {
  self.sourced.query(arc).map(event => EventWithOrigin(event))
}

///|
/// Query a canonical material member; invalid indexes produce no events.
pub fn[A] PatternSnapshotWithOrigins::query_for_entry(
  self : PatternSnapshotWithOrigins[A],
  index : Int,
  arc : TimeSpan,
) -> Array[EventWithOrigin[A]] {
  match self.entry_sourced.get(index) {
    None => []
    Some(entry) => entry.source.query(arc).map(event => EventWithOrigin(event))
  }
}

///|
/// Erase only origin capability, without compiling or interpreting time again.
pub fn[A] PatternSnapshotWithOrigins::as_snapshot(
  self : PatternSnapshotWithOrigins[A],
) -> PatternSnapshot[A] {
  fn erase_origin(value : ScopedValue[A, EventOrigin]) -> ScopedValue[A, Unit] {
    ScopedValue(value.value, value.scope, ())
  }
  {
    root: self.root,
    revision: self.revision,
    pat: self.pat,
    sourced: self.sourced.map_payload(erase_origin),
    entry_sourced: self.entry_sourced.map(entry => {
      CompiledEntry(entry.key, entry.source.map_payload(erase_origin))
    }),
  }
}

///|
pub fn[A] PatternDoc::lower_with_origins(
  self : PatternDoc[A],
  cache? : PatternLoweringCache[A] = PatternLoweringCache::new(),
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
    pat: compiled.pat.map_payload(erase_value),
    sourced: compiled.pat,
    entry_sourced: compiled.entries,
  }
}

///|
/// Generic values have unknown musical content, just like Pat::pure.
pub fn[A] PatternDoc::atom(
  id~ : @identity.PatternNodeId,
  source_atom~ : @identity.SourceAtomId,
  value~ : A,
) -> PatternDoc[A] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Atom(Pat::pure(value), source_atom)),
  )
}

///|
/// Use the canonical control constructor's signature; source IDs never enter it.
pub fn PatternDoc::control_atom(
  id~ : @identity.PatternNodeId,
  source_atom~ : @identity.SourceAtomId,
  key~ : String,
  value~ : Double,
) -> PatternDoc[ControlMap] {
  PatternDoc(
    root=id,
    revision=@identity.Revision::zero(),
    nodes=singleton_pattern_nodes(id, Atom(control(key, value), source_atom)),
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
/// `PatternDoc` is an immutable authoring layer above the runtime `Pat`
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
/// `PatternDoc` participates in incr's backdate-aware acceptance
/// (`@incr.AcceptedDerived::accepted_memo`) through its
/// `@identity.Revision` content stamp. `PatternDoc` is not `Eq` (it carries
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
pub fn[A] PatternDoc::node_count(self : PatternDoc[A]) -> Int {
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
pub fn[A] PatternDoc::lower(
  self : PatternDoc[A],
) -> PatternSnapshot[A] raise PatternDocError {
  self.lower_with_cache(PatternLoweringCache::new())
}

///|
pub fn[A] PatternDoc::lower_with_cache(
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
    pat: compiled.pat.map_payload(erase_value),
    sourced: compiled.pat,
    entry_sourced: compiled.entries,
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
pub fn[A] PatternDoc::filter_map(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  f~ : (A) -> A?,
) -> PatternDoc[A] raise PatternDocError {
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
pub fn PatternDoc::compose(
  self : PatternDoc[ControlMap],
  id~ : @identity.PatternNodeId,
  operation~ : CompositionOp,
) -> PatternDoc[ControlMap] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Composition(self.root, operation.snapshot(), value => value.get("note"), (
      value,
      note,
    ) => value.set("note", note)),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn[A] PatternDoc::tail(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  replacement~ : PatternDoc[A],
  cycles~ : Rational,
) -> PatternDoc[A] raise PatternDocError {
  let period = self.lower().pat().entry_period()
  guard cycles > Rational::from_int(0) && cycles <= period else {
    raise InvalidTailDuration
  }
  let nodes = copy_pattern_nodes(self.nodes)
  merge_pattern_nodes(nodes, replacement.nodes)
  let revision = self.revision.combine(replacement.revision).next()
  insert_pattern_node(
    nodes,
    id,
    Tail(self.root, replacement.root, cycles),
    revision~,
  )
  PatternDoc(root=id, revision~, nodes~)
}

///|
pub fn[A] PatternDoc::euclid(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  k~ : Int,
  n~ : Int,
  rotation? : Int = 0,
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
  seed? : Int = 42,
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
  n~ : Int,
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
pub fn PatternDoc::jux(
  self : PatternDoc[ControlMap],
  id~ : @identity.PatternNodeId,
  transform~ : TimeTransform,
) -> PatternDoc[ControlMap] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Jux(self.root, transform, merge_maps),
    revision=self.revision.next(),
  )
  PatternDoc(root=id, revision=self.revision.next(), nodes~)
}

///|
pub fn PatternDoc::merge_control(
  id~ : @identity.PatternNodeId,
  left~ : PatternDoc[ControlMap],
  right~ : PatternDoc[ControlMap],
) -> PatternDoc[ControlMap] raise PatternDocError {
  let docs = [left, right]
  let nodes : Map[String, PatternDocEntry[ControlMap]] = Map([])
  merge_pattern_nodes(nodes, left.nodes)
  merge_pattern_nodes(nodes, right.nodes)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(
    nodes,
    id,
    MergeControl(left.root, right.root, merge_maps),
    revision~,
  )
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
