///|
pub(all) suberror PatternDocError {
  MissingNode(String)
  DuplicateNodeId(String)
  EmptyPatternDocs
} derive(Eq, Debug)

///|
priv enum PatternDocNode[A] {
  Runtime(Pat[A])
  Reference(PatternDoc[A])
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
    Reference(definition) => Reference(definition)
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
            Reference(definition) =>
              append_pattern_cache_token(
                token,
                pattern_node_cache_token_memoized(
                  definition.nodes,
                  definition.root,
                  {},
                ),
              )
            Runtime(_) | Silence | Pure(_) => ()
            Fast(child, _)
            | Slow(child, _)
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
            MergeControl(left, right, _) => {
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
        Reference(_) => ()
        Runtime(_) | Silence | Pure(_) => ()
        Fast(child, _)
        | Slow(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _) => copy_reachable_pattern_nodes(source, child, target)
        MergeControl(left, right, _) => {
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
            Reference(definition) =>
              revision = revision.combine(definition.revision)
            Runtime(_) | Silence | Pure(_) => ()
            Fast(child, _)
            | Slow(child, _)
            | Rev(child)
            | FilterMap(child, _)
            | Euclid(child, _, _, _)
            | DegradeBy(child, _, _)
            | Every(child, _, _)
            | Jux(child, _) =>
              revision = revision.combine(
                pattern_node_revision_memoized(nodes, child, memo),
              )
            MergeControl(left, right, _) => {
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
pub struct PatternSnapshotEvent[A] {
  priv event : Event[A]
  priv pattern_nodes : Array[@identity.PatternNodeId]
}

///|
fn[A] PatternSnapshotEvent::PatternSnapshotEvent(
  event~ : Event[A],
  pattern_nodes~ : Array[@identity.PatternNodeId],
) -> PatternSnapshotEvent[A] {
  { event, pattern_nodes: pattern_nodes.copy(), }
}

///|
pub fn[A] PatternSnapshotEvent::event(
  self : PatternSnapshotEvent[A],
) -> Event[A] {
  self.event
}

///|
pub fn[A] PatternSnapshotEvent::pattern_node(
  self : PatternSnapshotEvent[A],
) -> @identity.PatternNodeId? {
  if self.pattern_nodes.is_empty() {
    None
  } else {
    Some(self.pattern_nodes[self.pattern_nodes.length() - 1])
  }
}

///|
pub fn[A] PatternSnapshotEvent::pattern_nodes(
  self : PatternSnapshotEvent[A],
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes.copy()
}

///|
priv struct SourcedPat[A] {
  query : (TimeSpan) -> Array[PatternSnapshotEvent[A]]
}

///|
fn[A] SourcedPat::query(
  self : SourcedPat[A],
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  (self.query)(arc)
}

///|
fn pattern_source_path(
  id : @identity.PatternNodeId,
) -> Array[@identity.PatternNodeId] {
  [id]
}

///|
fn pattern_source_path_with_parent(
  id : @identity.PatternNodeId,
  child_path : Array[@identity.PatternNodeId],
) -> Array[@identity.PatternNodeId] {
  let result : Array[@identity.PatternNodeId] = [id]
  for child in child_path {
    result.push(child)
  }
  result
}

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
        Reference(definition) =>
          append_reachable_pattern_source_ids(
            definition.nodes,
            definition.root,
            result,
            {},
          )
        Runtime(_) | Silence | Pure(_) => ()
        Fast(child, _)
        | Slow(child, _)
        | Rev(child)
        | FilterMap(child, _)
        | Euclid(child, _, _, _)
        | DegradeBy(child, _, _)
        | Every(child, _, _)
        | Jux(child, _) =>
          append_reachable_pattern_source_ids(nodes, child, result, seen)
        MergeControl(left, right, _) => {
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
) -> Array[@identity.PatternNodeId] raise PatternDocError {
  let result : Array[@identity.PatternNodeId] = [id]
  let seen : Map[String, Bool] = Map([])
  seen[id.value()] = true
  for child in children {
    append_reachable_pattern_source_ids(nodes, child, result, seen)
  }
  result
}

///|
fn[A] tag_pattern_event(
  event : Event[A],
  id : @identity.PatternNodeId,
) -> PatternSnapshotEvent[A] {
  PatternSnapshotEvent(event~, pattern_nodes=pattern_source_path(id))
}

///|
fn[A] prepend_pattern_source(
  event : PatternSnapshotEvent[A],
  id : @identity.PatternNodeId,
) -> PatternSnapshotEvent[A] {
  PatternSnapshotEvent(
    event=event.event(),
    pattern_nodes=pattern_source_path_with_parent(id, event.pattern_nodes()),
  )
}

///|
fn[A] retime_pattern_snapshot_event(
  source : PatternSnapshotEvent[A],
  whole : TimeSpan?,
  part : TimeSpan,
) -> PatternSnapshotEvent[A] {
  let event = source.event()
  PatternSnapshotEvent(
    event={ whole, part, value: event.value, },
    pattern_nodes=source.pattern_nodes(),
  )
}

///|
fn scale_time_span(span : TimeSpan, factor : Rational) -> TimeSpan {
  TimeSpan::new(span.begin * factor, span.end_ * factor)
}

///|
fn[A] scale_pattern_snapshot_event(
  source : PatternSnapshotEvent[A],
  factor : Rational,
) -> PatternSnapshotEvent[A] {
  let event = source.event()
  let whole = match event.whole {
    Some(whole) => Some(scale_time_span(whole, factor))
    None => None
  }
  retime_pattern_snapshot_event(
    source,
    whole,
    scale_time_span(event.part, factor),
  )
}

///|
fn[A] mirror_pattern_snapshot_event(
  source : PatternSnapshotEvent[A],
  cycle_end : Rational,
) -> PatternSnapshotEvent[A] {
  let event = source.event()
  let part = TimeSpan::new(
    cycle_end - event.part.end_,
    cycle_end - event.part.begin,
  )
  let whole = match event.whole {
    Some(whole) =>
      Some(TimeSpan::new(cycle_end - whole.end_, cycle_end - whole.begin))
    None => None
  }
  retime_pattern_snapshot_event(source, whole, part)
}

///|
fn[A] query_sourced_fast(
  child : SourcedPat[A],
  id : @identity.PatternNodeId,
  arc : TimeSpan,
  factor : Rational,
) -> Array[PatternSnapshotEvent[A]] {
  if factor.num <= 0L {
    return []
  }
  let scaled_arc = TimeSpan::new(arc.begin * factor, arc.end_ * factor)
  let inv = Rational::new(1L, 1L) / factor
  child
  .query(scaled_arc)
  .map(event => {
    prepend_pattern_source(scale_pattern_snapshot_event(event, inv), id)
  })
}

///|
fn[A] query_sourced_rev(
  child : SourcedPat[A],
  id : @identity.PatternNodeId,
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  let one = Rational::from_int(1)
  arc
  .whole_cycles()
  .iter()
  .flat_map(cycle_arc => {
    let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
    let cycle_end = cycle_start + one
    let mirror_arc = TimeSpan::new(
      cycle_end - cycle_arc.end_,
      cycle_end - cycle_arc.begin,
    )
    child
    .query(mirror_arc)
    .iter()
    .map(event => {
      prepend_pattern_source(
        mirror_pattern_snapshot_event(event, cycle_end),
        id,
      )
    })
  })
  .collect()
}

///|
fn[A] sourced_sequence_child_events(
  child : SourcedPat[A],
  id : @identity.PatternNodeId,
  child_index : Int,
  child_count : Int,
  cycle_start : Rational,
  query_intersect : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  let n_rat = Rational::from_int(child_count)
  let i_rat = Rational::from_int(child_index)
  let one = Rational::from_int(1)
  let slot_begin = cycle_start + i_rat / n_rat
  let slot_end = cycle_start + (i_rat + one) / n_rat
  let pat_begin = (query_intersect.begin - cycle_start) * n_rat - i_rat
  let pat_end = (query_intersect.end_ - cycle_start) * n_rat - i_rat
  let full_pat_arc = TimeSpan::new(
    (slot_begin - cycle_start) * n_rat - i_rat,
    (slot_end - cycle_start) * n_rat - i_rat,
  )
  let query_pat_arc = TimeSpan::new(pat_begin, pat_end)
  child
  .query(full_pat_arc)
  .filter_map(event => {
    let raw = event.event()
    raw.part
    .intersect(query_pat_arc)
    .map(part => {
      let mapped_part = TimeSpan::new(
        (part.begin + i_rat) / n_rat + cycle_start,
        (part.end_ + i_rat) / n_rat + cycle_start,
      )
      let mapped_whole = raw.whole.map(whole => {
        TimeSpan::new(
          (whole.begin + i_rat) / n_rat + cycle_start,
          (whole.end_ + i_rat) / n_rat + cycle_start,
        )
      })
      prepend_pattern_source(
        retime_pattern_snapshot_event(event, mapped_whole, mapped_part),
        id,
      )
    })
  })
}

///|
fn[A] query_sourced_sequence(
  children : Array[SourcedPat[A]],
  id : @identity.PatternNodeId,
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  let n = children.length()
  if n == 0 {
    return []
  }
  let n_rat = Rational::from_int(n)
  let one = Rational::from_int(1)
  let result : Array[PatternSnapshotEvent[A]] = []
  for cycle_arc in arc.whole_cycles() {
    let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
    for index in 0..<n {
      let i_rat = Rational::from_int(index)
      let slot_arc = TimeSpan::new(
        cycle_start + i_rat / n_rat,
        cycle_start + (i_rat + one) / n_rat,
      )
      if slot_arc.intersect(arc) is Some(query_intersect) {
        result.append(
          sourced_sequence_child_events(
            children[index],
            id,
            index,
            n,
            cycle_start,
            query_intersect,
          ),
        )
      }
    }
  }
  result
}

///|
fn[A] query_sourced_euclid(
  child : SourcedPat[A],
  id : @identity.PatternNodeId,
  arc : TimeSpan,
  k : Int,
  n : Int,
  rotation : Int,
) -> Array[PatternSnapshotEvent[A]] {
  if n <= 0 || k <= 0 {
    return []
  }
  let pattern = bjorklund(k, n)
  let r = (rotation % n + n) % n
  let n_rat = Rational::from_int(n)
  let one = Rational::from_int(1)
  let result : Array[PatternSnapshotEvent[A]] = []
  for cycle_arc in arc.whole_cycles() {
    let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
    for index in 0..<n {
      let pattern_index = (index + r) % n
      if pattern[pattern_index] {
        let i_rat = Rational::from_int(index)
        let slot_arc = TimeSpan::new(
          cycle_start + i_rat / n_rat,
          cycle_start + (i_rat + one) / n_rat,
        )
        if slot_arc.intersect(arc) is Some(query_intersect) {
          result.append(
            sourced_sequence_child_events(
              child, id, index, n, cycle_start, query_intersect,
            ),
          )
        }
      }
    }
  }
  result
}

///|
fn[A] query_opaque_pattern_source(
  pat : Pat[A],
  path : Array[@identity.PatternNodeId],
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  pat.query(arc).map(event => PatternSnapshotEvent(event~, pattern_nodes=path))
}

///|
/// A subtree has one compiled value with two views: playback and provenance.
/// Source paths are relative to this node; references prepend their use-site ID.
priv struct CompiledPattern[A] {
  pat : Pat[A]
  sourced : SourcedPat[A]
}

///|
fn[A] CompiledPattern::new(
  pat : Pat[A],
  query : (TimeSpan) -> Array[PatternSnapshotEvent[A]],
) -> CompiledPattern[A] {
  { pat, sourced: { query, }, }
}

///|
fn[A] lower_pattern_node_cached(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  cache : PatternLoweringCache[A],
  token_memo : Map[String, Array[Int64]],
) -> CompiledPattern[A] raise PatternDocError {
  let token = pattern_node_cache_token_memoized(nodes, id, token_memo)
  match cache.lookup(id, token) {
    Some(compiled) => compiled
    None => {
      let compiled = compile_pattern_node(nodes, id, cache, token_memo)
      cache.store(id, token, compiled)
      compiled
    }
  }
}

///|
fn[A] compile_pattern_node(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  cache : PatternLoweringCache[A],
  token_memo : Map[String, Array[Int64]],
) -> CompiledPattern[A] raise PatternDocError {
  let entry = match nodes.get(id.value()) {
    Some(entry) => entry
    None => raise MissingNode(id.value())
  }
  match entry.node {
    Reference(definition) => {
      // Node IDs are local to a document; only the dependency-keyed cache
      // crosses this scope, never the ID-keyed traversal memo.
      let target = lower_pattern_node_cached(
        definition.nodes,
        definition.root,
        cache,
        {},
      )
      CompiledPattern::new(target.pat, fn(arc) {
        target.sourced
        .query(arc)
        .map(event => prepend_pattern_source(event, id))
      })
    }
    Runtime(pat) => {
      let path = pattern_source_path(id)
      CompiledPattern::new(pat, fn(arc) {
        query_opaque_pattern_source(pat, path, arc)
      })
    }
    Silence => CompiledPattern::new(Pat::silence(), fn(_) { [] })
    Pure(value) => {
      let pat = Pat::pure(value)
      CompiledPattern::new(pat, fn(arc) {
        pat.query(arc).map(event => tag_pattern_event(event, id))
      })
    }
    Fast(child, factor) => {
      let child = lower_pattern_node_cached(nodes, child, cache, token_memo)
      CompiledPattern::new(child.pat.fast(factor), fn(arc) {
        query_sourced_fast(child.sourced, id, arc, factor)
      })
    }
    Slow(child, factor) => {
      let child = lower_pattern_node_cached(nodes, child, cache, token_memo)
      CompiledPattern::new(child.pat.slow(factor), fn(arc) {
        if factor.num <= 0L {
          []
        } else {
          query_sourced_fast(
            child.sourced,
            id,
            arc,
            Rational::new(1L, 1L) / factor,
          )
        }
      })
    }
    Rev(child) => {
      let child = lower_pattern_node_cached(nodes, child, cache, token_memo)
      CompiledPattern::new(child.pat.rev(), fn(arc) {
        query_sourced_rev(child.sourced, id, arc)
      })
    }
    FilterMap(child, f) => {
      let child = lower_pattern_node_cached(nodes, child, cache, token_memo)
      CompiledPattern::new(child.pat.filter_map(f), fn(arc) {
        child.sourced
        .query(arc)
        .filter_map(event => {
          let raw = event.event()
          f(raw.value).map(value => {
            prepend_pattern_source(
              PatternSnapshotEvent(
                event={ whole: raw.whole, part: raw.part, value, },
                pattern_nodes=event.pattern_nodes(),
              ),
              id,
            )
          })
        })
      })
    }
    Euclid(child, k, n, rotation) => {
      let child = lower_pattern_node_cached(nodes, child, cache, token_memo)
      CompiledPattern::new(child.pat.euclid(k, n, rotation~), fn(arc) {
        query_sourced_euclid(child.sourced, id, arc, k, n, rotation)
      })
    }
    DegradeBy(child, p, seed) => {
      let child = lower_pattern_node_cached(nodes, child, cache, token_memo)
      let prob = if p < 0.0 { 0.0 } else if p > 1.0 { 1.0 } else { p }
      CompiledPattern::new(child.pat.degrade_by(p, seed~), fn(arc) {
        if prob >= 1.0 {
          return []
        }
        child.sourced
        .query(arc)
        .filter(event => {
          let raw = event.event()
          let key = match raw.whole {
            Some(whole) => whole.begin
            None => raw.part.begin
          }
          prob <= 0.0 || hash_unit(key.num, key.den, seed) >= prob
        })
        .map(event => prepend_pattern_source(event, id))
      })
    }
    Every(child_id, n, f) => {
      let child = lower_pattern_node_cached(nodes, child_id, cache, token_memo)
      let fallback_path = pattern_source_path_for_opaque_children(nodes, id, [
        child_id,
      ])
      CompiledPattern::new(every(n, f, child.pat), fn(arc) {
        if n <= 0 {
          return child.sourced
            .query(arc)
            .map(event => prepend_pattern_source(event, id))
        }
        let n64 = Int64::from_int(n)
        arc
        .whole_cycles()
        .iter()
        .flat_map(cycle_arc => {
          let cycle_num = cycle_arc.begin.floor()
          let rem = (cycle_num % n64 + n64) % n64
          if rem == 0L {
            f(child.pat)
            .query(cycle_arc)
            .iter()
            .map(event => {
              PatternSnapshotEvent(event~, pattern_nodes=fallback_path)
            })
          } else {
            child.sourced
            .query(cycle_arc)
            .iter()
            .map(event => prepend_pattern_source(event, id))
          }
        })
        .collect()
      })
    }
    Jux(child_id, f) => {
      let child = lower_pattern_node_cached(nodes, child_id, cache, token_memo)
      let pat = f(child.pat)
      let path = pattern_source_path_for_opaque_children(nodes, id, [child_id])
      CompiledPattern::new(pat, fn(arc) {
        query_opaque_pattern_source(pat, path, arc)
      })
    }
    MergeControl(left_id, right_id, f) => {
      let left = lower_pattern_node_cached(nodes, left_id, cache, token_memo)
      let right = lower_pattern_node_cached(nodes, right_id, cache, token_memo)
      let pat = f(left.pat, right.pat)
      let path = pattern_source_path_for_opaque_children(nodes, id, [
        left_id, right_id,
      ])
      CompiledPattern::new(pat, fn(arc) {
        query_opaque_pattern_source(pat, path, arc)
      })
    }
    Sequence(children) => {
      let children = children.map(child => {
        lower_pattern_node_cached(nodes, child, cache, token_memo)
      })
      let pat = sequence(children.map(child => child.pat))
      let sourced = children.map(child => child.sourced)
      CompiledPattern::new(pat, fn(arc) {
        query_sourced_sequence(sourced, id, arc)
      })
    }
    Stack(children) => {
      let children = children.map(child => {
        lower_pattern_node_cached(nodes, child, cache, token_memo)
      })
      let pat = stack(children.map(child => child.pat))
      let sourced = children.map(child => child.sourced)
      CompiledPattern::new(pat, fn(arc) {
        sourced
        .iter()
        .flat_map(child => {
          child
          .query(arc)
          .iter()
          .map(event => prepend_pattern_source(event, id))
        })
        .collect()
      })
    }
  }
}

///|
priv struct PatternLoweringCacheEntry[A] {
  token : Array[Int64]
  compiled : CompiledPattern[A]
}

///|
/// Cache for compiled playback and provenance of pattern subtrees.
///
/// Entries are keyed by stable `PatternNodeId`, a recursive private subtree
/// token. The subtree token prevents stale hits
/// when callers rebuild unrelated docs or fork divergent edits from the same
/// base with identical stable IDs and revision counters. Every replacement gets
/// a fresh generation, and the token includes every dependency generation.
/// Revision is an editing API value; it adds no discrimination to this key.
pub struct PatternLoweringCache[A] {
  priv entries : Map[String, Array[PatternLoweringCacheEntry[A]]]
  priv mut hits : Int
  priv mut misses : Int
}

///|
pub fn[A] PatternLoweringCache::new() -> PatternLoweringCache[A] {
  { entries: {}, hits: 0, misses: 0, }
}

///|
fn[A] PatternLoweringCache::lookup(
  self : PatternLoweringCache[A],
  id : @identity.PatternNodeId,
  token : Array[Int64],
) -> CompiledPattern[A]? {
  match self.entries.get(id.value()) {
    None => {
      self.misses += 1
      None
    }
    Some(entries) => {
      for entry in entries {
        if pattern_cache_token_equal(entry.token, token) {
          self.hits += 1
          return Some(entry.compiled)
        }
      }
      self.misses += 1
      None
    }
  }
}

///|
/// Called only after a cache miss; the immutable dependency key is absent.
fn[A] PatternLoweringCache::store(
  self : PatternLoweringCache[A],
  id : @identity.PatternNodeId,
  token : Array[Int64],
  compiled : CompiledPattern[A],
) -> Unit {
  let key = id.value()
  match self.entries.get(key) {
    None => self.entries[key] = [{ token: token.copy(), compiled, }]
    Some(entries) => entries.push({ token: token.copy(), compiled, })
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
  priv sourced : SourcedPat[A]
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
pub fn[A] PatternSnapshot::query_sourced_events(
  self : PatternSnapshot[A],
  arc : TimeSpan,
) -> Array[PatternSnapshotEvent[A]] {
  self.sourced.query(arc)
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
/// `PatternDoc` participates in incr's backdate-aware acceptance
/// (`@incr.AcceptedDerived::accepted_memo`) through its `@identity.Revision`
/// content stamp. `PatternDoc` is not `Eq` (it carries closure fields), so it
/// qualifies via the revision identity rather than structural equality.
///
/// `changed_at` projects the revision's primary `value` into incr's 1-D
/// `Revision`. This projection is intentionally lossy (it drops the
/// `fingerprint`); it is NOT load-bearing because `backdate_equal` is
/// overridden below to drive the acceptance decision directly.
pub impl[A] @types.HasChangedAt for PatternDoc[A] with fn changed_at(self) -> @types.Revision {
  @types.Revision::{ value: self.revision.value().to_int(), }
}

///|
/// Override the default `backdate_equal` (which would compare only the lossy
/// 1-D `changed_at` projection): compare the full 2-D `@identity.Revision`
/// (`value` AND `fingerprint`) via its derived `Eq`, so two content-distinct
/// docs that happen to collide on `value` are still treated as changed. This
/// is the load-bearing acceptance predicate used by `accepted_memo`.
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
  { root, revision: pattern_node_revision(nodes, root), nodes, }
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
  let compiled = lower_pattern_node_cached(self.nodes, self.root, cache, {})
  {
    root: self.root,
    revision: self.revision,
    pat: compiled.pat,
    sourced: compiled.sourced,
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
  { root: self.root, revision: self.revision.next(), nodes, }
}

///|
pub fn[A] PatternDoc::replace_with_silence(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Silence)
  { root: self.root, revision: self.revision.next(), nodes, }
}

///|
pub fn[A] PatternDoc::replace_with_pure(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
  value~ : A,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  replace_pattern_node(nodes, id, Pure(value))
  { root: self.root, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
}

///|
pub fn[A] PatternDoc::rev(
  self : PatternDoc[A],
  id~ : @identity.PatternNodeId,
) -> PatternDoc[A] raise PatternDocError {
  let nodes = copy_pattern_nodes(self.nodes)
  insert_pattern_node(nodes, id, Rev(self.root), revision=self.revision.next())
  { root: id, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
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
  { root: id, revision: self.revision.next(), nodes, }
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
    MergeControl(left.root, right.root, merge_control),
    revision~,
  )
  { root: id, revision, nodes, }
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
  { root: id, revision, nodes, }
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
  { root: id, revision, nodes, }
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
  {
    root: id,
    revision: definition.revision,
    nodes: singleton_pattern_nodes(id, Reference(definition)),
  }
}

///|
/// Inspect the definition at a reference use site without losing its structure.
pub fn[A] PatternDoc::referenced_definition(
  self : PatternDoc[A],
  id : @identity.PatternNodeId,
) -> PatternDoc[A]? {
  match self.nodes.get(id.value()) {
    Some({ node: Reference(definition), .. }) => Some(definition)
    _ => None
  }
}
