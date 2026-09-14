# moondsp basic synth

This standalone Vite page is a small, monophonic instrument built against the public `@moondsp/browser` package. It authors one graph:

```text
triangle oscillator → low-pass biquad → ADSR × signal → gain → output
```

The keyboard uses last-held-note priority. There is one voice: pressing a new note changes frequency and gates the envelope; releasing it returns to the most recently held pointer or computer-key note. The 13 notes run from C4 through C5 and use `A W S E D F T G Y H U J K`. Click and hold the on-screen keys, or hold their computer-key equivalents.

## Reading the source

Start with [`src/main.ts`](src/main.ts), the composition root. Initialization
follows an explicit success/failure path:

```ts
const started = andThen(readPage(document), startApplication);
if (!started.ok) reportStartupFailure(document, started.error);
```

`readPage` acquires all required DOM nodes before any event registration or audio
creation. A failed acquisition skips `startApplication`. On success, the
application connects the DOM and audio actions, then initializes the instrument.

| File | Responsibility |
| --- | --- |
| [`src/main.ts`](src/main.ts) | Connects the outer actions and handles startup failure |
| [`src/controls.ts`](src/controls.ts) | Pure transport presentation, slider conversion, and error-message calculation |
| [`src/keyboard.ts`](src/keyboard.ts) | Pure held-note transitions, note-action decisions, and keyboard/navigation projections |
| [`src/synth.ts`](src/synth.ts) | Graph description and pure construction of parameter/gate control batches |
| [`src/dom.ts`](src/dom.ts) | Acquires DOM nodes, reads gestures, applies projections, and registers browser events |
| [`src/audio.ts`](src/audio.ts) | Owns audio resources and calls the public moondsp API, with serialized operations and stale-work rejection |
| [`src/result.ts`](src/result.ts) | Explicit success/failure values, short-circuit composition, and exception capture at action boundaries |

The pure modules need no browser globals. Keyboard transitions return a new
state and an optional note action; they neither modify their input nor play
audio. The DOM edge interprets that action. Audio receives settings as values
instead of reading slider elements.

To follow the sound path, read `SYNTH_GRAPH` in `synth.ts`, then `GraphEngine()`,
`mount()`, and `applyControls()` in `audio.ts`. The audio queue returns a
`Result` for each operation and routes failures to lifecycle error handling.
`resume()` still runs directly in the Start gesture, before the first await.
Cleanup is intentionally different from the short-circuit success path: it
attempts every owned resource and retains the first failure.

## Maintainer setup

From the repository root, build and pack the browser package first:

```sh
npm run pack:browser
cd examples/basic-synth
npm install ../../packages/browser/moondsp-browser-0.6.0.tgz
npm run dev
```

Use `npm run build` for a production bundle and `npm run preview` to serve that bundle locally. The Vite configuration keeps the package's AudioWorklet processor and WebAssembly file as separate production assets and uses relative URLs for subpath deploys.

On page load, the example initializes the audio engine and mounts the graph in a suspended `AudioContext`. The play icon and **Start** button perform the actual resume from the button gesture, then start the mounted graph. This two-step flow is intentional: graph mounting must happen while the context is suspended, while browser audio admission must come from a real user gesture.

## Using a packed package elsewhere

Copy `packages/browser/moondsp-browser-0.6.0.tgz` to another directory, create or copy this example there, and install the tarball:

```sh
npm install ./moondsp-browser-0.6.0.tgz
npm run build
npm run preview
```

Consumers use the prebuilt package only; they do not need MoonBit or the moondsp source tree. Use HTTPS in production or localhost for development: AudioWorklet requires a secure context. Opening `index.html` with `file://` is not supported. The package uses Wasm GC; a browser supporting both Wasm GC and AudioWorklet is required. Deployment CSP must allow its Wasm compilation and same-origin asset/Worklet loads.

## Controls and lifecycle

- **Volume** is linear gain from `0%` to `100%`; the graph starts at `15%`. Keep device volume low when first trying the instrument.
- **Filter** adjusts the low-pass cutoff logarithmically from `120–12,000 Hz` and starts at `2,000 Hz`.
- **Stop notes** is enabled while notes are held. It sends gate-off, clears the held-key display, and leaves the graph running so the 180 ms release can finish.
- **Power off** releases notes, unmounts and closes the engine, disconnects output, and closes the app-owned `AudioContext`. The next action is **Power on**, followed by **Loading…**, then **Start** once audio is ready.
- Window blur, hidden-page transitions, pointer cancellation/capture loss, and page disposal all release or clean up their resources. Errors keep the UI honest and offer a retry instead of leaving a stuck note.
- The piano layout shows computer-key shortcuts on desktop. The active note is orange with a filled marker; other held notes are pale with an outlined marker. The **Mono** readout identifies the active note, not an audio level; releasing a key can leave a short envelope tail after the readout clears.
- Focus a note and hold **Space** or **Enter** to play it without a mouse. At narrow widths, use the left/right buttons or swipe the keyboard to reach more notes. Navigation buttons disable at the corresponding end and disappear when the full keyboard fits. Starting a swipe releases the touched note.
- Reinitialization preserves the displayed volume and cutoff. **Power on** loads a fresh engine; **Start** resumes it from a fresh user gesture.

## Verification

The example was exercised in Chromium with virtual audio output, including
audible-signal PCM measurement, release-to-silence, note priority, volume/cutoff
changes, pointer/keyboard release, context suspension, disposal, and asset-error
retry. The same checks passed against a repository-external Vite development
server and production files served under `/synth/`.

Visual-state checks additionally cover loading and power labels, active versus
held notes against measured pitch, overlapping pointer/keyboard holds of the
same pitch, and mobile navigation buttons, swiping, and resize boundaries.

The effect-separated version was also checked for missing-DOM startup
short-circuiting (no audio context or Wasm download), cancellation during page
exit, context-suspension recovery, and pure note transitions without browser
globals. The refactored source passed the development and production consumer
checks above.

These checks do not replace hardware listening, Safari/Firefox compatibility
testing, or an audio-thread allocation/GC audit. No hard-real-time or
cross-browser guarantee is implied.
