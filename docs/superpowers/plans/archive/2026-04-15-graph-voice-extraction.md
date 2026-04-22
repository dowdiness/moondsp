# Graph & Voice Package Extraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract graph/ and voice/ packages from the lib/ monolith, making lib/ a pure re-export facade.

**Architecture:** Move all graph_*.mbt + control_binding.mbt to a new `graph/` package (depends on `dsp/`). Move voice.mbt to a new `voice/` package (depends on `graph/` and `dsp/`). lib/ becomes a zero-logic facade using `pub using` to re-export all three packages. All downstream consumers (scheduler/, browser/, browser_test/, root) continue importing lib/ unchanged.

**Tech Stack:** MoonBit, `pub using` facade pattern for zero-breakage package splits.

**Codex review incorporated:** Pan gain functions relocated to dsp/ instead of made pub in graph/. Graph package gets local `using @dsp` for unqualified DSP names. Moved test files get explicit `using` declarations. Final API check uses symbol coverage comparison, not raw mbti diff.

---

## File Structure

### Modified: `dsp/` package

- `dsp/pan.mbt` — add `pub fn pan_left_gain(Double) -> Double` and `pub fn pan_right_gain(Double) -> Double` (extracted from graph_feedback.mbt's `feedback_pan_left_gain`/`feedback_pan_right_gain`; these are pure equal-power pan math, not graph-specific)

### New: `graph/` package

Source files (moved from lib/):
- `graph/control_binding.mbt`
- `graph/graph_buffer_ops.mbt`
- `graph/graph_builder.mbt`
- `graph/graph_compile.mbt`
- `graph/graph_controllable.mbt`
- `graph/graph_debug.mbt`
- `graph/graph_debuggable.mbt`
- `graph/graph_feedback.mbt`
- `graph/graph_hotswap.mbt`
- `graph/graph_node.mbt`
- `graph/graph_optimize.mbt`
- `graph/graph_process.mbt`
- `graph/graph_runtime_control.mbt`
- `graph/graph_topology_controller.mbt`
- `graph/graph_topology_edit.mbt`
- `graph/graph_topology_edit_apply.mbt`
- `graph/graph_traits.mbt`
- `graph/graph_validate.mbt`

New:
- `graph/dsp_using.mbt` — `using @dsp { ... }` declarations so moved source files can continue using unqualified DSP names (`AudioBuffer`, `DspContext`, `Waveform`, etc.)
- `graph/moon.pkg`

Test files (moved from lib/):
- `graph/control_binding_test.mbt`
- `graph/graph_benchmark.mbt`
- `graph/graph_buffer_ops_wbtest.mbt`
- `graph/graph_builder_test.mbt`
- `graph/graph_compile_test.mbt`
- `graph/graph_debug_test.mbt`
- `graph/graph_debug_wbtest.mbt`
- `graph/graph_feedback_test.mbt`
- `graph/graph_hotswap_test.mbt`
- `graph/graph_node_test.mbt`
- `graph/graph_optimize_test.mbt`
- `graph/graph_process_test.mbt`
- `graph/graph_property_test.mbt`
- `graph/graph_runtime_control_test.mbt`
- `graph/graph_stereo_test.mbt`
- `graph/graph_test_helpers_test.mbt`
- `graph/graph_topology_edit_test.mbt`
- `graph/graph_traits_test.mbt`

### New: `voice/` package

Source files (moved from lib/):
- `voice/voice.mbt`

Test files (moved from lib/):
- `voice/voice_test.mbt`
- `voice/voice_wbtest.mbt`

New:
- `voice/moon.pkg`

### Modified: `lib/` (pure facade)

Remaining files:
- `lib/reexport.mbt` (renamed from `lib/dsp_reexport.mbt`, expanded to cover graph/ and voice/)
- `lib/integration_test.mbt` (unchanged — tests cross-package integration via facade)
- `lib/tagless_test.mbt` (unchanged — tests tagless algebra via facade)
- `lib/moon.pkg` (updated imports)

### Key dependency chain

```
dsp/          (zero internal deps — includes pan_left_gain/pan_right_gain)
  ^
graph/        (imports dsp/)
  ^       ^
voice/    |   (imports graph/ + dsp/)
  ^       |
lib/          (facade: pub using dsp/ + graph/ + voice/)
  ^
scheduler/, browser/, browser_test/, root package
```

---

## Task 1: Move pan gain functions to dsp/

**Files:**
- Modify: `dsp/pan.mbt` (add two pub functions)
- Modify: `lib/graph_feedback.mbt` (replace local definitions with calls to `@dsp.pan_left_gain`/`@dsp.pan_right_gain`)
- Modify: `lib/voice.mbt` (replace `feedback_pan_left_gain` → `@dsp.pan_left_gain`, same for right)

- [ ] **Step 1: Add pan_left_gain and pan_right_gain to dsp/pan.mbt**

Append to the end of `dsp/pan.mbt`:

```moonbit
///|
/// Equal-power left-channel gain for a pan position in [-1.0, 1.0].
/// -1.0 = hard left (gain 1.0), 0.0 = center (~0.707), 1.0 = hard right (gain 0.0).
/// Non-finite positions return 0.0.
pub fn pan_left_gain(position : Double) -> Double {
  if !is_finite(position) {
    0.0
  } else {
    let clamped = position.clamp(min=-1.0, max=1.0)
    if clamped <= -1.0 {
      1.0
    } else if clamped >= 1.0 {
      0.0
    } else {
      let angle = (clamped + 1.0) * @math.PI * 0.25
      @math.cos(angle)
    }
  }
}

///|
/// Equal-power right-channel gain for a pan position in [-1.0, 1.0].
/// -1.0 = hard left (gain 0.0), 0.0 = center (~0.707), 1.0 = hard right (gain 1.0).
/// Non-finite positions return 0.0.
pub fn pan_right_gain(position : Double) -> Double {
  if !is_finite(position) {
    0.0
  } else {
    let clamped = position.clamp(min=-1.0, max=1.0)
    if clamped <= -1.0 {
      0.0
    } else if clamped >= 1.0 {
      1.0
    } else {
      let angle = (clamped + 1.0) * @math.PI * 0.25
      @math.sin(angle)
    }
  }
}
```

- [ ] **Step 2: Run moon check on dsp/**

```bash
moon check
```

- [ ] **Step 3: Update lib/graph_feedback.mbt to delegate to dsp/**

Replace the two function bodies:

```moonbit
fn feedback_pan_left_gain(position : Double) -> Double {
  pan_left_gain(position)
}

fn feedback_pan_right_gain(position : Double) -> Double {
  pan_right_gain(position)
}
```

These now delegate to the dsp/ versions (available unqualified via `pub using @dsp` in lib/).

- [ ] **Step 4: Update lib/dsp_reexport.mbt to re-export the new functions**

Add to the existing `pub using @dsp { ... }` block:

```moonbit
  pan_left_gain,
  pan_right_gain,
```

- [ ] **Step 5: Run moon check && moon test**

```bash
moon check && moon test
```

Expected: all 532 tests pass. Pan behavior unchanged — same math, just relocated.

- [ ] **Step 6: Commit**

```bash
git add dsp/pan.mbt lib/graph_feedback.mbt lib/dsp_reexport.mbt
git commit -m "refactor: extract equal-power pan gain functions to dsp/pan.mbt"
```

---

## Task 2: Create graph/ package and move source files

**Files:**
- Create: `graph/moon.pkg`
- Create: `graph/dsp_using.mbt`
- Move: 18 source files from `lib/` to `graph/`

- [ ] **Step 1: Create graph/moon.pkg**

```
import {
  "dowdiness/moondsp/dsp" @dsp,
  "moonbitlang/core/bench" @bench,
  "moonbitlang/core/math" @math,
  "moonbitlang/core/ref" @ref,
}

import {
  "moonbitlang/core/double" @double,
  "moonbitlang/quickcheck" @qc,
} for "test"
```

- [ ] **Step 2: Create graph/dsp_using.mbt**

This file provides unqualified access to dsp/ types so that moved graph source files compile without edits. Whitebox and blackbox tests in graph/ also see these declarations (whitebox via shared scope, blackbox via the package's public surface).

```moonbit
///|
/// Import dsp/ types so graph source files can use them unqualified.
/// This replaces the implicit access they had when living inside lib/
/// (which had `pub using @dsp { ... }`).
using @dsp {
  type AudioBuffer,
  type DspContext,
  type Mono,
  type Stereo,
  type Oscillator,
  type Noise,
  type Adsr,
  type Biquad,
  type DelayLine,
  type ParamSmoother,
  type Gain,
  type Clip,
  type Mix,
  type Pan,
  type Waveform,
  type BiquadMode,
  type EnvStage,
}
```

Note: free functions from dsp/ (`is_finite`, `sanitize_buffer`, `effective_sample_count`, etc.) cannot be imported via `using` — they need `@dsp.` prefix or must be called unqualified only if the package re-exports them. Check whether graph source files call these unqualified; if so, add wrapper functions or use `@dsp.` prefix.

**Known unqualified dsp/ function calls in graph source files:**
- `is_finite(...)` — used in graph_feedback.mbt, graph_validate.mbt
- `is_finite_positive(...)` — used in graph_process.mbt
- `effective_sample_count(...)` — used in graph_process.mbt
- `sanitize_buffer(...)` — used in graph_process.mbt, graph_debug.mbt
- `mono_shape()` / `stereo_shape()` — used in graph_traits.mbt
- `max_feedback_amount()` — used in graph_feedback.mbt
- `pan_left_gain(...)` / `pan_right_gain(...)` — used in graph_feedback.mbt (after Task 1)

These must be prefixed with `@dsp.` in the moved files, OR re-declared as thin wrappers in graph/. The `@dsp.` prefix approach is cleaner — do a search-and-replace.

- [ ] **Step 3: Move all graph source files**

```bash
mkdir -p graph
for f in control_binding graph_buffer_ops graph_builder graph_compile \
         graph_controllable graph_debug graph_debuggable graph_feedback \
         graph_hotswap graph_node graph_optimize graph_process \
         graph_runtime_control graph_topology_controller graph_topology_edit \
         graph_topology_edit_apply graph_traits graph_validate; do
  git mv "lib/${f}.mbt" "graph/${f}.mbt"
done
```

- [ ] **Step 4: Prefix unqualified dsp/ free function calls in graph source files**

In the moved graph/ files, prefix all unqualified dsp/ function calls:

- `is_finite(` → `@dsp.is_finite(`
- `is_finite_positive(` → `@dsp.is_finite_positive(`
- `effective_sample_count(` → `@dsp.effective_sample_count(`
- `sanitize_buffer(` → `@dsp.sanitize_buffer(`
- `mono_shape()` → `@dsp.mono_shape()`
- `stereo_shape()` → `@dsp.stereo_shape()`
- `max_feedback_amount()` → `@dsp.max_feedback_amount()`
- `pan_left_gain(` → `@dsp.pan_left_gain(`
- `pan_right_gain(` → `@dsp.pan_right_gain(`

Also in graph_feedback.mbt, delete the now-delegating `feedback_pan_left_gain`/`feedback_pan_right_gain` functions and replace their call sites with `@dsp.pan_left_gain`/`@dsp.pan_right_gain`.

- [ ] **Step 5: Run moon check**

```bash
moon check
```

Expected: graph/ package compiles. lib/ will have errors about missing graph types — that's expected since we haven't updated the facade yet. voice.mbt still in lib/ will also fail since `feedback_pan_left_gain` was removed.

Fix any unexpected errors in graph/ iteratively.

---

## Task 3: Update lib/ facade to re-export graph/ and fix voice.mbt

**Files:**
- Modify: `lib/moon.pkg` (add graph/ dependency)
- Rename: `lib/dsp_reexport.mbt` → `lib/reexport.mbt`
- Modify: `lib/reexport.mbt` (add graph re-exports)
- Modify: `lib/voice.mbt` (replace `feedback_pan_*` with `pan_left_gain`/`pan_right_gain`)

- [ ] **Step 1: Add graph/ import to lib/moon.pkg**

```
import {
  "dowdiness/moondsp/dsp" @dsp,
  "dowdiness/moondsp/graph" @graph,
  "moonbitlang/core/int" @int,
  "moonbitlang/core/ref" @ref,
}

import {
  "moonbitlang/core/double" @double,
  "moonbitlang/quickcheck" @qc,
} for "test"
```

Note: `@bench`, `@math` move to graph/moon.pkg. lib/ keeps `@int` (used by voice.mbt) and `@ref` (check if still used — if not, remove).

- [ ] **Step 2: Rename dsp_reexport.mbt and add graph re-exports**

```bash
git mv lib/dsp_reexport.mbt lib/reexport.mbt
```

Add graph re-exports to `lib/reexport.mbt`. Full file contents:

```moonbit
///|
/// Re-export all public symbols from dsp/, graph/, and voice/ so that
/// existing consumers of lib/ continue to work without changing imports.

///|
// Foundation types from dsp/
pub using @dsp {
  type AudioBuffer,
  type DspContext,
  type Mono,
  type Stereo,

  // DSP primitives — stateful
  type Oscillator,
  type Noise,
  type Adsr,
  type Biquad,
  type DelayLine,
  type ParamSmoother,

  // DSP primitives — stateless
  type Gain,
  type Clip,
  type Mix,
  type Pan,

  // Enums
  type Waveform,
  type BiquadMode,
  type EnvStage,

  // Tagless algebra traits
  trait ArithSym,
  trait DspSym,
  trait FilterSym,
  trait DelaySym,
  trait StereoSym,
  trait StereoFilterSym,
  trait StereoDelaySym,
  trait ChannelSpec,

  // Utility functions
  is_finite,
  is_finite_positive,
  effective_sample_count,
  sanitize_buffer,
  mono_shape,
  stereo_shape,
  max_feedback_amount,
  pan_left_gain,
  pan_right_gain,

  // Tagless compositions
  exit_deliverable,
  range,
  lin_map,

  // Demo
  type DemoSource,
}

///|
// Compiled graph runtime from graph/
pub using @graph {
  // Core graph types
  type CompiledDsp,
  type CompiledDspHotSwap,
  type CompiledDspTopologyController,
  type CompiledStereoDsp,
  type CompiledStereoDspHotSwap,
  type CompiledStereoDspTopologyController,
  type DspNode,
  type DspNodeKind,
  type GraphBuilder,
  type GraphControl,
  type GraphControlKind,
  type GraphParamSlot,
  type GraphTopologyEdit,
  type GraphTopologyInputSlot,
  type GraphValidationError,

  // Control binding
  type ControlBinding,
  type ControlBindingBuilder,
  type ControlBindingError,
  type ControlBindingMap,

  // Traits
  trait GraphControllable,
  trait GraphDebuggable,
  trait NodeEditable,
  trait NodeFoldable,
  trait NodeSpanning,
  trait NodeStateful,

  // Functions
  node_accepts_slot,
  optimize_graph,
  replay,
}
```

- [ ] **Step 3: Fix lib/voice.mbt — replace removed pan functions**

In `lib/voice.mbt`, replace all 4 occurrences:
- `feedback_pan_left_gain(` → `pan_left_gain(`
- `feedback_pan_right_gain(` → `pan_right_gain(`

These are now available unqualified via `pub using @dsp { pan_left_gain, pan_right_gain }`.

Also delete the comment block about "feedback_pan_*" historical naming (lines 62-65 in voice.mbt).

- [ ] **Step 4: Run moon check**

```bash
moon check
```

Expected: lib/ compiles. voice.mbt resolves graph types through `pub using @graph` and pan functions through `pub using @dsp`. Fix any errors iteratively.

---

## Task 4: Move graph test files and fix references

**Files:**
- Move: 18 test files from `lib/` to `graph/`
- Modify: `graph/graph_builder_test.mbt` (replace `@lib.` → graph-local or `@dsp.`)
- Modify: `graph/graph_optimize_test.mbt` (same)

- [ ] **Step 1: Move all graph test files**

```bash
for f in control_binding_test graph_benchmark graph_buffer_ops_wbtest \
         graph_builder_test graph_compile_test graph_debug_test \
         graph_debug_wbtest graph_feedback_test graph_hotswap_test \
         graph_node_test graph_optimize_test graph_process_test \
         graph_property_test graph_runtime_control_test graph_stereo_test \
         graph_test_helpers_test graph_topology_edit_test graph_traits_test; do
  git mv "lib/${f}.mbt" "graph/${f}.mbt"
done
```

- [ ] **Step 2: Fix @lib. references in graph/graph_builder_test.mbt**

This file has 114 occurrences of `@lib.`. Replace with:
- `@lib.GraphBuilder` → `GraphBuilder` (graph-local type)
- `@lib.ArithSym` → `@dsp.ArithSym` (dsp/ trait)
- `@lib.DspSym` → `@dsp.DspSym`
- `@lib.FilterSym` → `@dsp.FilterSym`
- `@lib.DelaySym` → `@dsp.DelaySym`
- `@lib.StereoSym` → `@dsp.StereoSym`
- `@lib.StereoFilterSym` → `@dsp.StereoFilterSym`
- `@lib.StereoDelaySym` → `@dsp.StereoDelaySym`
- `@lib.DspNodeKind` → `DspNodeKind` (graph-local)
- `@lib.DspNode` → `DspNode` (graph-local)
- `@lib.Waveform` → `Waveform` (available via graph/dsp_using.mbt)
- `@lib.BiquadMode` → `BiquadMode` (available via graph/dsp_using.mbt)

- [ ] **Step 3: Fix @lib. references in graph/graph_optimize_test.mbt**

Same pattern — 32 occurrences. Replace `@lib.` with:
- Graph-local types (DspNode, DspNodeKind, GraphParamSlot, etc.) → remove prefix
- dsp/ types (Waveform, BiquadMode) → available unqualified via dsp_using.mbt

- [ ] **Step 4: Check all other moved blackbox tests for unqualified DSP names**

Moved blackbox tests (`*_test.mbt`) previously got unqualified DSP names from lib/'s `pub using @dsp`. Now in graph/, they get them from `graph/dsp_using.mbt` — but only if the `using` declarations are visible to blackbox tests.

**Important MoonBit semantics:** Blackbox tests (`_test.mbt`) see only the package's PUBLIC API. The `using @dsp { ... }` in `graph/dsp_using.mbt` is a *private* `using` (no `pub` prefix), so it makes types available within graph/'s source scope but NOT to blackbox tests.

**Fix:** Either:
- (a) Change to `pub using @dsp { ... }` in `graph/dsp_using.mbt` — this re-exports dsp types through graph/ (acceptable, they're already public in dsp/)
- (b) Add `using @dsp { ... }` declarations at the top of each blackbox test file that needs them

Option (a) is simpler. If it causes unwanted re-exports in graph/'s mbti, use option (b) instead.

- [ ] **Step 5: Run moon check && moon test**

```bash
moon check && moon test
```

Expected: all graph tests pass. Fix any remaining reference errors iteratively — `moon check` error messages identify exactly which symbols are unresolved.

- [ ] **Step 6: Commit**

```bash
git add -A graph/ lib/
git commit -m "refactor: extract graph/ package from lib/ monolith"
```

---

## Task 5: Create voice/ package and move source + test files

**Files:**
- Create: `voice/moon.pkg`
- Move: `lib/voice.mbt` → `voice/voice.mbt`
- Move: `lib/voice_test.mbt` → `voice/voice_test.mbt`
- Move: `lib/voice_wbtest.mbt` → `voice/voice_wbtest.mbt`
- Modify: all three to add cross-package references

- [ ] **Step 1: Create voice/moon.pkg**

```
import {
  "dowdiness/moondsp/dsp" @dsp,
  "dowdiness/moondsp/graph" @graph,
  "moonbitlang/core/int" @int,
}
```

- [ ] **Step 2: Move voice files**

```bash
mkdir -p voice
git mv lib/voice.mbt voice/voice.mbt
git mv lib/voice_test.mbt voice/voice_test.mbt
git mv lib/voice_wbtest.mbt voice/voice_wbtest.mbt
```

- [ ] **Step 3: Add using declarations to voice/voice.mbt**

Add after the first `///|`:

```moonbit
///|
using @dsp { type AudioBuffer, type DspContext }
using @graph {
  type CompiledDsp,
  type DspNode,
  type DspNodeKind,
  type GraphControl,
}
```

Also prefix free function calls:
- `pan_left_gain(` → `@dsp.pan_left_gain(`
- `pan_right_gain(` → `@dsp.pan_right_gain(`
- `sanitize_buffer(` → `@dsp.sanitize_buffer(`

- [ ] **Step 4: Add using declarations to voice/voice_test.mbt**

Add at top of file:

```moonbit
///|
using @dsp { type AudioBuffer, type DspContext, type Waveform }
using @graph {
  type CompiledDsp,
  type DspNode,
  type GraphControl,
  type GraphParamSlot,
}
```

- [ ] **Step 5: Check voice/voice_wbtest.mbt**

Whitebox tests share source scope, so they see voice.mbt's `using` declarations. Check if wbtest uses any additional types not covered:
- `DspNode::constant(...)` — covered by `using @graph { type DspNode }`
- `DspContext::new(...)` — covered by `using @dsp { type DspContext }`
- `@int.MAX_VALUE` — available via moon.pkg import

If wbtest uses `Waveform` or other types not in voice.mbt's using block, add them.

- [ ] **Step 6: Run moon check**

```bash
moon check
```

Fix any remaining errors iteratively.

---

## Task 6: Update lib/ facade to re-export voice/ and finalize

**Files:**
- Modify: `lib/moon.pkg` (add voice/ dependency, remove unused imports)
- Modify: `lib/reexport.mbt` (add voice re-exports)

- [ ] **Step 1: Update lib/moon.pkg**

```
import {
  "dowdiness/moondsp/dsp" @dsp,
  "dowdiness/moondsp/graph" @graph,
  "dowdiness/moondsp/voice" @voice,
}

import {
  "moonbitlang/core/double" @double,
  "moonbitlang/quickcheck" @qc,
} for "test"
```

Remove `@int`, `@ref`, `@bench`, `@math` — no longer used by lib/ source code.

- [ ] **Step 2: Add voice re-exports to lib/reexport.mbt**

Append to the file:

```moonbit
///|
// Voice pool from voice/
pub using @voice {
  type VoiceHandle,
  type VoicePool,
  type VoiceState,
}
```

- [ ] **Step 3: Run moon check && moon test**

```bash
moon check && moon test
```

Expected: all tests pass. integration_test.mbt and tagless_test.mbt in lib/ should work since all types are re-exported through the facade.

- [ ] **Step 4: Commit**

```bash
git add -A voice/ lib/
git commit -m "refactor: extract voice/ package from lib/ monolith"
```

---

## Task 7: Final verification and docs

**Files:**
- Modify: `CLAUDE.md` (update package table)
- Verify: WASM build, test count, API surface

- [ ] **Step 1: Run full test suite**

```bash
moon check && moon test
```

Expected: same test count as before (532 tests). If count differs, investigate.

- [ ] **Step 2: Build WASM target**

```bash
moon build --target wasm-gc
```

Expected: successful build. All browser/ exports still resolve through lib/ facade.

- [ ] **Step 3: Update moon info and format**

```bash
moon info && moon fmt
```

- [ ] **Step 4: Verify API surface coverage**

Compare the public symbol set before and after. `lib/pkg.generated.mbti` will change structurally (types now appear as re-exports with canonical origins like `@graph.CompiledDsp` instead of local definitions). The key check is that every symbol previously exported by lib/ is still exported:

```bash
# Extract sorted symbol names from the new mbti
grep -E '^pub ' lib/pkg.generated.mbti | sort > /tmp/new_symbols.txt
# Compare against the pre-refactor snapshot (check git)
git show HEAD~3:lib/pkg.generated.mbti | grep -E '^pub ' | sort > /tmp/old_symbols.txt
diff /tmp/old_symbols.txt /tmp/new_symbols.txt
```

Expected: the diff should show only re-export path changes (`@dsp.AudioBuffer` vs `AudioBuffer`), plus the two new pan functions. No symbols should be missing.

- [ ] **Step 5: Update CLAUDE.md package table**

Update the Project Structure table:

```markdown
| Package | Path | Purpose |
|---------|------|---------|
| `dowdiness/moondsp` | `./` | Demo entrypoint (`moondsp.mbt`), delegates to `lib/` |
| `dowdiness/moondsp/dsp` | `dsp/` | DSP primitives (oscillators, filters, tagless algebra, pan math) |
| `dowdiness/moondsp/graph` | `graph/` | Compiled graph runtime (compile, optimize, topology edit, hot-swap, control binding) |
| `dowdiness/moondsp/voice` | `voice/` | Polyphonic voice pool with priority stealing |
| `dowdiness/moondsp/lib` | `lib/` | Re-export facade (dsp/ + graph/ + voice/) |
| `dowdiness/moondsp/pattern` | `pattern/` | Pattern engine (rational time, combinators, control maps) |
| `dowdiness/moondsp/scheduler` | `scheduler/` | Pattern scheduler — bridges pattern engine to voice pool |
| `dowdiness/moondsp/browser` | `browser/` | AudioWorklet export wrapper |
| `dowdiness/moondsp/browser_test` | `browser_test/` | Browser integration test wrapper |
| `dowdiness/moondsp/cmd/main` | `cmd/main/` | CLI entry point |
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: update package structure after graph/voice extraction"
```
