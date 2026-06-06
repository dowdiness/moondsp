# moondsp CLAP prototype

This directory contains the native CLAP bring-up scaffold.

- `clap_payload.mbt` is a MoonBit native main package used to emit generated C
  for the `clap_host/` primitive handle bridge.
- `moondsp_clap.c` is the C CLAP ABI shim, compiled against the vendored
  official CLAP 1.2.8 headers in `../third_party/clap/`.
- `moondsp_clap_moonbit.h` is generated from the native payload C and maps the
  shim's stable `mb_engine_*` aliases to the current MoonBit-mangled
  `clap_host` symbols.

Build on Linux:

```bash
scripts/build-clap-prototype.sh
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

Output:

```text
_build/native/release/clap/moondsp-synth.clap
```

Before production use, load the plugin in a real CLAP host/DAW and complete the
audio-thread allocation audit.
