# Debug-Feedback Divergence Fix

## Problem

When `debug_validate` is enabled, `CompiledDsp::process` and `CompiledStereoDsp::process` take the debug path (`process_mono_debug` / `process_stereo_debug`) before checking for feedback edges. The debug path calls `process_debug_loop`, which processes nodes block-at-a-time via `process_node_block`. This ignores self-registers and back-edges, producing different output from the production per-sample feedback path (`process_feedback_graph_impl`).

## Fix: Validate-then-delegate

For feedback graphs in debug mode, validate all nodes once per block, then delegate to the existing production feedback processing path.

### `graph_debug.mbt`

1. **New `validate_all_nodes(graph) -> Bool`**: Resets `last_validation_errors`, iterates all nodes calling `validate_node_inputs` and `validate_node_state`, returns true if no errors.

2. **Modified `process_mono_debug`**: If `feedback_edges.length() > 0`, call `validate_all_nodes`. If valid, delegate to `process_feedback_graph`. If invalid, fill output with silence. Sanitize and return.

3. **Modified `process_stereo_debug`**: Same pattern for stereo.

### `graph_property_test.mbt`

Upgrade two property tests from "debug is deterministic for feedback" to "debug equals production for feedback" — compare debug-enabled vs debug-disabled output on the same graph topology.

## Non-goals

- Per-node skip in feedback graphs (skipping one node breaks the feedback chain)
- Per-sample validation (node inputs/state don't change mid-block)
- Changes to `process_debug_loop` or `process_feedback_graph_impl`
