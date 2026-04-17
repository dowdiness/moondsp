///|
/// Shared lifecycle scaffolding for browser graph variants.
///
/// `Output` is a two-method capability trait — the only methods whose
/// signatures are uniform across mono and stereo. Structurally-different
/// sample accessors and buffer getters live on concrete `MonoOut` /
/// `StereoOut` types, preserving compile-time shape safety.

///|
priv trait Output {
  reset(Self) -> Unit
  allocate(Self, block_size : Int) -> Unit
}

///|
/// Single-buffer output used by mono graph variants.
priv struct MonoOut {
  buffer : @ref.Ref[@lib.AudioBuffer?]

  fn new() -> MonoOut
}

///|
fn MonoOut::new() -> MonoOut {
  { buffer: @ref.new(None) }
}

///|
impl Output for MonoOut with reset(self) {
  self.buffer.val = None
}

///|
impl Output for MonoOut with allocate(self, n) {
  self.buffer.val = Some(@lib.AudioBuffer::filled(n))
}

///|
/// Concrete mono API — NOT on the trait.
fn MonoOut::get(self : MonoOut) -> @lib.AudioBuffer {
  self.buffer.val.unwrap()
}

///|
fn MonoOut::sample(self : MonoOut, index : Int) -> Double {
  checked_sample(index, self.buffer.val)
}

///|
/// Paired-buffer output used by stereo graph variants.
priv struct StereoOut {
  left : @ref.Ref[@lib.AudioBuffer?]
  right : @ref.Ref[@lib.AudioBuffer?]

  fn new() -> StereoOut
}

///|
fn StereoOut::new() -> StereoOut {
  { left: @ref.new(None), right: @ref.new(None) }
}

///|
impl Output for StereoOut with reset(self) {
  self.left.val = None
  self.right.val = None
}

///|
impl Output for StereoOut with allocate(self, n) {
  let left = @lib.AudioBuffer::filled(n)
  let right = @lib.AudioBuffer::filled(n)
  self.left.val = Some(left)
  self.right.val = Some(right)
}

///|
/// Concrete stereo API — NOT on the trait. Type-safe: calling
/// `mono.left_sample(i)` would fail to compile.
fn StereoOut::left_buf(self : StereoOut) -> @lib.AudioBuffer {
  self.left.val.unwrap()
}

///|
fn StereoOut::right_buf(self : StereoOut) -> @lib.AudioBuffer {
  self.right.val.unwrap()
}

///|
fn StereoOut::left_sample(self : StereoOut, index : Int) -> Double {
  checked_sample(index, self.left.val)
}

///|
fn StereoOut::right_sample(self : StereoOut, index : Int) -> Double {
  checked_sample(index, self.right.val)
}

///|
/// Generic slot parameterised by graph type `T` and output shape `O`.
/// Holds the uniform 5-Ref scaffolding and drives rate/block caching.
priv struct GraphSlot[T, O] {
  graph : @ref.Ref[T?]
  context : @ref.Ref[@lib.DspContext?]
  output : O
  sample_rate : @ref.Ref[Double]
  block_size : @ref.Ref[Int]
  compile : (@lib.DspContext) -> T?

  fn[T, O] new(
    output~ : O,
    compile~ : (@lib.DspContext) -> T?,
  ) -> GraphSlot[T, O]
}

///|
fn[T, O] GraphSlot::new(
  output~ : O,
  compile~ : (@lib.DspContext) -> T?,
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
fn[T, O : Output] GraphSlot::ensure(
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
  let ctx = @lib.DspContext::new(rate, block)
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
fn[T, O : Output] GraphSlot::reset(self : GraphSlot[T, O]) -> Unit {
  self.graph.val = None
  self.context.val = None
  self.output.reset()
  self.sample_rate.val = 0.0
  self.block_size.val = 0
}

///|
fn[T, O] GraphSlot::graph_val(self : GraphSlot[T, O]) -> T {
  self.graph.val.unwrap()
}

///|
fn[T, O] GraphSlot::ctx_val(self : GraphSlot[T, O]) -> @lib.DspContext {
  self.context.val.unwrap()
}

///|
/// Bounds-checked sample read from an optional buffer. Returns 0.0
/// for out-of-bounds indices or uninitialized buffers. Shared by
/// `MonoOut::sample` / `StereoOut::*_sample` and the scheduler file.
fn checked_sample(index : Int, output : @lib.AudioBuffer?) -> Double {
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
