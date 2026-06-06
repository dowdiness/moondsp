# CLAP plugin bring-up plan

This is the native-plugin path for moondsp. The current prototype has three
layers:

```text
DAW / CLAP host
  -> clap_plugin/moondsp_clap.c       C CLAP ABI shim
  -> clap_host/                       primitive MoonBit handle bridge
  -> clap_engine/                     MoonBit synth engine
  -> moondsp graph + voice pool
```

## Current slice

`clap_engine/` provides:

- a fixed default synth template with stable node indices for CLAP parameter
  binding;
- `ClapSynthEngine::new(sample_rate?, max_block_size?, max_voices?)`;
- CLAP-style `note_on(note_id~, key~, velocity~)` and
  `note_off(note_id~, key~)`;
- parameter ids for master gain, voice gain, cutoff, resonance, and pan;
- `process(frame_count)` plus `left_sample(i)` / `right_sample(i)` accessors.

`clap_host/` wraps that object API in positive integer handles and primitive
functions so C does not need to understand MoonBit objects, `Result`, or
`Option` layouts.

`clap_plugin/` contains:

- `clap_payload.mbt`: a native main package that forces MoonBit to emit the
  CLAP payload C for `clap_host`;
- `moondsp_clap.c`: descriptor/factory/plugin callbacks, audio/note/param
  extensions, event translation, and output copying through the official CLAP
  headers;
- `moondsp_clap_moonbit.h`: declarations for the current MoonBit-mangled bridge
  symbols.

`third_party/clap/` vendors the official CLAP 1.2.8 C headers used by the
prototype build and smoke test.

Build the Linux prototype shared object with:

```bash
scripts/build-clap-prototype.sh
```

Run a local dlopen/process smoke test with a timestamped note event:

```bash
scripts/smoke-clap-prototype.sh
```

This produces:

```text
_build/native/release/clap/moondsp-synth.clap
```

The build compiles the MoonBit generated C payload plus the C CLAP shim into an
ELF shared object exporting `clap_entry`.

Validation:

```bash
moon check --target all
moon test clap_engine --target native
moon test clap_host --target native
scripts/build-clap-prototype.sh
scripts/smoke-clap-prototype.sh
scripts/validate-clap-prototype.sh
```

## Remaining risks

- `moondsp_clap_moonbit.h` currently names MoonBit-mangled symbols from the
  generated C payload. This is acceptable for bring-up, but a durable build
  should either generate this header or use stable native exports if MoonBit
  exposes them.
- The produced `.clap` passes the local dlopen/process smoke test and
  `clap-validator` 0.3.2 via `scripts/validate-clap-prototype.sh`, but has not
  yet been loaded in a DAW in this repo session.
- The engine still creates voices from note events through the current voice
  pool path. Do a hard real-time allocation audit once host loading works.

## Next slice

1. Generate `moondsp_clap_moonbit.h` from the built payload C, or add a stable
   native export path if the MoonBit toolchain supports one.
2. Load the built plugin in a real CLAP host/DAW after validator stays green.
3. Audit audio-callback allocations and move any remaining allocation-heavy work
   to activation/control-side preparation.

## Real-time cautions

- Do not parse mini-notation or compile graphs in the CLAP audio callback.
- Preallocate for CLAP's max block size during activation.
- Keep process-block splitting around CLAP event timestamps intact when adding
  more event types or automation paths.
- Treat current CLAP support as a bring-up prototype until DAW tests pass and
  the audio-thread allocation audit is complete.
