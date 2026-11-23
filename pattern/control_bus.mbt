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
/// and the authored signal the merge's provider compiles, when it is one.
priv struct ControlBus {
  key : @control.Control
  signal : BusSignal
  source : @identity.SourceAtomId?
}

///|
/// The authored signal a control-provider subtree compiles: the source of its
/// single continuous leaf, through time transforms and references.
fn[A] signal_source(
  nodes : Map[String, PatternDocEntry[A]],
  id : @identity.PatternNodeId,
) -> @identity.SourceAtomId? {
  guard nodes.get(id.value()) is Some(entry) else { return None }
  match entry.node {
    Continuous(_, _, _, source) => source
    Reference(definition, _) => signal_source(definition.nodes, definition.root)
    Fast(child, _) | Slow(child, _) | Rev(child) => signal_source(nodes, child)
    _ => None
  }
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
  /// The snapshot's buses, in root time.
  priv table : Array[ControlBus]
  priv bindings : FixedArray[BusBinding]
  priv placement : Placement
  /// The material's own clock onto this event's clock: set where playback
  /// dispatches it (`Controls::on_playback_clock`), then moved with it.
  priv material : Placement
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
    material: Placement(),
  }
}

///|
/// The controls of a lowered event whose own payload is `own`, projected at
/// `onset`.
fn Controls::lowered(
  own : ControlMap,
  bindings : FixedArray[BusBinding],
  buses : Array[ControlBus],
  onset : Rational,
) -> Controls {
  if bindings.is_empty() {
    return Controls::fixed(own)
  }
  {
    values: project_controls(own, bindings, buses, onset),
    own,
    table: buses,
    bindings,
    placement: Placement(),
    material: Placement(),
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
  {
    ..self,
    placement: self.placement.then(placement),
    material: self.material.then(placement),
  }
}

///|
/// Move the controls onto the playback clock of a material whose own clock
/// starts at `origin`, as playback moves the material's events.
pub fn Controls::on_playback_clock(
  self : Controls,
  origin : Rational,
) -> Controls {
  if self.bindings.is_empty() {
    return self
  }
  let material = Placement(origin~)
  { ..self, placement: self.placement.then(material), material, }
}

///|
/// Where the clock of the material that dispatched this event starts on the
/// event's clock: time `t` is material time `(t - material_origin) ×
/// material_rate`, for a song, song time.
pub fn Controls::material_origin(self : Controls) -> Rational {
  self.material.origin
}

///|
/// Material cycles per cycle of this event's clock; see `material_origin`.
pub fn Controls::material_rate(self : Controls) -> Rational {
  self.material.rate
}

///|
/// The authored signal the bus `key` follows, when it is one.
pub fn Controls::signal_source(
  self : Controls,
  key : @control.Control,
) -> @identity.SourceAtomId? {
  match bus_binding_for(self.bindings, key) {
    Some(binding) => self.table[binding.bus].source
    None => None
  }
}

///|
/// `signal` on this event's clock.
fn Controls::place(self : Controls, signal : BusSignal) -> BusSignal {
  place_signal(signal, self.placement)
}

///|
/// `signal` moved as `placement` moves events, as `Event::placed` does.
fn place_signal(signal : BusSignal, placement : Placement) -> BusSignal {
  if placement.is_identity() {
    signal
  } else {
    Mapped(placement.time_map(), [signal])
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
    let placed = self.place(
      binding.signal(self.own, self.table[binding.bus].signal),
    )
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
    let signal = binding.signal(self.own, self.table[binding.bus].signal)
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
  /// A time function `(cycles, before)`, as `PatternDoc::continuous` takes
  /// it, and the cycles after which it repeats, when it does. A `NaN` result
  /// counts as absent.
  Continuous((Double, Bool) -> Double, Rational?)
  /// `(f, delay)`: a one-shot time function of the time since its material
  /// entered, `f(t − delay, before)` (ADR-0025).
  Once((Double, Bool) -> Double, Double)
  /// Each piece of the map reads its child (one per slot) at the mapped
  /// time; a silent slot's child is `Absent`.
  Mapped(TimeMap, Array[BusSignal])
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
fn BusSignal::eval(
  self : BusSignal,
  num : Int64,
  den : Int64,
  left : Bool,
) -> @control.ControlValue {
  match self {
    Absent => @control.ControlValue::absent()
    Const(value) => @control.ControlValue::of(value)
    Continuous(f, _) =>
      @control.ControlValue::of(f(num.to_double() / den.to_double(), left))
    Once(f, delay) =>
      @control.ControlValue::of(
        f(num.to_double() / den.to_double() - delay, left),
      )
    Mapped(map, children) => {
      let cycle = map.cycle_at(num, den, left)
      let slot = map.slot_at(num, den, left, cycle)
      // child = (an / ad)·(num / den) + bn / bd, over one denominator.
      let an = map.scale_num()
      let ad = map.scale_den(slot)
      let bn = map.offset_num(cycle, slot)
      let bd = map.offset_den(slot)
      // `b` shares `a`'s denominator or has none, except for a placement
      // with both an origin and a rate.
      let (n, d) = if bd == 1L {
        (num * an + bn * den * ad, den * ad)
      } else if bd == ad {
        (num * an + bn * den, den * ad)
      } else {
        let common = gcd(ad, bd)
        (
          num * an * (bd / common) + bn * den * (ad / common),
          den * ad * (bd / common),
        )
      }
      // Reduce only when the denominator grew, so nested maps stay in range;
      // equal slots and integer factors keep it.
      let g = if d == den { 1L } else { gcd(n, d) }
      // A decreasing map turns a limit from below into one from above.
      children[slot].eval(n / g, d / g, if an < 0L { !left } else { left })
    }
    Every(n, plain, transformed) => {
      let cycle = time_floor(num, den, left)
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
/// The longest period `BusSignal::period` reports, in cycles.
const MAX_BUS_PERIOD : Int64 = 1024L

///|
/// Cycles after which the signal repeats: the least common multiple of its
/// parts' periods, which a time map turns into its own as it does a
/// pattern's (`TimeMap::period`). `None` when a time function declares no
/// period, for a one-shot signal, or when the period exceeds
/// `MAX_BUS_PERIOD` cycles.
fn BusSignal::period(self : BusSignal) -> Rational? {
  fn bounded(period : Rational) -> Rational? {
    if period > Rational(MAX_BUS_PERIOD, 1L) {
      None
    } else {
      Some(period)
    }
  }
  fn lcm(periods : Array[Rational?]) -> Rational? {
    let mut result = Rational::from_int(1)
    for period in periods {
      guard period is Some(p) && bounded(result.lcm(p)) is Some(next) else {
        return None
      }
      result = next
    }
    Some(result)
  }
  match self {
    Absent | Const(_) => Some(Rational::from_int(1))
    Continuous(_, period) => period
    Once(_, _) => None
    Mapped(map, children) =>
      lcm(children.map(child => child.period())).bind(period => {
        bounded(map.period(period))
      })
    Every(n, plain, transformed) =>
      lcm([Some(Rational(n, 1L)), plain.period(), transformed.period()])
    Stack(children) => lcm(children.map(child => child.period()))
    Product(inner, outer) => lcm([inner.period(), outer.period()])
    Merge(presence, left, right) =>
      lcm([presence.period(), left.period(), right.period()])
  }
}

///|
/// One control signal a provider gives a snapshot, in the snapshot's root time
/// with every enclosing transform applied: the curve the voices it controls
/// follow.
pub struct ControlTrace {
  priv signal : BusSignal
}

///|
fn ControlTrace::ControlTrace(signal : BusSignal) -> ControlTrace {
  { signal, }
}

///|
/// The trace moved as `placement` moves events, as `Controls::placed` does.
pub fn ControlTrace::placed(
  self : ControlTrace,
  placement : Placement,
) -> ControlTrace {
  ControlTrace(place_signal(self.signal, placement))
}

///|
/// The value at `time`, as a voice following this trace reads it.
pub fn ControlTrace::value_at(
  self : ControlTrace,
  time : Rational,
) -> @control.ControlValue {
  self.signal.eval(time.num, time.den, false)
}

///|
/// The value just before `time`: its limit from below.
pub fn ControlTrace::value_before(
  self : ControlTrace,
  time : Rational,
) -> @control.ControlValue {
  self.signal.eval(time.num, time.den, true)
}

///|
/// The cycles after which the trace repeats, not necessarily whole. `None`
/// when a time function declares no period, or the period is longer than 1024
/// cycles.
pub fn ControlTrace::period(self : ControlTrace) -> Rational? {
  self.signal.period()
}

///|
fn BusSignal::is_constant(self : BusSignal) -> Bool {
  match self {
    Absent | Const(_) => true
    Mapped(Slots(_), _) => false
    Mapped(_, children) => children[0].is_constant()
    _ => false
  }
}

///|
/// Whether a one-shot signal is inside.
fn BusSignal::has_once(self : BusSignal) -> Bool {
  match self {
    Once(_, _) => true
    Absent | Const(_) | Continuous(_, _) => false
    Mapped(_, children) | Stack(children) =>
      children.iter().any(c => c.has_once())
    Every(_, plain, transformed) => plain.has_once() || transformed.has_once()
    Product(inner, outer) => inner.has_once() || outer.has_once()
    Merge(presence, left, right) =>
      presence.has_once() || left.has_once() || right.has_once()
  }
}

///|
/// This signal for a material that entered `delay` after its origin: its
/// one-shot signals start `delay` later (ADR-0025). A rate scales the delay
/// for its children. A cycle map keeps it, because the delay is a whole
/// number of the material's periods, so a whole number of cycles there, and
/// shifting a cycle map's input by whole cycles shifts its output the same.
fn BusSignal::delayed(self : BusSignal, delay : Rational) -> BusSignal {
  match self {
    Once(f, before) => Once(f, before + delay.to_double())
    Absent | Const(_) | Continuous(_, _) => self
    Mapped(map, children) => {
      let inner = match map {
        Affine(scale, _) => delay * scale
        MirrorCycles | Slots(_) => delay
      }
      Mapped(map, children.map(child => child.delayed(inner)))
    }
    Stack(children) => Stack(children.map(child => child.delayed(delay)))
    Every(n, plain, transformed) =>
      Every(n, plain.delayed(delay), transformed.delayed(delay))
    Product(inner, outer) => Product(inner.delayed(delay), outer.delayed(delay))
    Merge(presence, left, right) =>
      Merge(presence, left.delayed(delay), right.delayed(delay))
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
/// This signal through `map`; `None` silences it.
fn BusSignal::through(self : BusSignal, map : TimeMap?) -> BusSignal {
  match map {
    Some(map) => Mapped(map, [self])
    None => Absent
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
  Mapped(
    TimeMap::sequence(n),
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
    Continuous(_, key, _, _) => add(key)
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
    | FilterMap(child, _, _)
    | Jux(child, _, _) => control_keys(nodes, child, keys)
    MergeControl(left, right) => {
      control_keys(nodes, left, keys)
      control_keys(right.nodes, right.root, keys)
    }
    // Its values are sampled at onsets, so they cannot follow a bus.
    MergeValues(_, _) => raise UnsupportedControl(id)
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
    Continuous(_, k, signal, _) =>
      match key {
        None => Const(0.0)
        Some(key) => if k == key { signal } else { Absent }
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
    Fast(child, factor) =>
      sub(child).through(TimeTransform::Fast(factor).time_map())
    Slow(child, factor) =>
      sub(child).through(TimeTransform::Slow(factor).time_map())
    Rev(child) => sub(child).through(Some(MirrorCycles))
    Euclid(child, k, n, rotation) => euclid_slots(k, n, rotation, sub(child))
    Every(child, n, transform) => {
      let plain = sub(child)
      if n <= 0 {
        plain
      } else {
        Every(n.to_int64(), plain, plain.through(transform.time_map()))
      }
    }
    Sequence(children) =>
      Mapped(TimeMap::sequence(children.length()), children.map(sub))
    WeightedSequence(children, weights) =>
      Mapped(TimeMap::weighted(weights), children.map(sub))
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
    Gate(_, _)
    | DegradeBy(_, _, _)
    | FilterMap(_, _, _)
    | Jux(_, _, _)
    | MergeValues(_, _) => raise UnsupportedControl(id)
  }
}
