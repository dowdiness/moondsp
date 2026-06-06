# moondsp CLAP prototype

This directory contains the native CLAP bring-up scaffold.

- `clap_payload.mbt` is a MoonBit native main package used to emit generated C
  for the `clap_host/` primitive handle bridge.
- `moondsp_clap.c` is the C CLAP ABI shim, compiled against the vendored
  official CLAP 1.2.8 headers in `../third_party/clap/`.
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

Run the pinned `clap-validator` check:

```bash
scripts/validate-clap-prototype.sh
```

Output:

```text
_build/native/release/clap/moondsp-synth.clap
```

Before production use, stabilize the MoonBit bridge symbols, load the plugin in
a real CLAP host/DAW, and complete the audio-thread allocation audit.
