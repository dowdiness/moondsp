///|
/// Capability trait for signal shape queries.
pub(open) trait NodeSpanning {
  fn signal_shape(Self) -> Int
}

///|
/// Capability trait for compile-time constant folding.
pub(open) trait NodeFoldable: NodeSpanning {
  fn is_foldable(Self) -> Bool
  fn fold_value(Self, Double, Double) -> Double
}

///|
/// Capability trait for stateful node identification.
pub(open) trait NodeStateful: NodeSpanning {
  fn is_stateful(Self) -> Bool
}

///|
/// Capability trait for topology editing queries.
pub(open) trait NodeEditable: NodeSpanning + NodeFoldable {
  fn can_insert_after(Self) -> Bool
  fn can_delete(Self) -> Bool
}

///|
pub impl NodeSpanning for DspNode with fn signal_shape(self) -> Int {
  @model.node_signal_shape(self.raw())
}

///|
pub impl NodeFoldable for DspNode with fn is_foldable(self) -> Bool {
  @model.node_is_foldable(self.raw())
}

///|
pub impl NodeFoldable for DspNode with fn fold_value(
  self,
  input0 : Double,
  input1 : Double,
) -> Double {
  @model.node_fold_value(self.raw(), input0, input1)
}

///|
pub impl NodeStateful for DspNode with fn is_stateful(self) -> Bool {
  @model.node_is_stateful(self.raw())
}

///|
pub impl NodeEditable for DspNode with fn can_insert_after(self) -> Bool {
  @model.node_can_insert_after(self.raw())
}

///|
pub impl NodeEditable for DspNode with fn can_delete(self) -> Bool {
  @model.node_can_delete(self.raw())
}
