# Typed Control Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a validated bridge layer (`ControlBindingMap`) that maps pattern engine string keys to DSP graph control targets, catching mismatches at graph construction time.

**Architecture:** Validated builder pattern in `lib/`. `ControlBindingBuilder` accumulates bindings, `build()` validates against a `DspNode` template and returns `Result[ControlBindingMap, ControlBindingError]`. `ControlBindingMap::resolve_controls` converts `Map[String, Double]` to `Array[GraphControl]` in insertion order.

**Tech Stack:** MoonBit, moon check/test/fmt/info

**Spec:** `docs/superpowers/specs/2026-04-02-typed-control-interface-design.md`

---

### Task 1: Add slot compatibility predicate

Extract a structural check from the existing `updated_node_param` logic: "does this node kind accept this slot?" This is needed by the binding validator in Task 3.

**Files:**
- Modify: `lib/graph.mbt` (add function after `valid_delay_samples` at ~line 2261)
- Test: `lib/graph_test.mbt` (append tests)

- [ ] **Step 1: Write failing tests for slot compatibility**

Append to `lib/graph_test.mbt`:

```moonbit
///|
test "node_accepts_slot: Constant accepts Value0" {
  let node = DspNode::constant(1.0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: Constant rejects Value1" {
  let node = DspNode::constant(1.0)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Biquad accepts Value0 and Value1" {
  let node = DspNode::biquad(0, BiquadMode::LowPass, 1000.0, 0.707)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_true(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Delay accepts Value0 and DelaySamples" {
  let node = DspNode::delay(0, 128, delay_samples=0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_true(node_accepts_slot(node, GraphParamSlot::DelaySamples))
  assert_false(node_accepts_slot(node, GraphParamSlot::Value1))
}

///|
test "node_accepts_slot: Output rejects all slots" {
  let node = DspNode::output(0)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value0))
  assert_false(node_accepts_slot(node, GraphParamSlot::DelaySamples))
}

///|
test "node_accepts_slot: FM oscillator rejects Value0" {
  let node = DspNode::oscillator_from(0, Waveform::Sine)
  assert_false(node_accepts_slot(node, GraphParamSlot::Value0))
}

///|
test "node_accepts_slot: non-FM oscillator accepts Value0" {
  let node = DspNode::oscillator(Waveform::Sine, 440.0)
  assert_true(node_accepts_slot(node, GraphParamSlot::Value0))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -f graph_test.mbt 2>&1 | tail -5`
Expected: FAIL — `node_accepts_slot` not defined

- [ ] **Step 3: Implement node_accepts_slot**

Add to `lib/graph.mbt` after the `valid_delay_samples` function (~line 2267):

```moonbit
///|
/// Structural check: does this node kind accept SetParam on the given slot?
/// Used by ControlBindingBuilder::build() to validate bindings at graph
/// construction time. Does not check value-domain constraints.
pub fn node_accepts_slot(node : DspNode, slot : GraphParamSlot) -> Bool {
  match node.kind {
    Constant => slot is Value0
    Oscillator => node.input0 < 0 && slot is Value0
    Noise => false
    Adsr => false
    Biquad => slot is Value0 || slot is Value1
    Delay => slot is Value0 || slot is DelaySamples
    Gain => slot is Value0
    Mul => false
    Mix => false
    Clip => slot is Value0
    Output => false
    Pan => slot is Value0
    StereoGain => slot is Value0
    StereoClip => slot is Value0
    StereoBiquad => slot is Value0 || slot is Value1
    StereoDelay => slot is Value0 || slot is DelaySamples
    StereoMixDown => false
    StereoOutput => false
  }
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -f graph_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/graph.mbt lib/graph_test.mbt
git commit -m "feat: add node_accepts_slot predicate for control binding validation"
```

---

### Task 2: Define ControlBinding, ControlBindingError, and ControlBindingBuilder structs

**Files:**
- Create: `lib/control_binding.mbt`

- [ ] **Step 1: Create the data structures file**

Create `lib/control_binding.mbt`:

```moonbit
///|
pub struct ControlBinding {
  key : String
  node_index : Int
  slot : GraphParamSlot

  fn new(
    key~ : String,
    node_index~ : Int,
    slot~ : GraphParamSlot,
  ) -> ControlBinding
} derive(Show, Eq)

///|
fn ControlBinding::new(
  key~ : String,
  node_index~ : Int,
  slot~ : GraphParamSlot,
) -> ControlBinding {
  { key, node_index, slot }
}

///|
pub(all) enum ControlBindingError {
  InvalidNodeIndex(Int)
  InvalidSlotForNode(Int, GraphParamSlot)
  DuplicateKey(String)
} derive(Show, Eq)

///|
pub struct ControlBindingBuilder {
  bindings : Array[ControlBinding]

  fn new() -> ControlBindingBuilder
} derive(Show)

///|
fn ControlBindingBuilder::new() -> ControlBindingBuilder {
  { bindings: [] }
}

///|
/// Add a binding. Mutates internal array, returns self for chaining.
pub fn ControlBindingBuilder::bind(
  self : ControlBindingBuilder,
  key~ : String,
  node_index~ : Int,
  slot~ : GraphParamSlot,
) -> ControlBindingBuilder {
  self.bindings.push(ControlBinding(key~, node_index~, slot~))
  self
}
```

- [ ] **Step 2: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add lib/control_binding.mbt
git commit -m "feat: add ControlBinding, ControlBindingError, ControlBindingBuilder structs"
```

---

### Task 3: Implement ControlBindingBuilder::build() validation

**Files:**
- Modify: `lib/control_binding.mbt` (append build function)
- Test: `lib/control_binding_test.mbt` (create)

- [ ] **Step 1: Write failing tests for build validation**

Create `lib/control_binding_test.mbt`:

```moonbit
///|
test "build: valid bindings produce Ok" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_true(result.is_ok())
}

///|
test "build: invalid node index returns InvalidNodeIndex" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder()
    .bind(key="note", node_index=5, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(5)))
}

///|
test "build: negative node index returns InvalidNodeIndex" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder()
    .bind(key="note", node_index=-1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(result, Err(ControlBindingError::InvalidNodeIndex(-1)))
}

///|
test "build: invalid slot for node returns InvalidSlotForNode" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder()
    .bind(key="x", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(
    result,
    Err(ControlBindingError::InvalidSlotForNode(1, GraphParamSlot::Value0)),
  )
}

///|
test "build: duplicate keys returns DuplicateKey" {
  let template = [
    DspNode::constant(1.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let result = ControlBindingBuilder()
    .bind(key="gain", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
  assert_eq(result, Err(ControlBindingError::DuplicateKey("gain")))
}

///|
test "build: duplicate targets allowed" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let result = ControlBindingBuilder()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .build(template)
  assert_true(result.is_ok())
}

///|
test "build: empty builder produces Ok with empty map" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let result = ControlBindingBuilder().build(template)
  assert_true(result.is_ok())
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -f control_binding_test.mbt 2>&1 | tail -5`
Expected: FAIL — `build` not defined

- [ ] **Step 3: Implement build()**

Append to `lib/control_binding.mbt`:

```moonbit
///|
/// No public constructor — only reachable through ControlBindingBuilder::build().
pub struct ControlBindingMap {
  bindings : Array[ControlBinding]
} derive(Show, Eq)

///|
/// Validate all bindings against the graph template and transition to
/// the proven-valid ControlBindingMap. Checks node index bounds, slot
/// compatibility, and key uniqueness. Returns the first error found.
pub fn ControlBindingBuilder::build(
  self : ControlBindingBuilder,
  template : Array[DspNode],
) -> Result[ControlBindingMap, ControlBindingError] {
  let seen_keys : Map[String, Bool] = {}
  for i = 0; i < self.bindings.length(); i = i + 1 {
    let binding = self.bindings[i]
    // 1. Node index bounds
    if binding.node_index < 0 || binding.node_index >= template.length() {
      return Err(ControlBindingError::InvalidNodeIndex(binding.node_index))
    }
    // 2. Slot compatibility (structural, not value-domain)
    if !node_accepts_slot(template[binding.node_index], binding.slot) {
      return Err(
        ControlBindingError::InvalidSlotForNode(
          binding.node_index,
          binding.slot,
        ),
      )
    }
    // 3. No duplicate keys
    if seen_keys.contains(binding.key) {
      return Err(ControlBindingError::DuplicateKey(binding.key))
    }
    seen_keys[binding.key] = true
  }
  Ok({ bindings: self.bindings })
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -f control_binding_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/control_binding.mbt lib/control_binding_test.mbt
git commit -m "feat: implement ControlBindingBuilder::build() with validation"
```

---

### Task 4: Implement ControlBindingMap::resolve_controls

**Files:**
- Modify: `lib/control_binding.mbt` (append resolve function)
- Modify: `lib/control_binding_test.mbt` (append tests)

- [ ] **Step 1: Write failing tests for resolve_controls**

Append to `lib/control_binding_test.mbt`:

```moonbit
///|
test "resolve: full map converts all bound keys in insertion order" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let map = ControlBindingBuilder()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let controls : Map[String, Double] = { "note": 60.0, "gain": 0.5 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 2)
  assert_eq(result[0].node_index, 0)
  assert_eq(result[0].slot, GraphParamSlot::Value0)
  assert_eq(result[0].value, 60.0)
  assert_eq(result[1].node_index, 1)
  assert_eq(result[1].slot, GraphParamSlot::Value0)
  assert_eq(result[1].value, 0.5)
}

///|
test "resolve: partial map skips missing keys" {
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let map = ControlBindingBuilder()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let controls : Map[String, Double] = { "gain": 0.8 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 1)
  assert_eq(result[0].node_index, 1)
  assert_eq(result[0].value, 0.8)
}

///|
test "resolve: extra keys in map are ignored" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let controls : Map[String, Double] = { "freq": 220.0, "unknown": 99.0 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 1)
  assert_eq(result[0].value, 220.0)
}

///|
test "resolve: empty map produces empty controls" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder()
    .bind(key="freq", node_index=0, slot=GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let controls : Map[String, Double] = {}
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 0)
}

///|
test "resolve: empty binding map produces empty controls" {
  let template = [DspNode::constant(1.0), DspNode::output(0)]
  let map = ControlBindingBuilder().build(template).unwrap()
  let controls : Map[String, Double] = { "freq": 440.0 }
  let result = map.resolve_controls(controls)
  assert_eq(result.length(), 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -f control_binding_test.mbt 2>&1 | tail -5`
Expected: FAIL — `resolve_controls` not defined

- [ ] **Step 3: Implement resolve_controls**

Append to `lib/control_binding.mbt`:

```moonbit
///|
/// Convert pattern controls to graph controls using the validated bindings.
/// Emits GraphControl::set_param for each bound key found in the input map,
/// in binding insertion order. Missing keys are skipped; unrecognized keys
/// are ignored. Values are passed through without domain validation.
pub fn ControlBindingMap::resolve_controls(
  self : ControlBindingMap,
  controls : Map[String, Double],
) -> Array[GraphControl] {
  let result = Array::new(capacity=self.bindings.length())
  for i = 0; i < self.bindings.length(); i = i + 1 {
    let binding = self.bindings[i]
    match controls[binding.key] {
      Some(value) =>
        result.push(
          GraphControl::set_param(binding.node_index, binding.slot, value),
        )
      None => ()
    }
  }
  result
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -f control_binding_test.mbt 2>&1 | tail -5`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/control_binding.mbt lib/control_binding_test.mbt
git commit -m "feat: implement ControlBindingMap::resolve_controls"
```

---

### Task 5: Integration test with VoicePool

**Files:**
- Modify: `lib/control_binding_test.mbt` (append integration test)

- [ ] **Step 1: Write integration test**

Append to `lib/control_binding_test.mbt`:

```moonbit
///|
test "integration: resolved controls accepted by VoicePool::note_on" {
  let ctx = DspContext::new(48000.0, 16)
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::gain(0, 0.3),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(template, ctx, max_voices=4).unwrap()
  let bindings = ControlBindingBuilder()
    .bind(key="note", node_index=0, slot=GraphParamSlot::Value0)
    .bind(key="gain", node_index=1, slot=GraphParamSlot::Value0)
    .build(template)
    .unwrap()
  let controls : Map[String, Double] = { "note": 880.0, "gain": 0.5 }
  let resolved = bindings.resolve_controls(controls)
  let handle = pool.note_on(resolved)
  assert_true(handle is Some(_))
  // Voice should be active with the resolved parameters
  assert_true(pool.voice_state(handle.unwrap()) is VoiceState::Active)
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `moon test -f control_binding_test.mbt 2>&1 | tail -5`
Expected: All pass (this test exercises the full pipeline)

- [ ] **Step 3: Commit**

```bash
git add lib/control_binding_test.mbt
git commit -m "test: add VoicePool integration test for control binding"
```

---

### Task 6: Final verification and cleanup

**Files:**
- Run: `moon info && moon fmt` to update interfaces and format
- Verify: `git diff *.mbti` to confirm public API additions are intentional

- [ ] **Step 1: Run full test suite**

Run: `moon test 2>&1 | tail -5`
Expected: All tests pass (412 existing + ~19 new)

- [ ] **Step 2: Update interfaces and format**

Run: `moon info && moon fmt`

- [ ] **Step 3: Check API surface**

Run: `git diff lib/pkg.generated.mbti`
Expected: New public symbols: `ControlBinding`, `ControlBindingBuilder`, `ControlBindingMap`, `ControlBindingError`, `node_accepts_slot`, and their methods.

- [ ] **Step 4: Commit interface changes**

```bash
git add lib/pkg.generated.mbti
git commit -m "chore: update .mbti for control binding public API"
```
