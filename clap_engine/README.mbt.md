# CLAP synth engine

`clap_engine` provides the core polyphonic synthesizer engine backing moondsp's
native CLAP plugin prototype. It orchestrates a voice pool (`BoundVoicePool`),
parameter management, note lifecycle tracking, voice stealing, and stereo
sample rendering without depending on host-specific C types.

## Architecture context

In moondsp's layered design, `clap_engine` sits between native host bindings
and the DSP graph / voice subsystem:

```text
[ moondsp_clap.c ] (C CLAP ABI plugin entry point)
   ↓
[ clap_host ] (flat primitive handle bridge)
   ↓
[ clap_engine ] ← (polyphonic CLAP synth engine, voice lifecycle, params)
   ↓
[ voice ] (BoundVoicePool, voice allocation, stealing)
   ↓
[ graph ] (template compilation, live controls)
   ↓
[ dsp ] (oscillators, filters, envelopes, buffers)
```

- **Upstream consumers**: [`clap_host/`](../clap_host/) wraps this engine in
  a flat integer-handle C ABI for use by `moondsp_clap.c` / `clap_plugin/`.
- **Downstream dependencies**: [`voice/`](../voice/) manages polyphony and
  voice stealing; [`graph/`](../graph/) compiles and runs the default stereo
  synth template; [`dsp/`](../dsp/) executes sample-level DSP operations.

## API quick reference

| Category | Types / Constants | Key operations |
|---|---|---|
| **Lifecycle** | `ClapSynthEngine`, `ClapEngineError` | `ClapSynthEngine::new`, error variants for sample rate, block size, voices |
| **Note Events** | `ClapSynthEngine` | `ClapSynthEngine::note_on`, `ClapSynthEngine::note_off`, `ClapSynthEngine::all_notes_off` |
| **Parameters** | `CLAP_PARAM_*`, `ClapSynthEngine` | `ClapSynthEngine::set_param`, `ClapSynthEngine::set_master_gain`, `ClapSynthEngine::set_cutoff_hz`, `ClapSynthEngine::set_resonance`, `ClapSynthEngine::set_pan` |
| **Audio Rendering** | `ClapSynthEngine` | `ClapSynthEngine::process`, `ClapSynthEngine::left_sample`, `ClapSynthEngine::right_sample` |
| **Template** | `default_synth_template` | Predefined 6-node stereo subtractive synth graph (Saw osc -> LowPass biquad -> ADSR gain -> Pan -> StereoOutput) |

## Initialize and render audio

Initialize an engine with the host's sample rate, maximum block capacity, and
voice count. The engine preallocates all buffers and voice slots up front.

```mbt check
///|
test "initialize clap synth engine and process audio" {
  let engine = match
    @clap_engine.ClapSynthEngine::new(
      sample_rate=48000.0,
      max_block_size=128,
      max_voices=8,
    ) {
    Ok(e) => e
    Err(_) => fail("failed to initialize clap engine")
  }

  // Before note events, processing produces silence
  assert_eq(engine.process(128), 128)
  assert_eq(engine.left_sample(0), 0.0)
  assert_eq(engine.right_sample(0), 0.0)

  // Trigger a note and process
  assert_true(engine.note_on(note_id=1, key=69, velocity=1.0))
  assert_eq(engine.process(128), 128)
  assert_true(engine.left_sample(0) != 0.0 || engine.right_sample(0) != 0.0)

  // Release note
  assert_true(engine.note_off(note_id=1, key=69))
}
```

## Note lifecycle and wildcards

CLAP note events specify both a `note_id` (a host-assigned tracking id) and a
MIDI `key` (0–127). The engine supports standard CLAP wildcard conventions:

- `note_off(note_id=X, key=Y)`: matches exact note id and key.
- `note_off(note_id=-1, key=Y)`: wildcard note id; releases all active notes
  matching `key`.
- `note_off(note_id=-1, key=-1)`: full wildcard; releases all currently held
  notes across all keys.

## Real-time allocation rule

`ClapSynthEngine::process` reuses preallocated scratch and voice buffers. It
does not allocate memory, resize collections, or trigger garbage collection
during audio block processing.
