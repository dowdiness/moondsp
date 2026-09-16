# moondsp basic synth

This example contains two UI adapters for the same monophonic instrument:

- [`vanilla/`](vanilla/) — framework-free TypeScript and explicit DOM projection
- [`svelte/`](svelte/) — Svelte 5 runes and declarative markup

Both consume the framework-independent implementation in [`core/`](core/) and only import the public `@moondsp/browser` package. The graph is:

```text
triangle oscillator → low-pass biquad → ADSR × signal → gain → output
```

The keyboard uses last-held-note priority. Its 13 notes run from C4 through C5 and use `A W S E D F T G Y H U J K`.

## Structure

```text
basic-synth/
├── core/                 Shared audio, graph, controls, keyboard, and styles
├── vanilla/              Framework-free DOM adapter
├── svelte/               Svelte 5 UI adapter
├── tests/                Shared browser lifetime scenarios
├── package.json          Shared dependencies and adapter scripts
└── package-lock.json     One resolved browser payload and frontend toolchain
```

The seam between `core/` and each UI adapter is `AudioView` / `AudioActions` in [`core/audio.ts`](core/audio.ts). UI adapters render lifecycle state and translate gestures into actions. `@moondsp/browser/audio` owns context admission, engine lifetime, and cleanup. Core code retains application UI state, serializes graph operations per session, and rejects stale command and note completions.

| File | Responsibility |
|---|---|
| [`core/synth.ts`](core/synth.ts) | Named graph parameters and pure raw note-control batches |
| [`core/notes.ts`](core/notes.ts) | Shared C4–C5 note table, key maps, and accessible labels |
| [`core/keyboard.ts`](core/keyboard.ts) | Pure last-held-note transitions and keyboard projections |
| [`core/input.ts`](core/input.ts) | Gesture interpretation, pointer-session tracking, note-input controller, and [`input.test.ts`](core/input.test.ts) |
| [`core/audio.ts`](core/audio.ts) | Package-owned power handles, application state projection, serialized commands, and note epochs |
| [`core/controls.ts`](core/controls.ts) | Pure transport projection and slider conversions |
| [`core/result.ts`](core/result.ts) | Explicit success/failure values and exception capture |
| [`vanilla/src/dom.ts`](vanilla/src/dom.ts) | Required-element acquisition, DOM rendering, and browser event wiring |
| [`svelte/src/App.svelte`](svelte/src/App.svelte) | Declarative rendering and Svelte event wiring over the shared core |

## Maintainer setup

From the repository root, build and pack the browser package, then install the shared example dependencies:

```sh
npm run pack:browser
cd examples/basic-synth
npm install ../../packages/browser/moondsp-browser-0.6.0.tgz
```

Run either adapter:

```sh
npm run dev:vanilla
npm run dev:svelte
```

Build both production applications with `npm run build`, or build one with `npm run build:vanilla` / `npm run build:svelte`. Preview them with `npm run preview:vanilla` / `npm run preview:svelte`.

When engine sources change, stop the development server, rebuild the tarball, reinstall it from this directory, and restart the selected adapter. Rebuilding the tarball alone does not replace the installed `node_modules` copy.

Consumers use the prebuilt package only; they do not need MoonBit or the moondsp source tree. Use HTTPS in production or localhost for development: AudioWorklet requires a secure context. The package also requires Wasm GC support.

## Controls and lifecycle

- **Volume** is linear gain from `0%` to `100%`; the graph starts at `15%`.
- **Filter** adjusts low-pass cutoff logarithmically from `120–12,000 Hz` and starts at `2,000 Hz`.
- **Power on** admits audio, loads the engine, mounts the graph, and enables playing. The same button becomes **Power off** while loading or running.
- **Power off** clears notes and retires that package-owned context/engine generation, even during startup.
- Processor failure is shown immediately. **Power on** retries with a fresh session.
- Releasing the active key returns to the most recently held pointer or computer key. Blur, hidden-page transitions, context suspension, pointer cancellation, and capture loss release notes.
- Power cycling preserves the displayed volume and cutoff.

## Verification

After installing the packed dependency, run from the repository root:

```sh
npm ci
npx playwright install chromium
npm --prefix examples/basic-synth run test:unit
npm run test:vanilla-synth
npm run test:svelte-synth
```

`test:unit` covers the shared notes table and gesture helpers. The Playwright commands execute [`tests/lifetime.spec.js`](tests/lifetime.spec.js) against each adapter. The scenarios cover processor failure recovery, normal context closure, cancellation during loading and mounting, stale resume completion, one-gesture startup, measured output, and release-to-silence.

For a manual check, activate Power on with the keyboard, hold and release a note, set volume to zero, and move focus away while holding a note. Confirm silence after release or blur and confirm that volume and cutoff survive a power cycle. Check touch input and keyboard scrolling on a narrow viewport.

These checks do not replace hardware listening, Safari/Firefox compatibility testing, or an audio-thread allocation/GC audit. No hard-real-time or cross-browser guarantee is implied.
