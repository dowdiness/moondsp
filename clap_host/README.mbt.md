# CLAP host primitive bridge

`clap_host` provides a flat, primitive C-ABI bridge between the C CLAP plugin
shim (`moondsp_clap.c`) and MoonBit's `ClapSynthEngine`. It exposes integer
handles, primitive scalar types (`Double`, `Int`, `Bool`), and direct sample
accessors without leaking MoonBit object references or complex memory layouts
across the foreign function boundary.

## Architecture context

In moondsp's native CLAP bridge, `clap_host` serves as the immediate boundary:

```text
[ DAW / Host ] (Bitwig, Reaper, etc.)
   ↓ CLAP 1.2.8 ABI
[ moondsp_clap.c ] (C shim compiled with native compiler)
   ↓ C ABI bridge
[ clap_host ] ← (flat primitive handles: engine_create, engine_process, etc.)
   ↓ MoonBit native objects
[ clap_engine ] (ClapSynthEngine polyphonic synth)
```

- **Upstream consumers**: [`clap_plugin/`](../clap_plugin/) generates C bindings
  (`moondsp_clap_moonbit.h`) from `clap_host` symbols to link into `moondsp_clap.c`.
- **Downstream dependencies**: [`clap_engine/`](../clap_engine/) provides the
  underlying `ClapSynthEngine` instances referenced by the integer handles.

## API quick reference

| Category | Primitive functions | Description |
|---|---|---|
| **Lifecycle** | `engine_create`, `engine_destroy` | Create engine returning a positive handle (`0` on failure); destroy instance |
| **Note Events** | `engine_note_on`, `engine_note_off`, `engine_all_notes_off` | Dispatch CLAP note on/off with note id and MIDI key (supports `-1` wildcards) |
| **Parameters** | `engine_set_param`, `engine_master_gain`, `engine_cutoff_hz`, `engine_resonance`, `engine_pan`, `engine_voice_gain` | Flat parameter dispatcher and inspection getters |
| **Audio Rendering** | `engine_process`, `engine_left_sample`, `engine_right_sample` | Render audio frames (clamped to max block size) and read interleaved or channel samples |

## Handle lifecycle and processing

Hosts manage plugin instances through integer handles. Handles are 1-based
indices into an append-only slot array (`engine_slots`) that allocates and
grows when `engine_create` registers a new engine. Slots are marked `None` on
`engine_destroy` and are never recycled or resurrected.

```mbt check
///|
test "create, run, and destroy engine handle" {
  let handle = @clap_host.engine_create(48000.0, 128, 8)
  assert_true(handle > 0)

  // Render initial block (produces silence before notes)
  assert_eq(@clap_host.engine_process(handle, 128), 128)
  assert_eq(@clap_host.engine_left_sample(handle, 0), 0.0)

  // Send note-on event
  assert_true(@clap_host.engine_note_on(handle, 1, 69, 1.0))
  assert_eq(@clap_host.engine_process(handle, 128), 128)

  // Set master gain
  assert_true(@clap_host.engine_set_param(handle, 0, 0.5))
  assert_eq(@clap_host.engine_master_gain(handle), 0.5)

  // Destroy handle
  assert_true(@clap_host.engine_destroy(handle))
  // Calls on destroyed handles safely fail closed
  assert_eq(@clap_host.engine_process(handle, 128), 0)
}
```

## Foreign Function Interface (FFI) contract

1. **Allocation boundaries**: Lifecycle operations (`engine_create`) allocate
   the underlying synth engine and grow the slot registry on the heap.
   Sample-access functions (`engine_left_sample`, `engine_right_sample`) perform
   no heap allocation, returning raw scalars directly from internal buffers.
2. **Fail closed**: Any call with an invalid or already-destroyed handle returns
   `0`, `0.0`, or `false` without crashing or panicking.
3. **Bounded processing**: `engine_process(handle, frames)` clamps requested
   frames to the engine's preallocated maximum block size.
