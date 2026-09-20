///|
/// Block-boundary mono graph hot-swap wrapper for `Dsp`.
///
/// Public facade wrapper; implementation lives in `graph/internal/staging`.
struct DspHotSwap(@staging.DspHotSwap)

///|
/// Block-boundary stereo graph hot-swap wrapper for `StereoDsp`.
///
/// Public facade wrapper; implementation lives in `graph/internal/staging`.
struct StereoDspHotSwap(@staging.StereoDspHotSwap)

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
pub fn DspHotSwap::from_graph(
  active : Dsp,
  crossfade_samples? : Int = 0,
) -> DspHotSwap {
  DspHotSwap(@staging.DspHotSwap::from_graph(active.raw(), crossfade_samples~))
}

///|
/// Queue a replacement graph for the next `process(...)` call.
///
/// Returns an error when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn DspHotSwap::queue_swap(
  self : DspHotSwap,
  next : Dsp,
) -> Result[Unit, HotSwapQueueError] {
  hot_swap_queue_result_from_staging(self.0.queue_swap(next.raw()))
}

///|
/// Process one block, crossfading between the active and pending graphs when a
/// swap is in flight.
pub fn DspHotSwap::process(
  self : DspHotSwap,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  self.0.process(context, output)
}

///|
/// Create a hot-swap wrapper around an active stereo compiled graph.
pub fn StereoDspHotSwap::from_graph(
  active : StereoDsp,
  crossfade_samples? : Int = 0,
) -> StereoDspHotSwap {
  StereoDspHotSwap(
    @staging.StereoDspHotSwap::from_graph(active.raw(), crossfade_samples~),
  )
}

///|
/// Queue a replacement stereo graph for the next `process(...)` call.
///
/// Returns an error when the replacement graph is incompatible with the active
/// graph's compile-time sample rate or block capacity.
pub fn StereoDspHotSwap::queue_swap(
  self : StereoDspHotSwap,
  next : StereoDsp,
) -> Result[Unit, HotSwapQueueError] {
  hot_swap_queue_result_from_staging(self.0.queue_swap(next.raw()))
}

///|
/// Process one block, crossfading between the active and pending stereo graphs
/// when a swap is in flight.
pub fn StereoDspHotSwap::process(
  self : StereoDspHotSwap,
  context : DspContext,
  left_output : AudioBuffer,
  right_output : AudioBuffer,
) -> Unit {
  self.0.process(context, left_output, right_output)
}
