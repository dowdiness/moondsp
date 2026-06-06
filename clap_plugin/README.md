# moondsp CLAP prototype

This directory contains the native CLAP bring-up scaffold.

- `clap_payload.mbt` is a MoonBit native main package used to emit generated C
  for the `clap_host/` primitive handle bridge.
- `moondsp_clap.c` is the C CLAP ABI shim.
- `clap_minimal.h` is a temporary local subset of CLAP headers for prototype
  compilation.
- `moondsp_clap_moonbit.h` declares the current MoonBit-mangled payload symbols
  used by the shim.

Build on Linux:

```bash
scripts/build-clap-prototype.sh
```

Run the local dlopen/process smoke test:

```bash
scripts/smoke-clap-prototype.sh
```

Output:

```text
_build/native/release/clap/moondsp-synth.clap
```

Before production use, replace/verify the minimal CLAP header against official
CLAP headers and run `clap-validator`.
