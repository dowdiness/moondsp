# Performance Baseline — 2026-04-09 (Pre-Architecture Redesign)

Snapshot before architecture restructuring (dispatch dedup + package split).

## Process (µs, mean @ 128 samples)

| Graph | 64 | 128 | 256 |
|-------|-----|------|------|
| passthrough | 0.39 | 0.78 | 1.64 |
| minimal_voice | 1.30 | 2.85 | 5.64 |
| fm_voice | 6.88 | 16.86 | 29.56 |
| full_voice | 3.71 | 6.62 | 13.88 |
| feedback_voice | 5.61 | 9.26 | 18.17 |
| stereo_chain | 5.66 | 8.97 | 24.17 |

## Compile (µs, mean)

| Graph | Time |
|-------|------|
| passthrough | 1.90 |
| minimal_voice | 3.01 |
| fm_voice | 9.27 |
| full_voice | 13.17 |
| feedback_voice | 13.12 |
| stereo_chain | 24.17 |

## Hot-swap (µs, mean @ 128 samples)

| Graph | 64 | 128 | 256 |
|-------|-----|------|------|
| minimal_voice | 7.75 | 24.81 | 31.22 |
| fm_voice | 11.18 | 22.11 | 42.16 |
| full_voice | 13.71 | 27.50 | 51.61 |
| stereo_chain | 15.18 | 23.12 | 43.89 |

## Topology (µs, mean @ 128 samples)

| Edit | 64 | 128 | 256 |
|------|-----|------|------|
| replace_node | 25.32 | 35.20 | 71.08 |
| insert_delete_roundtrip | 46.11 | 79.72 | 151.72 |

## Environment

- Tests: 531 pass, 0 fail
- MoonBit WASM-GC target
- WSL2 Linux 6.6.87.2
