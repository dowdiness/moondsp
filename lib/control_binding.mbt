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
fn ControlBindingBuilder::new() -> ControlBindingBuilder {
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
