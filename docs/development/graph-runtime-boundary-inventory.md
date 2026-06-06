# Graph runtime boundary inventory

Issue #163 asked whether `graph/internal/runtime` should be split into an
audio-hot runtime core plus compile/control support packages. This inventory is
the decision point before any package move.

## Decision

Do **not** split `graph/internal/runtime` in this slice.

The package already has strong file-level separation between audio processing,
compile/validation/diagnostics, runtime control, and debug support. A package
split would add manifests and a new internal API between packages, but the
inventory does not yet show a small stable crossing contract:

- `CompiledGraph`, `CompiledDsp`, and `CompiledStereoDsp` are the shared runtime
  state and wrapper types. Compile, process, control, staging, hot-swap, and
  debug helpers all need access to the same private state.
- `graph_compile.mbt` is the boundary knot: it owns the runtime state type,
  public wrapper constructors, template/raw compile entry points, topological
  planning, state allocation, and runtime-state constructors.
- `graph_runtime_control.mbt` is cold/control-side logic, but applying controls
  mutates the same node array and delay/envelope runtime state that processing
  reads.
- `graph_debug.mbt` is debug/test support, but its process path intentionally
  delegates to the same per-node and feedback process functions for behavioral
  parity.
- Typed compile diagnostics reuse the same topology, feedback-edge remapping,
  and shape validation helpers used by compile rejection.

A split can still be valuable later, but only after a concrete crossing contract
exists. The least risky future direction would be to extract cold compile and
diagnostic helpers behind an explicit `CompiledGraph` construction API. That
should happen only if the package grows enough that the added constructor/API
surface is cheaper than the current private-state locality.

No DSP algorithms or hot process paths were changed for this inventory.

## Existing boundary constraints

This inventory preserves ADR-0010:

- `Array[DspNode]` remains an authoring exchange type.
- `CompiledTemplate` remains the runtime exchange type.
- `CompiledTemplate::analyze(Array[DspNode])` remains the canonical crossing.
- Runtime APIs must not add new bare `Array[DspNode]` public entry points except
  documented topology-controller/authoring carve-outs.

It also preserves ADR-0015:

- `graph/internal/runtime` may depend on `dsp`, `graph/internal/model`, and
  `graph/internal/template`.
- It must not import `identity`, `pattern`, `song`, `mini`, `scheduler`,
  `browser`, or the root facade.
- Public consumers continue to use `dowdiness/moondsp/graph` or the root facade,
  not `graph/internal/runtime`.

## Category key

| Key | Category |
| --- | --- |
| A | audio-hot runtime/process state |
| C | compile/validation/diagnostics |
| R | runtime-control validation/application |
| D | debug/test support |
| S | package/source scaffolding with no runtime behavior |

`S` entries are included because they are files in the package, but they are not
split candidates by themselves.

## File inventory

| File | Category | Notes |
| --- | --- | --- |
| `dsp_using.mbt` | S | Package-local import convenience for DSP runtime types used by A/C/R/D files. |
| `model_using.mbt` | S | Package-local import convenience for model node/control types and validation constants. |
| `template_using.mbt` | S | Package-local import convenience for `CompiledTemplate`. |
| `moon.pkg` | S | Declares the current package dependencies. |
| `pkg.generated.mbti` | S | Generated interface; should stay stable unless an intentional API change is scoped. |
| `graph_buffer_ops.mbt` | A | Allocation-free buffer copy/mix/gain/clip helpers used by process/debug paths. |
| `graph_process.mbt` | A | Block process entry points and block-at-a-time node dispatch. |
| `graph_feedback.mbt` | A | Per-sample feedback process path, feedback self-register helpers, and buffer/state clearing helpers. Contains one shape helper used by validation. |
| `graph_compile.mbt` | A + C | Owns runtime state/wrapper types and compile-time construction/planning. This is the main package-split knot. |
| `graph_validate.mbt` | C | Compile-time shape and input validation for mono/stereo and feedback graphs. |
| `graph_compile_error.mbt` | C | Typed compile-result diagnostics and diagnostic remapping to authoring indices. |
| `graph_runtime_control.mbt` | R + A | Runtime control validation/application. Also contains `is_voice_finished` runtime-state read and delay-state constructor used during compile. |
| `graph_debug.mbt` | D + A | Debug validation toggles/errors and debug process wrappers that reuse production process helpers. |
| `graph_buffer_ops_wbtest.mbt` | D | Whitebox tests for buffer helpers. |
| `graph_debug_wbtest.mbt` | D | Whitebox tests for debug validation behavior. |

## Symbol inventory

### `graph_buffer_ops.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `copy_buffer` | A | Hot/block buffer copy and zero-fill helper. |
| `copy_stereo_buffers` | A | Hot/block stereo copy helper. |
| `mixdown_stereo_buffers` | A | Hot/block stereo-to-mono helper. |
| `fill_constant_buffer` | A | Hot/block constant fill helper. |
| `apply_envelope_gain_buffer` | A | Hot/block envelope modulation helper. |
| `apply_gain_buffer` | A | Hot/block gain helper. |
| `mix_buffers` | A | Hot/block summing helper. |
| `multiply_buffers` | A | Hot/block multiplication helper. |
| `clip_buffer` | A | Hot/block clipping helper. |
| `min_buffer_length` | A | Bounds helper for buffer operations. |

### `graph_process.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `process_node_block` | A | Shared block-at-a-time node dispatch for mono, stereo, and debug mode. |
| `CompiledGraph::run_node_loop` | A | Runs each compiled node for non-feedback graphs. |
| `CompiledDsp::process` | A | Public mono process entry point. |
| `CompiledStereoDsp::process` | A | Public stereo process entry point. |
| `compiled_stereo_sample_count` | A | Bounds helper for stereo processing. |

### `graph_feedback.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `CompiledGraph::process_feedback_graph_impl` | A | Unified per-sample feedback process loop. |
| `CompiledDsp::process_feedback_graph` | A | Mono feedback wrapper. |
| `CompiledStereoDsp::process_feedback_graph` | A | Stereo feedback wrapper. |
| `process_graph_biquad` | A | Biquad update/process helper used by process paths. |
| `CompiledGraph::prepare_feedback_biquads` | A | Per-block coefficient refresh for feedback process. |
| `self_register_input_sample` | A | Mono feedback self-register read helper. |
| `self_register_stereo_input_left` | A | Stereo-left feedback self-register read helper. |
| `self_register_stereo_input_right` | A | Stereo-right feedback self-register read helper. |
| `clip_feedback_sample` | A | Per-sample feedback clipping helper. |
| `reset_graph_env_states` | A | Runtime reset helper used by invalid-process guards. |
| `clear_compiled_buffers` | A | Runtime buffer clearing helper. |
| `is_mono_shape` | C | Shape-validation helper currently colocated in feedback file. It is not itself hot. |

### `graph_compile.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `CompiledGraph` | A | Shared runtime state for mono/stereo compiled graphs; also constructed by compile. |
| `CompiledGraph::compile_sample_rate` | A | Runtime metadata accessor used by control validation. |
| `CompiledGraph::copy_compatible_runtime_state_from` | A | Hot-swap/topology runtime state transfer. |
| `CompiledDsp` | A | Mono runtime wrapper type. |
| `CompiledStereoDsp` | A | Stereo runtime wrapper type. |
| `CompiledDsp::from_graph` | A | Internal wrapper constructor used by staging/hot-swap. |
| `CompiledDsp::raw_graph` | A | Internal graph accessor used by staging/hot-swap. |
| `CompiledStereoDsp::from_graph` | A | Internal stereo wrapper constructor used by staging/hot-swap. |
| `CompiledStereoDsp::raw_graph` | A | Internal stereo graph accessor used by staging/hot-swap. |
| `CompiledDsp::last_sanitized_count` | A | Process-result metadata accessor. |
| `CompiledStereoDsp::last_sanitized_count` | A | Process-result metadata accessor. |
| `CompiledDsp::has_feedback_edges` | A | Runtime topology metadata accessor. |
| `CompiledStereoDsp::has_feedback_edges` | A | Runtime topology metadata accessor. |
| `CompiledDsp::compile` | C | Mono compile from `CompiledTemplate`; constructs A state. |
| `CompiledDsp::compile_raw` | C | Mono raw compile for documented topology-controller carve-out. |
| `compile_graph_impl` | C + A | Shared compile pipeline; allocates buffers/state for runtime. |
| `CompiledDsp::compile_internal` | C | Mono compile implementation. |
| `CompiledStereoDsp::compile` | C | Stereo compile from `CompiledTemplate`; constructs A state. |
| `CompiledStereoDsp::compile_raw` | C | Stereo raw compile for documented topology-controller carve-out. |
| `CompiledStereoDsp::compile_internal` | C | Stereo compile implementation. |
| `stereo_compile_plan` | C | Stereo topology validation/planning and feedback-edge detection. |
| `CompiledGraph::compiled_buffer_capacity` | A | Runtime buffer capacity accessor. |
| `CompiledGraph::compiled_index_for` | A + R | Authoring-to-compiled index lookup used by controls. |
| `CompiledDsp::compiled_buffer_capacity` | A | Mono wrapper capacity accessor. |
| `CompiledStereoDsp::compiled_buffer_capacity` | A | Stereo wrapper capacity accessor. |
| `mono_compile_plan` | C | Mono topology validation/planning and feedback-edge detection. |
| `visit_graph_node_with_feedback` | C | Topological traversal with back-edge detection. |
| `visit_graph_dependencies_with_feedback` | C | Per-node dependency traversal. |
| `visit_graph_input_with_feedback` | C | Input traversal/back-edge recording helper. |
| `find_single_output_index` | C | Mono output lookup. |
| `find_single_output_index_of_kind` | C | Output-kind lookup shared by compile diagnostics. |
| `remapped_feedback_edges` | C | Remap helper shared by compile and diagnostics. |
| `compiled_block_size` | C | Compile-time block-size guard for buffer allocation. |
| `make_graph_osc_state` | C + A | Allocates oscillator runtime state for compile. |
| `make_graph_noise_state` | C + A | Allocates noise runtime state for compile. |
| `make_graph_env_state` | C + A | Allocates ADSR runtime state for compile. |
| `make_graph_biquad_state` | C + A | Allocates mono biquad runtime state for compile. |
| `make_graph_stereo_biquad_state` | C + A | Allocates stereo biquad runtime state for compile. |
| `make_graph_stereo_delay_state` | C + A | Allocates stereo delay runtime state for compile. |

### `graph_validate.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `valid_any_node_inputs` | C | Node input/parameter validation shared by mono/stereo compile. |
| `valid_node_inputs` | C | Mono output-kind validation wrapper. |
| `valid_stereo_node_inputs` | C | Stereo output-kind validation wrapper. |
| `valid_reference` | C | Input index bounds helper shared by diagnostics. |
| `valid_feedback_terminal_mono_graph` | C | Mono feedback shape/terminal validation. |
| `valid_terminal_mono_shapes` | C | Mono non-feedback shape/terminal validation. |
| `valid_terminal_stereo_shapes` | C | Stereo non-feedback shape validation wrapper. |
| `compiled_stereo_shapes` | C | Stereo non-feedback shape inference. |
| `compiled_feedback_stereo_shapes` | C | Stereo feedback shape inference. |
| `feedback_resolved_input_shape` | C | Shape lookup helper that accounts for back-edges. |
| `valid_feedback_terminal_stereo_graph` | C | Stereo feedback shape/terminal validation. |
| `feedback_target_shape` | C | Expected input shape for feedback targets. |
| `input_shape` | C | Bounds-checked shape lookup helper. |

### `graph_compile_error.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `GraphInputSlot` | C | Compile-diagnostic input-slot enum (`Input0`, `Input1`). |
| `GraphCompileError` | C | Typed compile rejection enum. Variants: invalid sample rate, missing/multiple/wrong output, invalid input/param/delay, unreachable node, invalid/duplicate feedback, invalid terminal shape, internal rejection. |
| `Show for GraphCompileError` | C | Diagnostic formatting. |
| `CompiledDsp::compile_result` | C | Mono typed compile entry point. |
| `CompiledStereoDsp::compile_result` | C | Stereo typed compile entry point. |
| `compile_checked_template` | C | Shared typed compile wrapper. |
| `compile_error_for_template` | C | Template-level diagnostic orchestration and remap. |
| `graph_compile_error` | C | Optimized-graph diagnostic pass. |
| `authoring_graph_compile_error` | C | Reachable authoring-graph diagnostic pass before optimization. |
| `mark_reachable` | C | Diagnostic-local reachability helper. |
| `compile_error_inverse_map` | C | Optimized-index to authoring-index map. |
| `remap_compile_index` | C | Index remap helper. |
| `remap_graph_compile_error` | C | Diagnostic remapping to authoring indices. |
| `count_output_kind` | C | Output-kind count helper. |
| `invalid_compile_node` | C | Per-node diagnostic dispatcher. |
| `invalid_oscillator_node` | C | Oscillator diagnostic helper. |
| `invalid_adsr_node` | C | ADSR diagnostic helper. |
| `invalid_biquad_node` | C | Biquad diagnostic helper. |
| `invalid_delay_node` | C | Delay diagnostic helper. |
| `invalid_gain_node` | C | Gain diagnostic helper. |
| `invalid_binary_input_node` | C | Binary-input diagnostic helper. |
| `invalid_unary_positive_param_node` | C | Unary input + positive param diagnostic helper. |
| `invalid_output_node` | C | Output-kind/input diagnostic helper. |
| `invalid_unary_finite_param_node` | C | Unary input + finite param diagnostic helper. |
| `invalid_unary_input_node` | C | Unary input diagnostic helper. |
| `invalid_input` | C | Input bounds diagnostic helper. |
| `invalid_finite_param` | C | Finite parameter diagnostic helper. |
| `invalid_biquad_params` | C | Biquad parameter diagnostic helper. |
| `invalid_delay_params` | C | Delay parameter diagnostic helper. |
| `invalid_feedback_edges` | C | Feedback-edge structural diagnostic helper. |

### `graph_runtime_control.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `GraphControlError` | R | Runtime control rejection enum. Variants: invalid index, orphan node, invalid gate, invalid slot, invalid param value, missing runtime state. |
| `Show for GraphControlError` | R | Diagnostic formatting. |
| `CompiledDsp::apply_control` | R | Mono control application wrapper. |
| `CompiledDsp::apply_controls` | R | Mono transactional batch application wrapper. |
| `CompiledDsp::validate_controls` | R | Mono validation-only wrapper. |
| `CompiledDsp::is_voice_finished` | A | Runtime-state read used for voice reclamation. Not compile/control validation. |
| `CompiledStereoDsp::apply_control` | R | Stereo control application wrapper. |
| `CompiledStereoDsp::apply_controls` | R | Stereo transactional batch application wrapper. |
| `CompiledStereoDsp::validate_controls` | R | Stereo validation-only wrapper. |
| `CompiledGraph::apply_control_impl` | R | Shared control application dispatcher. |
| `CompiledGraph::apply_controls_impl` | R | Shared transactional batch application. |
| `CompiledGraph::validate_controls_impl` | R | Shared validation-only batch pass. |
| `CompiledGraph::compiled_index_result` | R | Control-facing index lookup with typed errors. |
| `apply_graph_gate_control_result` | R | Gate control application. |
| `apply_graph_param_control_result` | R | Parameter control application plus runtime side effects. |
| `valid_graph_control_result` | R | Control validation dispatcher. |
| `valid_graph_gate_control_result` | R | Gate validation. |
| `valid_graph_param_control_result` | R | Parameter validation using simulated nodes for batches. |
| `updated_model_node_param_result` | R | Public internal helper for validating/model-updating a parameter control. |
| `updated_model_node_param` | R | Per-node parameter update rules. |
| `apply_runtime_param_side_effect` | R + A | Applies runtime state side effects after accepted parameter control. |
| `exact_int_value` | R | `Double` to exact `Int` helper for delay samples. |
| `apply_stereo_delay_param_side_effect` | R + A | Updates stereo delay runtime state after accepted parameter control. |
| `make_graph_delay_state` | C + A | Allocates mono delay runtime state for compile. It lives here because delay side effects are also controlled here. |

### `graph_debug.mbt`

| Symbol | Category | Notes |
| --- | --- | --- |
| `MAX_DEBUG_ERRORS` | D | Debug error cap. |
| `GraphValidationError` | D | Debug validation error enum (`InvalidInput0`, `InvalidInput1`, `InvalidStateIndex`). |
| `Show for GraphValidationError` | D | Debug diagnostic formatting. |
| `CompiledDsp::enable_debug_validation` | D | Mono debug toggle. |
| `CompiledDsp::disable_debug_validation` | D | Mono debug toggle/reset. |
| `CompiledDsp::last_validation_errors` | D | Mono debug error accessor. |
| `CompiledStereoDsp::enable_debug_validation` | D | Stereo debug toggle. |
| `CompiledStereoDsp::disable_debug_validation` | D | Stereo debug toggle/reset. |
| `CompiledStereoDsp::last_validation_errors` | D | Stereo debug error accessor. |
| `validate_node_inputs` | D | Debug-only input bounds validation. |
| `validate_node_state` | D | Debug-only state presence validation. |
| `process_debug_loop` | D + A | Debug process loop that delegates to production node processing. |
| `validate_all_nodes` | D | Debug preflight for feedback graphs. |
| `CompiledDsp::process_mono_debug` | D + A | Debug mono process wrapper. |
| `CompiledStereoDsp::process_stereo_debug` | D + A | Debug stereo process wrapper. |

### Whitebox tests

| File / symbol | Category | Notes |
| --- | --- | --- |
| `graph_buffer_ops_wbtest.mbt` tests | D | Cover buffer helper bounds/zero-fill, gain, mix, multiply, clip, stereo copy, mixdown. |
| `graph_debug_wbtest.mbt::corrupt_input0` | D | Test helper that intentionally mutates private runtime state. |
| `debug: invalid input0 produces InvalidInput0 error` | D | Debug validation error regression. |
| `debug: skipped node outputs silence, downstream processes normally` | D | Debug skip/silence behavior regression. |
| `debug: errors reset on next process call` | D | Debug error lifecycle regression. |
| `debug: feedback graph validation failure yields silence and records errors` | D | Debug feedback preflight regression. |
| `debug: multiple errors in one block` | D | Debug multi-error behavior regression. |

## Split analysis

### What would move cleanly

- `graph_validate.mbt` and most of `graph_compile_error.mbt` are cold compile
  and diagnostic logic.
- `graph_buffer_ops.mbt`, `graph_process.mbt`, and most of
  `graph_feedback.mbt` are audio process logic.
- Most of `graph_runtime_control.mbt` is runtime-control logic.
- `graph_debug.mbt` is debug support.

### What blocks a low-cost package split

- **Private runtime state access.** Control, debug, process, hot-swap, and
  compile construction all read or mutate `CompiledGraph` internals. Splitting
  packages would require exposing constructor and mutation/accessor APIs that do
  not exist today.
- **Compile constructs the core.** A `runtime_core` package would need to own
  the runtime types, but a separate compile package would still have to allocate
  every buffer/state field and initialize feedback scratch arrays. That crossing
  API would be large and easy to drift from the private field layout.
- **Control mutates process-visible state.** Accepted `GraphControl` messages
  update model nodes and delay runtime state in place. Moving control out of the
  core would require dedicated mutation hooks or exposed state arrays.
- **Debug intentionally shares processing.** Debug mode is not an independent
  interpreter; it validates and then calls the production process helpers. A
  separate debug package would need access to both process helpers and private
  state.
- **Diagnostics reuse compile planning.** Typed errors reuse output lookup,
  topological traversal, feedback-edge remapping, and shape validation. Splitting
  diagnostics from compile would duplicate or expose these helpers.

## Recommended guardrails

- Keep the current package shape for now.
- Treat `graph_compile.mbt` as the first future extraction target only if a
  stable `CompiledGraph` construction contract is designed first.
- Prefer file-local cleanup before package extraction. For example, shape-only
  helpers should live with validation if they are touched for other reasons.
- If a future change moves hot-path code, run the relevant graph benchmarks
  before and after. This inventory did not move hot-path code, so no benchmark
  comparison is attached.

## Verification run for this inventory

- `moon update`
- `moon check`
- `scripts/check-public-boundary.sh`
- `scripts/check-architecture-boundaries.sh`
