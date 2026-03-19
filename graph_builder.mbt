///|
/// A tagless interpretation that builds an `Array[DspNode]` graph.
///
/// Each `GraphBuilder` value carries a mutable node array and the index
/// of the "current" node within that array.  Source nodes (`constant`,
/// `noise`, `adsr`) start a fresh array, unary ops append to the
/// existing array, and binary ops merge two arrays when they originate
/// from different sources.
pub struct GraphBuilder {
  nodes_ : Array[DspNode]
  index : Int
}

///|
pub fn GraphBuilder::new() -> GraphBuilder {
  { nodes_: [], index: 0 }
}

///|
/// Return the accumulated node array.
pub fn GraphBuilder::nodes(self : GraphBuilder) -> Array[DspNode] {
  self.nodes_
}

///|
/// Merge `source` nodes into `target`, remapping indices by the target
/// length.  Returns the offset applied (0 when arrays are identical).
fn merge_into(target : Array[DspNode], source : Array[DspNode]) -> Int {
  if physical_equal(target, source) {
    return 0
  }
  let offset = target.length()
  for i = 0; i < source.length(); i = i + 1 {
    target.push(remap_node_by_offset(source[i], offset))
  }
  offset
}

///|
/// Create a copy of `node` with `input0` and `input1` shifted by `offset`.
/// Inputs that are `-1` (meaning "no input") are left unchanged.
fn remap_node_by_offset(node : DspNode, offset : Int) -> DspNode {
  let new_input0 = if node.input0 >= 0 {
    node.input0 + offset
  } else {
    node.input0
  }
  let new_input1 = if node.input1 >= 0 {
    node.input1 + offset
  } else {
    node.input1
  }
  DspNode(
    node.kind,
    new_input0,
    new_input1,
    node.value0,
    node.value1,
    node.value2,
    node.value3,
    node.waveform,
    node.filter_mode,
    node.delay_max_samples,
    node.delay_samples,
    node.seed,
  )
}

// ---------------------------------------------------------------------------
// ArithSym
// ---------------------------------------------------------------------------

///|
pub impl ArithSym for GraphBuilder with constant(v) -> GraphBuilder {
  let nodes : Array[DspNode] = []
  nodes.push(DspNode::constant(v))
  { nodes_: nodes, index: 0 }
}

///|
pub impl ArithSym for GraphBuilder with mul(a, b) -> GraphBuilder {
  let b_offset = merge_into(a.nodes_, b.nodes_)
  let b_index = b.index + b_offset
  let idx = a.nodes_.length()
  a.nodes_.push(DspNode::mul(a.index, b_index))
  { nodes_: a.nodes_, index: idx }
}

///|
pub impl ArithSym for GraphBuilder with mix(a, b) -> GraphBuilder {
  let b_offset = merge_into(a.nodes_, b.nodes_)
  let b_index = b.index + b_offset
  let idx = a.nodes_.length()
  a.nodes_.push(DspNode::mix(a.index, b_index))
  { nodes_: a.nodes_, index: idx }
}

///|
pub impl ArithSym for GraphBuilder with clip(self, threshold) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::clip(self.index, threshold))
  { nodes_: self.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// DspSym
// ---------------------------------------------------------------------------

///|
pub impl DspSym for GraphBuilder with oscillator(freq, waveform) -> GraphBuilder {
  let idx = freq.nodes_.length()
  freq.nodes_.push(
    DspNode(
      DspNodeKind::Oscillator,
      freq.index,
      -1,
      0.0,
      0.0,
      0.0,
      0.0,
      waveform,
      BiquadMode::LowPass,
      0,
      0,
      0U,
    ),
  )
  { nodes_: freq.nodes_, index: idx }
}

///|
pub impl DspSym for GraphBuilder with noise(seed) -> GraphBuilder {
  let nodes : Array[DspNode] = []
  nodes.push(DspNode::noise(seed))
  { nodes_: nodes, index: 0 }
}

///|
pub impl DspSym for GraphBuilder with adsr(a, d, s, r) -> GraphBuilder {
  let nodes : Array[DspNode] = []
  nodes.push(DspNode::adsr(a, d, s, r))
  { nodes_: nodes, index: 0 }
}

///|
pub impl DspSym for GraphBuilder with gain(self, amount) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::gain(self.index, amount))
  { nodes_: self.nodes_, index: idx }
}

///|
pub impl DspSym for GraphBuilder with output(self) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::output(self.index))
  { nodes_: self.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// FilterSym
// ---------------------------------------------------------------------------

///|
pub impl FilterSym for GraphBuilder with biquad(self, mode, cutoff, q) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::biquad(self.index, mode, cutoff, q))
  { nodes_: self.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// DelaySym
// ---------------------------------------------------------------------------

///|
pub impl DelaySym for GraphBuilder with delay(
  self,
  max_samples,
  delay_samples,
  feedback,
) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(
    DspNode::delay(self.index, max_samples, delay_samples~, feedback~),
  )
  { nodes_: self.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// StereoSym
// ---------------------------------------------------------------------------

///|
pub impl StereoSym for GraphBuilder with pan(self, position) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::pan(self.index, position))
  { nodes_: self.nodes_, index: idx }
}

///|
pub impl StereoSym for GraphBuilder with stereo_gain(self, amount) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::stereo_gain(self.index, amount))
  { nodes_: self.nodes_, index: idx }
}

///|
pub impl StereoSym for GraphBuilder with stereo_clip(self, threshold) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::stereo_clip(self.index, threshold))
  { nodes_: self.nodes_, index: idx }
}

///|
pub impl StereoSym for GraphBuilder with stereo_mixdown(a, b) -> GraphBuilder {
  let b_offset = merge_into(a.nodes_, b.nodes_)
  let b_index = b.index + b_offset
  let idx = a.nodes_.length()
  a.nodes_.push(
    DspNode(
      DspNodeKind::StereoMixDown,
      a.index,
      b_index,
      0.0,
      0.0,
      0.0,
      0.0,
      Waveform::Sine,
      BiquadMode::LowPass,
      0,
      0,
      0U,
    ),
  )
  { nodes_: a.nodes_, index: idx }
}

///|
pub impl StereoSym for GraphBuilder with stereo_output(a, b) -> GraphBuilder {
  let b_offset = merge_into(a.nodes_, b.nodes_)
  let b_index = b.index + b_offset
  let idx = a.nodes_.length()
  a.nodes_.push(
    DspNode(
      DspNodeKind::StereoOutput,
      a.index,
      b_index,
      0.0,
      0.0,
      0.0,
      0.0,
      Waveform::Sine,
      BiquadMode::LowPass,
      0,
      0,
      0U,
    ),
  )
  { nodes_: a.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// StereoFilterSym
// ---------------------------------------------------------------------------

///|
pub impl StereoFilterSym for GraphBuilder with stereo_biquad(
  self,
  mode,
  cutoff,
  q,
) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(DspNode::stereo_biquad(self.index, mode, cutoff, q))
  { nodes_: self.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// StereoDelaySym
// ---------------------------------------------------------------------------

///|
pub impl StereoDelaySym for GraphBuilder with stereo_delay(
  self,
  max_samples,
  delay_samples,
  feedback,
) -> GraphBuilder {
  let idx = self.nodes_.length()
  self.nodes_.push(
    DspNode::stereo_delay(self.index, max_samples, delay_samples~, feedback~),
  )
  { nodes_: self.nodes_, index: idx }
}

// ---------------------------------------------------------------------------
// Replay bridge
// ---------------------------------------------------------------------------

///|
/// Walk a `DspNode` array and reconstruct the DSP graph through the tagless
/// API, enabling round-trip testing (GraphBuilder -> nodes -> replay -> Eval).
pub fn[
  T : ArithSym + DspSym + FilterSym + DelaySym + StereoSym + StereoFilterSym + StereoDelaySym,
] replay(
  nodes : Array[DspNode],
) -> T {
  let len = nodes.length()
  let results : FixedArray[T?] = FixedArray::make(len, None)
  for i = 0; i < len; i = i + 1 {
    let node = nodes[i]
    let value : T = match node.kind {
      Constant => T::constant(node.value0)
      Oscillator =>
        if node.input0 >= 0 {
          T::oscillator(results[node.input0].unwrap(), node.waveform)
        } else {
          T::oscillator(T::constant(node.value0), node.waveform)
        }
      Noise => T::noise(node.seed)
      Adsr => T::adsr(node.value0, node.value1, node.value2, node.value3)
      Biquad =>
        T::biquad(
          results[node.input0].unwrap(),
          node.filter_mode,
          node.value0,
          node.value1,
        )
      Delay =>
        T::delay(
          results[node.input0].unwrap(),
          node.delay_max_samples,
          node.delay_samples,
          node.value0,
        )
      Gain => T::gain(results[node.input0].unwrap(), node.value0)
      Mul =>
        T::mul(results[node.input0].unwrap(), results[node.input1].unwrap())
      Mix =>
        T::mix(results[node.input0].unwrap(), results[node.input1].unwrap())
      Clip => T::clip(results[node.input0].unwrap(), node.value0)
      Output => T::output(results[node.input0].unwrap())
      Pan => T::pan(results[node.input0].unwrap(), node.value0)
      StereoGain => T::stereo_gain(results[node.input0].unwrap(), node.value0)
      StereoClip => T::stereo_clip(results[node.input0].unwrap(), node.value0)
      StereoBiquad =>
        T::stereo_biquad(
          results[node.input0].unwrap(),
          node.filter_mode,
          node.value0,
          node.value1,
        )
      StereoDelay =>
        T::stereo_delay(
          results[node.input0].unwrap(),
          node.delay_max_samples,
          node.delay_samples,
          node.value0,
        )
      StereoMixDown =>
        T::stereo_mixdown(
          results[node.input0].unwrap(),
          results[node.input1].unwrap(),
        )
      StereoOutput =>
        T::stereo_output(
          results[node.input0].unwrap(),
          results[node.input1].unwrap(),
        )
    }
    results[i] = Some(value)
  }
  results[len - 1].unwrap()
}
