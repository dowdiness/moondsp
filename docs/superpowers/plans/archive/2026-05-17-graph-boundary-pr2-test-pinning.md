# PR 2: Graph Boundary Type — Test Pinning

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add property tests that pin current behavior across the graph compile path, `VoicePool`, `VoicePool::set_template`, and `BoundVoicePool`. These tests run against current `main` (Array-taking signatures) using `CompiledTemplate::analyze(nodes)` as the comparison reference, and parameterize over a closure so the PR 3 migration only changes the closure body.

**Architecture:** Two files per test category. `*_temporary_equivalence_pins.mbt` holds the direct A↔B side-door-vs-front-door tests (deleted in PR 3 because the front door ceases to exist). `*_behavior_test.mbt` holds the persistent property tests parameterized over a closure; PR 3 rewrites the closure body in one line and the tests survive.

**Tech Stack:** MoonBit; `@qc.quick_check_fn` for property tests; `moon check` / `moon test`.

**Spec:** `docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md` → §Test Strategy A.

**Branch:** `feat/graph-boundary-test-pinning` off `main` (after PR 1 lands).

**Landing path:** Single PR against `main`. No behavior change. All new tests must pass against current `main`.

**Verification before merging:** `moon check && moon test` green; new tests demonstrably fail if the comparison reference is corrupted (sanity-check by temporarily breaking `CompiledTemplate::analyze` and confirming A1 fails).

---

### Task 1: Define the PR-2-local A2Reason / A3Reason enums

**Files:**
- Create: `voice/voice_pinning_test.mbt` (new blackbox test file in voice/ package)

- [ ] **Step 1: Create the file with the local reason enums**

Create `voice/voice_pinning_test.mbt`:

```moonbit
///| PR-2 local enum used by A2/A3 closure-parameterized tests. Mirrors
///| the future VoicePoolError but lives in the test file because
///| VoicePoolError doesn't exist yet (added in PR 3). The pre-classifier
///| inside the test closure populates these variants by checking
///| max_voices and orphan_adsr_count before invoking the current
///| Option/Bool-returning API.
enum A2Reason {
  InvalidMaxVoices
  OrphanAdsr
  CompileRejected
} derive(Eq, @debug.Debug)

///|
enum A3Reason {
  OrphanAdsr
  CompileRejected
} derive(Eq, @debug.Debug)

///| Closure type for A2. PR 3 swaps the body to call the new
///| VoicePool::new(CompiledTemplate, ctx, max_voices?) -> Result[Self, VoicePoolError]
///| and map via A2Reason::from_voice_pool.
typealias A2Closure = (Array[@graph.DspNode], @dsp.DspContext, Int) ->
  Result[@voice.VoicePool, A2Reason]

///|
typealias A3Closure = (@voice.VoicePool, Array[@graph.DspNode]) ->
  Result[Unit, A3Reason]
```

- [ ] **Step 2: Verify it compiles**

Run: `moon check`
Expected: clean. The enums and typealiases are declared but not yet used.

- [ ] **Step 3: Commit**

```bash
git add voice/voice_pinning_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): add PR-2-local A2Reason/A3Reason enums for closure-parameterized pins

PR 3 deletes these in favor of the real VoicePoolError (which can't
exist yet — same name, different package, would clash).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Implement the A2 / A3 PR-2 closures with pre-classifiers

**Files:**
- Modify: `voice/voice_pinning_test.mbt`

- [ ] **Step 1: Add the PR-2 closure implementations**

Append to `voice/voice_pinning_test.mbt`:

```moonbit
///| PR-2 A2 closure: pre-classify failure reasons before calling the
///| current Option-returning VoicePool::new. PR 3 replaces this body
///| with `VoicePool::new(CompiledTemplate::analyze(nodes), ctx, max_voices?)
///| .map_err(A2Reason::from_voice_pool)`.
fn pr2_a2_closure(
  nodes : Array[@graph.DspNode],
  ctx : @dsp.DspContext,
  max_voices : Int,
) -> Result[@voice.VoicePool, A2Reason] {
  if max_voices <= 0 {
    return Err(A2Reason::InvalidMaxVoices)
  }
  if @graph.CompiledTemplate::analyze(nodes).orphan_adsr_count() > 0 {
    return Err(A2Reason::OrphanAdsr)
  }
  match @voice.VoicePool::new(nodes, ctx, max_voices~) {
    Some(pool) => Ok(pool)
    None => Err(A2Reason::CompileRejected)
  }
}

///| PR-2 A3 closure: pre-classify orphan_adsr before calling the
///| current Bool-returning VoicePool::set_template.
fn pr2_a3_closure(
  pool : @voice.VoicePool,
  nodes : Array[@graph.DspNode],
) -> Result[Unit, A3Reason] {
  if @graph.CompiledTemplate::analyze(nodes).orphan_adsr_count() > 0 {
    return Err(A3Reason::OrphanAdsr)
  }
  if @voice.VoicePool::set_template(pool, nodes) {
    Ok(())
  } else {
    Err(A3Reason::CompileRejected)
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `moon check`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add voice/voice_pinning_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): add PR-2 closures for A2/A3 with pre-classifier strategy

Pre-classifiers check max_voices and orphan_adsr_count before invoking
the current Option/Bool APIs (which collapse failure reasons). PR 3
collapses each closure to one line when the real Result-typed APIs land.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Write the A2 VoicePool construction property tests

**Files:**
- Modify: `voice/voice_pinning_test.mbt`

- [ ] **Step 1: Write the property tests**

Append:

```moonbit
///| A2 well-formed: a minimal valid template (Oscillator → Output)
///| produces a VoicePool successfully.
test "A2: well-formed template constructs VoicePool successfully" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 4)
  match result {
    Ok(_) => ()
    Err(reason) => @debug.assert_eq(reason, A2Reason::CompileRejected) // never reached
  }
  assert_true(result is Ok(_))
}

///| A2 InvalidMaxVoices: max_voices=0 fails with the specific reason.
test "A2: max_voices=0 fails with InvalidMaxVoices" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 0)
  @debug.assert_eq(result, Err(A2Reason::InvalidMaxVoices))
}

///| A2 OrphanAdsr: a dead-code ADSR node (no consumer) fails with the
///| specific reason. Note: ADSR must be in the template but unreferenced
///| by Output, so optimize_graph eliminates it.
test "A2: orphan ADSR fails with OrphanAdsr" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::adsr(
      attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0,
    ),  // orphan — not referenced by Output
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 4)
  @debug.assert_eq(result, Err(A2Reason::OrphanAdsr))
}

///| A2 CompileRejected: a template with no Output node fails with
///| CompileRejected.
test "A2: missing Output fails with CompileRejected" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let result = pr2_a2_closure(nodes, ctx, 4)
  @debug.assert_eq(result, Err(A2Reason::CompileRejected))
}
```

- [ ] **Step 2: Run tests against current main**

Run: `moon test voice/`
Expected: all 4 new tests pass. If any fail, investigate — the closure or the test inputs may be wrong.

- [ ] **Step 3: Commit**

```bash
git add voice/voice_pinning_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): pin A2 VoicePool construction behavior across all failure modes

Property: each VoicePoolError variant fires under the right condition
when invoked via the PR-2 pre-classifier closure. PR 3 swaps the
closure body to invoke the real Result-typed VoicePool::new.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Write the A3 VoicePool::set_template property tests

**Files:**
- Modify: `voice/voice_pinning_test.mbt`

- [ ] **Step 1: Write the A3 tests**

Append:

```moonbit
///| A3: replacing with a well-formed template succeeds.
test "A3: well-formed replacement succeeds" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @voice.VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let new_nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Square, 880.0),
    @graph.DspNode::output(0),
  ]
  @debug.assert_eq(pr2_a3_closure(pool, new_nodes), Ok(()))
}

///| A3: replacing with an orphan-ADSR template fails with OrphanAdsr.
test "A3: orphan ADSR replacement fails with OrphanAdsr" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @voice.VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let new_nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::adsr(
      attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0,
    ),
    @graph.DspNode::output(0),
  ]
  @debug.assert_eq(pr2_a3_closure(pool, new_nodes), Err(A3Reason::OrphanAdsr))
}

///| A3: replacing with a no-Output template fails with CompileRejected.
test "A3: missing Output replacement fails with CompileRejected" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @voice.VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let new_nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
  ]
  @debug.assert_eq(pr2_a3_closure(pool, new_nodes), Err(A3Reason::CompileRejected))
}
```

- [ ] **Step 2: Run tests**

Run: `moon test voice/`
Expected: all 3 new A3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add voice/voice_pinning_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): pin A3 VoicePool::set_template behavior across failure modes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Write the A4 BoundVoicePool behavior tests

**Files:**
- Modify: `voice/voice_pinning_test.mbt`

- [ ] **Step 1: Write the A4 closure and tests**

Append:

```moonbit
///| PR-2 A4 closure: passes through unchanged. BoundVoicePool already
///| returns Result[..., BoundVoicePoolError]. PR 3 changes only the
///| input type (Array → CompiledTemplate).
fn pr2_a4_closure(
  nodes : Array[@graph.DspNode],
  ctx : @dsp.DspContext,
  builder : @graph.ControlBindingBuilder,
  max_voices : Int,
) -> Result[@voice.BoundVoicePool, @voice.BoundVoicePoolError] {
  @voice.BoundVoicePool::new(nodes, ctx, builder, max_voices~)
}

///| A4: well-formed template + valid bindings constructs BoundVoicePool.
test "A4: well-formed template constructs BoundVoicePool successfully" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = @graph.ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 4)
  assert_true(result is Ok(_))
}

///| A4 InvalidMaxVoices: max_voices=0 fails with the specific variant.
test "A4: max_voices=0 fails with InvalidMaxVoices" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = @graph.ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 0)
  @debug.assert_eq(result, Err(@voice.BoundVoicePoolError::InvalidMaxVoices))
}

///| A4 OrphanAdsr: dead-code ADSR fails with the specific variant.
test "A4: orphan ADSR fails with OrphanAdsr" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::adsr(
      attack_ms=10.0, decay_ms=50.0, sustain=0.5, release_ms=100.0,
    ),
    @graph.DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = @graph.ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 4)
  @debug.assert_eq(result, Err(@voice.BoundVoicePoolError::OrphanAdsr))
}

///| A4 CompileRejected: missing Output fails with the specific variant.
test "A4: missing Output fails with CompileRejected" {
  let nodes : Array[@graph.DspNode] = [
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let builder = @graph.ControlBindingBuilder::new()
  let result = pr2_a4_closure(nodes, ctx, builder, 4)
  @debug.assert_eq(result, Err(@voice.BoundVoicePoolError::CompileRejected))
}
```

- [ ] **Step 2: Run tests**

Run: `moon test voice/`
Expected: all 4 new A4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add voice/voice_pinning_test.mbt
git commit -m "$(cat <<'EOF'
test(voice): pin A4 BoundVoicePool behavior — closure passes through unchanged

BoundVoicePool already returns Result[..., BoundVoicePoolError]; PR 3
only changes the closure's input type from Array to CompiledTemplate.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Write the A1 compile equivalence pins (graph/)

**Files:**
- Create: `graph/graph_compile_temporary_equivalence_pins.mbt`

- [ ] **Step 1: Create the temporary-pin file**

Create `graph/graph_compile_temporary_equivalence_pins.mbt`:

```moonbit
///| PR-2 equivalence pin: CompiledDsp::compile(Array, ctx) must
///| produce block-equivalent output to
///| CompiledDsp::compile_template(CompiledTemplate::analyze(nodes), ctx).
///| This file is DELETED in PR 3 because compile(Array) ceases to
///| exist (it collapses into compile(CompiledTemplate)).
test "A1: compile(Array) and compile_template(analyze) produce identical first block" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::output(0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled_a = CompiledDsp::compile(nodes, ctx).unwrap()
  let compiled_b = CompiledDsp::compile_template(
    CompiledTemplate::analyze(nodes),
    ctx,
  ).unwrap()
  let buf_a = @dsp.AudioBuffer::filled(128)
  let buf_b = @dsp.AudioBuffer::filled(128)
  compiled_a.process(ctx, buf_a)
  compiled_b.process(ctx, buf_b)
  for i in 0..<128 {
    @debug.assert_eq(buf_a.get(i), buf_b.get(i))
  }
}

///| A1 adversarial: both paths agree on "missing Output" rejection.
test "A1: compile(Array) and compile_template both reject missing Output with None" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  assert_true(CompiledDsp::compile(nodes, ctx) is None)
  assert_true(
    CompiledDsp::compile_template(CompiledTemplate::analyze(nodes), ctx)
      is None,
  )
}

///| A1 stereo: same equivalence for CompiledStereoDsp.
test "A1: stereo compile(Array) and compile_template(analyze) produce identical first block" {
  let nodes : Array[DspNode] = [
    DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    DspNode::stereo_mixdown(0),
    DspNode::stereo_output(1),
  ]
  let ctx = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let compiled_a = CompiledStereoDsp::compile(nodes, ctx).unwrap()
  let compiled_b = CompiledStereoDsp::compile_template(
    CompiledTemplate::analyze(nodes),
    ctx,
  ).unwrap()
  let left_a = @dsp.AudioBuffer::filled(128)
  let right_a = @dsp.AudioBuffer::filled(128)
  let left_b = @dsp.AudioBuffer::filled(128)
  let right_b = @dsp.AudioBuffer::filled(128)
  compiled_a.process(ctx, left_a, right_a)
  compiled_b.process(ctx, left_b, right_b)
  for i in 0..<128 {
    @debug.assert_eq(left_a.get(i), left_b.get(i))
    @debug.assert_eq(right_a.get(i), right_b.get(i))
  }
}
```

- [ ] **Step 2: Run tests**

Run: `moon test graph/`
Expected: all 3 new tests pass. If equivalence fails, the front door and side door are diverging today — investigate before proceeding (this is exactly the safety net A1 is supposed to catch).

- [ ] **Step 3: Commit**

```bash
git add graph/graph_compile_temporary_equivalence_pins.mbt
git commit -m "$(cat <<'EOF'
test(graph): pin A1 compile(Array) ≡ compile_template(analyze) equivalence

Temporary pin — deleted in PR 3 when compile(Array) ceases to exist.
If A1 ever fails on current main, the front-door/side-door semantics
have diverged and the migration plan needs reconsidering.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Sanity-check the safety net

**Files:**
- Read-only verification (no edits).

- [ ] **Step 1: Confirm test counts increased**

Run: `moon test 2>&1 | tail -5`
Expected: a line like `passed N + 14, total N + 14` (14 new tests: 4 A2 + 3 A3 + 4 A4 + 3 A1). Verify N matches the pre-PR test count.

- [ ] **Step 2: Confirm only test files were added**

Run: `git diff main..HEAD --stat`
Expected: only `voice/voice_pinning_test.mbt` and `graph/graph_compile_temporary_equivalence_pins.mbt` listed. No production `.mbt` files modified.

- [ ] **Step 3: Run full check**

Run: `moon check && moon test && moon fmt --check`
Expected: all green.

- [ ] **Step 4: Update .mbti snapshots if any drift**

Run: `moon info`
Expected: no changes (PR 2 adds no public API). If `*.mbti` files changed, investigate — the test file may have inadvertently added public functions.

If `*.mbti` files changed:
```bash
git diff --stat | grep "\.mbti$"
```
Should be empty. If not, audit the new test files for accidentally-public symbols.

- [ ] **Step 5: Commit any incidental fixups (if needed)**

```bash
git add -A
git commit -m "chore: moon info snapshot after PR 2 test pinning" || echo "no changes"
```

---

### Task 8: Push branch and open PR

**Files:**
- None to edit.

- [ ] **Step 1: Push branch**

```bash
git push -u origin feat/graph-boundary-test-pinning
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --base main --title "test: pin graph compile + voice pool behavior ahead of CompiledTemplate migration" --body "$(cat <<'EOF'
## Summary

Adds property tests pinning current behavior across:

- **A1**: `CompiledDsp::compile(Array)` ≡ `compile_template(analyze(Array))` (mono + stereo) — temporary equivalence pins, deleted in PR 3.
- **A2**: `VoicePool::new` failure-mode coverage via pre-classifier closure.
- **A3**: `VoicePool::set_template` failure-mode coverage via pre-classifier closure.
- **A4**: `BoundVoicePool::new` failure-mode coverage (closure passes through).

Closures are parameterized so PR 3 swaps only the closure body to use the new `CompiledTemplate`-taking signatures.

## Why this PR

PR 3 (the migration) is mechanical given PR 1 (the docs/principle) and PR 2 (this PR — the safety net). If the front-door/side-door semantics ever diverge, A1 catches it BEFORE the migration removes the front door.

## Test plan

- [x] `moon check` green.
- [x] `moon test` shows +14 tests, all passing.
- [x] `moon info` shows no public-API changes.
- [x] No production `.mbt` files modified.

Spec: `docs/superpowers/specs/2026-05-17-graph-boundary-type-design.md` → §Test Strategy A.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Wait for review**

Once merged, proceed to PR 3 (the migration).
