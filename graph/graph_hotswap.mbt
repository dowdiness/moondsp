///|
/// Block-boundary mono graph hot-swap wrapper for `CompiledDsp`.
///
/// Public facade wrapper; implementation lives in `graph/internal/staging`.
struct CompiledDspHotSwap(@staging.CompiledDspHotSwap)

///|
/// Block-boundary stereo graph hot-swap wrapper for `CompiledStereoDsp`.
///
/// Public facade wrapper; implementation lives in `graph/internal/staging`.
struct CompiledStereoDspHotSwap(@staging.CompiledStereoDspHotSwap)

///|
/// Failure reason for result-typed hot-swap queue APIs.
pub(all) enum HotSwapQueueError {
  SampleRateMismatch(Double, Double)
  BlockCapacityMismatch(Int, Int)
} derive(Debug)

///|
pub impl Show for HotSwapQueueError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn hot_swap_queue_error_from_staging(
  error : @staging.HotSwapQueueError,
) -> HotSwapQueueError {
  match error {
    @staging.HotSwapQueueError::SampleRateMismatch(active_rate, next_rate) =>
      HotSwapQueueError::SampleRateMismatch(active_rate, next_rate)
    @staging.HotSwapQueueError::BlockCapacityMismatch(
      active_capacity,
      next_capacity
    ) =>
      HotSwapQueueError::BlockCapacityMismatch(active_capacity, next_capacity)
  }
}

///|
fn hot_swap_queue_result_from_staging(
  result : Result[Unit, @staging.HotSwapQueueError],
) -> Result[Unit, HotSwapQueueError] {
  match result {
    Ok(_) => Ok(())
    Err(error) => Err(hot_swap_queue_error_from_staging(error))
  }
}

///|
/// Create a hot-swap wrapper around an active mono compiled graph.
pub fn CompiledDspHotSwap::from_graph(
  active : CompiledDsp,
  crossfade_samples? : Int = 0,
) -> CompiledDspHotSwap {
  CompiledDspHotSwap(
    @staging.CompiledDspHotSwap::from_graph(active.raw(), crossfade_samples~),
  )
}

///|
/// Queue a replacement graph for the next `process(...)` call.
///
/// Returns an error when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn CompiledDspHotSwap::queue_swap(
  self : CompiledDspHotSwap,
  next : CompiledDsp,
) -> Result[Unit, HotSwapQueueError] {
  hot_swap_queue_result_from_staging(self.0.queue_swap(next.raw()))
}

///|
/// Process one block, crossfading between the active and pending graphs when a
/// swap is in flight.
pub fn CompiledDspHotSwap::process(
  self : CompiledDspHotSwap,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  self.0.process(context, output)
}

///|
/// Create a hot-swap wrapper around an active stereo compiled graph.
pub fn CompiledStereoDspHotSwap::from_graph(
  active : CompiledStereoDsp,
  crossfade_samples? : Int = 0,
) -> CompiledStereoDspHotSwap {
  CompiledStereoDspHotSwap(
    @staging.CompiledStereoDspHotSwap::from_graph(
      active.raw(),
      crossfade_samples~,
    ),
  )
}

///|
/// Queue a replacement stereo graph for the next `process(...)` call.
///
/// Returns an error when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn CompiledStereoDspHotSwap::queue_swap(
  self : CompiledStereoDspHotSwap,
  next : CompiledStereoDsp,
) -> Result[Unit, HotSwapQueueError] {
  hot_swap_queue_result_from_staging(self.0.queue_swap(next.raw()))
}

///|
/// Process one block, crossfading between the active and pending stereo graphs
/// when a swap is in flight.
pub fn CompiledStereoDspHotSwap::process(
  self : CompiledStereoDspHotSwap,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  self.0.process(context, left_output, right_output)
}
