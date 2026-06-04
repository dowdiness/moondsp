///|
/// Capability trait for signal shape queries.
pub trait NodeSpanning {
  fn signal_shape(Self) -> Int
}

///|
/// Capability trait for compile-time constant folding.
pub trait NodeFoldable: NodeSpanning {
  fn is_foldable(Self) -> Bool
  fn fold_value(Self, Double, Double) -> Double
}

///|
/// Capability trait for stateful node identification.
pub trait NodeStateful: NodeSpanning {
  fn is_stateful(Self) -> Bool
}

///|
/// Capability trait for topology editing queries.
pub trait NodeEditable: NodeSpanning + NodeFoldable {
  fn can_insert_after(Self) -> Bool
  fn can_delete(Self) -> Bool
}

///|
pub impl NodeSpanning for DspNode with fn signal_shape(self) -> Int {
  match self.kind {
    Pan | StereoGain | StereoClip | StereoBiquad | StereoDelay | StereoOutput =>
      STEREO_SIGNAL_SHAPE
    _ => MONO_SIGNAL_SHAPE
  }
}

///|
pub impl NodeFoldable for DspNode with fn is_foldable(self) -> Bool {
  match self.kind {
    Constant | Mul | Mix | Gain | Clip => true
    _ => false
  }
}

///|
pub impl NodeFoldable for DspNode with fn fold_value(
  self,
  input0 : Double,
  input1 : Double,
) -> Double {
  match self.kind {
    Constant => self.value0
    Mul => input0 * input1
    Mix => input0 + input1
    Gain => input0 * self.value0
    Clip => input0.clamp(min=-self.value0, max=self.value0)
    _ => 0.0
  }
}

///|
pub impl NodeStateful for DspNode with fn is_stateful(self) -> Bool {
  match self.kind {
    Oscillator | Noise | Adsr | Biquad | Delay | StereoBiquad | StereoDelay =>
      true
    _ => false
  }
}

///|
pub impl NodeEditable for DspNode with fn can_insert_after(self) -> Bool {
  match self.kind {
    Output | StereoOutput => false
    _ => true
  }
}

///|
pub impl NodeEditable for DspNode with fn can_delete(self) -> Bool {
  match self.kind {
    Output | StereoOutput => false
    _ => self.input1 < 0
  }
}

///|
pub fn node_signal_shape(node : DspNode) -> Int {
  node.signal_shape()
}

///|
pub fn node_is_foldable(node : DspNode) -> Bool {
  node.is_foldable()
}

///|
pub fn node_fold_value(
  node : DspNode,
  input0 : Double,
  input1 : Double,
) -> Double {
  node.fold_value(input0, input1)
}

///|
pub fn node_is_stateful(node : DspNode) -> Bool {
  node.is_stateful()
}

///|
pub fn node_can_insert_after(node : DspNode) -> Bool {
  node.can_insert_after()
}

///|
pub fn node_can_delete(node : DspNode) -> Bool {
  node.can_delete()
}
