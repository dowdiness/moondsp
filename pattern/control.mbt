///|
/// Numeric control map — the contract between Pattern and DSP engines.
/// Values are immutable to callers; entries() returns an owned copy.
#derive(Debug, Eq)
pub struct ControlMap {
  priv values : Map[@control.Control, Double]
}

///|
pub impl Show for ControlMap with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn ControlMap::empty() -> ControlMap {
  { values: Map([]), }
}

///|
pub fn ControlMap::single(key : @control.Control, value : Double) -> ControlMap {
  let m : Map[@control.Control, Double] = Map([])
  m[key] = value
  { values: m, }
}

///|
pub fn ControlMap::get(self : ControlMap, key : @control.Control) -> Double? {
  self.values.get(key)
}

///|
pub fn ControlMap::each(
  self : ControlMap,
  f : (@control.Control, Double) -> Unit,
) -> Unit {
  self.values.each(f)
}

///|
/// Return a fresh map snapshot of this control map.
pub fn ControlMap::entries(self : ControlMap) -> Map[@control.Control, Double] {
  let result : Map[@control.Control, Double] = Map([])
  self.values.each(fn(k, v) { result[k] = v })
  result
}

///|
/// Return a new control map with this value replaced; leave self unchanged.
pub fn ControlMap::set(
  self : ControlMap,
  key : @control.Control,
  value : Double,
) -> ControlMap {
  let result = self.entries()
  result[key] = value
  { values: result, }
}

///|
/// Return a new control map with the other values overriding self.
pub fn ControlMap::merge(self : ControlMap, other : ControlMap) -> ControlMap {
  let result = self.entries()
  other.values.each(fn(k, v) { result[k] = v })
  { values: result, }
}

///|
/// A continuous control: `key` is `f(t)` at the start of every queried part,
/// with no onsets. `f` must not allocate when it drives a control bus.
pub fn continuous(
  key : @control.Control,
  f : (Double) -> Double,
) -> Pat[ControlMap] {
  Pat::from_query(arc => {
    [
      {
        whole: None,
        part: arc,
        value: ControlMap::single(key, f(arc.begin.to_double())),
      },
    ]
  })
}

///|
pub fn s_lpf(frequency_hz : Double, resonance? : Double) -> Pat[ControlMap] {
  let cutoff = ControlMap::single(Lpf, frequency_hz)
  controls(
    match resonance {
      None => cutoff
      Some(q) => cutoff.set(LpfResonance, q)
    },
  )
}

///|
pub fn s_hpf(frequency_hz : Double, resonance? : Double) -> Pat[ControlMap] {
  let cutoff = ControlMap::single(Hpf, frequency_hz)
  controls(
    match resonance {
      None => cutoff
      Some(q) => cutoff.set(HpfResonance, q)
    },
  )
}

///|
pub fn s_gain(g : Double) -> Pat[ControlMap] {
  control(Gain, g)
}

///|
pub fn s_pan(p : Double) -> Pat[ControlMap] {
  control(Pan, p)
}

///|
/// Strudel-style stereo split. Plays `self` panned hard left and
/// `f(self)` panned hard right, both stacked. Pre-existing `pan`
/// values on the input are overridden by the ±1 outer pan (Strudel-
/// correct: `jux` sets pan unconditionally).
///
/// Doubles per-pool concurrency only when `f` causes same-sound
/// coincidence (e.g. `fast(2)` packs the right channel denser, or
/// `rev` over a single-sound layer like `hh*16` puts left's hh at
/// slot t and right's hh at slot 1-t). For sparse multi-sound
/// patterns like `s("bd sd hh sd").jux(rev)` the per-pool pressure
/// stays at 1.
/// Arbitrary callback content is unknown. Use TimeTransform for known operations.
pub fn[A : WithControls] Pat::jux(
  self : Pat[A],
  f : (Pat[A]) -> Pat[A],
) -> Pat[A] {
  self.jux_known(f, "")
}

///|
fn[A : WithControls] Pat::jux_known(
  self : Pat[A],
  f : (Pat[A]) -> Pat[A],
  signature : String,
) -> Pat[A] {
  jux_kernel(self, f, A::with_controls, signature)
}

///|
fn[A] jux_kernel(
  pat : Pat[A],
  f : (Pat[A]) -> Pat[A],
  merge : (A, ControlMap) -> A,
  signature : String,
) -> Pat[A] {
  if signature != "" && pat.body is Silence {
    return pat
  }
  let left = merge_control_kernel(pat, s_pan(-1.0), merge)
  let right = merge_control_kernel(f(pat), s_pan(1.0), merge)
  let combined = stack([left, right])
  make_pat(
    combined.query,
    pat.metadata.period,
    Opaque([]),
    pat.metadata.scope,
    transformed_signature(
      pat.entry_signature(),
      if signature == "" {
        ""
      } else {
        "jux:" + signature
      },
    ),
  )
}

///|
/// Merge overlapping right-hand payloads into each left-hand event (`jux`).
fn[A, B] merge_control_kernel(
  a : Pat[A],
  b : Pat[B],
  merge : (A, B) -> A,
) -> Pat[A] {
  if a.body is Silence {
    return a
  }
  let left = a
  let children = a.transform_children(p => merge_control_kernel(p, b, merge))
  make_pat(
    fn(arc) {
      let b_events = b.query(arc)
      left
      .query(arc)
      .map(ae => {
        let merged = b_events.fold(init=ae.value, (merged, be) => {
          // Sample the control at the fragment start, so the value does not
          // depend on how long the query arc is.
          if be.part.contains(ae.part.begin) {
            merge(merged, be.value)
          } else {
            merged
          }
        })
        { whole: ae.whole, part: ae.part, value: merged, }
      })
    },
    a.metadata.period,
    Opaque(children),
    a.metadata.scope,
    merged_signature(a, b.entry_signature()),
  )
}

///|
/// The content of `a` with controls whose content is `provider` merged in.
fn[A] merged_signature(a : Pat[A], provider : String) -> String {
  let change = if provider == "" { "" } else { "merge:" + provider }
  transformed_signature(a.entry_signature(), change)
}

///|
/// The shape and content of `merge_control_kernel(a, b, _)`, where `b` has
/// content `provider`, without querying `b`: `bind` maps each event of `a`.
/// Lowering uses this when buses supply the merged values.
fn[A] bind_control_kernel(
  a : Pat[A],
  provider : String,
  bind : (A) -> A,
) -> Pat[A] {
  if a.body is Silence {
    return a
  }
  let children = a.transform_children(p => {
    bind_control_kernel(p, provider, bind)
  })
  make_pat(
    fn(arc) {
      a
      .query(arc)
      .map(ae => { whole: ae.whole, part: ae.part, value: bind(ae.value), })
    },
    a.metadata.period,
    Opaque(children),
    a.metadata.scope,
    merged_signature(a, provider),
  )
}

///|
/// A scalar control source whose content is tracked automatically.
pub fn control(key : @control.Control, value : Double) -> Pat[ControlMap] {
  controls(ControlMap::single(key, value))
}

///|
/// A source carrying several controls on one event, whose content is tracked
/// automatically. Combine controls on one event here; nested controls that
/// follow their own timing belong to `PatternDoc::merge_control`.
pub fn controls(values : ControlMap) -> Pat[ControlMap] {
  let pat = Pat::pure(values)
  let parts : Array[String] = []
  values.values.each((key, value) => {
    let name = key.name()
    parts.push("control:\{name.length()}:\{name}:\{value}")
  })
  make_pat(
    pat.query,
    pat.metadata.period,
    pat.body,
    pat.metadata.scope,
    parts.join("+"),
  )
}

///|
/// Select events carrying a control; optionally require an exact value.
pub fn[A : WithControls] Pat::select_control(
  self : Pat[A],
  key : @control.Control,
  value? : Double,
) -> Pat[A] {
  select_control_kernel(self, A::controls, key, value)
}

///|
fn[A] select_control_kernel(
  pat : Pat[A],
  controls : (A) -> ControlMap,
  key : @control.Control,
  value : Double?,
) -> Pat[A] {
  let condition = match value {
    Some(v) => "equals:\{v}"
    None => "present"
  }
  pat.filter_map_payload(
    payload => {
      match controls(payload).get(key) {
        None => None
        Some(v) =>
          if value is Some(expected) && v != expected {
            None
          } else {
            Some(payload)
          }
      }
    },
    "select:\{key.name().length()}:\{key.name()}:" + condition,
  )
}

///|
/// A payload that carries controls. The document layer reads and writes an
/// event's controls through this trait (ADR-0022).
pub(open) trait WithControls {
  fn controls(Self) -> ControlMap
  /// The payload with `controls` set over its own.
  fn with_controls(Self, ControlMap) -> Self
}

///|
pub impl WithControls for ControlMap with fn controls(self) {
  self
}

///|
pub impl WithControls for ControlMap with fn with_controls(self, controls) {
  self.merge(controls)
}

///|
pub extend ControlMap with Debug::{to_repr}

///|
pub extend ControlMap with Show::{to_string, output}
