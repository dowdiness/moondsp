///|
/// How a score value converts to the value its target takes.
pub(all) enum ControlUnit {
  Linear
  /// MIDI note number to Hz.
  MidiToHz
  /// Seconds to milliseconds.
  SecondsToMs
} derive(Debug, Eq)

///|
pub extend ControlUnit with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlUnit with Eq::{not_equal, equal}

///|
/// A score value in this unit, as its target takes it.
pub fn ControlUnit::convert(self : ControlUnit, value : Double) -> Double {
  match self {
    Linear => value
    MidiToHz => 440.0 * @math.pow(2.0, (value - 69.0) / 12.0)
    SecondsToMs => value * 1000.0
  }
}

///|
/// A target value back in score units.
pub fn ControlUnit::invert(self : ControlUnit, value : Double) -> Double {
  match self {
    Linear => value
    MidiToHz => 69.0 + 12.0 * @math.log2(value / 440.0)
    SecondsToMs => value / 1000.0
  }
}

///|
/// A parameter every voice has outside its graph (ADR-0019 Decision 8).
/// The mix order is gain -> pan -> (dry, send).
pub(all) enum VoiceParam {
  Gain
  Pan
  Send
} derive(Debug, Eq)

///|
pub extend VoiceParam with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend VoiceParam with Eq::{not_equal, equal}

///|
pub(all) enum BindingTarget {
  Graph(Int, @model.GraphParamSlot)
  Voice(VoiceParam)
} derive(Debug, Eq)

///|
pub extend BindingTarget with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BindingTarget with Eq::{not_equal, equal}

///|
priv struct ControlBinding {
  key : String
  target : BindingTarget
  unit : ControlUnit
} derive(Debug, Eq)

///|
pub enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, @model.GraphParamSlot)
  DuplicateKey(String)
  /// Binding (key, node_index) targets a template node that
  /// optimize_graph eliminated. Prevents silent set_param no-ops.
  OrphanBinding(String, Int)
} derive(Debug, Eq)

///|
pub extend ControlBindingError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBindingError with Eq::{not_equal, equal}

///|
pub struct ControlBindingBuilder {
  priv bindings : Array[ControlBinding]
} derive(Debug)

///|
pub extend ControlBindingBuilder with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn ControlBindingBuilder::ControlBindingBuilder() -> ControlBindingBuilder {
  { bindings: [], }
}

///|
/// Add a binding. Mutates internal array, returns self for chaining.
pub fn ControlBindingBuilder::bind(
  self : ControlBindingBuilder,
  key~ : String,
  target~ : BindingTarget,
  unit~ : ControlUnit,
) -> ControlBindingBuilder {
  self.bindings.push({ key, target, unit, })
  self
}

///|
/// Proven-valid control bindings. Validated against a specific
/// AnalyzedGraph at build time (bounds + slot compatibility +
/// orphan detection + key uniqueness).
///
/// No public constructor — only reachable through ControlBindingBuilder::build().
///
/// WARNING: A ControlBindingMap's validity is tied to the template it was
/// built against. After VoicePool::set_template swaps to a new template,
/// bindings validated against the prior template remain type-level valid
/// but may silently retarget the wrong kind of node or no-op against
/// nodes the new template's optimize_graph eliminated. Rebuild the
/// ControlBindingMap whenever the template changes. Structural staleness
/// detection is tracked as a follow-up.
pub struct ControlBindingMap {
  priv bindings : Array[ControlBinding]
  priv defaults : Array[Double]
} derive(Debug, Eq)

///|
pub extend ControlBindingMap with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBindingMap with Eq::{not_equal, equal}

///|
/// Number of validated bindings in this map.
pub fn ControlBindingMap::length(self : ControlBindingMap) -> Int {
  self.bindings.length()
}

///|
/// Validate all bindings against the compiled template and transition
/// to the proven-valid ControlBindingMap. Per-binding checks in order:
/// node index bounds, slot compatibility with the authoring node kind,
/// post-optimization liveness (rejects bindings on nodes eliminated by
/// optimize_graph), and key uniqueness. Returns the first error found.
pub fn ControlBindingBuilder::build(
  self : ControlBindingBuilder,
  compiled_template : @template.AnalyzedGraph,
) -> Result[ControlBindingMap, ControlBindingError] {
  let defaults : Array[Double] = []
  let seen_keys : Map[String, Bool] = Map([])
  for i in 0..<self.bindings.length() {
    let binding = self.bindings[i]
    if seen_keys.contains(binding.key) {
      return Err(ControlBindingError::DuplicateKey(binding.key))
    }
    seen_keys[binding.key] = true
    let (node_index, slot) = match binding.target {
      Graph(node_index, slot) => (node_index, slot)
      // A new voice starts with unit gain, centre pan, and no send.
      Voice(Gain) => {
        defaults.push(1.0)
        continue
      }
      Voice(Pan | Send) => {
        defaults.push(0.0)
        continue
      }
    }
    if node_index < 0 || node_index >= compiled_template.length() {
      return Err(ControlBindingError::InvalidNodeIndex(node_index))
    }
    if !@model.node_accepts_slot(compiled_template.node_at(node_index), slot) {
      return Err(ControlBindingError::InvalidSlotForNode(node_index, slot))
    }
    if !compiled_template.is_node_live(node_index) {
      return Err(ControlBindingError::OrphanBinding(binding.key, node_index))
    }
    let node = compiled_template.node_at(node_index)
    defaults.push(
      binding.unit.invert(
        match slot {
          Value0 => node.value0()
          Value1 => node.value1()
          Value2 => node.value2()
          Value3 => node.value3()
          DelaySamples => node.delay_samples().to_double()
        },
      ),
    )
  }
  // WHY copy: self.bindings is a mutable Array shared with the builder.
  // Without copying, post-build bind() calls would mutate the validated map,
  // breaking the proven-valid invariant.
  Ok({ bindings: self.bindings.copy(), defaults, })
}

///|
/// Convert score controls to graph controls using the validated bindings.
/// Emits GraphControl::set_param, in target units, for each graph-bound key
/// found in the input map, in binding insertion order. Missing keys are
/// skipped; unrecognized keys and voice-frame keys are ignored. Values are
/// passed through without domain validation.
pub fn ControlBindingMap::resolve_controls(
  self : ControlBindingMap,
  controls : Map[String, Double],
) -> Array[@model.GraphControl] {
  let result : Array[@model.GraphControl] = []
  result.reserve_capacity(self.bindings.length())
  for i in 0..<self.bindings.length() {
    let binding = self.bindings[i]
    match (binding.target, controls.get(binding.key)) {
      (Graph(node_index, slot), Some(value)) =>
        result.push(
          @model.GraphControl::set_param(
            node_index,
            slot,
            binding.unit.convert(value),
          ),
        )
      _ => ()
    }
  }
  result
}

///|
/// Visit each voice-frame-bound key found in `controls`, in binding order.
pub fn ControlBindingMap::each_voice_value(
  self : ControlBindingMap,
  controls : Map[String, Double],
  f : (VoiceParam, Double) -> Unit,
) -> Unit {
  for binding in self.bindings {
    match (binding.target, controls.get(binding.key)) {
      (Voice(param), Some(value)) => f(param, value)
      _ => ()
    }
  }
}

///|
/// The target and unit `key` is bound to, if any.
pub fn ControlBindingMap::binding(
  self : ControlBindingMap,
  key : String,
) -> (BindingTarget, ControlUnit)? {
  for binding in self.bindings {
    if binding.key == key {
      return Some((binding.target, binding.unit))
    }
  }
  None
}

///|
/// Read the default captured when these bindings were validated, in score
/// units.
pub fn ControlBindingMap::default_value(
  self : ControlBindingMap,
  key : String,
) -> Double? {
  for i in 0..<self.bindings.length() {
    if self.bindings[i].key == key {
      return Some(self.defaults[i])
    }
  }
  None
}
