///|
pub struct ControlBinding {
  key : String
  node_index : Int
  slot : GraphParamSlot

  fn new(
    key~ : String,
    node_index~ : Int,
    slot~ : GraphParamSlot,
  ) -> ControlBinding
} derive(Show, Eq)

///|
fn ControlBinding::new(
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
} derive(Show, Eq)

///|
pub struct ControlBindingBuilder {
  bindings : Array[ControlBinding]

  fn new() -> ControlBindingBuilder
} derive(Show)

///|
pub fn ControlBindingBuilder::new() -> ControlBindingBuilder {
  { bindings: [] }
}

///|
/// Add a binding. Mutates internal array, returns self for chaining.
pub fn ControlBindingBuilder::bind(
  self : ControlBindingBuilder,
  key~ : String,
  node_index~ : Int,
  slot~ : GraphParamSlot,
) -> ControlBindingBuilder {
  self.bindings.push(ControlBinding(key~, node_index~, slot~))
  self
}

///|
/// No public constructor — only reachable through ControlBindingBuilder::build().
pub struct ControlBindingMap {
  priv bindings : Array[ControlBinding]
} derive(Show, Eq)

///|
/// Number of validated bindings in this map.
pub fn ControlBindingMap::length(self : ControlBindingMap) -> Int {
  self.bindings.length()
}

///|
/// Validate all bindings against the graph template and transition to
/// the proven-valid ControlBindingMap. Checks node index bounds, slot
/// compatibility, and key uniqueness. Returns the first error found.
pub fn ControlBindingBuilder::build(
  self : ControlBindingBuilder,
  template : Array[DspNode],
) -> Result[ControlBindingMap, ControlBindingError] {
  let seen_keys : Map[String, Bool] = {}
  for i = 0; i < self.bindings.length(); i = i + 1 {
    let binding = self.bindings[i]
    if binding.node_index < 0 || binding.node_index >= template.length() {
      return Err(ControlBindingError::InvalidNodeIndex(binding.node_index))
    }
    if !node_accepts_slot(template[binding.node_index], binding.slot) {
      return Err(
        ControlBindingError::InvalidSlotForNode(
          binding.node_index,
          binding.slot,
        ),
      )
    }
    if seen_keys.contains(binding.key) {
      return Err(ControlBindingError::DuplicateKey(binding.key))
    }
    seen_keys[binding.key] = true
  }
  // WHY copy: self.bindings is a mutable Array shared with the builder.
  // Without copying, post-build bind() calls would mutate the validated map,
  // breaking the proven-valid invariant.
  Ok({ bindings: self.bindings.copy() })
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
  let result = Array::new(capacity=self.bindings.length())
  for i = 0; i < self.bindings.length(); i = i + 1 {
    let binding = self.bindings[i]
    match controls.get(binding.key) {
      Some(value) =>
        result.push(
          GraphControl::set_param(binding.node_index, binding.slot, value),
        )
      None => ()
    }
  }
  result
}
