# moondsp CLAP prototype

This directory contains the native CLAP bring-up scaffold.

- `clap_payload.mbt` is a MoonBit native main package used to emit generated C
  for the `clap_host/` primitive handle bridge.
- `moondsp_clap.c` is the C CLAP ABI shim, compiled against the vendored
  official CLAP 1.2.8 headers in `../third_party/clap/`.
- `moondsp_clap_moonbit.h` is generated from the native payload C and maps the
  shim's stable `mb_engine_*` aliases to the current MoonBit-mangled
  `clap_host` symbols.

Build the Linux prototype:

```bash
scripts/build-clap-prototype.sh
```

Cross-build a Windows x86_64 prototype for Windows CLAP hosts such as Bitwig
Studio with MinGW-w64:

```bash
scripts/build-clap-prototype-windows.sh
```

Install the Windows build for the current user with:

```text
%LOCALAPPDATA%\Programs\Common\CLAP\moondsp-synth.clap
```

Run the local dlopen/process smoke test:

```bash
scripts/smoke-clap-prototype.sh
```

Regenerate the MoonBit bridge header after a MoonBit toolchain or package-name
change:

```bash
moon build --target native --release clap_plugin
scripts/generate-clap-moonbit-header.sh \
  _build/native/release/build/clap_plugin/clap_plugin.c \
  clap_plugin/moondsp_clap_moonbit.h
```

Run the pinned `clap-validator` check:

```bash
scripts/validate-clap-prototype.sh
```

Outputs:

```text
_build/native/release/clap/moondsp-synth.clap   # Linux ELF shared object
_build/windows/release/clap/moondsp-synth.clap # Windows x86_64 PE DLL
```

The Windows build has loaded in Bitwig Studio 6.0.6; see
`../docs/development/2026-06-06-clap-bitwig-windows-host-load.md`. Before
production use, complete the audio-thread allocation audit.
