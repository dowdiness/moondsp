///|
pub(all) suberror PatternDocError {
  MissingNode(String)
  DuplicateNodeId(String)
  EmptyPatternDocs
} derive(Eq, Debug)

///|
priv enum PatternDocNode[A] {
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
priv struct PatternDocEntry[A] {
  generation : Int64
  revision : @identity.Revision
  node : PatternDocNode[A]
}

///|
let pattern_node_generation_counter : Ref[Int64] = Ref::new(0L)

///|
fn next_pattern_node_generation() -> Int64 {
  pattern_node_generation_counter.val = pattern_node_generation_counter.val + 1L
  pattern_node_generation_counter.val
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
  let result : Map[String, PatternDocEntry[A]] = {}
  nodes.each(fn(id, entry) { result[id] = entry.snapshot() })
  result
}

///|
fn[A] singleton_pattern_nodes(
  id : @identity.PatternNodeId,
  node : PatternDocNode[A],
) -> Map[String, PatternDocEntry[A]] {
  let nodes : Map[String, PatternDocEntry[A]] = {}
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
        generation: entry.generation,
        revision: entry.revision.next(),
        node: node.snapshot(),
      }
  }
}

///|
fn[A] pattern_node_revision(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
) -> @identity.Revision raise PatternDocError {
  match nodes.get(id.value()) {
    None => raise MissingNode(id.value())
    Some(entry) => {
      let mut revision = entry.revision
      match entry.node {
        Runtime(_) | Silence | Pure(_) => ()
        Fast(child, _)
        | Slow(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _) =>
          revision = revision.combine(pattern_node_revision(nodes, child))
        MergeControl(left, right, _) => {
          revision = revision.combine(pattern_node_revision(nodes, left))
          revision = revision.combine(pattern_node_revision(nodes, right))
        }
        Sequence(children) | Stack(children) =>
          for child in children {
            revision = revision.combine(pattern_node_revision(nodes, child))
          }
      }
      revision
    }
  }
}

///|
fn[A] lower_pattern_node(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
) -> Pat[A] raise PatternDocError {
  match nodes.get(id.value()) {
    None => raise MissingNode(id.value())
    Some(entry) =>
      match entry.node {
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
priv struct PatternLoweringCacheEntry[A] {
  generation : Int64
  revision : @identity.Revision
  pat : Pat[A]
}

///|
/// Cache for lowered pattern subtrees.
///
/// Entries are keyed by stable `PatternNodeId`, a private node-generation guard,
/// and full `Revision` equality. The generation guard prevents stale hits when
/// callers rebuild unrelated documents with the same stable IDs and fresh
/// zero revisions.
pub struct PatternLoweringCache[A] {
  priv entries : Map[String, Array[PatternLoweringCacheEntry[A]]]
  priv mut hits : Int
  priv mut misses : Int
}

///|
pub fn[A] PatternLoweringCache::new() -> PatternLoweringCache[A] {
  { entries: {}, hits: 0, misses: 0 }
}

///|
fn[A] PatternLoweringCache::lookup(
  self : PatternLoweringCache[A],
  id : @identity.PatternNodeId,
  generation : Int64,
  revision : @identity.Revision,
) -> Pat[A]? {
  match self.entries.get(id.value()) {
    None => {
      self.misses += 1
      None
    }
    Some(entries) => {
      for entry in entries {
        if entry.generation == generation && entry.revision == revision {
          self.hits += 1
          return Some(entry.pat)
        }
      }
      self.misses += 1
      None
    }
  }
}

///|
fn[A] PatternLoweringCache::store(
  self : PatternLoweringCache[A],
  id : @identity.PatternNodeId,
  generation : Int64,
  revision : @identity.Revision,
  pat : Pat[A],
) -> Unit {
  let key = id.value()
  match self.entries.get(key) {
    None => self.entries[key] = [{ generation, revision, pat }]
    Some(entries) => {
      for index in 0..<entries.length() {
        if entries[index].generation == generation &&
          entries[index].revision == revision {
          entries[index] = { generation, revision, pat }
          return
        }
      }
      entries.push({ generation, revision, pat })
    }
  }
}

///|
fn[A] lower_pattern_node_cached(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  cache : PatternLoweringCache[A],
) -> Pat[A] raise PatternDocError {
  let key = id.value()
  let revision = pattern_node_revision(nodes, id)
  let generation = match nodes.get(key) {
    None => raise MissingNode(key)
    Some(entry) => entry.generation
  }
  match cache.lookup(id, generation, revision) {
    Some(pat) => pat
    None => {
      let pat = match nodes.get(key) {
        None => raise MissingNode(key)
        Some(entry) =>
          match entry.node {
            Runtime(pat) => pat
            Silence => Pat::silence()
            Pure(value) => Pat::pure(value)
            Fast(child, factor) =>
              lower_pattern_node_cached(nodes, child, cache).fast(factor)
            Slow(child, factor) =>
              lower_pattern_node_cached(nodes, child, cache).slow(factor)
            Rev(child) => lower_pattern_node_cached(nodes, child, cache).rev()
            FilterMap(child, f) =>
              lower_pattern_node_cached(nodes, child, cache).filter_map(f)
            Euclid(child, k, n, rotation) =>
              lower_pattern_node_cached(nodes, child, cache).euclid(
                k,
                n,
                rotation~,
              )
            DegradeBy(child, p, seed) =>
              lower_pattern_node_cached(nodes, child, cache).degrade_by(
                p,
                seed~,
              )
            Every(child, n, f) =>
              every(n, f, lower_pattern_node_cached(nodes, child, cache))
            Jux(child, f) => f(lower_pattern_node_cached(nodes, child, cache))
            MergeControl(left, right, f) =>
              f(
                lower_pattern_node_cached(nodes, left, cache),
                lower_pattern_node_cached(nodes, right, cache),
              )
            Sequence(children) => {
              let pats : Array[Pat[A]] = []
              for child in children {
                pats.push(lower_pattern_node_cached(nodes, child, cache))
              }
              sequence(pats)
            }
            Stack(children) => {
              let pats : Array[Pat[A]] = []
              for child in children {
                pats.push(lower_pattern_node_cached(nodes, child, cache))
              }
              stack(pats)
            }
          }
      }
      cache.store(id, generation, revision, pat)
      pat
    }
  }
}

///|
pub fn[A] PatternLoweringCache::hit_count(
  self : PatternLoweringCache[A],
) -> Int {
  self.hits
}

///|
pub fn[A] PatternLoweringCache::miss_count(
  self : PatternLoweringCache[A],
) -> Int {
  self.misses
}

///|
pub fn[A] PatternLoweringCache::entry_count(
  self : PatternLoweringCache[A],
) -> Int {
  let mut count = 0
  self.entries.each(fn(_, entries) { count += entries.length() })
  count
}

///|
pub fn[A] PatternLoweringCache::reset_stats(
  self : PatternLoweringCache[A],
) -> Unit {
  self.hits = 0
  self.misses = 0
}

///|
pub fn[A] PatternLoweringCache::clear(self : PatternLoweringCache[A]) -> Unit {
  self.entries.clear()
  self.reset_stats()
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
  priv nodes : Map[String, PatternDocEntry[A]]
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
  {
    root: self.root,
    revision: self.revision,
    pat: lower_pattern_node(self.nodes, self.root),
  }
}

///|
pub fn[A] PatternDoc::lower_with_cache(
  self : PatternDoc[A],
  cache : PatternLoweringCache[A],
) -> PatternSnapshot[A] raise PatternDocError {
  {
    root: self.root,
    revision: self.revision,
    pat: lower_pattern_node_cached(self.nodes, self.root, cache),
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
  insert_pattern_node(
    nodes,
    id,
    Fast(self.root, factor),
    revision=self.revision.next(),
  )
  { root: id, revision: self.revision.next(), nodes }
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
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn[A] PatternDoc::rev(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Rev(self.root), revision=self.revision.next())
  { root: id, revision: self.revision.next(), nodes }
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
  insert_pattern_node(
    nodes,
    id,
    Euclid(self.root, k, n, rotation),
    revision=self.revision.next(),
  )
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
  insert_pattern_node(
    nodes,
    id,
    DegradeBy(self.root, p, seed),
    revision=self.revision.next(),
  )
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
  insert_pattern_node(
    nodes,
    id,
    Every(self.root, n, f),
    revision=self.revision.next(),
  )
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn PatternDoc::jux(
  self : PatternDoc[ControlMap],
  id~ : @identity.PatternNodeId,
  f~ : (Pat[ControlMap]) -> Pat[ControlMap],
) -> PatternDoc[ControlMap] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(
    nodes,
    id,
    Jux(self.root, fn(p) { p.jux(f) }),
    revision=self.revision.next(),
  )
  { root: id, revision: self.revision.next(), nodes }
}

///|
pub fn PatternDoc::merge_control(
  id~ : @identity.PatternNodeId,
  left~ : PatternDoc[ControlMap],
  right~ : PatternDoc[ControlMap],
) -> PatternDoc[ControlMap] raise PatternDocError {
  let docs = [left, right]
  let nodes : Map[String, PatternDocEntry[ControlMap]] = {}
  merge_pattern_nodes(nodes, left.nodes)
  merge_pattern_nodes(nodes, right.nodes)
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(
    nodes,
    id,
    MergeControl(left.root, right.root, merge_control),
    revision~,
  )
  { root: id, revision, nodes }
}

///|
pub fn[A] PatternDoc::sequence(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
) -> PatternDoc[A] raise PatternDocError {
  if docs.length() == 0 {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocEntry[A]] = {}
  let children : Array[@identity.PatternNodeId] = []
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
    children.push(doc.root)
  }
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(nodes, id, Sequence(children), revision~)
  { root: id, revision, nodes }
}

///|
pub fn[A] PatternDoc::stack(
  id~ : @identity.PatternNodeId,
  docs~ : Array[PatternDoc[A]],
) -> PatternDoc[A] raise PatternDocError {
  if docs.length() == 0 {
    raise EmptyPatternDocs
  }
  let nodes : Map[String, PatternDocEntry[A]] = {}
  let children : Array[@identity.PatternNodeId] = []
  for doc in docs {
    merge_pattern_nodes(nodes, doc.nodes)
    children.push(doc.root)
  }
  let revision = aggregate_pattern_revision(docs)
  insert_pattern_node(nodes, id, Stack(children), revision~)
  { root: id, revision, nodes }
}
