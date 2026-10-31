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
fn ControlUnit::to_model(self : ControlUnit) -> @binding.ControlUnit {
  match self {
    Linear => Linear
    MidiToHz => MidiToHz
    SecondsToMs => SecondsToMs
  }
}

///|
fn ControlUnit::from_model(unit : @binding.ControlUnit) -> ControlUnit {
  match unit {
    Linear => Linear
    MidiToHz => MidiToHz
    SecondsToMs => SecondsToMs
  }
}

///|
/// A score value in this unit, as its target takes it.
pub fn ControlUnit::convert(self : ControlUnit, value : Double) -> Double {
  self.to_model().convert(value)
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
fn VoiceParam::to_model(self : VoiceParam) -> @binding.VoiceParam {
  match self {
    Gain => Gain
    Pan => Pan
    Send => Send
  }
}

///|
fn VoiceParam::from_model(param : @binding.VoiceParam) -> VoiceParam {
  match param {
    Gain => Gain
    Pan => Pan
    Send => Send
  }
}

///|
/// What a bound key sets: a graph parameter or a voice-frame parameter.
pub(all) enum ControlTarget {
  Graph(Int, GraphParamSlot)
  Voice(VoiceParam)
} derive(Debug, Eq)

///|
pub extend ControlTarget with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlTarget with Eq::{not_equal, equal}

///|
pub struct ControlBinding {
  key : String
  target : ControlTarget
  unit : ControlUnit
} derive(Debug, Eq)

///|
pub extend ControlBinding with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBinding with Eq::{not_equal, equal}

///|
pub fn ControlBinding::ControlBinding(
  key~ : String,
  target~ : ControlTarget,
  unit~ : ControlUnit,
) -> ControlBinding {
  { key, target, unit, }
}

///|
pub(all) enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, GraphParamSlot)
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
fn control_binding_error_from_internal(
  error : @binding.ControlBindingError,
) -> ControlBindingError {
  match error {
    @binding.ControlBindingError::InvalidNodeIndex(index) =>
      ControlBindingError::InvalidNodeIndex(index)
    @binding.ControlBindingError::InvalidSlotForNode(index, slot) =>
      ControlBindingError::InvalidSlotForNode(
        index,
        graph_param_slot_from_model(slot),
      )
    @binding.ControlBindingError::DuplicateKey(key) =>
      ControlBindingError::DuplicateKey(key)
    @binding.ControlBindingError::OrphanBinding(key, index) =>
      ControlBindingError::OrphanBinding(key, index)
  }
}

///|
pub struct ControlBindingBuilder {
  priv raw : @binding.ControlBindingBuilder
} derive(Debug)

///|
pub extend ControlBindingBuilder with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn ControlBindingBuilder::ControlBindingBuilder() -> ControlBindingBuilder {
  { raw: @binding.ControlBindingBuilder(), }
}

///|
fn ControlBindingBuilder::from_internal(
  raw : @binding.ControlBindingBuilder,
) -> ControlBindingBuilder {
  { raw, }
}

///|
/// Bind `key` to a graph parameter; `unit` converts score values to the
/// parameter's unit. Mutates internal array, returns self for chaining.
pub fn ControlBindingBuilder::bind(
  self : ControlBindingBuilder,
  key~ : String,
  node_index~ : Int,
  slot~ : GraphParamSlot,
  unit? : ControlUnit = Linear,
) -> ControlBindingBuilder {
  {
    raw: self.raw.bind(
      key~,
      target=@binding.BindingTarget::Graph(node_index, slot.to_model()),
      unit=unit.to_model(),
    ),
  }
}

///|
/// Bind `key` to a voice-frame parameter, which every voice has whatever its
/// graph. Mutates internal array, returns self for chaining.
pub fn ControlBindingBuilder::bind_voice(
  self : ControlBindingBuilder,
  key~ : String,
  param~ : VoiceParam,
) -> ControlBindingBuilder {
  { raw: self.raw.bind(key~, target=Voice(param.to_model()), unit=Linear), }
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
  priv raw : @binding.ControlBindingMap
} derive(Debug, Eq)

///|
pub extend ControlBindingMap with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBindingMap with Eq::{not_equal, equal}

///|
fn ControlBindingMap::from_internal(
  raw : @binding.ControlBindingMap,
) -> ControlBindingMap {
  { raw, }
}

///|
/// Number of validated bindings in this map.
pub fn ControlBindingMap::length(self : ControlBindingMap) -> Int {
  self.raw.length()
}

///|
/// Validate all bindings against the compiled template and transition
/// to the proven-valid ControlBindingMap. Per-binding checks in order:
/// node index bounds, slot compatibility with the authoring node kind,
/// post-optimization liveness (rejects bindings on nodes eliminated by
/// optimize_graph), and key uniqueness. Returns the first error found.
pub fn ControlBindingBuilder::build(
  self : ControlBindingBuilder,
  compiled_template : AnalyzedGraph,
) -> Result[ControlBindingMap, ControlBindingError] {
  match self.raw.build(compiled_template.raw()) {
    Ok(map) => Ok(ControlBindingMap::from_internal(map))
    Err(error) => Err(control_binding_error_from_internal(error))
  }
}

///|
/// Convert score controls to graph controls using the validated bindings.
/// Emits GraphControl::set_param, in parameter units, for each graph-bound key
/// found in the input map, in binding insertion order. Missing keys are
/// skipped; unrecognized and voice-frame keys are ignored. Values are passed
/// through without domain validation.
pub fn ControlBindingMap::resolve_controls(
  self : ControlBindingMap,
  controls : Map[String, Double],
) -> Array[GraphControl] {
  let raw_controls = self.raw.resolve_controls(controls)
  let result : Array[GraphControl] = []
  result.reserve_capacity(raw_controls.length())
  for control in raw_controls {
    result.push(GraphControl::from_model(control))
  }
  result
}

///|
/// The binding for `key`, if any.
pub fn ControlBindingMap::binding(
  self : ControlBindingMap,
  key : String,
) -> ControlBinding? {
  match self.raw.binding(key) {
    Some((Graph(node_index, slot), unit)) =>
      Some(
        ControlBinding(
          key~,
          target=Graph(node_index, graph_param_slot_from_model(slot)),
          unit=ControlUnit::from_model(unit),
        ),
      )
    Some((Voice(param), unit)) =>
      Some(
        ControlBinding(
          key~,
          target=Voice(VoiceParam::from_model(param)),
          unit=ControlUnit::from_model(unit),
        ),
      )
    None => None
  }
}

///|
/// Visit each voice-frame-bound key found in `controls`, in binding order.
pub fn ControlBindingMap::each_voice_value(
  self : ControlBindingMap,
  controls : Map[String, Double],
  f : (VoiceParam, Double) -> Unit,
) -> Unit {
  self.raw.each_voice_value(controls, (param, value) => {
    f(VoiceParam::from_model(param), value)
  })
}

///|
pub impl Show for ControlBinding with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBinding with Show::{to_string, output}

///|
pub impl Show for ControlBindingError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBindingError with Show::{to_string, output}

///|
pub impl Show for ControlBindingBuilder with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBindingBuilder with Show::{to_string, output}

///|
pub impl Show for ControlBindingMap with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBindingMap with Show::{to_string, output}

///|
/// Read the default captured when these bindings were validated, in score
/// units.
pub fn ControlBindingMap::default_value(
  self : ControlBindingMap,
  key : String,
) -> Double? {
  self.raw.default_value(key)
}
