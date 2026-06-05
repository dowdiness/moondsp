///|
pub struct ControlBinding {
  key : String
  node_index : Int
  slot : GraphParamSlot
} derive(Debug, Eq)

///|
#alias(new)
pub fn ControlBinding::ControlBinding(
  key~ : String,
  node_index~ : Int,
  slot~ : GraphParamSlot,
) -> ControlBinding {
  { key, node_index, slot }
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
#alias(new)
pub fn ControlBindingBuilder::ControlBindingBuilder() -> ControlBindingBuilder {
  { raw: @binding.ControlBindingBuilder::new() }
}

///|
fn ControlBindingBuilder::from_internal(
  raw : @binding.ControlBindingBuilder,
) -> ControlBindingBuilder {
  { raw, }
}

///|
/// Add a binding. Mutates internal array, returns self for chaining.
pub fn ControlBindingBuilder::bind(
  self : ControlBindingBuilder,
  key~ : String,
  node_index~ : Int,
  slot~ : GraphParamSlot,
) -> ControlBindingBuilder {
  { raw: self.raw.bind(key~, node_index~, slot=slot.to_model()) }
}

///|
/// Proven-valid control bindings. Validated against a specific
/// CompiledTemplate at build time (bounds + slot compatibility +
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
  compiled_template : CompiledTemplate,
) -> Result[ControlBindingMap, ControlBindingError] {
  match self.raw.build(compiled_template.raw()) {
    Ok(map) => Ok(ControlBindingMap::from_internal(map))
    Err(error) => Err(control_binding_error_from_internal(error))
  }
}

///|
/// Convert pattern controls to graph controls using the validated bindings.
/// Emits GraphControl::set_param for each bound key found in the input map,
/// in binding insertion order. Missing keys are skipped; unrecognized keys
/// are ignored. Values are passed through without domain validation.
pub fn ControlBindingMap::resolve_controls(
  self : ControlBindingMap,
  controls : Map[String, Double],
) -> Array[GraphControl] {
  let raw_controls = self.raw.resolve_controls(controls)
  let result = Array::new(capacity=raw_controls.length())
  for control in raw_controls {
    result.push(GraphControl::from_model(control))
  }
  result
}

///|
pub impl Show for ControlBinding with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for ControlBindingError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for ControlBindingBuilder with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for ControlBindingMap with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
