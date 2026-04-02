# Debug Validation Mode for Graph Processing

**Date:** 2026-04-02
**Status:** Approved (revised after Codex review)
**Motivation:** Audit finding R1 — the graph process loop accesses `buffers[node.input0]` without runtime bounds checks, relying entirely on compile-time validation. Hot-swap and topology editing introduce runtime mutation through index remapping. One remapping bug would cause silent out-of-bounds access. A debug mode catches these during development.

## Problem

Every node in the process loop accesses `buffers[node.input0]` and `buffers[node.input1]` without runtime bounds checking. Safety depends on compile-time validation (`valid_reference()`) and correct index map composition after optimization and topology editing. If any of these invariants are violated, the result is an out-of-bounds array access with no diagnostic.

The NaN firewall (already shipped) catches corruption at the output boundary but cannot diagnose which node caused it. Debug validation mode fills that gap — it validates buffer indices before each access and reports exactly where the violation is.

## Design

### Flag on CompiledGraph

```moonbit
mut debug_validate : Bool  // default: false
mut last_validation_errors : Array[GraphValidationError]
```

Added to the private `CompiledGraph` struct. When `debug_validate` is false (default), the process function takes the fast path — the existing loop runs structurally unchanged. When true, a separate debug loop runs with per-node validation.

### GraphValidationError

```moonbit
pub(all) enum GraphValidationError {
  InvalidInput0(Int, Int, Int)        // (node_index, input0_value, max_valid)
  InvalidInput1(Int, Int, Int)        // (node_index, input1_value, max_valid)
  InvalidStateIndex(Int, String)      // (node_index, state_kind)
} derive(Show, Eq)
```

- **InvalidInput0/InvalidInput1:** The node at `node_index` has an `input0` or `input1` value outside `[0, buffers.length())`. `max_valid` is `buffers.length() - 1`.
- **InvalidStateIndex:** The node at `node_index` expects state of type `state_kind` (e.g., "osc", "biquad", "delay", "env") but the state array has `None` at that index. The kind string identifies which state store failed.

### Error storage

Errors are stored in a pre-allocated `Array[GraphValidationError]` on `CompiledGraph`. To prevent unbounded allocation on the audio thread, errors are capped at 32 per block. Once the cap is reached, further violations are counted but not recorded. The error array is cleared at the start of each `process()` call — `last_validation_errors()` returns errors from the most recent block only.

```moonbit
const MAX_DEBUG_ERRORS : Int = 32
```

### Public API

```moonbit
pub fn CompiledDsp::enable_debug_validation(self : CompiledDsp) -> Unit
pub fn CompiledDsp::disable_debug_validation(self : CompiledDsp) -> Unit
pub fn CompiledDsp::last_validation_errors(self : CompiledDsp) -> Array[GraphValidationError]
```

Same three methods on `CompiledStereoDsp`.

### Core invariant

**Validation runs before any buffer read or state mutation.** When debug mode is enabled, each node is validated before any of its processing code executes. This guarantees:
- No partial state mutation on invalid nodes (oscillator phase, delay write position, etc. are not advanced)
- No stale data in the node's output buffer (it is filled with silence before continuing)
- Downstream nodes see deterministic 0.0 from skipped nodes, not garbage

### How validation runs

The `process()` function checks `debug_validate` once at the top:

1. If `!self.0.debug_validate` — **fast path:** the existing process loop runs structurally unchanged. No validation helpers are called. No per-node branches are added. The compiled code shape is preserved.

2. If `self.0.debug_validate` — **debug path:** a separate `process_debug()` private function runs. This function:
   - Clears `last_validation_errors`
   - Iterates nodes in the same topological order
   - Before each node: validates `input0`/`input1` bounds and state presence
   - On violation: records error (up to cap), fills output buffer with 0.0, skips to next node
   - On valid: processes normally

This two-path design ensures the fast path is never polluted by debug logic, even at the IR/optimization level.

### Implementation approach

Validation helpers (called only from the debug path):

```moonbit
fn validate_node_inputs(
  node : DspNode,
  node_index : Int,
  buffer_count : Int,
  errors : Array[GraphValidationError],
) -> Bool  // true = valid, false = skip this node
```

For state validation, pass the compiled graph context rather than individual arrays:

```moonbit
fn validate_node_state(
  graph : CompiledGraph,
  node : DspNode,
  node_index : Int,
  errors : Array[GraphValidationError],
) -> Bool
```

This avoids the wide parameter list. The helper inspects the relevant state store based on `node.kind`.

### Hot-swap and topology editing

The `debug_validate` flag lives on the `CompiledGraph` instance. When hot-swap replaces the active graph, the new graph starts with `debug_validate = false`. The caller must re-enable debug validation after graph replacement if needed. This is documented in the API:

> Debug validation does not survive graph replacement (hot-swap, topology edit recompilation). Re-enable after calling `queue_swap` or `queue_topology_edit` if needed.

### What it does NOT do

- **No NaN checking** — that's the NaN firewall's job (already shipped)
- **No topology validation** — that's compile-time
- **No performance optimization** — debug mode is explicitly for development, not production
- **No feedback graph validation** — feedback paths use `self_register_input_sample` with their own bounds logic. Extending to feedback graphs is a future enhancement if needed.
- **No VoicePool validation** — VoicePool calls `CompiledDsp::process` per voice, which inherits the debug flag. No separate VoicePool debug mode needed.

### Performance

When `debug_validate` is false: one bool check per `process()` call, then the existing loop runs unchanged. Branch predictor trains on "not taken" immediately. No measurable overhead — the fast path code shape is identical to pre-debug-mode code.

When `debug_validate` is true: one bounds check per node per buffer access (2-3 comparisons per node, ~20 nodes typical). Plus state array None checks. Roughly 2x slower than normal processing. Acceptable for debug/development use.

## Testing

1. **Debug off by default:** New CompiledDsp has empty validation errors
2. **Valid graph produces no errors:** Enable debug, process clean graph, errors is empty
3. **Invalid input0 detected:** Manually corrupt a node's input0 after compilation, process with debug, verify InvalidInput0 error with correct indices
4. **Invalid input1 detected:** Same for input1 (Mul/Mix nodes)
5. **Invalid state detected:** Corrupt a node kind to expect state that doesn't exist, verify InvalidStateIndex with correct state_kind
6. **Errors reset each process call:** Process with error, process again with valid graph, verify errors cleared
7. **Error cap respected:** Corrupt many nodes, verify at most 32 errors recorded
8. **Multiple errors in one block:** Two bad nodes produce two errors in one process call
9. **Stereo variant works:** Same validation on CompiledStereoDsp
10. **Skip node on error:** When a node has invalid input, its output buffer is silence, downstream nodes process normally with 0.0 input
11. **Enable/disable toggle:** Enable, process, disable, process, verify second call has no errors and runs fast path
12. **Debug flag does not survive hot-swap:** Replace graph, verify debug_validate is false on new graph
