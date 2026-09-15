# moondsp vanilla synth

This framework-free Vite page is a small, monophonic instrument built against the public `@moondsp/browser` package. It authors one graph:

```text
triangle oscillator → low-pass biquad → ADSR × signal → gain → output
```

The keyboard uses last-held-note priority. There is one voice: pressing a new note changes frequency and gates the envelope; releasing it returns to the most recently held pointer or computer-key note. The 13 notes run from C4 through C5 and use `A W S E D F T G Y H U J K`. Click and hold the on-screen keys, or hold their computer-key equivalents.

For the underlying graph descriptions, atomic control batches, cancellation,
and engine termination contract, see the
[browser API guide](../../docs/browser-api-contract.md). Applications written
in JavaScript or TypeScript do not need the separate MoonBit host binding.

## Reading the source

Start with [`src/main.ts`](src/main.ts), the composition root. Initialization
follows an explicit success/failure path:

```ts
const started = andThen(readPage(document, PAGE_BINDINGS), elements => startApplication(elements, PAGE_BINDINGS));
if (!started.ok) reportStartupFailure(document, started.error, PAGE_BINDINGS.selectors);
```

`readPage` acquires all required DOM nodes before any event registration or audio
creation. A failed acquisition skips `startApplication`. On success, the
application connects the DOM and audio actions. Audio stays off until Power on.

| [`src/synth.ts`](src/synth.ts) | Named graph parameter declarations/references and pure raw note-control batches |
| [`src/dom.ts`](src/dom.ts) | Acquires DOM nodes, reads gestures, applies projections, and registers browser events |
| [`src/audio.ts`](src/audio.ts) | Owns audio resources and calls the public moondsp API, with serialized operations and stale-work rejection |
| [`src/result.ts`](src/result.ts) | Explicit success/failure values, short-circuit composition, and exception capture at action boundaries |

The pure modules need no browser globals. Keyboard transitions return a new
state and an optional note action; they neither modify their input nor play
audio. The DOM edge interprets that action. Audio receives settings as values
instead of reading slider elements.

To follow the sound path, read `SYNTH_GRAPH` in `synth.ts`, then
`createAudioOwner().open()` in `audio.ts`: admit the context in the Power on
gesture, suspend it for mounting, initialize `GraphEngine()`, mount the graph,
apply the current UI settings through `setParams({ volume, cutoff })`, call
`play()`, resume the context, and connect output. The graph declares those two
names with `DEFAULT_SETTINGS` as initial values; the settings record is kept by
the UI across power cycles. Note frequency and gate remain one raw,
atomic `applyControls` batch so note epoch cancellation and keyboard policy
stay unchanged.

One `AudioOwner` releases both partially acquired resources and the complete
session. Its idempotent `close()` cancels initialization and observation,
disconnects output, closes the engine and all its graphs, then closes the
app-owned context. Every release is attempted; the first cleanup failure is
retained. A retry admits its new context before any await to preserve the user
gesture, but waits for the previous owner's cleanup before creating its engine.

Commands serialize within each session and route their `Result` failures to
lifecycle error handling. Retirement does not wait behind those commands, so
pending mount or resume work cannot prevent cleanup or block the next session.
Session identity rejects old completions; the session's note epoch rejects
notes queued before automatic note release. No global lifecycle counter or
command queue remains. The first `resume()` runs directly in the Power on
gesture, before the first await; loading and suspended mounting happen afterward.
An independently cancellable `engine.wait()` observer reports runtime failure
without waiting for the next control action. Cleanup does not send note-off or
unmount requests to a dead Worklet.

### Changing the page markup

`PAGE_BINDINGS` in `main.ts` supplies the page-specific names to the DOM actions:

- `selectors`: CSS selectors for required controls, note buttons and labels, and editable targets that should not play computer-key notes.
- `classes`: single class-name tokens for held/active note feedback, without a leading `.`.
- `data`: `dataset` keys for note pitch, computer-key bindings, transport phase, and active-note feedback. Use camelCase (`computerKey` corresponds to `data-computer-key`).

When changing IDs, classes, or data attributes, update this configuration and the
matching HTML/CSS together. `readPage`, `createDomConnection`, and startup-error
reporting receive their bindings as arguments; they have no built-in page-name
defaults. Standard event names and ARIA attributes remain browser contracts,
not page configuration.

## Maintainer setup

This requires Node.js/npm and the MoonBit toolchain. The build wrapper keeps
`NEW_MOON_MOD=0` set for its MoonBit invocation.

From the repository root, build and pack the browser package first:

```sh
npm run pack:browser
cd examples/vanilla-synth
npm install ../../packages/browser/moondsp-browser-0.6.0.tgz
npm run dev
```

Use `npm run build` for a production bundle and `npm run preview` to serve that bundle locally. The Vite configuration keeps the package's AudioWorklet processor and WebAssembly file as separate production assets and uses relative URLs for subpath deploys.

The page starts with audio off and no `AudioContext`. One **Power on** action
performs admission, loading, and playback startup; no separate Start action is
needed. During loading, the same button becomes **Power off** so startup can be
cancelled. The existing suspended-mount restriction is preserved inside this
flow rather than exposed as another user step.

When engine sources change, stop the example development server, run
`npm run pack:browser` from the repository root again, then repeat the tarball
installation and restart `npm run dev` in this directory. Rebuilding the
tarball alone does not replace the copy already installed in `node_modules`.

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
- **Power on** initializes the instrument and enables playing when loading finishes. The same button then offers **Power off**.
- **Power off** clears held notes, disconnects output, closes the engine and all its graphs, and closes the app-owned `AudioContext`. It also cancels startup while loading.
- Releasing a key sends gate-off and lets the 180 ms envelope release finish. Window blur, hidden-page transitions, pointer cancellation/capture loss, and context suspension also release notes automatically; there is no Stop notes button.
- Page disposal closes audio resources. Processor failures immediately disable controls and show an error; **Power on** retries through the same button. External context closure is normal termination, not an error.
- The graph's `volume` and `cutoff` names are shared parameter targets. Their
  declared values are mount-time initial values; `setParams` writes the current
  UI value to every matching target and does not maintain a hidden current-value
  cache. Named updates are serialized with lifecycle and note commands. Raw
  `applyControls` remains available alongside them: this synth deliberately
  keeps frequency plus gate-on/off in one raw batch, rather than splitting
  notes into parameter and gate calls.
- The piano layout shows computer-key shortcuts on desktop. The active note is orange with a filled marker; other held notes are pale with an outlined marker. The **Mono** readout identifies the active note, not an audio level; releasing a key can leave a short envelope tail after the readout clears.
- Focus a note and hold **Space** or **Enter** to play it without a mouse. At narrow widths, use the left/right buttons or swipe the keyboard to reach more notes. Navigation buttons disable at the corresponding end and disappear when the full keyboard fits. Starting a swipe releases the touched note.
- Power cycling preserves the displayed volume and cutoff. After a browser suspends an active context, the status reads **Audio paused** and **Power on** resumes the existing session.

## Verification

Build and install the tarball with the maintainer setup above. Then, from the
repository root:

```sh
npm ci
npx playwright install chromium
npm run test:vanilla-synth
```

The command starts a Vite server on port 4187 and runs Chromium regressions
against the packed and installed package:

- Processor failure notification and fresh-engine recovery through Power on.
- Normal context closure and isolation from a retired engine's late failure.
- Cancellation during Wasm loading and during a pending mount.
- Session replacement while an old resume completion is delayed.
- One-click playback after transient user activation expires during loading,
  including measured DSP output and release-to-silence.

The activation test reads through CDP without granting another user gesture;
ordinary Playwright evaluation would renew activation and invalidate the check.
Chromium runs with `--autoplay-policy=user-gesture-required`.

For a manual check, activate Power on with the keyboard, hold and release a
note, set volume to zero, and move focus away while holding a note. Confirm
silence after release or blur, and confirm that volume and cutoff survive a
power cycle. Check touch input and keyboard scrolling on a narrow viewport.

Run `npm run build` in this example directory for TypeScript checking and a
production bundle. Use `npm run preview` to check the emitted Worklet and Wasm
assets, not just the development server.

These checks do not replace hardware listening, Safari/Firefox compatibility
testing, or an audio-thread allocation/GC audit. No hard-real-time or
cross-browser guarantee is implied.
