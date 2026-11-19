///|
/// How a score value converts to the value its target takes.
#derive(Debug, Eq)
pub(all) enum ControlUnit {
  Linear
  /// MIDI note number to Hz.
  MidiToHz
  /// Seconds to milliseconds.
  SecondsToMs
}

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
#derive(Debug, Eq)
pub(all) enum VoiceParam {
  Gain
  Pan
  Send
}

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
#derive(Debug, Eq)
pub(all) enum ControlTarget {
  Graph(Int32, GraphParamSlot)
  Voice(VoiceParam)
}

///|
pub extend ControlTarget with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlTarget with Eq::{not_equal, equal}

///|
#derive(Debug, Eq)
pub struct ControlBinding[K] {
  key : K
  target : ControlTarget
  unit : ControlUnit
}

///|
pub extend ControlBinding with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBinding with Eq::{not_equal, equal}

///|
pub fn[K] ControlBinding::ControlBinding(
  key~ : K,
  target~ : ControlTarget,
  unit~ : ControlUnit,
) -> ControlBinding[K] {
  { key, target, unit, }
}

///|
#derive(Debug, Eq)
pub(all) enum ControlBindingError[K] {
  InvalidNodeIndex(Int32)
  InvalidSlotForNode(Int32, GraphParamSlot)
  DuplicateKey(K)
  /// Binding (key, node_index) targets a template node that
  /// optimize_graph eliminated. Prevents silent set_param no-ops.
  OrphanBinding(K, Int32)
}

///|
pub extend ControlBindingError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBindingError with Eq::{not_equal, equal}

///|
fn[K] control_binding_error_from_internal(
  error : @binding.ControlBindingError[K],
) -> ControlBindingError[K] {
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
#derive(Debug)
pub struct ControlBindingBuilder[K] {
  priv raw : @binding.ControlBindingBuilder[K]
}

///|
pub extend ControlBindingBuilder with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn[K] ControlBindingBuilder::ControlBindingBuilder() -> ControlBindingBuilder[
  K,
] {
  { raw: @binding.ControlBindingBuilder(), }
}

///|
fn[K] ControlBindingBuilder::from_internal(
  raw : @binding.ControlBindingBuilder[K],
) -> ControlBindingBuilder[K] {
  { raw, }
}

///|
/// Bind `key` to a graph parameter; `unit` converts score values to the
/// parameter's unit. Mutates internal array, returns self for chaining.
pub fn[K] ControlBindingBuilder::bind(
  self : ControlBindingBuilder[K],
  key~ : K,
  node_index~ : Int32,
  slot~ : GraphParamSlot,
  unit~ : ControlUnit = Linear,
) -> ControlBindingBuilder[K] {
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
pub fn[K] ControlBindingBuilder::bind_voice(
  self : ControlBindingBuilder[K],
  key~ : K,
  param~ : VoiceParam,
) -> ControlBindingBuilder[K] {
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
#derive(Debug, Eq)
pub struct ControlBindingMap[K] {
  priv raw : @binding.ControlBindingMap[K]
}

///|
pub extend ControlBindingMap with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlBindingMap with Eq::{not_equal, equal}

///|
fn[K] ControlBindingMap::from_internal(
  raw : @binding.ControlBindingMap[K],
) -> ControlBindingMap[K] {
  { raw, }
}

///|
/// Number of validated bindings in this map.
pub fn[K] ControlBindingMap::length(self : ControlBindingMap[K]) -> Int32 {
  self.raw.length()
}

///|
/// Validate all bindings against the compiled template and transition
/// to the proven-valid ControlBindingMap. Per-binding checks in order:
/// node index bounds, slot compatibility with the authoring node kind,
/// post-optimization liveness (rejects bindings on nodes eliminated by
/// optimize_graph), and key uniqueness. Returns the first error found.
pub fn[K : Eq + Hash] ControlBindingBuilder::build(
  self : ControlBindingBuilder[K],
  compiled_template : AnalyzedGraph,
) -> Result[ControlBindingMap[K], ControlBindingError[K]] {
  match self.raw.build(compiled_template.raw()) {
    Ok(map) => Ok(ControlBindingMap::from_internal(map))
    Err(error) => Err(control_binding_error_from_internal(error))
  }
}

///|
/// Convert score controls to graph controls using the validated bindings.
/// Emits GraphControl::set_param, in parameter units, for each graph-bound key
/// `value_of` gives a value, in binding insertion order. Missing keys are
/// skipped; unrecognized and voice-frame keys are ignored. Values are passed
/// through without domain validation.
pub fn[K] ControlBindingMap::resolve_controls(
  self : ControlBindingMap[K],
  value_of : (K) -> Double?,
) -> Array[GraphControl] {
  let raw_controls = self.raw.resolve_controls(value_of)
  let result : Array[GraphControl] = []
  result.reserve_capacity(raw_controls.length())
  for control in raw_controls {
    result.push(GraphControl::from_model(control))
  }
  result
}

///|
/// The binding for `key`, if any.
pub fn[K : Eq] ControlBindingMap::binding(
  self : ControlBindingMap[K],
  key : K,
) -> ControlBinding[K]? {
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
/// Visit each voice-frame-bound key `value_of` gives a value, in binding order.
pub fn[K] ControlBindingMap::each_voice_value(
  self : ControlBindingMap[K],
  value_of : (K) -> Double?,
  f : (VoiceParam, Double) -> Unit,
) -> Unit {
  self.raw.each_voice_value(value_of, (param, value) => {
    f(VoiceParam::from_model(param), value)
  })
}

///|
pub impl[K : Debug] Show for ControlBinding[K] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBinding with Show::{to_string, output}

///|
pub impl[K : Debug] Show for ControlBindingError[K] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBindingError with Show::{to_string, output}

///|
pub impl[K : Debug] Show for ControlBindingBuilder[K] with fn output(
  self,
  logger,
) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBindingBuilder with Show::{to_string, output}

///|
pub impl[K : Debug] Show for ControlBindingMap[K] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend ControlBindingMap with Show::{to_string, output}

///|
/// Read the default captured when these bindings were validated, in score
/// units.
pub fn[K : Eq] ControlBindingMap::default_value(
  self : ControlBindingMap[K],
  key : K,
) -> Double? {
  self.raw.default_value(key)
}
