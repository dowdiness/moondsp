/// # Threading Contract for Browser WASM Exports
///
/// All exported functions assume **single-threaded access** per graph variant.
/// The `@ref.Ref` globals below carry mutable graph state across JavaScript
/// calls and provide no synchronization primitives.
///
/// ## Expected call pattern
///
/// 1. **`init_*_graph(sample_rate, block_size)`** -- call once from the main
///    thread before audio starts. This allocates the graph, context, and
///    output buffers.
/// 2. **`process_*_block(...)`** -- call from the AudioWorklet `process()`
///    callback (audio thread). Must not overlap with any other call on the
///    same graph variant.
/// 3. **`queue_*` / `set_*`** -- call from the main thread only between
///    process calls. Use AudioWorklet `port.postMessage` to synchronize.
/// 4. **`*_sample(index)`** -- call only after `process_*_block` returns
///    `true` and before the next process call, to read output samples.
///
/// ## No concurrent access guarantee
///
/// If `init_*` is called while `process_*` is executing, behavior is
/// undefined (potential use-after-free of graph state). The same applies to
/// any pair of exported functions that touch the same `@ref.Ref` globals
/// concurrently.
///
/// ## Re-initialization
///
/// Calling `init_*` with different `sample_rate`/`block_size` rebuilds the
/// graph from scratch; the old graph is discarded. This must never happen
/// during a `process_*` call.

///|
let demo : @ref.Ref[@lib.DemoSource] = @ref.new(@lib.DemoSource::new())

///|
/// Browser-export wrapper package that preserves the original Phase 0/1 wasm ABI.
fn main {
  ()
}

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

///|
const BROWSER_COMPILED_DEFAULT_FREQ : Double = 440.0

///|
const BROWSER_COMPILED_DEFAULT_GAIN : Double = 0.3

///|
const BROWSER_COMPILED_CLIP_THRESHOLD : Double = 0.95

///|
const BROWSER_COMPILED_DEFAULT_PAN : Double = 0.0

///|
const BROWSER_COMPILED_DEFAULT_CUTOFF : Double = 1800.0

///|
const BROWSER_COMPILED_FILTER_Q : Double = 0.707

///|
const BROWSER_COMPILED_DELAY_CAPACITY : Int = 128

///|
const BROWSER_COMPILED_DELAY_SAMPLES : Int = 0

///|
const BROWSER_COMPILED_OSC_GAIN : Double = 0.2

///|
const BROWSER_COMPILED_MAX_FEEDBACK_GAIN : Double = 0.95

///|
const BROWSER_HOT_SWAP_OLD_CONSTANT : Double = 0.25

///|
const BROWSER_HOT_SWAP_NEW_CONSTANT : Double = 0.75

///|
const BROWSER_HOT_SWAP_CROSSFADE_SAMPLES : Int = 128

///|
const BROWSER_TOPOLOGY_EDIT_INSERTED_GAIN : Double = 0.5

///|
const BROWSER_TOPOLOGY_EDIT_CROSSFADE_SAMPLES : Int = 1024

///|
const BROWSER_STEREO_HOT_SWAP_OLD_CONSTANT : Double = 0.25

///|
const BROWSER_STEREO_HOT_SWAP_NEW_CONSTANT : Double = 0.75

///|
const BROWSER_STEREO_HOT_SWAP_CROSSFADE_SAMPLES : Int = 128

///|
const BROWSER_STEREO_TOPOLOGY_EDIT_OLD_PAN : Double = 0.0

///|
const BROWSER_STEREO_TOPOLOGY_EDIT_NEW_PAN : Double = 1.0

///|
const BROWSER_STEREO_TOPOLOGY_EDIT_CROSSFADE_SAMPLES : Int = 128

// ---------------------------------------------------------------------------
// Demo tick passthrough
// ---------------------------------------------------------------------------

///|
/// Reset browser demo state.
pub fn reset_phase() -> Unit {
  demo.val.reset()
  reset_compiled_graph()
  reset_compiled_hot_swap_graph()
  reset_compiled_topology_edit_graph()
  reset_compiled_stereo_graph()
  reset_compiled_stereo_hot_swap_graph()
  reset_compiled_stereo_topology_edit_graph()
  reset_exit_deliverable_graph()
  reset_scheduler_graph()
}

///|
/// Generate one sine sample for the browser demo.
pub fn tick(freq : Double, sample_rate : Double) -> Double {
  demo.val.tick_source(0, freq, sample_rate)
}

///|
/// Generate one sample from the selected browser demo source.
pub fn tick_source(
  source_id : Int,
  freq : Double,
  sample_rate : Double,
) -> Double {
  demo.val.tick_source(source_id, freq, sample_rate)
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

///|
/// Clamp gain to safe feedback range, replacing NaN/Inf with default.
fn bounded_feedback_gain(gain : Double) -> Double {
  if gain.is_nan() || gain.is_inf() {
    BROWSER_COMPILED_DEFAULT_GAIN
  } else if gain < 0.0 {
    0.0
  } else if gain > BROWSER_COMPILED_MAX_FEEDBACK_GAIN {
    BROWSER_COMPILED_MAX_FEEDBACK_GAIN
  } else {
    gain
  }
}
