///|
/// Shared lifecycle scaffolding for browser graph variants.
///
/// `Output` is a two-method capability trait — the only methods whose
/// signatures are uniform across mono and stereo. Structurally-different
/// sample accessors and buffer getters live on concrete `MonoOut` /
/// `StereoOut` types, preserving compile-time shape safety.

///|
pub trait Output {
  fn reset(Self) -> Unit
  fn allocate(Self, block_size : Int) -> Unit
}

///|
/// Single-buffer output used by mono graph variants.
pub struct MonoOut {
  priv buffer : @ref.Ref[@moondsp.AudioBuffer?]
}

///|
#alias(new)
pub fn MonoOut::MonoOut() -> MonoOut {
  { buffer: @ref.new(None) }
}

///|
pub impl Output for MonoOut with fn reset(self) {
  self.buffer.val = None
}

///|
pub impl Output for MonoOut with fn allocate(self, n) {
  self.buffer.val = Some(@moondsp.AudioBuffer::filled(n))
}

///|
/// Concrete mono API — NOT on the trait.
pub fn MonoOut::get(self : MonoOut) -> @moondsp.AudioBuffer {
  self.buffer.val.unwrap()
}

///|
pub fn MonoOut::sample(self : MonoOut, index : Int) -> Double {
  checked_sample(index, self.buffer.val)
}

///|
/// Paired-buffer output used by stereo graph variants.
pub struct StereoOut {
  priv left : @ref.Ref[@moondsp.AudioBuffer?]
  priv right : @ref.Ref[@moondsp.AudioBuffer?]
}

///|
#alias(new)
pub fn StereoOut::StereoOut() -> StereoOut {
  { left: @ref.new(None), right: @ref.new(None) }
}

///|
pub impl Output for StereoOut with fn reset(self) {
  self.left.val = None
  self.right.val = None
}

///|
pub impl Output for StereoOut with fn allocate(self, n) {
  let left = @moondsp.AudioBuffer::filled(n)
  let right = @moondsp.AudioBuffer::filled(n)
  self.left.val = Some(left)
  self.right.val = Some(right)
}

///|
/// Concrete stereo API — NOT on the trait. Type-safe: calling
/// `mono.left_sample(i)` would fail to compile.
pub fn StereoOut::left_buf(self : StereoOut) -> @moondsp.AudioBuffer {
  self.left.val.unwrap()
}

///|
pub fn StereoOut::right_buf(self : StereoOut) -> @moondsp.AudioBuffer {
  self.right.val.unwrap()
}

///|
pub fn StereoOut::left_sample(self : StereoOut, index : Int) -> Double {
  checked_sample(index, self.left.val)
}

///|
pub fn StereoOut::right_sample(self : StereoOut, index : Int) -> Double {
  checked_sample(index, self.right.val)
}

///|
/// Generic slot parameterised by graph type `T` and output shape `O`.
/// Holds the uniform 5-Ref scaffolding and drives rate/block caching.
pub struct GraphSlot[T, O] {
  graph : @ref.Ref[T?]
  context : @ref.Ref[@moondsp.DspContext?]
  output : O
  priv sample_rate : @ref.Ref[Double]
  priv block_size : @ref.Ref[Int]
  priv compile : (@moondsp.DspContext) -> T?
}

///|
#alias(new)
pub fn[T, O] GraphSlot::GraphSlot(
  output~ : O,
  compile~ : (@moondsp.DspContext) -> T?,
) -> GraphSlot[T, O] {
  {
    graph: @ref.new(None),
    context: @ref.new(None),
    output,
    sample_rate: @ref.new(0.0),
    block_size: @ref.new(0),
    compile,
  }
}

///|
/// Ensure the slot is initialized for the given rate/block.
/// Returns true iff the slot is now ready to `process`.
///
/// Invariant: after `ensure` returns true, graph/context/output/rate/block
/// are all consistent. After it returns false, the slot is reset.
/// Allocation happens BEFORE publishing graph/context so that a failing
/// allocator leaves the slot cleared rather than half-initialized.
///
/// `on_rebuild` fires when the graph is actually rebuilt (not on cache
/// hit or reset). Use it to reset variant-owned structural state
/// (e.g. a `topo_edit_inserted` flag) whose validity is tied to the
/// specific compiled graph instance.
pub fn[T, O : Output] GraphSlot::ensure(
  self : GraphSlot[T, O],
  rate : Double,
  block : Int,
  on_rebuild? : () -> Unit = fn() {  },
) -> Bool {
  if rate <= 0.0 || block <= 0 {
    self.reset()
    return false
  }
  if self.graph.val is Some(_) &&
    self.sample_rate.val == rate &&
    self.block_size.val == block {
    return true
  }
  let ctx = @moondsp.DspContext::new(sample_rate=rate, block_size=block)
  match (self.compile)(ctx) {
    Some(g) => {
      self.output.allocate(block)
      self.graph.val = Some(g)
      self.context.val = Some(ctx)
      self.sample_rate.val = rate
      self.block_size.val = block
      on_rebuild()
      true
    }
    None => {
      self.reset()
      false
    }
  }
}

///|
pub fn[T, O : Output] GraphSlot::reset(self : GraphSlot[T, O]) -> Unit {
  self.graph.val = None
  self.context.val = None
  self.output.reset()
  self.sample_rate.val = 0.0
  self.block_size.val = 0
}

///|
pub fn[T, O] GraphSlot::graph_val(self : GraphSlot[T, O]) -> T {
  self.graph.val.unwrap()
}

///|
pub fn[T, O] GraphSlot::ctx_val(self : GraphSlot[T, O]) -> @moondsp.DspContext {
  self.context.val.unwrap()
}

///|
/// Bounds-checked sample read from an optional buffer. Returns 0.0
/// for out-of-bounds indices or uninitialized buffers. Shared by
/// `MonoOut::sample` / `StereoOut::*_sample` and the scheduler file.
fn checked_sample(index : Int, output : @moondsp.AudioBuffer?) -> Double {
  match output {
    Some(buffer) =>
      if index >= 0 && index < buffer.length() {
        buffer.get(index)
      } else {
        0.0
      }
    None => 0.0
  }
}
