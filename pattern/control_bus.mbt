///|
/// Automatic control buses (ADR-0019).
///
/// A sounding voice follows a control by reading a bus, instead of the
/// scheduler re-matching each block's event fragments to voices. Lowering
/// derives one bus per `MergeControl` occurrence and control key: the control
/// with every enclosing time transform applied, so it is in root time. Each
/// event records which bus each control key reads.
///
/// An event's payload holds only its own values: lowering never writes a bus
/// value into it. A bound key reads its bus nested over its own value by the
/// key's `Control::nesting`, so the event's own value is the innermost
/// occurrence of that key. Bus values enter a payload only where controls
/// leave lowering (`project_controls`).
///
/// Compiled subtrees keep their buses in their own local time, and every
/// enclosing node wraps them with its transform, so the lowering cache can
/// share a subtree's buses wherever the subtree is reused.

///|
/// An outer value over an inner one by `nesting`. Where the outer has no
/// value, the inner applies alone.
fn nested_value(
  nesting : @control.Nesting,
  inner : @control.ControlValue,
  outer : @control.ControlValue,
) -> @control.ControlValue {
  match nesting {
    Override => outer.or_else(inner)
    Multiply => inner.times(outer)
  }
}

///|
/// `nested_value` as a signal: an outer signal over an inner one.
fn nested_signal(
  nesting : @control.Nesting,
  inner : BusSignal,
  outer : BusSignal,
) -> BusSignal {
  match nesting {
    Override => Stack([inner, outer])
    Multiply => Product(inner, outer)
  }
}

///|
/// The bus one control key reads. Shared and never mutated.
priv struct BusBinding {
  key : @control.Control
  bus : Int32
}

///|
/// The signal this key reads: its bus over the event's own value, if any.
fn BusBinding::signal(
  self : BusBinding,
  own : ControlMap,
  bus : BusSignal,
) -> BusSignal {
  match own.get(self.key) {
    Some(value) =>
      nested_signal(self.key.nesting(), BusSignal::of_value(value), bus)
    None => bus
  }
}

///|
/// `signal` at exact time `num / den`, without building it.
fn BusBinding::eval(
  self : BusBinding,
  own : ControlMap,
  bus : BusSignal,
  num : Int64,
  den : Int64,
) -> @control.ControlValue {
  let outer = bus.eval(num, den, false)
  match own.get(self.key) {
    Some(value) =>
      nested_value(self.key.nesting(), @control.ControlValue::of(value), outer)
    None => outer
  }
}

///|
let no_bus_bindings : FixedArray[BusBinding] = []

///|
fn bus_binding_for(
  bindings : FixedArray[BusBinding],
  key : @control.Control,
) -> BusBinding? {
  for binding in bindings {
    if binding.key == key {
      return Some(binding)
    }
  }
  None
}

///|
/// One bus of a compiled subtree: the signal one `MergeControl` gives `key`,
/// and how that merge reads and writes the payload's controls.
priv struct ControlBus {
  key : @control.Control
  signal : BusSignal
}

///|
fn ControlBus::map_signal(
  self : ControlBus,
  f : (BusSignal) -> BusSignal,
) -> ControlBus {
  { ..self, signal: f(self.signal), }
}

///|
/// Bind each `(key, bus)` of `provided`. A key already bound to an inner bus
/// moves to the bus in `chained` that combines with that inner bus by the
/// key's `Nesting`. The binding depends neither on time nor on the payload,
/// so a sounding voice keeps the right bus across rests and events of one
/// atom share their bindings.
fn bind_buses(
  bindings : FixedArray[BusBinding],
  provided : Array[(@control.Control, Int32)],
  chained : Map[Int32, Int32],
) -> FixedArray[BusBinding] {
  let fresh = provided.filter(pair => bus_binding_for(bindings, pair.0) is None)
  let inner = bindings.length()
  FixedArray::makei(inner + fresh.length(), i => {
    if i < inner {
      let binding = bindings[i]
      match chained.get(binding.bus) {
        Some(bus) => { ..binding, bus, }
        None => binding
      }
    } else {
      let (key, bus) = fresh[i - inner]
      { key, bus, }
    }
  })
}

///|
/// Drop the bindings of the keys `keys` sets to fixed values (`jux` pan).
fn unbind_keys(
  bindings : FixedArray[BusBinding],
  keys : ControlMap,
) -> FixedArray[BusBinding] {
  let mut kept = 0
  for binding in bindings {
    if keys.get(binding.key) is None {
      kept += 1
    }
  }
  if kept == bindings.length() {
    return bindings
  }
  let result = FixedArray::make(kept, bindings[0])
  let mut next = 0
  for binding in bindings {
    if keys.get(binding.key) is None {
      result[next] = binding
      next += 1
    }
  }
  result
}

///|
/// `value` as controls leave lowering: each bound key takes its signal at
/// `time`. A key whose signal has no value there keeps the own value.
fn project_controls(
  value : ControlMap,
  bindings : FixedArray[BusBinding],
  buses : Array[ControlBus],
  time : Rational,
) -> ControlMap {
  guard bindings.length() > 0 else { return value }
  let values : Map[@control.Control, Double] = Map([])
  for binding in bindings {
    let v = binding.eval(value, buses[binding.bus].signal, time.num, time.den)
    if v.get() is Some(value) {
      values[binding.key] = value
    }
  }
  value.merge({ values, })
}

///|
fn shift_bus_bindings(
  bindings : FixedArray[BusBinding],
  offset : Int32,
) -> FixedArray[BusBinding] {
  if bindings.is_empty() {
    return bindings
  }
  FixedArray::makei(bindings.length(), i => {
    ..bindings[i],
    bus: bindings[i].bus + offset,
  })
}

///|
/// An event's controls as a voice reads them: its values at the onset, and
/// the buses its bound keys follow while it sounds, placed on the clock the
/// event is on. Only lowering pairs values with buses (`Controls::lowered`),
/// so the two always belong to the same event.
pub struct Controls {
  /// Projected at the onset, so a bound key already holds its bus value.
  priv values : ControlMap
  /// The event's own values, which its bound keys read under their buses.
  priv own : ControlMap
  priv table : Array[BusSignal]
  priv bindings : FixedArray[BusBinding]
  priv placement : Placement
}

///|
/// Controls that follow no bus: every key holds its value for the whole note.
pub fn Controls::fixed(values : ControlMap) -> Controls {
  {
    values,
    own: values,
    table: [],
    bindings: no_bus_bindings,
    placement: Placement(),
  }
}

///|
/// The controls of a lowered event whose own payload is `own`, projected at
/// `onset`.
fn Controls::lowered(
  own : ControlMap,
  bindings : FixedArray[BusBinding],
  buses : Array[ControlBus],
  table : Array[BusSignal],
  onset : Rational,
) -> Controls {
  if bindings.is_empty() {
    return Controls::fixed(own)
  }
  {
    values: project_controls(own, bindings, buses, onset),
    own,
    table,
    bindings,
    placement: Placement(),
  }
}

///|
/// The values at the onset, as the event's payload holds them.
pub fn Controls::values(self : Controls) -> ControlMap {
  self.values
}

///|
/// Follow the event when `placement` moves it, as `Event::placed` does.
pub fn Controls::placed(self : Controls, placement : Placement) -> Controls {
  if self.bindings.is_empty() {
    return self
  }
  { ..self, placement: self.placement.then(placement), }
}

///|
/// `signal` on this event's clock.
fn Controls::place(self : Controls, signal : BusSignal) -> BusSignal {
  let { origin, rate, } = self.placement
  let scaled : BusSignal = if rate == Rational::from_int(1) {
    signal
  } else {
    Fast(rate.num, rate.den, signal)
  }
  if origin.num == 0L {
    scaled
  } else {
    Shift(origin.num, origin.den, scaled)
  }
}

///|
/// The bus `key` follows, read at exact time `num / den` (`den > 0`) on this
/// event's clock. Reading allocates nothing. `None` when `key` follows no bus.
pub fn Controls::reader(
  self : Controls,
  key : @control.Control,
) -> ((Int64, Int64) -> @control.ControlValue)? {
  bus_binding_for(self.bindings, key).map(binding => {
    let placed = self.place(binding.signal(self.own, self.table[binding.bus]))
    (num, den) => placed.eval(num, den, false)
  })
}

///|
pub impl @control.ControlSource for Controls with fn value(self, key) {
  match self.values.get(key) {
    Some(value) => @control.ControlValue::of(value)
    None => @control.ControlValue::absent()
  }
}

///|
/// A constant bus has no reader: the onset value already holds.
pub impl @control.ControlSource for Controls with fn each_varying(self, f) {
  for binding in self.bindings {
    let signal = binding.signal(self.own, self.table[binding.bus])
    guard !signal.is_constant() else { continue }
    let placed = self.place(signal)
    f(binding.key, (num, den) => placed.eval(num, den, false))
  }
}

///|
/// A control as a function of exact time, with gaps (`Absent`).
priv enum BusSignal {
  /// No value anywhere.
  Absent
  /// The same value everywhere; never `NaN` (see `BusSignal::of_value`).
  Const(Double)
  /// A function of time; a `NaN` result counts as absent.
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
  /// The product where both have a value, else whichever has one: nested
  /// `gain` merges.
  Product(BusSignal, BusSignal)
  /// `(presence, left, right)`: right-hand values override left where the
  /// left has an event. `presence` is present exactly there, so a left
  /// event that does not set this key still takes the right-hand value.
  Merge(BusSignal, BusSignal, BusSignal)
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
) -> @control.ControlValue {
  match self {
    Absent => @control.ControlValue::absent()
    Const(value) => @control.ControlValue::of(value)
    Continuous(f) =>
      @control.ControlValue::of(f(num.to_double() / den.to_double()))
    Fast(fnum, fden, child) => {
      // A non-positive factor silences the pattern (`Pat::fast`/`slow`), so
      // the bus has no value; it must not divide by a zero denominator.
      guard fnum > 0L && fden > 0L else {
        return @control.ControlValue::absent()
      }
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
      let n = children.length().to_int64()
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
      let mut value = @control.ControlValue::absent()
      for child in children {
        value = child.eval(num, den, left).or_else(value)
      }
      value
    }
    Product(inner, outer) =>
      inner.eval(num, den, left).times(outer.eval(num, den, left))
    Merge(presence, left_signal, right_signal) => {
      if presence.eval(num, den, left).is_absent() {
        return @control.ControlValue::absent()
      }
      right_signal
      .eval(num, den, left)
      .or_else(left_signal.eval(num, den, left))
    }
  }
}

///|
fn BusSignal::is_constant(self : BusSignal) -> Bool {
  match self {
    Absent | Const(_) => true
    Fast(_, _, child) | Shift(_, _, child) | Rev(child) => child.is_constant()
    _ => false
  }
}

///|
fn BusSignal::of_value(value : Double) -> BusSignal {
  if @control.ControlValue::of(value).is_absent() {
    Absent
  } else {
    Const(value)
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
  k : Int32,
  n : Int32,
  rotation : Int32,
  hit : BusSignal,
) -> BusSignal {
  if n <= 0 || k <= 0 {
    return Absent
  }
  let pattern = bjorklund(k, n)
  let r = (rotation % n + n) % n
  Sequence(
    Array::makei(n, i => if pattern[(i + r) % n] { hit } else { Absent }),
  )
}

///|
fn slot_signals(
  count : Int32,
  index : Int32,
  hit : BusSignal,
) -> Array[BusSignal] {
  Array::makei(count, i => if i == index { hit } else { Absent })
}

///|
fn weight_bounds(weights : Array[Int32]) -> Array[Int64] {
  let bounds = [0L]
  for weight in weights {
    bounds.push(bounds[bounds.length() - 1] + weight.to_int64())
  }
  bounds
}

///|
/// Every key a control-provider subtree can set, in first-seen order.
fn[A : WithControls] control_keys(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  keys : Array[@control.Control],
) -> Unit raise PatternDocError {
  guard nodes.get(id.value()) is Some(entry) else {
    raise PatternDocError::MissingNode(id.value())
  }
  fn add(key : @control.Control) {
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  match entry.node {
    Reference(definition, _) =>
      control_keys(definition.nodes, definition.root, keys)
    Continuous(_, key, _) => add(key)
    Pure(value) | Atom(_, value, _) =>
      value.controls().each((key, _) => add(key))
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
    | Jux(child, _) => control_keys(nodes, child, keys)
    MergeControl(left, right) => {
      control_keys(nodes, left, keys)
      control_keys(right.nodes, right.root, keys)
    }
    Sequence(children) | Stack(children) | WeightedSequence(children, _) =>
      for child in children {
        control_keys(nodes, child, keys)
      }
  }
}

///|
/// Compile one key of a control-provider subtree into its signal. With
/// `key=None`, compile its presence instead: `0` wherever the subtree has an
/// event, whichever keys it sets, and `Absent` elsewhere.
fn[A : WithControls] compile_signal(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
  key : @control.Control?,
) -> BusSignal raise PatternDocError {
  guard nodes.get(id.value()) is Some(entry) else {
    raise PatternDocError::MissingNode(id.value())
  }
  fn sub(child : @identity.PatternNodeId) -> BusSignal raise PatternDocError {
    compile_signal(nodes, child, key)
  }
  match entry.node {
    Reference(definition, _) =>
      compile_signal(definition.nodes, definition.root, key)
    Continuous(_, k, f) =>
      match key {
        None => Const(0.0)
        Some(key) => if k == key { Continuous(f) } else { Absent }
      }
    Pure(value) | Atom(_, value, _) =>
      match key {
        None => Const(0.0)
        Some(key) =>
          match value.controls().get(key) {
            Some(v) => BusSignal::of_value(v)
            None => Absent
          }
      }
    Runtime(_) => raise UnsupportedControl(id)
    Silence => Absent
    Fast(child, factor) => Fast(factor.num, factor.den, sub(child))
    Slow(child, factor) => Fast(factor.den, factor.num, sub(child))
    Rev(child) => Rev(sub(child))
    Euclid(child, k, n, rotation) => euclid_slots(k, n, rotation, sub(child))
    Every(child, n, transform) => {
      let plain = sub(child)
      if n <= 0 {
        plain
      } else {
        Every(n.to_int64(), plain, plain.transformed(transform))
      }
    }
    Sequence(children) => Sequence(children.map(sub))
    WeightedSequence(children, weights) =>
      Weighted(children.map(sub), weight_bounds(weights))
    Stack(children) => Stack(children.map(sub))
    MergeControl(left, right) =>
      match key {
        None => sub(left)
        Some(key) => {
          let inner = sub(left)
          Merge(
            compile_signal(nodes, left, None),
            inner,
            nested_signal(
              key.nesting(),
              inner,
              compile_signal(right.nodes, right.root, Some(key)),
            ),
          )
        }
      }
    Gate(_, _) | DegradeBy(_, _, _) | FilterMap(_, _) | Jux(_, _) =>
      raise UnsupportedControl(id)
  }
}
