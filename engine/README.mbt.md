# Host-independent graph engine

`engine` manages the lifecycle of compiled mono graphs without browser globals,
JSON, or a host registry. It mounts canonical `DspNode` arrays, returns typed
handles, and mixes every playing graph into one caller-owned `AudioBuffer`.

## Architecture context

In moondsp's layered design, `engine` sits alongside `voice` as an orchestrator
of compiled graphs, providing host-independent mounting and buffer mixing:

```text
[ Browser Worklet / Native CLI / Game Runtime ]
   ↓
[ engine ] ← (host-independent graph lifecycle, mounts, mixing)
   ↓
[ graph ] (topology validation & compilation)
   ↓
[ dsp ] (primitive state & buffer processing)
```

- **Upstream consumers**: `browser/` uses `GraphEngine` to fulfill browser
  mount requests; CLI tools and standalone MoonBit applications embed
  `GraphEngine` directly for headless audio rendering.
- **Downstream dependencies**: [`graph/`](../graph/) compiles DAG templates and
  provides `Dsp` runtimes; [`dsp/`](../dsp/) supplies `DspContext` and
  `AudioBuffer`. `engine` has zero dependencies on browser globals or JSON.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Lifecycle & Mixing** | `GraphEngine` | `GraphEngine::new`, `GraphEngine::mount`, `GraphEngine::process`, `GraphEngine::close` |
| **Mounted Sound** | `MountedGraph` | `MountedGraph::play`, `MountedGraph::pause`, `MountedGraph::unmount`, `MountedGraph::apply_controls` |
| **Errors** | `GraphEngineError` | `InvalidConfiguration`, `EngineClosed`, `MountClosed`, `CapacityExceeded`, `InvalidHandle`, `InvalidGraph`, `BufferSizeMismatch`, `ControlRejected` |

## Mount and play a graph

Construct an engine with a `DspContext`. Mounting validates and compiles the
graph but leaves it paused.

```mbt check
///|
test "mount and play a graph" {
  let context = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=128)
  let engine = @engine.GraphEngine::GraphEngine(context)
  let sound = engine.mount([
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 375.0),
    @graph.DspNode::gain(0, 0.1),
    @graph.DspNode::output(1),
  ])
  let output = context.make_buffer()

  engine.process(output)
  assert_true(output.all(sample => sample == 0.0))

  sound.play()
  engine.process(output)
  assert_true(output.any(sample => sample != 0.0))

  sound.unmount()
  engine.close()
}
```

`mount` follows the canonical graph boundary:
`AnalyzedGraph::analyze` then `Dsp::compile_result`. Invalid graphs
raise `GraphEngineError::InvalidGraph` with the underlying compile error and do
not consume capacity.

## Mix independent mounts

Each mount owns independent DSP state. `process` clears the destination and
writes the mono sum of all playing mounts.

```mbt check
///|
test "mix playing mounts" {
  let context = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=4)
  let engine = @engine.GraphEngine::GraphEngine(context)
  let quiet = engine.mount([
    @graph.DspNode::constant(0.25),
    @graph.DspNode::output(0),
  ])
  let loud = engine.mount([
    @graph.DspNode::constant(0.5),
    @graph.DspNode::output(0),
  ])
  let output = context.make_buffer()

  quiet.play()
  loud.play()
  engine.process(output)
  assert_true(output.all(sample => sample == 0.75))

  quiet.pause()
  engine.process(output)
  assert_true(output.all(sample => sample == 0.5))

  loud.unmount()
  quiet.unmount()
  engine.close()
}
```

`pause` preserves a graph's DSP state; resuming continues from the same phase.
`unmount` permanently detaches the graph and is idempotent.

## Capacity and admission

An engine has a fixed mount capacity, defaulting to 16. Capacity must be
positive. A failed mount leaves the engine usable.

Calling `play` seals further mount admission for that engine. Mount every graph
needed for the session before playback begins. Pausing or unmounting after
playback does not reopen admission.

```mbt check
///|
test "play seals mount admission" {
  let context = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=4)
  let engine = @engine.GraphEngine::GraphEngine(context, capacity=2)
  let sound = engine.mount([
    @graph.DspNode::constant(0.25),
    @graph.DspNode::output(0),
  ])
  sound.play()

  let rejected = try {
    let _ = engine.mount([
      @graph.DspNode::constant(0.5),
      @graph.DspNode::output(0),
    ])
    None
  } catch {
    error => Some(error)
  }
  assert_true(rejected is Some(@engine.GraphEngineError::MountClosed))

  sound.unmount()
  engine.close()
}
```

Separate `GraphEngine` instances have separate capacity, admission, playback,
and close state.

## Typed handles

`MountedGraph` is an opaque capability tied to its owning engine and slot
generation. If an unmounted slot is reused, the retired handle cannot play,
pause, or unmount the replacement.

Use the checked `GraphEngineError` variants at integration boundaries:

| Error | Meaning |
|---|---|
| `InvalidConfiguration` | Invalid context or engine capacity |
| `EngineClosed` | Operation after engine shutdown |
| `MountClosed` | Mount attempted after playback began |
| `CapacityExceeded` | No free mount slot |
| `InvalidHandle` | Retired or foreign mounted handle |
| `InvalidGraph(error)` | Graph compilation rejected |
| `BufferSizeMismatch` | Output length differs from the context block size |

`close` is idempotent. It releases mounted graphs and invalidates handles that
were still attached.

## Processing contract

The output buffer length must exactly match the engine's block size. A mismatch
is rejected before the buffer changes or any graph advances.

```mbt check
///|
test "reject a mismatched output buffer" {
  let context = @dsp.DspContext::DspContext(sample_rate=48000.0, block_size=4)
  let engine = @engine.GraphEngine::GraphEngine(context)
  let output = @dsp.AudioBuffer::filled(3, init=0.25)
  let rejected = try {
    engine.process(output)
    None
  } catch {
    error => Some(error)
  }

  assert_true(
    rejected
    is Some(@engine.GraphEngineError::BufferSizeMismatch(expected=4, actual=3)),
  )
  assert_true(output.all(sample => sample == 0.25))
  engine.close()
}
```

Compilation and lifecycle mutation belong outside processing. Successful
`process` calls reuse preallocated graph and mix buffers. The caller must
serialize operations; `GraphEngine` is not a concurrent API.

## Package boundary

`engine` depends only on `dsp` and `graph`. It does not add scheduling,
parameter automation, hot-swap, or browser resource management.

- [`dsp/`](../dsp/) — buffers and signal-processing primitives.
- [`graph/`](../graph/) — compilation, controls, and hot-swap.
- [Browser API contract](../docs/browser-api-contract.md) — JavaScript adapter.
- [Technical reference](../docs/technical-reference.md#354-host-independent-graph-engine)
