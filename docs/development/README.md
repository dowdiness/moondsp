# Development, Audits & Hardware Verification

This directory contains point-in-time investigations, real-time allocation audits, host/DAW compatibility records, and architectural boundary inventories for `moondsp`.

These documents provide concrete empirical evidence that `moondsp` satisfies its core constraints: **hard real-time safety**, **zero-allocation audio callbacks**, and **robust multi-platform ABI compatibility**.

---

## Index of Verifications & Records

### 1. Real-Time Allocation & Audio Audits
- **[`2026-06-06-clap-audio-allocation-audit.md`](2026-06-06-clap-audio-allocation-audit.md)**  
  Verification of zero heap allocations (`malloc`, `calloc`, `realloc`) during audio processing via `scripts/audit-clap-audio-allocations.sh --expect-zero` using `LD_PRELOAD`.
- **[`2026-06-25-browser-sine-audio-worklet-probe.md`](2026-06-25-browser-sine-audio-worklet-probe.md)**  
  Empirical probe and telemetry analyzing real-time PCM rendering in browser AudioWorklet contexts.

### 2. Hardware & DAW Host Compatibility
- **[`2026-06-06-clap-bitwig-windows-host-load.md`](2026-06-06-clap-bitwig-windows-host-load.md)**  
  Verification of the cross-compiled Windows x86_64 PE DLL (`moondsp-synth.clap`) loaded and running in Bitwig Studio 6.0.6 on Windows 11.
- **[`2026-06-07-clap-host-coverage.md`](2026-06-07-clap-host-coverage.md)**  
  Compatibility matrix, test checklist, and verification protocols across multiple DAWs (Bitwig, Reaper, etc.).

### 3. Native Bridge & C ABI Probes
- **[`2026-06-07-clap-native-bridge-symbol-probe.md`](2026-06-07-clap-native-bridge-symbol-probe.md)**  
  Investigation of MoonBit native package export symbols and the generated header bridge guard (`moondsp_clap_moonbit.h`).
- **[`2026-09-08-clap-runtime-layout.md`](2026-09-08-clap-runtime-layout.md)**  
  Analysis of memory layout, handle allocations, and threading boundaries in the native CLAP runtime.

### 4. Architecture Boundary Inventories
- **[`graph-runtime-boundary-inventory.md`](graph-runtime-boundary-inventory.md)**  
  Comprehensive inventory of types, methods, and private state across `graph/internal/runtime`, formalizing boundary decisions for zero-allocation performance.
- **[`graph-facade-model-parity.md`](graph-facade-model-parity.md)**  
  Contributor guardrails for maintaining parity between the public graph facade and `graph/internal/model`.

### 5. DSP & Feature Research
- **[`2026-09-11-shared-reverb-research.md`](2026-09-11-shared-reverb-research.md)**  
  Research and evaluation for the shared stereo room-reverb bus integrated in release `v0.6.0`.
