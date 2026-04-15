///|
/// Capability trait for signal shape queries.
pub(open) trait NodeSpanning {
  signal_shape(Self) -> Int
}

///|
/// Capability trait for compile-time constant folding.
pub(open) trait NodeFoldable: NodeSpanning {
  is_foldable(Self) -> Bool
  fold_value(Self, Double, Double) -> Double
}

///|
/// Capability trait for stateful node identification.
pub(open) trait NodeStateful: NodeSpanning {
  is_stateful(Self) -> Bool
}

///|
/// Capability trait for topology editing queries.
pub(open) trait NodeEditable: NodeSpanning + NodeFoldable {
  can_insert_after(Self) -> Bool
  can_delete(Self) -> Bool
}

///|
pub impl NodeSpanning for DspNode with signal_shape(self) -> Int {
  match self.kind {
    Pan | StereoGain | StereoClip | StereoBiquad | StereoDelay | StereoOutput =>
      STEREO_SIGNAL_SHAPE
    _ => MONO_SIGNAL_SHAPE
  }
}

///|
pub impl NodeFoldable for DspNode with is_foldable(self) -> Bool {
  match self.kind {
    Constant | Mul | Mix | Gain | Clip => true
    _ => false
  }
}

///|
pub impl NodeFoldable for DspNode with fold_value(
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
pub impl NodeStateful for DspNode with is_stateful(self) -> Bool {
  match self.kind {
    Oscillator | Noise | Adsr | Biquad | Delay | StereoBiquad | StereoDelay =>
      true
    _ => false
  }
}

///|
pub impl NodeEditable for DspNode with can_insert_after(self) -> Bool {
  match self.kind {
    Output | StereoOutput => false
    _ => true
  }
}

///|
pub impl NodeEditable for DspNode with can_delete(self) -> Bool {
  match self.kind {
    Output | StereoOutput => false
    _ => self.input1 < 0
  }
}
