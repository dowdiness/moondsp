///|
/// PROTOTYPE: automatic control buses.
///
/// A sounding voice follows a control by reading a bus, instead of the
/// scheduler re-matching each block's event fragments to voices. Lowering
/// derives one bus per `MergeControl` occurrence and control key: the control
/// with every enclosing time transform applied, so it is in root time. Each
/// event records which bus each control key reads.
///
/// A bus exists in two forms. `BusSignal` is the playback form: a tree of
/// time maps evaluated at one exact time without allocating. The query form
/// (`Pat[ControlMap]`) is kept only to check the signal against the pattern
/// semantics it must reproduce.
pub struct BusVoice {
  controls : ControlMap
  /// `(key, bus)` pairs. The outermost `MergeControl` for a key wins, the same
  /// order as `ControlMap::merge`.
  bindings : Array[(String, Int)]
}

///|
pub fn BusVoice::controls(self : BusVoice) -> ControlMap {
  self.controls
}

///|
pub fn BusVoice::bus_for(self : BusVoice, key : String) -> Int? {
  for binding in self.bindings {
    if binding.0 == key {
      return Some(binding.1)
    }
  }
  None
}

///|
/// Replace the controls after `filter_map`. A key whose value the map changed
/// or removed no longer follows its bus: the bus would undo the mapping.
fn BusVoice::with_controls(self : BusVoice, controls : ControlMap) -> BusVoice {
  {
    controls,
    bindings: self.bindings.filter(binding => {
      controls.get(binding.0) == self.controls.get(binding.0)
    }),
  }
}

///|
fn BusVoice::bind(
  self : BusVoice,
  controls : ControlMap,
  keys : ControlMap,
  bus_of : Map[String, Int],
) -> BusVoice {
  let bindings = self.bindings.filter(binding => keys.get(binding.0) is None)
  keys.each((key, _) => {
    if bus_of.get(key) is Some(bus) {
      bindings.push((key, bus))
    }
  })
  { controls, bindings }
}

///|
fn BusVoice::unbind(
  self : BusVoice,
  controls : ControlMap,
  keys : ControlMap,
) -> BusVoice {
  {
    controls,
    bindings: self.bindings.filter(binding => keys.get(binding.0) is None),
  }
}

///|
/// A control as a function of exact time. `NaN` means "no value here".
priv enum BusSignal {
  Const(Double)
  Continuous((Double) -> Double)
  /// Local time = time × num / den.
  Fast(Int64, Int64, BusSignal)
  /// Mirror each cycle.
  Rev(BusSignal)
  /// Equal slots; each child sees its own [0, 1).
  Sequence(Array[BusSignal])
  /// Weighted slots; `bounds` holds the n + 1 cumulative weights.
  Weighted(Array[BusSignal], Array[Int64])
  /// `(n, plain, transformed)`: cycles ≡ 0 mod n read `transformed`.
  Every(Int64, BusSignal, BusSignal)
  /// The last child with a value wins, like the merge fold.
  Stack(Array[BusSignal])
  /// Right-hand values override left where the left has an event.
  Merge(BusSignal, BusSignal)
}

///|
priv suberror BusSignalError {
  Unsupported(String)
}

///|
fn bus_gcd(a : Int64, b : Int64) -> Int64 {
  let mut x = a.abs()
  let mut y = b.abs()
  while y != 0L {
    let t = y
    y = x % y
    x = t
  }
  x
}

///|
/// The floor of `num / den`. With `left`, the limit from below: an exact
/// integer belongs to the previous unit, because a sample at `t` stands for
/// `[t, t + ε)` and mirroring turns that into `(t' - ε, t']`.
fn bus_floor(num : Int64, den : Int64, left : Bool) -> Int64 {
  let q = num / den
  let r = num % den
  let q = if r < 0L { q - 1L } else { q }
  if left && r == 0L {
    q - 1L
  } else {
    q
  }
}

///|
fn BusSignal::eval(
  self : BusSignal,
  num : Int64,
  den : Int64,
  left : Bool,
) -> Double {
  match self {
    Const(value) => value
    Continuous(f) => f(num.to_double() / den.to_double())
    Fast(fnum, fden, child) => {
      // A non-positive factor silences the pattern (`Pat::fast`/`slow`), so
      // the bus has no value; it must not divide by a zero denominator.
      guard fnum > 0L && fden > 0L else { return @double.not_a_number }
      let n = num * fnum
      let d = den * fden
      let g = bus_gcd(n, d)
      let g = if g == 0L { 1L } else { g }
      child.eval(n / g, d / g, left)
    }
    Rev(child) => {
      let cycle = bus_floor(num, den, left)
      child.eval((cycle + 1L) * den - num, den, !left)
    }
    Sequence(children) => {
      let n = Int64::from_int(children.length())
      let cycle = bus_floor(num, den, left)
      let pos = (num - cycle * den) * n
      let slot = bus_floor(pos, den, left)
      children[slot.to_int()].eval(pos - slot * den, den, left)
    }
    Weighted(children, bounds) => {
      let total = bounds[bounds.length() - 1]
      let cycle = bus_floor(num, den, left)
      let pos = (num - cycle * den) * total
      let mut slot = 0
      while slot + 1 < children.length() &&
            (if left {
              bounds[slot + 1] * den < pos
            } else {
              bounds[slot + 1] * den <= pos
            }) {
        slot += 1
      }
      let width = bounds[slot + 1] - bounds[slot]
      children[slot].eval(pos - bounds[slot] * den, den * width, left)
    }
    Every(n, plain, transformed) => {
      let cycle = bus_floor(num, den, left)
      if (cycle % n + n) % n == 0L {
        transformed.eval(num, den, left)
      } else {
        plain.eval(num, den, left)
      }
    }
    Stack(children) => {
      let mut value = @double.not_a_number
      for child in children {
        let v = child.eval(num, den, left)
        if !v.is_nan() {
          value = v
        }
      }
      value
    }
    Merge(left_signal, right_signal) => {
      let base = left_signal.eval(num, den, left)
      if base.is_nan() {
        base
      } else {
        let over = right_signal.eval(num, den, left)
        if over.is_nan() {
          base
        } else {
          over
        }
      }
    }
  }
}

///|
fn BusSignal::transformed(
  self : BusSignal,
  transform : TimeTransform,
) -> BusSignal {
  match transform {
    Fast(factor) => Fast(factor.num, factor.den, self)
    Slow(factor) => Fast(factor.den, factor.num, self)
    Reverse => Rev(self)
  }
}

///|
fn euclid_slots(
  k : Int,
  n : Int,
  rotation : Int,
  hit : BusSignal,
) -> BusSignal {
  if n <= 0 || k <= 0 {
    return Const(@double.not_a_number)
  }
  let pattern = bjorklund(k, n)
  let r = (rotation % n + n) % n
  Sequence(
    Array::makei(n, i => {
      if pattern[(i + r) % n] {
        hit
      } else {
        Const(@double.not_a_number)
      }
    }),
  )
}

///|
fn slot_signals(count : Int, index : Int, hit : BusSignal) -> Array[BusSignal] {
  Array::makei(count, i => {
    if i == index {
      hit
    } else {
      Const(@double.not_a_number)
    }
  })
}

///|
fn weight_bounds(weights : Array[Int]) -> Array[Int64] {
  let bounds = [0L]
  for weight in weights {
    bounds.push(bounds[bounds.length() - 1] + Int64::from_int(weight))
  }
  bounds
}

///|
/// Fold an opaque atom to a constant when it is the same pure value in every
/// probed cycle. Anything else cannot become a signal.
fn constant_controls(pat : Pat[ControlMap]) -> ControlMap? {
  let mut value : ControlMap? = None
  for cycle in 0..<4 {
    let begin = Rational::from_int(cycle)
    let whole = TimeSpan(begin, begin + Rational::from_int(1))
    let events = pat.query(whole)
    guard events.length() == 1 &&
      events[0].whole is Some(w) &&
      w == whole &&
      events[0].part == whole else {
      return None
    }
    match value {
      None => value = Some(events[0].value)
      Some(first) =>
        if first.entries() != events[0].value.entries() {
          return None
        }
    }
  }
  value
}

///|
fn control_keys(
  nodes : Map[String, PatternDocEntry[ControlMap]],
  id : @identity.PatternNodeId,
  keys : Array[String],
) -> Unit raise {
  guard nodes.get(id.value()) is Some(entry) else {
    raise PatternDocError::MissingNode(id.value())
  }
  fn add(key : String) {
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  match entry.node {
    Reference(definition, _) =>
      control_keys(definition.nodes, definition.root, keys)
    Continuous(_, key, _) => add(key)
    Pure(value) => value.each((key, _) => add(key))
    Runtime(pat) | Atom(pat, _, _) =>
      match constant_controls(pat) {
        Some(value) => value.each((key, _) => add(key))
        None => raise Unsupported("opaque control pattern \{id.value()}")
      }
    Silence => ()
    Fast(child, _)
    | Slow(child, _)
    | Rev(child)
    | Euclid(child, _, _, _)
    | Every(child, _, _)
    | Gate(child, _)
    | DegradeBy(child, _, _)
    | FilterMap(child, _)
    | Jux(child, _, _) => control_keys(nodes, child, keys)
    MergeControl(left, right, _) => {
      control_keys(nodes, left, keys)
      control_keys(nodes, right, keys)
    }
    Sequence(children) | Stack(children) | WeightedSequence(children, _) =>
      for child in children {
        control_keys(nodes, child, keys)
      }
  }
}

///|
/// Compile one key of a control-provider subtree into its signal.
fn compile_signal(
  nodes : Map[String, PatternDocEntry[ControlMap]],
  id : @identity.PatternNodeId,
  key : String,
) -> BusSignal raise {
  guard nodes.get(id.value()) is Some(entry) else {
    raise PatternDocError::MissingNode(id.value())
  }
  fn sub(child : @identity.PatternNodeId) -> BusSignal raise {
    compile_signal(nodes, child, key)
  }
  let none = @double.not_a_number
  match entry.node {
    Reference(definition, _) =>
      compile_signal(definition.nodes, definition.root, key)
    Continuous(_, k, f) => if k == key { Continuous(f) } else { Const(none) }
    Pure(value) => Const(value.get(key).unwrap_or(none))
    Runtime(pat) | Atom(pat, _, _) =>
      match constant_controls(pat) {
        Some(value) => Const(value.get(key).unwrap_or(none))
        None => raise Unsupported("opaque control pattern \{id.value()}")
      }
    Silence => Const(none)
    Fast(child, factor) => Fast(factor.num, factor.den, sub(child))
    Slow(child, factor) => Fast(factor.den, factor.num, sub(child))
    Rev(child) => Rev(sub(child))
    Euclid(child, k, n, rotation) => euclid_slots(k, n, rotation, sub(child))
    Every(child, n, transform) => {
      let plain = sub(child)
      if n <= 0 {
        plain
      } else {
        Every(Int64::from_int(n), plain, plain.transformed(transform))
      }
    }
    Sequence(children) => Sequence(children.map(sub))
    WeightedSequence(children, weights) =>
      Weighted(children.map(sub), weight_bounds(weights))
    Stack(children) => Stack(children.map(sub))
    MergeControl(left, right, _) => Merge(sub(left), sub(right))
    Gate(_, _) | DegradeBy(_, _, _) | FilterMap(_, _) | Jux(_, _, _) =>
      raise Unsupported("event selection inside a control \{id.value()}")
  }
}

///|
pub struct ControlBusSnapshot {
  priv pat : Pat[BusVoice]
  priv signals : Array[BusSignal]
  priv queries : Array[(Pat[ControlMap], String)]
}

///|
pub fn ControlBusSnapshot::query(
  self : ControlBusSnapshot,
  arc : TimeSpan,
) -> Array[Event[BusVoice]] {
  self.pat.query(arc)
}

///|
pub fn ControlBusSnapshot::bus_count(self : ControlBusSnapshot) -> Int {
  self.signals.length()
}

///|
/// Playback form: the bus value at exact time `at`. Allocation-free.
pub fn ControlBusSnapshot::bus_value(
  self : ControlBusSnapshot,
  bus : Int,
  at : Rational,
) -> Double {
  self.signals[bus].eval(at.num, at.den, false)
}

///|
/// Evaluate every bus once for a block into a caller-owned array.
pub fn ControlBusSnapshot::evaluate_all(
  self : ControlBusSnapshot,
  at : Rational,
  out : Array[Double],
) -> Unit {
  for bus in 0..<self.signals.length() {
    out[bus] = self.signals[bus].eval(at.num, at.den, false)
  }
}

///|
/// Reference form: query the bus pattern over `arc` and take the value at
/// `arc.begin`. Allocates; used only to check `bus_value`.
pub fn ControlBusSnapshot::query_bus_value(
  self : ControlBusSnapshot,
  bus : Int,
  arc : TimeSpan,
) -> Double? {
  let (pat, key) = self.queries[bus]
  let mut value = None
  for event in pat.query(arc) {
    if event.part.contains(arc.begin) {
      value = event.value.get(key)
    }
  }
  value
}

///|
priv struct BusTables {
  signals : Array[BusSignal]
  queries : Array[(Pat[ControlMap], String)]
  controls : CompiledCache[ControlMap, Unit]
}

///|
pub fn PatternDoc::lower_with_buses(
  self : PatternDoc[ControlMap],
) -> ControlBusSnapshot raise {
  let tables = { signals: [], queries: [], controls: CompiledCache::new() }
  let pat = lower_bus_node(self.nodes, self.root, p => p, s => s, tables)
  { pat, signals: tables.signals, queries: tables.queries }
}

///|
/// `to_root` and `to_root_signal` map this node's local time to root time,
/// for the query form and the signal form of a bus.
fn lower_bus_node(
  nodes : Map[String, PatternDocEntry[ControlMap]],
  id : @identity.PatternNodeId,
  to_root : (Pat[ControlMap]) -> Pat[ControlMap],
  to_root_signal : (BusSignal) -> BusSignal,
  tables : BusTables,
) -> Pat[BusVoice] raise {
  guard nodes.get(id.value()) is Some(entry) else {
    raise PatternDocError::MissingNode(id.value())
  }
  fn lower(
    child : @identity.PatternNodeId,
    to_root : (Pat[ControlMap]) -> Pat[ControlMap],
    to_root_signal : (BusSignal) -> BusSignal,
  ) -> Pat[BusVoice] raise {
    lower_bus_node(nodes, child, to_root, to_root_signal, tables)
  }
  fn unbound(pat : Pat[ControlMap]) -> Pat[BusVoice] {
    pat.map_payload(controls => { controls, bindings: [] })
  }
  match entry.node {
    Reference(definition, _) =>
      lower_bus_node(
        definition.nodes,
        definition.root,
        to_root,
        to_root_signal,
        tables,
      )
    Runtime(pat) | Atom(pat, _, _) | Continuous(pat, _, _) => unbound(pat)
    Silence => Pat::silence()
    Pure(value) => Pat::pure({ controls: value, bindings: [] })
    // Time transforms: the bus gets the same transform.
    Fast(child, factor) =>
      lower(child, p => to_root(p.fast(factor)), s => {
        to_root_signal(Fast(factor.num, factor.den, s))
      }).fast(factor)
    Slow(child, factor) =>
      lower(child, p => to_root(p.slow(factor)), s => {
        to_root_signal(Fast(factor.den, factor.num, s))
      }).slow(factor)
    Rev(child) =>
      lower(child, p => to_root(p.rev()), s => to_root_signal(Rev(s))).rev()
    Euclid(child, k, n, rotation) =>
      lower(child, p => to_root(p.euclid(k, n, rotation~)), s => {
        to_root_signal(euclid_slots(k, n, rotation, s))
      }).euclid(k, n, rotation~)
    Every(child, n, transform) => {
      let apply = (p : Pat[ControlMap]) => transform.apply(p)
      every(
        n,
        p => transform.apply(p),
        lower(child, p => to_root(every(n, apply, p)), s => {
          if n <= 0 {
            to_root_signal(s)
          } else {
            to_root_signal(
              Every(Int64::from_int(n), s, s.transformed(transform)),
            )
          }
        }),
      )
    }
    // Event selection: the bus keeps flowing; only voices are dropped. A
    // filter_map that rewrites a bound value unbinds that key.
    Gate(child, factor) => lower(child, to_root, to_root_signal).gate(factor)
    DegradeBy(child, p, seed) =>
      lower(child, to_root, to_root_signal).degrade_by(p, seed~)
    FilterMap(child, f) =>
      lower(child, to_root, to_root_signal).filter_map_payload(
        voice => f(voice.controls).map(c => voice.with_controls(c)),
        "",
      )
    // Time partition: the bus is silent outside this child's slot.
    Sequence(children) => {
      let count = children.length()
      sequence(
        children.mapi((index, child) => {
          lower(
            child,
            p => to_root(sequence(slot_only(count, index, p))),
            s => to_root_signal(Sequence(slot_signals(count, index, s))),
          )
        }),
      )
    }
    WeightedSequence(children, weights) => {
      let count = children.length()
      let bounds = weight_bounds(weights)
      sequence_weighted(
        children.mapi((index, child) => {
          lower(
            child,
            p => to_root(
              sequence_weighted(slot_only(count, index, p), weights),
            ),
            s => to_root_signal(Weighted(slot_signals(count, index, s), bounds)),
          )
        }),
        weights,
      )
    }
    Stack(children) =>
      stack(children.map(child => lower(child, to_root, to_root_signal)))
    // Simultaneous branches with different transforms: one bus per branch.
    Jux(child, transform, merge) => {
      let pan = (voice : BusVoice, c : ControlMap) => {
        voice.unbind(merge(voice.controls, c), c)
      }
      let left = merge_control_kernel(
        lower(child, to_root, to_root_signal),
        s_pan(-1.0),
        pan,
      )
      let right = merge_control_kernel(
        transform.apply(
          lower(child, p => to_root(transform.apply(p)), s => {
            to_root_signal(s.transformed(transform))
          }),
        ),
        s_pan(1.0),
        pan,
      )
      stack([left, right])
    }
    MergeControl(left, right, merge) => {
      let control = lower_pattern_node_cached(
        nodes,
        right,
        tables.controls,
        tables.controls,
        {},
        End,
      ).pat.map_payload(erase_value)
      let keys = []
      control_keys(nodes, right, keys)
      let bus_of : Map[String, Int] = Map([])
      let query = to_root(control)
      for key in keys {
        bus_of[key] = tables.signals.length()
        tables.signals.push(to_root_signal(compile_signal(nodes, right, key)))
        tables.queries.push((query, key))
      }
      merge_control_kernel(
        lower(left, to_root, to_root_signal),
        control,
        (voice, c) => voice.bind(merge(voice.controls, c), c, bus_of),
      )
    }
  }
}

///|
fn slot_only(
  count : Int,
  index : Int,
  pat : Pat[ControlMap],
) -> Array[Pat[ControlMap]] {
  Array::makei(count, i => if i == index { pat } else { Pat::silence() })
}
