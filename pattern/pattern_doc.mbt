///|
pub(all) suberror PatternDocError {
  MissingNode(String)
  DuplicateNodeId(String)
  EmptyPatternDocs
} derive(Eq, Debug)

///|
enum PatternDocNode[A] {
  Runtime(Pat[A])
  Silence
  Pure(A)
  Fast(@identity.PatternNodeId, Rational)
  Slow(@identity.PatternNodeId, Rational)
  Rev(@identity.PatternNodeId)
  FilterMap(@identity.PatternNodeId, (A) -> A?)
  Euclid(@identity.PatternNodeId, Int, Int, Int)
  DegradeBy(@identity.PatternNodeId, Double, Int)
  Every(@identity.PatternNodeId, Int, (Pat[A]) -> Pat[A])
  Jux(@identity.PatternNodeId, (Pat[A]) -> Pat[A])
  MergeControl(
    @identity.PatternNodeId,
    @identity.PatternNodeId,
    (Pat[A], Pat[A]) -> Pat[A]
  )
  Sequence(Array[@identity.PatternNodeId])
  Stack(Array[@identity.PatternNodeId])
}

///|
fn[A] PatternDocNode::snapshot(self : PatternDocNode[A]) -> PatternDocNode[A] {
  match self {
    Runtime(pat) => Runtime(pat)
    Silence => Silence
    Pure(value) => Pure(value)
    Fast(child, factor) => Fast(child, factor)
    Slow(child, factor) => Slow(child, factor)
    Rev(child) => Rev(child)
    FilterMap(child, f) => FilterMap(child, f)
    Euclid(child, k, n, rotation) => Euclid(child, k, n, rotation)
    DegradeBy(child, p, seed) => DegradeBy(child, p, seed)
    Every(child, n, f) => Every(child, n, f)
    Jux(child, f) => Jux(child, f)
    MergeControl(left, right, f) => MergeControl(left, right, f)
    Sequence(children) => Sequence(children.copy())
    Stack(children) => Stack(children.copy())
  }
}

///|
fn[A] copy_pattern_nodes(
  nodes : Map[String, PatternDocNode[A]],
) -> Map[String, PatternDocNode[A]] {
  let result : Map[String, PatternDocNode[A]] = {}
  nodes.each(fn(id, node) { result[id] = node.snapshot() })
  result
}

///|
fn[A] singleton_pattern_nodes(
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
) -> Map[String, PatternDocNode[A]] {
  let nodes : Map[String, PatternDocNode[A]] = {}
  nodes[id.value()] = node.snapshot()
  nodes
}

///|
fn[A] insert_pattern_node(
  nodes : Map[String, PatternDocNode[A]],
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
) -> Unit raise PatternDocError {
  let key = id.value()
  if nodes.contains(key) {
    raise DuplicateNodeId(key)
  }
  nodes[key] = node.snapshot()
}

///|
fn[A] merge_pattern_nodes(
  target : Map[String, PatternDocNode[A]],
  source : Map[String, PatternDocNode[A]],
) -> Unit raise PatternDocError {
  source.each((id, node) => {
    if target.contains(id) {
      raise DuplicateNodeId(id)
    }
    target[id] = node.snapshot()
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
  nodes : Map[String, PatternDocNode[A]],
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
) -> Unit raise PatternDocError {
  let key = id.value()
  if !nodes.contains(key) {
    raise MissingNode(key)
  }
  nodes[key] = node.snapshot()
}

///|
fn[A] lower_pattern_node(
  nodes : Map[String, PatternDocNode[A]],
  id : @identity.PatternNodeId,
) -> Pat[A] raise PatternDocError {
  match nodes.get(id.value()) {
    None => raise MissingNode(id.value())
    Some(node) =>
      match node {
        Runtime(pat) => pat
        Silence => Pat::silence()
        Pure(value) => Pat::pure(value)
        Fast(child, factor) => lower_pattern_node(nodes, child).fast(factor)
        Slow(child, factor) => lower_pattern_node(nodes, child).slow(factor)
        Rev(child) => lower_pattern_node(nodes, child).rev()
        FilterMap(child, f) => lower_pattern_node(nodes, child).filter_map(f)
        Euclid(child, k, n, rotation) =>
          lower_pattern_node(nodes, child).euclid(k, n, rotation~)
        DegradeBy(child, p, seed) =>
          lower_pattern_node(nodes, child).degrade_by(p, seed~)
        Every(child, n, f) => every(n, f, lower_pattern_node(nodes, child))
        Jux(child, f) => f(lower_pattern_node(nodes, child))
        MergeControl(left, right, f) =>
          f(lower_pattern_node(nodes, left), lower_pattern_node(nodes, right))
        Sequence(children) => {
          let pats : Array[Pat[A]] = []
          for child in children {
            pats.push(lower_pattern_node(nodes, child))
          }
          sequence(pats)
        }
        Stack(children) => {
          let pats : Array[Pat[A]] = []
          for child in children {
            pats.push(lower_pattern_node(nodes, child))
          }
          stack(pats)
        }
      }
  }
}

///|
/// Lowered pattern snapshot for scheduler/runtime consumers.
pub struct PatternSnapshot[A] {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv pat : Pat[A]
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
/// Identity-bearing pattern authoring document.
///
/// `PatternDoc` is an immutable authoring layer above the runtime `Pat`
/// closure model. Node storage is private so future incremental lowering can
/// cache by stable node identity and revision without exposing storage shape.
pub struct PatternDoc[A] {
  priv root : @identity.PatternNodeId
  priv revision : @identity.Revision
  priv nodes : Map[String, PatternDocNode[A]]
}

///|
pub fn[A] PatternDoc::from_pattern(
  id~ : @identity.PatternNodeId,
  pat~ : Pat[A],
) -> PatternDoc[A] {
  {
    root: id,
    revision: @identity.Revision::zero(),
    nodes: singleton_pattern_nodes(id, Runtime(pat)),
  }
}

///|
pub fn[A] PatternDoc::silence(id~ : @identity.PatternNodeId) -> PatternDoc[A] {
  {
    root: id,
    revision: @identity.Revision::zero(),
    nodes: singleton_pattern_nodes(id, Silence),
  }
}

///|
pub fn[A] PatternDoc::pure(
  id~ : @identity.PatternNodeId,
  value~ : A,
) -> PatternDoc[A] {
  {
    root: id,
    revision: @identity.Revision::zero(),
    nodes: singleton_pattern_nodes(id, Pure(value)),
  }
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
pub fn[A] PatternDoc::lower(
  self : PatternDoc[A],
) -> PatternSnapshot[A] raise PatternDocError {
  {
    root: self.root,
    revision: self.revision,
    pat: lower_pattern_node(self.nodes, self.root),
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
  {
    root,
    revision: self.revision.next(),
    nodes: copy_pattern_nodes(self.nodes),
  }
}

///|
pub fn[A] PatternDoc::replace_with_pattern(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  pat~ : Pat[A],
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Runtime(pat))
  { root: self.root, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::replace_with_silence(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Silence)
  { root: self.root, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::replace_with_pure(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  value~ : A,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Pure(value))
  { root: self.root, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::fast(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Fast(self.root, factor))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::slow(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  factor~ : Rational,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Slow(self.root, factor))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::rev(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Rev(self.root))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::filter_map(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  f~ : (A) -> A?,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, FilterMap(self.root, f))
  { root: id, revision: self.revision.next(), nodes }
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
  insert_pattern_node(nodes, id, Euclid(self.root, k, n, rotation))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::degrade_by(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  p~ : Double,
  seed? : Int = 42,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, DegradeBy(self.root, p, seed))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::every(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  n~ : Int,
  f~ : (Pat[A]) -> Pat[A],
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Every(self.root, n, f))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn PatternDoc::jux(
  self : PatternDoc[ControlMap],
  id~ : @identity.PatternNodeId,
  f~ : (Pat[ControlMap]) -> Pat[ControlMap],
) -> PatternDoc[ControlMap] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Jux(self.root, fn(p) { p.jux(f) }))
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn PatternDoc::merge_control(
  id~ : @identity.PatternNodeId,
  left~ : PatternDoc[ControlMap],
  right~ : PatternDoc[ControlMap],
) -> PatternDoc[ControlMap] raise PatternDocError {
  let docs = [left, right]
  let nodes : Map[String, PatternDocNode[ControlMap]] = {}
  merge_pattern_nodes(nodes, left.nodes)
  merge_pattern_nodes(nodes, right.nodes)
  insert_pattern_node(
    nodes,
    id,
    MergeControl(left.root, right.root, merge_control),
  )
  { root: id, revision: aggregate_pattern_revision(docs), nodes }
}

///|
pub fn[A] PatternDoc::sequence(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
) -> PatternDoc[A] raise PatternDocError {
  if docs.length() == 0 {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocNode[A]] = {}
  let children : Array[@identity.PatternNodeId] = []
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
    children.push(doc.root)
  }
  insert_pattern_node(nodes, id, Sequence(children))
  { root: id, revision: aggregate_pattern_revision(docs), nodes }
}

///|
pub fn[A] PatternDoc::stack(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
) -> PatternDoc[A] raise PatternDocError {
  if docs.length() == 0 {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocNode[A]] = {}
  let children : Array[@identity.PatternNodeId] = []
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
    children.push(doc.root)
  }
  insert_pattern_node(nodes, id, Stack(children))
  { root: id, revision: aggregate_pattern_revision(docs), nodes }
}
