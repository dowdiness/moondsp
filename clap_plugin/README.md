# moondsp CLAP prototype

This directory contains the native CLAP plugin payload, C ABI shim, build scripts, and validation tooling for DAW integration.

## Architecture context

In moondsp's native audio architecture, `clap_plugin` sits at the boundary between native DAWs and the MoonBit runtime:

```text
[ DAW / Host ] (Bitwig Studio, Reaper, etc.)
   ↓ CLAP 1.2.8 ABI (`clap_plugin_entry`, `clap_plugin_factory`)
[ moondsp_clap.c ] (C ABI shim, lifecycle & parameter events)
   ↕ Symbol header: `moondsp_clap_moonbit.h` (`mb_engine_*` aliases)
[ clap_payload.mbt ] (Native executable package anchoring MoonBit symbols)
   ↓ C ABI bridge
[ clap_host ] (Flat primitive integer-handle bridge)
   ↓ Native objects
[ clap_engine ] (ClapSynthEngine polyphonic synth core)
   ↓
[ voice ] / [ graph ] / [ dsp ]
```

- **Upstream Host / DAW**: Communicates with the shared library (`moondsp-synth.clap`) via standard CLAP 1.2.8 entrypoints and C function tables.
- **C ABI Shim (`moondsp_clap.c`)**: Implements `clap_plugin_t`, translates host parameter/note/transport events, initializes the runtime through `moonbit_init`, and interacts with MoonBit through stable `mb_engine_*` function aliases.
- **Symbol Bridge Header (`moondsp_clap_moonbit.h`)**: Declares the stable `mb_engine_*` symbols that `clap_payload.mbt` exports with `#export_name`.
- **Downstream dependencies**: [`clap_host/`](../clap_host/README.mbt.md) provides the flat integer-handle bridge functions; [`clap_engine/`](../clap_engine/README.mbt.md) drives the polyphonic synth engine.

## Component overview

| Component | File | Role & Responsibility |
|---|---|---|
| **C ABI Shim** | `moondsp_clap.c` | Implements CLAP 1.2.8 plugin interface (`audio-ports`, `note-ports`, `params`), manages MoonBit runtime lifecycle, and routes host events to MoonBit |
| **Bridge Header** | `moondsp_clap_moonbit.h` | Hand-maintained declarations of the exported `mb_engine_*` symbols; the build scripts compile the payload C with it included, so signature drift fails the build |
| **Payload Exports** | `clap_payload.mbt` | `foreign_library` package whose `#export_name` wrappers export the `clap_host` functions under stable C names |
| **Build Scripts** | `scripts/build-clap-prototype*.sh` | Compiles native MoonBit C payload, builds C shim, links MoonBit runtime, and produces `.clap` shared library (Linux ELF / Windows MinGW DLL) |
| **Validator** | `scripts/validate-clap-prototype.sh` | Builds plugin and executes automated verification using pinned `clap-validator` |
| **Smoke Runner** | `scripts/smoke-clap-prototype.sh` | Headless dynamic-linking (`dlopen`) smoke test validating plugin factory, activation, and audio processing |

## Build and verification

### 1. Build Linux prototype

```bash
scripts/build-clap-prototype.sh
```

### 2. Cross-build Windows prototype (x86_64)

Cross-build a Windows x86_64 prototype for Windows CLAP hosts such as Bitwig Studio using MinGW-w64:

```bash
scripts/build-clap-prototype-windows.sh
```

Install the Windows build for the current user:

```text
%LOCALAPPDATA%\Programs\Common\CLAP\moondsp-synth.clap
```

### 3. Run dlopen smoke test

Run the local headless `dlopen` and processing smoke test:

```bash
scripts/smoke-clap-prototype.sh
```

### 4. Change the bridge ABI

When a `clap_host` primitive is added or changes signature, update its
`#export_name` wrapper in `clap_payload.mbt` and its declaration in
`moondsp_clap_moonbit.h` together. The build scripts fail on a mismatch.

### 5. Automated CLAP validator

Run the official pinned `clap-validator` suite:

```bash
scripts/validate-clap-prototype.sh
```

## Build artifacts

```text
_build/native/release/clap/moondsp-synth.clap   # Linux ELF shared object
_build/windows/release/clap/moondsp-synth.clap # Windows x86_64 PE DLL
```

## Host compatibility & real-time safety

- **Host validation**: The Windows build has loaded and rendered in Bitwig Studio 6.0.6; see [`docs/development/2026-06-06-clap-bitwig-windows-host-load.md`](../docs/development/2026-06-06-clap-bitwig-windows-host-load.md).
- **Audio-thread safety**: Plugin activation (`moondsp_plugin_activate`) initializes runtime resources and allocates the engine handle. During the steady-state `process` callback, scalar sample accessors (`engine_left_sample`, `engine_right_sample`) read directly from preallocated buffers without heap allocations. Before production use, a whole-thread allocation audit remains a required gate.

