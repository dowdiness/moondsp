///|
/// Automatic control buses (ADR-0019).
///
/// A sounding voice follows a control by reading a bus, instead of the
/// scheduler re-matching each block's event fragments to voices. Lowering
/// derives one bus per `MergeControl` occurrence and control key: the control
/// with every enclosing time transform applied, so it is in root time. Each
/// event records which bus each control key reads.
///
/// Compiled subtrees keep their buses in their own local time, and every
/// enclosing node wraps them with its transform, so the lowering cache can
/// share a subtree's buses wherever the subtree is reused.

///|
/// `(key, bus)` pairs, shared and never mutated. The outermost `MergeControl`
/// for a key wins, the same order as `ControlMap::merge`.
let no_bus_bindings : FixedArray[(String, Int)] = []

///|
fn bus_binding_for(
  bindings : FixedArray[(String, Int)],
  key : String,
) -> Int? {
  for binding in bindings {
    if binding.0 == key {
      return Some(binding.1)
    }
  }
  None
}

///|
/// Keep the bindings `keys` does not override, then bind each key of `keys`
/// that has a bus in `bus_of`, so the outermost merge wins like
/// `ControlMap::merge`. One allocation; none when nothing changes.
fn rebind_buses(
  bindings : FixedArray[(String, Int)],
  keys : ControlMap,
  bus_of : Map[String, Int],
) -> FixedArray[(String, Int)] {
  let mut kept = 0
  for binding in bindings {
    if keys.get(binding.0) is None {
      kept += 1
    }
  }
  let mut bound = 0
  keys.each((key, _) => if bus_of.contains(key) { bound += 1 })
  if bound == 0 && kept == bindings.length() {
    return bindings
  }
  let result = FixedArray::make(kept + bound, ("", 0))
  let mut next = 0
  for binding in bindings {
    if keys.get(binding.0) is None {
      result[next] = binding
      next += 1
    }
  }
  keys.each((key, _) => {
    if bus_of.get(key) is Some(bus) {
      result[next] = (key, bus)
      next += 1
    }
  })
  result
}

///|
/// For a fixed value that overrides keys without binding them (`jux` pan).
let no_buses : Map[String, Int] = {}

///|
fn shift_bus_bindings(
  bindings : FixedArray[(String, Int)],
  offset : Int,
) -> FixedArray[(String, Int)] {
  if bindings.is_empty() {
    return bindings
  }
  FixedArray::makei(bindings.length(), i => {
    (bindings[i].0, bindings[i].1 + offset)
  })
}

///|
/// The buses one event's controls follow, placed on the clock the event is on:
/// the snapshot's local time is `(t - origin) × rate`.
pub struct EventBuses {
  priv table : Array[BusSignal]
  priv bindings : FixedArray[(String, Int)]
  priv origin : Rational
  priv rate : Rational
}

///|
let no_event_buses : EventBuses = {
  table: [],
  bindings: no_bus_bindings,
  origin: Rational::from_int(0),
  rate: Rational::from_int(1),
}

///|
/// For events that follow no bus.
pub fn EventBuses::none() -> EventBuses {
  no_event_buses
}

///|
fn EventBuses::in_snapshot(
  table : Array[BusSignal],
  bindings : FixedArray[(String, Int)],
) -> EventBuses {
  if bindings.is_empty() {
    return no_event_buses
  }
  { ..no_event_buses, table, bindings, }
}

///|
/// Follow the event when it is placed at `t / rate + origin`, the same
/// placement a caller applies to the event's spans.
pub fn EventBuses::placed(
  self : EventBuses,
  origin~ : Rational,
  rate? : Rational = Rational::from_int(1),
) -> EventBuses {
  if self.bindings.is_empty() {
    return self
  }
  { ..self, origin: origin + self.origin / rate, rate: rate * self.rate, }
}

///|
/// `signal` on this event's clock.
fn EventBuses::place(self : EventBuses, signal : BusSignal) -> BusSignal {
  let scaled : BusSignal = if self.rate == Rational::from_int(1) {
    signal
  } else {
    Fast(self.rate.num, self.rate.den, signal)
  }
  if self.origin == Rational::from_int(0) {
    scaled
  } else {
    Shift(self.origin.num, self.origin.den, scaled)
  }
}

///|
/// The bus `key` follows, read at exact time `num / den` (`den > 0`) on this
/// event's clock; `NaN` where the control has no value. Reading allocates
/// nothing. `None` when `key` follows no bus.
pub fn EventBuses::reader(
  self : EventBuses,
  key : String,
) -> ((Int64, Int64) -> Double)? {
  bus_binding_for(self.bindings, key).map(bus => {
    let placed = self.place(self.table[bus])
    (num, den) => placed.eval(num, den, false)
  })
}

///|
/// Visit each bound key whose bus changes over time, with its reader. A
/// constant bus needs no reader: the value set at note-on already holds.
pub fn EventBuses::each_reader(
  self : EventBuses,
  f : (String, (Int64, Int64) -> Double) -> Unit,
) -> Unit {
  for binding in self.bindings {
    let signal = self.table[binding.1]
    guard !signal.is_constant() else { continue }
    let placed = self.place(signal)
    f(binding.0, (num, den) => placed.eval(num, den, false))
  }
}

///|
/// A control as a function of exact time. `NaN` means "no value here".
priv enum BusSignal {
  Const(Double)
  Continuous((Double) -> Double)
  /// Local time = time × num / den.
  Fast(Int64, Int64, BusSignal)
  /// Local time = time − num / den.
  Shift(Int64, Int64, BusSignal)
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
    Shift(snum, sden, child) => {
      let n = num * sden - snum * den
      let d = den * sden
      let g = bus_gcd(n, d)
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
fn BusSignal::is_constant(self : BusSignal) -> Bool {
  match self {
    Const(_) => true
    Fast(_, _, child) | Shift(_, _, child) | Rev(child) => child.is_constant()
    _ => false
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
fn slot_signals(
  count : Int,
  index : Int,
  hit : BusSignal,
) -> Array[BusSignal] {
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
/// Every key a control-provider subtree can set, in first-seen order.
/// `controls_of` views the generic payload as the controls it carries.
fn[A] control_keys(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  controls_of : (A) -> ControlMap,
  keys : Array[String],
) -> Unit raise PatternDocError {
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
      control_keys(definition.nodes, definition.root, controls_of, keys)
    Continuous(_, key, _) => add(key)
    Pure(value) | Atom(_, value, _, _) =>
      controls_of(value).each((key, _) => add(key))
    Runtime(_) => raise UnsupportedControl(id)
    Silence => ()
    Fast(child, _)
    | Slow(child, _)
    | Rev(child)
    | Euclid(child, _, _, _)
    | Every(child, _, _)
    | Gate(child, _)
    | DegradeBy(child, _, _)
    | FilterMap(child, _)
    | Jux(child, _, _) => control_keys(nodes, child, controls_of, keys)
    MergeControl(left, right, _, _) => {
      control_keys(nodes, left, controls_of, keys)
      control_keys(nodes, right, controls_of, keys)
    }
    Sequence(children) | Stack(children) | WeightedSequence(children, _) =>
      for child in children {
        control_keys(nodes, child, controls_of, keys)
      }
  }
}

///|
/// Compile one key of a control-provider subtree into its signal.
fn[A] compile_signal(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  key : String,
  controls_of : (A) -> ControlMap,
) -> BusSignal raise PatternDocError {
  guard nodes.get(id.value()) is Some(entry) else {
    raise PatternDocError::MissingNode(id.value())
  }
  fn sub(child : @identity.PatternNodeId) -> BusSignal raise PatternDocError {
    compile_signal(nodes, child, key, controls_of)
  }
  let none = @double.not_a_number
  match entry.node {
    Reference(definition, _) =>
      compile_signal(definition.nodes, definition.root, key, controls_of)
    Continuous(_, k, f) => if k == key { Continuous(f) } else { Const(none) }
    Pure(value) | Atom(_, value, _, _) =>
      Const(controls_of(value).get(key).unwrap_or(none))
    Runtime(_) => raise UnsupportedControl(id)
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
    MergeControl(left, right, _, _) => Merge(sub(left), sub(right))
    Gate(_, _) | DegradeBy(_, _, _) | FilterMap(_, _) | Jux(_, _, _) =>
      raise UnsupportedControl(id)
  }
}
