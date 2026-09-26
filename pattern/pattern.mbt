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
/// A named scope anchors entry addresses; a material scope groups one clock.
/// Both prevent raw normalization from erasing their authored boundary.
priv enum EntryScope {
  Anonymous
  Named(String)
  Material
  NamedMaterial(String)
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
/// Map event payloads without changing query spans, period, scope, or origins.
/// Named composition changes contribute to content identity; plain projections
/// preserve it. Child bodies retain their corresponding transformed identity.
fn[A, B] Pat::map_payload(
  self : Pat[A],
  f : (A) -> B,
  change? : String = "",
) -> Pat[B] {
  let body : PatBody[B] = match self.body {
    Silence => Silence
    Opaque(children) =>
      Opaque(children.map(child => child.map_payload(f, change~)))
    Overlay(children) =>
      Overlay(children.map(child => child.map_payload(f, change~)))
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
    if change == "" {
      self.metadata.content
    } else {
      transformed_signature(self.metadata.content, change)
    },
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
pub fn[A] Pat::pure(value : A) -> Pat[A] {
  make_pat(
    fn(arc) {
      arc
      .whole_cycles()
      .filter_map(span => {
        // the whole event spans one full cycle: [floor(begin), floor(begin)+1)
        let cycle_n = span.begin.floor()
        let whole_begin = Rational::new(cycle_n, 1L)
        let whole_end = Rational::new(cycle_n + 1L, 1L)
        let whole = TimeSpan::new(whole_begin, whole_end)
        // part is the intersection of whole with the original query arc
        whole.intersect(arc).map(part => { whole: Some(whole), part, value, })
      })
    },
    Rational::from_int(1),
    Opaque([]),
    Anonymous,
    "",
  )
}

///|
pub fn[A] Pat::query(self : Pat[A], arc : TimeSpan) -> Array[Event[A]] {
  (self.query)(arc)
}

///|
/// WHY two-step time scaling: query the inner pattern in compressed time
/// (arc * factor), then scale returned events back (timestamps / factor).
/// The inner pattern "sees" time passing faster, but events are reported
/// in the caller's real-time frame. Both whole and part are scaled.
pub fn[A] Pat::fast(self : Pat[A], factor : Rational) -> Pat[A] {
  guard factor.num > 0L else { return Pat::silence() }
  guard !(self.body is Silence) else {
    return make_pat(
      self.query,
      self.metadata.period / factor,
      Silence,
      self.metadata.scope,
      self.metadata.content,
    )
  }
  let inner = self
  let children = self.transform_children(p => p.fast(factor))
  make_pat(
    fn(arc) {
      // Scale the query arc forward in time by factor (compress)
      let scaled_begin = arc.begin * factor
      let scaled_end = arc.end_ * factor
      let scaled_arc = TimeSpan::new(scaled_begin, scaled_end)
      let inv = Rational::new(1L, 1L) / factor
      // Scale the returned events back by 1/factor
      inner
      .query(scaled_arc)
      .map(ev => {
        let new_part = TimeSpan::new(ev.part.begin * inv, ev.part.end_ * inv)
        let new_whole = ev.whole.map(w => {
          TimeSpan::new(w.begin * inv, w.end_ * inv)
        })
        { whole: new_whole, part: new_part, value: ev.value, }
      })
    },
    self.metadata.period / factor,
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
  let inv = Rational::new(1L, 1L) / factor
  self.fast(inv)
}

///|
pub fn[A] Pat::rev(self : Pat[A]) -> Pat[A] {
  guard !(self.body is Silence) else { return self }
  let inner = self
  let children = self.transform_children(p => p.rev())
  make_pat(
    fn(arc) {
      let one = Rational::from_int(1)
      arc
      .whole_cycles()
      .iter()
      .flat_map(cycle_arc => {
        // Determine the full cycle boundaries from cycle_arc.begin
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        let cycle_end = cycle_start + one
        // Mirror the query sub-arc within the cycle:
        // [begin, end) -> [cycle_end - end, cycle_end - begin)
        let mirror_arc = TimeSpan::new(
          cycle_end - cycle_arc.end_,
          cycle_end - cycle_arc.begin,
        )
        inner
        .query(mirror_arc)
        .iter()
        .map(ev => {
          // Mirror part back
          let new_part = TimeSpan::new(
            cycle_end - ev.part.end_,
            cycle_end - ev.part.begin,
          )
          let new_whole = ev.whole.map(w => {
            TimeSpan::new(cycle_end - w.end_, cycle_end - w.begin)
          })
          { whole: new_whole, part: new_part, value: ev.value, }
        })
      })
      .collect()
    },
    self.metadata.period,
    Opaque(children),
    self.metadata.scope,
    transformed_signature(self.entry_signature(), "rev"),
  )
}
