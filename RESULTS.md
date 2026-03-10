# Step 0 Results

This file records the outcome of the Phase 0 MoonBit `wasm-gc` AudioWorklet
experiment.

## Current Status

- MoonBit exports `tick` and `reset_phase` from the root package for the
  `wasm-gc` and `js` backends.
- `web/index.html` and `web/processor.js` provide the browser demo scaffold.
- `serve.sh` copies the built `.wasm` into `web/` and starts a local server.
- Browser validation has not been completed yet in this environment.

## How To Run

1. `moon build --target wasm-gc --release`
2. `./serve.sh`
3. Open `http://localhost:8080`
4. Click `Start Audio`
5. Move the frequency slider and listen for smooth pitch change

## What To Check

- The page loads without console errors
- The processor reports `ready`
- `tick` appears in the wasm exports logged in the browser console
- A sine wave plays continuously for at least 30 seconds without glitches
- The frequency slider changes pitch without obvious clicks or pops

## Open Questions

- Does the generated `wasm-gc` module instantiate in the target browser without
  extra imports beyond the current stubs?
- Does the browser show any GC-related glitches during sustained playback?
- Is the current `wasm-gc` path viable enough to keep as the default browser
  backend, or should the project prefer the `js` backend for AudioWorklet?
