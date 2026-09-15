# moondsp Svelte synth

This Svelte 5/Vite page is a small, monophonic instrument built against the public `@moondsp/browser` package. It authors one graph:

```text
triangle oscillator → low-pass biquad → ADSR × signal → gain → output
```

The keyboard uses last-held-note priority. There is one voice: pressing a new note changes frequency and gates the envelope; releasing it returns to the most recently held pointer or computer-key note. The 13 notes run from C4 through C5 and use `A W S E D F T G Y H U J K`.

For the framework-free implementation of the same instrument, see [`../vanilla-synth`](../vanilla-synth/README.md). Both examples keep the audio lifecycle and graph code separate from their UI implementation.

## Reading the source

Start with [`src/App.svelte`](src/App.svelte). It declares the controls, keyboard markup, projected UI state, and browser event handlers in one component. Svelte owns DOM creation and reactive attributes, so this version has no selector registry, required-element acquisition pass, or manual render functions.

| File | Responsibility |
|---|---|
| [`src/App.svelte`](src/App.svelte) | Declarative controls and keyboard, browser gestures, pointer capture, and the `AudioView` connection |
| [`src/synth.ts`](src/synth.ts) | Named graph parameters and pure raw note-control batches |
| [`src/keyboard.ts`](src/keyboard.ts) | Pure last-held-note transitions and keyboard projections |
| [`src/audio.ts`](src/audio.ts) | Audio resource ownership, serialized operations, and stale-work rejection |
| [`src/controls.ts`](src/controls.ts) | Pure transport projection and slider conversions |
| [`src/result.ts`](src/result.ts) | Explicit success/failure values and exception capture at action boundaries |

The component generates all piano keys from one note table. `<svelte:window>` and `<svelte:document>` own global listeners and remove them with the component. Range handlers read `HTMLInputElement.valueAsNumber` from the event before updating both Svelte state and the audio engine, so UI and audio values cannot diverge through binding order.

The framework-independent modules intentionally match the vanilla example. `AudioOwner` still releases partial and complete sessions, command serialization remains per session, and old asynchronous completions cannot publish into a replacement session.

## Maintainer setup

This requires Node.js/npm and the MoonBit toolchain. From the repository root, build and pack the browser package first:

```sh
npm run pack:browser
cd examples/svelte-synth
npm install
npm run dev
```

Use `npm run build` for Svelte/TypeScript checking and a production bundle. Use `npm run preview` to check the emitted Worklet and Wasm assets, not only the development server. The Vite configuration keeps those assets separate and uses relative URLs for subpath deployment.

When engine sources change, stop the example development server, run `npm run pack:browser` from the repository root, reinstall in this directory, and restart `npm run dev`. Rebuilding the tarball alone does not replace the installed `node_modules` copy.

Consumers use the prebuilt package only; they do not need MoonBit or the moondsp source tree. Use HTTPS in production or localhost for development: AudioWorklet requires a secure context. The package also requires Wasm GC support.

## Controls and lifecycle

- **Volume** is linear gain from `0%` to `100%`; the graph starts at `15%`.
- **Filter** adjusts low-pass cutoff logarithmically from `120–12,000 Hz` and starts at `2,000 Hz`.
- **Power on** admits audio, loads the engine, mounts the graph, and enables playing. The same button becomes **Power off** while loading or running.
- **Power off** cancels startup or clears notes and closes the graph, engine, and app-owned `AudioContext`.
- Processor failure is shown immediately. **Power on** retries with a fresh session.
- Releasing the active key returns to the most recently held pointer or computer key. Blur, hidden-page transitions, context suspension, pointer cancellation, and capture loss release notes.
- Power cycling preserves the displayed volume and cutoff.

## Verification

Build and install the packed browser dependency first. Then, from the repository root:

```sh
npm ci
npx playwright install chromium
npm run test:svelte-synth
```

The command starts the Svelte Vite application on port 4188 and runs Chromium regressions for processor failure recovery, normal context closure, cancellation during loading and mounting, stale resume completion, one-gesture startup, measured output, and release-to-silence.

For a manual check, activate Power on with the keyboard, hold and release a note, set volume to zero, and move focus away while holding a note. Confirm silence after release or blur and confirm that volume and cutoff survive a power cycle. Check touch input and keyboard scrolling on a narrow viewport.

These checks do not replace hardware listening, Safari/Firefox compatibility testing, or an audio-thread allocation/GC audit. No hard-real-time or cross-browser guarantee is implied.
