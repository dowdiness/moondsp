///|
/// Result of applying one or more topology edits to an authoring graph.
/// `old_to_new[i]` is the final index of original node `i`, or -1 when deleted.
pub struct GraphEditResult {
  priv final_nodes : Array[DspNode]
  priv correspondence : FixedArray[Int]
}

///|
pub fn GraphEditResult::nodes(self : GraphEditResult) -> Array[DspNode] {
  self.final_nodes.copy()
}

///|
pub fn GraphEditResult::old_to_new(self : GraphEditResult) -> FixedArray[Int] {
  self.correspondence
}
