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
- `moondsp_clap_moonbit.h`: generated declarations mapping stable
  `mb_engine_*` C aliases to the current MoonBit-mangled `clap_host` bridge
  symbols; `scripts/generate-clap-moonbit-header.sh` regenerates or verifies it
  from the native payload C.

`third_party/clap/` vendors the official CLAP 1.2.8 C headers used by the
prototype build and smoke test.

Build the Linux prototype shared object with:

```bash
scripts/build-clap-prototype.sh
```

Cross-build a Windows x86_64 prototype for Windows CLAP hosts such as Bitwig
Studio with MinGW-w64:

```bash
scripts/build-clap-prototype-windows.sh
```

Run a local dlopen/process smoke test with a timestamped note event:

```bash
scripts/smoke-clap-prototype.sh
```

This produces:

```text
_build/native/release/clap/moondsp-synth.clap   # Linux ELF shared object
_build/windows/release/clap/moondsp-synth.clap # Windows x86_64 PE DLL
```

Both builds verify `clap_plugin/moondsp_clap_moonbit.h` against the generated
MoonBit payload C, then compile that payload plus the C CLAP shim into a native
CLAP shared object exporting `clap_entry`.

Validation:

```bash
moon check --target all
moon test clap_engine --target native
moon test clap_host --target native
scripts/build-clap-prototype.sh
scripts/build-clap-prototype-windows.sh
scripts/smoke-clap-prototype.sh
scripts/validate-clap-prototype.sh
```

## Bridge-symbol guard

MoonBit native package exports do not currently provide stable C aliases for the
`clap_host` primitives, so the prototype keeps the C shim on stable
`mb_engine_*` aliases and generates their mapping to MoonBit's package-mangled
payload symbols. `scripts/build-clap-prototype.sh` and
`scripts/build-clap-prototype-windows.sh` fail if
`clap_plugin/moondsp_clap_moonbit.h` is stale for the generated payload.

## Remaining risks

- The Linux `.clap` passes the local dlopen/process smoke test and
  `clap-validator` 0.3.2 via `scripts/validate-clap-prototype.sh`.
- The Windows cross-built `.clap` has been checked as an x86_64 PE DLL exporting
  `clap_entry` and loaded successfully in Bitwig Studio 6.0.6 on Windows 11.
  See `docs/development/2026-06-06-clap-bitwig-windows-host-load.md`.
- The engine still creates voices from note events through the current voice
  pool path. Do a hard real-time allocation audit once host loading works.

## Next slice

1. Audit audio-callback allocations and move any remaining allocation-heavy work
   to activation/control-side preparation.
2. Exercise additional hosts/DAWs as the prototype matures.

## Real-time cautions

- Do not parse mini-notation or compile graphs in the CLAP audio callback.
- Preallocate for CLAP's max block size during activation.
- Keep process-block splitting around CLAP event timestamps intact when adding
  more event types or automation paths.
- Treat current CLAP support as a bring-up prototype until host-load coverage is
  broader and the audio-thread allocation audit is complete.
