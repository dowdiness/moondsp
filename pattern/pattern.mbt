///|
/// A pattern query together with an explicit execution shape.
///
/// `Overlay` is reserved for the raw overlay constructor.  Every operation
/// that owns a query closure uses `Opaque`, even when it keeps authored child
/// projections for `entries()`.  This makes normalization structural instead
/// of guessing from a member array.
priv enum PatBody[A] {
  Silence
  Opaque(Array[Pat[A]])
  Overlay(Array[Pat[A]])
}

///|
/// Entry metadata is deliberately independent from the execution body.
///
/// A material groups one clock. An addressed material also carries its entry
/// address, which document lowering derives from node IDs. Both prevent raw
/// normalization from erasing their authored boundary.
priv enum EntryScope {
  Anonymous
  Material
  Addressed(String)
}

///|
priv struct PatMetadata {
  period : Rational
  scope : EntryScope
  content : String
}

///|
/// A musical-time query with authored entry metadata. An entry cycle does not
/// imply that event values repeat: transformations can vary between cycles.
pub struct Pat[A] {
  query : (TimeSpan) -> Array[Event[A]]
  priv body : PatBody[A]
  priv metadata : PatMetadata
}

///|
fn[A] make_pat(
  query : (TimeSpan) -> Array[Event[A]],
  period : Rational,
  body : PatBody[A],
  scope : EntryScope,
  content : String,
) -> Pat[A] {
  { query, body, metadata: { period, scope, content, }, }
}

///|
fn[A, B] Pat::transform_children(
  self : Pat[A],
  f : (Pat[A]) -> Pat[B],
) -> Array[Pat[B]] {
  match self.body {
    Silence => []
    Opaque(children) => children.map(f)
    Overlay(children) => children.map(f)
  }
}

///|
/// Map event payloads without changing query spans or authored metadata.
/// Child bodies are mapped recursively while preserving their shape.
fn[A, B] Pat::map_payload(self : Pat[A], f : (A) -> B) -> Pat[B] {
  let body : PatBody[B] = match self.body {
    Silence => Silence
    Opaque(children) => Opaque(children.map(child => child.map_payload(f)))
    Overlay(children) => Overlay(children.map(child => child.map_payload(f)))
  }
  make_pat(
    fn(arc) {
      self
      .query(arc)
      .map(ev => { whole: ev.whole, part: ev.part, value: f(ev.value), })
    },
    self.metadata.period,
    body,
    self.metadata.scope,
    self.metadata.content,
  )
}

///|
/// Construct a custom musical-time source with one-cycle entries. The query
/// must be deterministic for a given span. Use slow/fast to scale source time.
pub fn[A] Pat::from_query(query : (TimeSpan) -> Array[Event[A]]) -> Pat[A] {
  make_pat(query, Rational::from_int(1), Opaque([]), Anonymous, "")
}

///|
pub fn[A] Pat::silence() -> Pat[A] {
  make_pat(
    fn(_arc) { [] },
    Rational::from_int(1),
    Silence,
    Anonymous,
    "silence",
  )
}

///|
/// One `value` per cycle. `content` describes the value for playback
/// entries; equal content must mean an equal value. Without it, the content
/// is unknown, and no other pattern has the same content.
pub fn[A] Pat::pure(value : A, content~ : String = "") -> Pat[A] {
  make_pat(
    fn(arc) {
      arc
      .whole_cycles()
      .filter_map(span => {
        // the whole event spans one full cycle: [floor(begin), floor(begin)+1)
        let cycle_n = span.begin.floor()
        let whole_begin = Rational(cycle_n, 1L)
        let whole_end = Rational(cycle_n + 1L, 1L)
        let whole = TimeSpan(whole_begin, whole_end)
        // part is the intersection of whole with the original query arc
        whole.intersect(arc).map(part => { whole: Some(whole), part, value, })
      })
    },
    Rational::from_int(1),
    Opaque([]),
    Anonymous,
    content,
  )
}

///|
pub fn[A] Pat::query(self : Pat[A], arc : TimeSpan) -> Array[Event[A]] {
  (self.query)(arc)
}

///|
/// The inner pattern sees time `factor` times faster; its events come back on
/// the caller's clock (`TimeMap::Affine`).
pub fn[A] Pat::fast(self : Pat[A], factor : Rational) -> Pat[A] {
  guard TimeMap::scaled(factor) is Some(map) else { return Pat::silence() }
  guard !(self.body is Silence) else {
    return make_pat(
      self.query,
      map.period(self.metadata.period),
      Silence,
      self.metadata.scope,
      self.metadata.content,
    )
  }
  let inner = [self]
  let children = self.transform_children(p => p.fast(factor))
  make_pat(
    arc => map.query(inner, arc),
    map.period(self.metadata.period),
    Opaque(children),
    self.metadata.scope,
    transformed_signature(
      self.entry_signature(),
      "fast:\{factor.num}:\{factor.den}",
    ),
  )
}

///|
pub fn[A] Pat::slow(self : Pat[A], factor : Rational) -> Pat[A] {
  guard factor.num > 0L else { return Pat::silence() }
  let inv = Rational(1L, 1L) / factor
  self.fast(inv)
}

///|
pub fn[A] Pat::rev(self : Pat[A]) -> Pat[A] {
  guard !(self.body is Silence) else { return self }
  let inner = [self]
  let children = self.transform_children(p => p.rev())
  let map = TimeMap::MirrorCycles
  make_pat(
    arc => map.query(inner, arc),
    map.period(self.metadata.period),
    Opaque(children),
    self.metadata.scope,
    transformed_signature(self.entry_signature(), "rev"),
  )
}
