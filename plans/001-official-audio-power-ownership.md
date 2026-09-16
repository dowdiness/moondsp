# Plan 001: Add owned audio power lifecycle

> **Executor instructions**: Read this plan completely before editing. Execute the steps in order. Run each verification command where specified. If a STOP condition occurs, stop and report the evidence instead of changing the contract. Mark this plan `DONE` in `plans/README.md` only after every done criterion passes.
>
> **Drift check**: this plan was written against commit `3073004` on 2026-09-15. Before implementation, run:
>
> ```bash
> git diff --stat 3073004..HEAD -- \
>   docs/browser-api-contract.md \
>   packages/browser/host/moon.mod packages/browser/host/lifetime.mbt \
>   packages/browser/host/browser_test \
>   web/graph-engine.js web/graph-engine.d.ts \
>   web/audio-power.js web/audio-power.d.ts \
>   scripts/build-browser-package.mjs scripts/build-audio-power-core.mjs \
>   packages/browser/package.json packages/browser/README.md \
>   package.json playwright-serve.sh .gitignore \
>   README.mbt.md .github/workflows/browser-smoke.yml \
>   playwright-tests examples/basic-synth CHANGELOG.md
> ```
>
> If an in-scope file has changed, compare the live behavior with the repository baseline below. A semantic mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: DX / browser audio reliability

## Goal

Add an opt-in `@moondsp/browser/audio` interface for applications that want the package to own a realtime `AudioContext`, its `GraphEngine`, and their complete power lifecycle. Implement lifecycle orchestration in the existing MoonBit JS-host module; keep JavaScript as the narrow Web API and npm-facing adapter.

The interface must let an application:

1. turn audio on directly from a user gesture;
2. set up one or more graphs while the context is suspended;
3. observe when setup is ready;
4. resume after an operating-system or device interruption;
5. turn off exactly the powered-audio generation it holds;
6. observe clean turn-off separately from failure; and
7. start a replacement power cycle without overlapping the predecessor engine.

Keep `GraphEngine` unchanged for applications that need caller-owned contexts, `OfflineAudioContext`, or custom output routing.

## Domain language

Use these terms consistently in code, tests, and documentation.

| Term | Meaning |
|---|---|
| **Audio power** | An application-scoped owner that coordinates repeated power cycles. Represented by `AudioPower`. |
| **Power cycle** | One call to `AudioPower.turnOn()`, from context admission through final cleanup. |
| **Powered audio** | The generation-scoped capability returned by `turnOn()`. Represented by `PoweredAudio<Value>`. |
| **Audio setup** | The suspended-context callback that mounts and configures graphs. Represented by `AudioSetup`. |
| **Power off** | Retirement of one powered-audio generation. Setup observes it through `AudioSetup.powerOff`; callers request it through `PoweredAudio.turnOff()`. |
| **Audio end** | The retained terminal result of a power cycle. Represented by `AudioEnd`. |

One `AudioPower` value permits at most one generation that has not started turning off. Different `AudioPower` values are independent and must never block each other.

## Repository baseline

### Low-level engine ownership

`GraphEngine` is intentionally a low-level interface. `web/graph-engine.d.ts:104-125` requires a caller-owned `AudioContext | OfflineAudioContext`; `GraphEngine.close()` closes the engine but leaves that context open.

`docs/browser-api-contract.md:81-87` defines realtime admission ordering:

1. call `AudioContext.resume()` from the user gesture before the first asynchronous boundary;
2. suspend the admitted context;
3. create the engine and mount graphs while suspended; and
4. resume after setup.

The new module owns this ordering. It does not change `GraphEngine`.

### Existing MoonBit JS host

`packages/browser/host` is the separate JS-target MoonBit module
`dowdiness/moondsp-browser-host`. It already depends on
`moonbitlang/async@0.21.3` and proves the required interop:

- `lifetime.mbt` wraps an opaque JavaScript `GraphEngine`, awaits
  `engine.wait({ signal })`, closes the engine under cancellation protection,
  and retains native error identity;
- `browser_test/driver.mbt` exports Promise-returning MoonBit functions to
  JavaScript and uses structured concurrency; and
- `.github/workflows/browser-smoke.yml` checks and tests this module on the JS
  target.

Build the new production bridge as an executable package inside this module,
not in the `browser/` Wasm/AudioWorklet package. The page-side owner must remain
in the browser control realm; moving it into the audio-render Wasm would mix
platform lifecycle with realtime DSP.

The existing host test driver builds to about 198 KB raw / 17.6 KB gzip in
release mode. This plan accepts that async-runtime cost in exchange for one
coherent MoonBit owner. Do not replace the design with a JavaScript state
machine or a MoonBit reducer plus JavaScript effect protocol merely to reduce
generated size.

### Application behavior to move into the package

`examples/basic-synth/core/audio.ts` currently implements owned realtime audio locally. The load-bearing behaviors are:

- `audio.ts:51-75`: construct and admit the replacement context in the current user gesture, suspend it, then wait for predecessor cleanup before creating the replacement engine;
- `audio.ts:78-83`: close an engine acquired after its generation started turning off instead of publishing it;
- `audio.ts:92-95`: resume and connect output only after graph setup succeeds;
- `audio.ts:101-130`: make cleanup idempotent, attempt output disconnect, engine close, and context close, and preserve the first failure;
- `audio.ts:168-177`: observe context state changes;
- `audio.ts:192-199`: observe processor termination without polling; and
- `audio.ts:201-220`: invoke resume synchronously from a power-on gesture.

The predecessor ordering is mandatory. `AudioContext.close()` resolves only after system audio resources that can block another context are released. Replacement context admission must begin in the new gesture, but replacement `GraphEngine` creation must wait for predecessor cleanup to settle.

### Existing observable coverage

`examples/basic-synth/tests/lifetime.spec.js` currently covers:

- one-gesture audible startup even when loading outlasts transient activation;
- turn-off during delayed Wasm loading;
- turn-off during an unacknowledged mount;
- processor failure without a follow-up command;
- retry with a fresh engine;
- external context closure; and
- stale resume completion that cannot affect replacement audio.

Move package-owned race and cleanup assertions into direct `@moondsp/browser/audio` tests. Keep application-visible power state, errors, keyboard behavior, settings, and audible output in the example suite.

### Web Audio facts

- `AudioContext.resume()` rejects for a closed realtime context: <https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/resume>.
- `AudioContext.close()` resolves after context-creation-blocking resources are released: <https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/close>.
- `BaseAudioContext.state` includes `running`, `suspended`, `interrupted`, and `closed`: <https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/state>.

Treat every state other than `running` and `closed` as temporarily non-playing. Chromium tests prove the implementation path; they do not establish Safari or Firefox compatibility.

## Public interface

Create the `@moondsp/browser/audio` subpath. Do not re-export it from the root `@moondsp/browser` entry point.

```ts
import type { GraphEngine } from "./graph-engine.js";

export interface AudioPowerOptions {
  readonly contextOptions?: AudioContextOptions;
  readonly wasmUrl?: string | URL;
  readonly processorUrl?: string | URL;
  readonly closeTimeoutMs?: number;
}

export interface AudioSetup {
  readonly context: AudioContext;
  readonly engine: GraphEngine;
  /** Aborted when this powered-audio generation starts turning off. */
  readonly powerOff: AbortSignal;
}

export type AudioEnd =
  | { readonly reason: "turnedOff" }
  | { readonly reason: "failed"; readonly error: Error };

export interface PoweredAudio<Value> {
  /** Available immediately so statechange can be observed during setup. */
  readonly context: AudioContext;
  /** Resolves with the opaque value returned by setupAudio after connection. */
  readonly ready: Promise<Value>;
  /** Retained terminal result; always resolves and never rejects. */
  readonly ended: Promise<AudioEnd>;
  /** Restore this ready generation after a platform interruption. */
  readonly resume: () => Promise<void>;
  /** Idempotently turn off only this powered-audio generation. */
  readonly turnOff: () => Promise<void>;
}

export interface AudioPower {
  /** Starts context admission synchronously before returning. */
  readonly turnOn: <Value>(
    setupAudio: (audio: AudioSetup) => Promise<Value>,
  ) => PoweredAudio<Value>;
}

export function AudioPower(
  options?: AudioPowerOptions,
): AudioPower;
```

Example:

```ts
const audioPower = AudioPower();

function powerOn() {
  const poweredAudio = audioPower.turnOn(async ({ engine, powerOff }) => {
    powerOff.throwIfAborted();
    const graph = await engine.mount(description);
    await graph.setParams(currentSettings());
    await graph.play();
    return graph;
  });

  void poweredAudio.ready.then(publishGraph, showStartupError);
  void poweredAudio.ended.then(publishAudioEnd);
  return poweredAudio;
}
```

## Behavioral contract

### `AudioPower()`

- Stores options and generation bookkeeping only; `AudioContext` and `GraphEngine` validate the values they own during `turnOn()`.
- Creates no `AudioContext`, `GraphEngine`, Worklet node, or listener.
- Returns a frozen value.
- Each returned value owns an independent sequence of power cycles.

### `audioPower.turnOn(setupAudio)`

- Validates `setupAudio` and current generation state before allocation.
- Throws `DOMException("Audio is already powered on", "InvalidStateError")` if the current generation has not started turning off.
- Throws synchronously if `AudioContext` is unavailable or construction fails.
- Constructs the context and invokes its first `resume()` synchronously before returning.
- Returns frozen `PoweredAudio` immediately; asynchronous setup continues through `ready`.
- Allows a new power cycle after the predecessor has started turning off.
- Admits and suspends the replacement context before waiting for the captured
  cumulative retirement tail.
- Waits for every cleanup in that captured tail to settle before creating the
  replacement `GraphEngine`.
- Does not propagate an earlier cleanup failure into replacement setup.

Setup order is fixed:

1. construct `AudioContext`;
2. start gesture admission with `context.resume()`;
3. await admission;
4. suspend the context;
5. await the captured cumulative retirement tail;
6. create `GraphEngine`;
7. call `setupAudio` while suspended;
8. resume the context;
9. connect `engine.output` to `context.destination`; and
10. resolve `ready` with the value returned by `setupAudio`.

`setupAudio` may mount and configure multiple graphs. It must call `play()` on
graphs intended to produce audio. Graph descriptions, parameters, notes,
scheduling, and application command queues remain caller policy.

### `poweredAudio.ready`

- Resolves only after the entire setup order succeeds.
- Never resolves after turn-off starts.
- Resolves with the exact value returned by `setupAudio`.
- Rejects with `AbortError` when `turnOff()` or external context closure
  interrupts setup.
- Rejects with the primary setup, final-resume, connection, or processor error
  when still pending.
- Normalizes non-`Error` thrown values to `Error` while preserving
  `GraphEngineError` identity and `cause`.

### `poweredAudio.turnOff()`

- Starts turn-off synchronously and aborts `AudioSetup.powerOff` before returning.
- Bypasses pending setup and application command queues.
- Is generation-scoped: a stale `PoweredAudio` cannot turn off replacement audio.
- Is idempotent: concurrent and repeated calls return the same cleanup promise.
- Resolves after all cleanup succeeds.
- Rejects with the first cleanup error after attempting every available cleanup step.
- Attempts output disconnect, `engine.close()`, and owned-context close in that order.
- Attempts all available cleanup steps and preserves the first cleanup failure.
- Closes a resource acquired after turn-off began instead of publishing it.

### `poweredAudio.ended`

- Has one retained promise identity and one frozen result identity.
- Always resolves; it never rejects.
- Resolves `{ reason: "turnedOff" }` for successful `turnOff()` and external context closure.
- Resolves `{ reason: "failed", error }` for setup, resume, processor, or cleanup failure.
- Publishes a setup or processor failure before cleanup starts and keeps it primary if cleanup also fails.

### `poweredAudio.resume()`

- Is one method on the generation-scoped handle; callers do not exchange the
  handle after readiness.
- Rejects `InvalidStateError` before `ready` resolves, after retirement starts,
  or when the native context is closed. This single public-seam temporal check
  is intentional and must not be duplicated through the orchestrator.
- Calls `context.resume()` synchronously when the parsed context disposition is
  temporarily unavailable, covering native `suspended` and `interrupted`.
- Resolves immediately when the parsed disposition is already playing.
- Concurrent calls while a native resume is in flight return the same retained
  resume promise.
- Rejects a native resume completion that loses a race with retirement.

## Design boundaries

### Ownership split

The MoonBit JS-target package owns all lifecycle policy and asynchronous
orchestration:

- application-local generation allocation and typed state transitions;
- admission, suspension, predecessor retirement, engine creation, setup,
  final resume, and connection ordering;
- centralized liveness arbitration at asynchronous suspension points;
- processor-exit observation through the existing `EngineLifetime`;
- idempotent cleanup initiation and cleanup sequencing;
- first-error precedence and the retained `AudioEnd`; and
- isolation between independent `AudioPower` values.

### State-space model

Do not represent a generation as a phase enum beside an optional-resource bag.
Each state variant carries exactly the resources valid in that state. The
implementation may adjust names, but it must preserve this shape:

```moonbit
#external type NativeValue

enum GenerationState {
  Admitting(Admission)
  Suspending(AdmittedContext)
  WaitingForEngineGate(SuspendedContext, EngineGate)
  CreatingEngine(SuspendedContext)
  SettingUp(OwnedEngine)
  Resuming(ConfiguredEngine) // retains the setup NativeValue
  Ready(RunningEngine)
  Restoring(RunningEngine, ResumeTask)
  Retiring(Retirement)
  Ended(AudioEnd)
}
```

`NativeEngine?`, `connected : Bool`, and `cleanup_task?` must not coexist with
an independent phase field. Engine-owning variants contain an engine;
pre-engine variants cannot. The successful `Resuming -> Ready` transition
settles `ready` with the stored setup value. `Restoring` represents one retained
post-readiness resume operation instead of a parallel optional task.

The owner has two intentional, independently valid dimensions:

```moonbit
enum CurrentSlot {
  Vacant
  Occupied(CurrentLease)
}

struct OwnerState {
  current : CurrentSlot
  retirement_tail : EngineGate
}
```

`CurrentSlot` controls admission. `retirement_tail` is a cumulative barrier
covering every earlier generation that might still own context or engine
resources; it is not merely an optional pointer to one predecessor. When a
generation retires, its cleanup starts immediately and the owner replaces the
tail with `join(old_tail, cleanup)`. Cleanup executions need not serialize, but
later engine creation must await the cumulative tail and cannot overtake any
older retirement.

`turnOn()` performs the single `CurrentSlot` transition at the public seam:
`Vacant -> Occupied`, or `Occupied -> AlreadyPowered`. This temporal conflict
cannot be removed by TypeScript's type system, but it is checked once; async
continuations do not repeatedly compare generation IDs against owner state.

Retirement is also a state machine rather than optional cleanup fields:

```moonbit
enum RetirementStage {
  ResolvingEngineAcquisition(
    PendingEngineOwnership,
    OwnedContext,
    FirstFailure,
  )
  Disconnecting(ConnectedEngine, FirstFailure)
  ClosingEngine(OwnedEngine, FirstFailure)
  ClosingContext(OwnedContext, FirstFailure)
  Complete(AudioEnd)
}
```

A generation that never acquired or connected a resource enters the first
applicable stage directly. Retirement during `CreatingEngine` enters
`ResolvingEngineAcquisition`, which cannot advance to context close until the
bounded ownership disposition proves that no engine exists or transfers a late
engine to `ClosingEngine`. Every cleanup outcome advances to the next stage
while retaining the first failure.

The transition table is normative:

| Current state | Input | Next state | Required effect |
|---|---|---|---|
| `Admitting` | admission succeeded while live | `Suspending` | suspend owned context |
| `Suspending` | suspension succeeded while live | `WaitingForEngineGate` | await the captured cumulative gate |
| `WaitingForEngineGate` | captured gate settled, regardless of predecessor cleanup result | `CreatingEngine` | start engine creation |
| `CreatingEngine` | engine succeeded while live | `SettingUp` | transfer engine ownership and invoke setup |
| `SettingUp` | setup succeeded while live | `Resuming` | retain setup value and start final resume |
| `Resuming` | final resume and connection succeeded while live | `Ready` | settle `ready` with the setup value |
| `Ready` | resume requested while playing | `Ready` | return an already-resolved promise |
| `Ready` | resume requested while temporarily unavailable | `Restoring` | invoke native resume synchronously and retain its promise |
| `Restoring` | resume succeeded while context remains live | `Ready` | settle the retained resume promise |
| `Ready` | resume requested while context is closed | `Retiring` | reject `InvalidStateError` and begin clean external-close retirement |
| `Restoring` | concurrent resume requested | `Restoring` | return the retained resume promise |
| any live operation state | native admission/suspend/engine/setup/resume/connect failure | `Retiring` | retain primary failure and begin cleanup |
| any live state except `CreatingEngine` | `TurnOff` | first applicable `RetirementStage` | abort setup, release current slot, start cleanup, join cleanup into retirement tail |
| `CreatingEngine` | `TurnOff` | `ResolvingEngineAcquisition` | abort creation, release current slot, register ownership disposition in retirement tail |
| `ResolvingEngineAcquisition` | no engine can publish | `ClosingContext` | continue context cleanup |
| `ResolvingEngineAcquisition` | late engine success | `ClosingEngine` | transfer engine to cleanup and close exactly once |
| any live state | context closed | `Retiring` | classify as clean external turn-off and begin cleanup |
| any engine-owning live state | processor failed | `Retiring` | retain processor failure and begin cleanup |
| any retirement stage | cleanup outcome | next retirement stage | preserve first failure |
| `Retiring` or `Ended` | duplicate turn-off/terminal signal | same state | return retained cleanup/end result |

`turnOn()` while `CurrentSlot` is occupied and `resume()` outside `Ready` or
`Restoring` are rejected at the public seam before event dispatch; they are
expected temporal misuse, not impossible internal transitions.

An input incompatible with every documented row is an internal defect and must
`fail`; it must not be ignored by a wildcard branch.

Parse native values once at the JavaScript seam:

```moonbit
enum NativeOutcome[T] {
  Succeeded(T)
  Failed(NativeError)
}

enum ContextDisposition {
  Playing
  TemporarilyUnavailable
  Closed
}
```

Do not repeat native string checks or `{ ok, error }` inspection throughout the
orchestrator.

### Async ownership arbitration

Typed resource snapshots cannot prove that a browser context or generation is
still live after an `await`: the browser may close the context and another task
may start retirement while the operation is suspended. Liveness arbitration is
therefore required, but it must be centralized rather than repeated as ad hoc
generation/phase guards.

Use one generation-local primitive with the semantics:

```moonbit
enum AwaitOutcome[T] {
  Completed(NativeOutcome[T], ContextDisposition)
  Retired(Retirement)
}

enum LateSuccessOwner[T] {
  NoPackageResource
  DisposeAndJoin((T) -> @js_async.Promise[NativeOutcome[Unit]])
}

async fn[T] await_owned(
  operation : @js_async.Promise[T],
  lease : CurrentLease,
  late_owner : LateSuccessOwner[T],
) -> AwaitOutcome[T]
```

The exact signature may differ, but every admission/setup/resume suspension
point while a generation is live must use the same arbitration rule:

- register the operation's `late_owner` before racing operation completion
  against retirement, so no completion can fall between winner selection and
  disposer installation;
- operation completion while the lease is live is parsed together with current
  browser liveness and dispatched to the typed state transition;
- ownership arbitration and the resulting state transition run without another
  suspension point, so retirement cannot interleave between a live verdict and
  transition commit;
- retirement winning detaches the public waiter but does not abandon the
  operation;
- a later successful result is transferred to `late_owner`;
- resource-acquiring operations must provide a bounded ownership disposition:
  cancellation either proves that no resource can later be published or yields
  the resource to the disposing owner; retirement joins that disposition and
  any resulting close, but never waits for unrelated underlying loading;
- a late `NativeEngine` success must call `engine.close()` exactly once and
  join that close with retirement;
- operations returning `Unit` may use a no-resource owner because the
  generation already owns the affected context; and
- a late `setupAudio` value uses an explicit non-owning-value handler because
  returning the value never transfers a package-owned resource. Its arbitrary
  callback may be detached without blocking retirement; engine/context cleanup
  remains authoritative, and the callback must use `powerOff` for any
  application-owned work.

Never use a non-owning late handler for an operation that can acquire ownership.
Every completion must advance state, settle a caller, transfer a resource to
retirement, return the retained terminal result, or report an impossible
internal transition with `fail`. There is no catch-all “stale, return” branch.

JavaScript is a narrow platform adapter only. It may:

- construct `AudioContext`, `AbortController`, native Promise/deferred values,
  `DOMException`, and normalized `Error` values;
- invoke `AudioContext` and `GraphEngine` methods and connect/disconnect nodes;
- attach and detach native event listeners;
- invoke the arbitrary JavaScript `setupAudio` callback; and
- expose frozen camelCase npm-facing objects.

The first `context.resume()` call must originate synchronously from the exported
MoonBit `turn_on` entrypoint before that entrypoint returns to the JavaScript
facade. No MoonBit `async` boundary, queued callback, or JavaScript `.then()`
may precede it.

Keep `AudioContext`, `GraphEngine`, setup return values, and errors opaque at
the MoonBit seam. The production package uses `NativeValue` for arbitrary setup
results; TypeScript generic inference exists only in `web/audio-power.d.ts`.
Preserve JavaScript error identity; do not invent a second MoonBit error
taxonomy for platform failures. FFI-reachable MoonBit code must not call
`abort`. Expected native failures are values, impossible internal states use
catchable `fail`, and every exported seam catches defects and settles the
appropriate public promise.

### Generated ESM bridge contract

The production executable exports exactly four snake_case functions. Treat the
following JavaScript-level shapes as the bridge contract even though MoonBit's
generated `.d.ts` uses `any` for external values:

```ts
type NativeTurnOnOutcome =
  | {
      readonly ok: true;
      readonly generation: unknown;
      readonly context: AudioContext;
      readonly ready: Promise<unknown>;
      readonly ended: Promise<AudioEnd>;
    }
  | { readonly ok: false; readonly error: Error };

audio_power_new(
  options: AudioPowerOptions | undefined,
  graphEngineFactory: typeof GraphEngine,
): unknown;

audio_power_turn_on(
  owner: unknown,
  setupAudio: (audio: AudioSetup) => Promise<unknown>,
): NativeTurnOnOutcome;

powered_audio_resume(generation: unknown): Promise<void>;
powered_audio_turn_off(generation: unknown): Promise<void>;
```

`web/audio-power.js` imports `GraphEngine` from `./graph-engine.js` and passes
it to `audio_power_new`; this is a private cross-language dependency, not a
public factory option. The success outcome contains the exact retained
`ready`/`ended` Promise objects created for that generation.

`audio_power_turn_on` is synchronous and performs this non-suspending prefix:

1. validate the setup callback and `CurrentSlot`;
2. construct the native context;
3. create the generation, retained deferreds, abort controller, and internal
   context-state listener;
4. attach that listener before admission can settle;
5. invoke the first `context.resume()` and retain its native Promise; and
6. start the MoonBit async continuation and return `NativeTurnOnOutcome`.

Invalid callback/current-slot state, missing `AudioContext`, and context
construction failure return `{ ok: false, error }`; the facade throws that
same error synchronously. A synchronous exception from the first `resume()`
happens after context acquisition: return a successful generation whose
`ready` rejects with that error and whose cleanup closes the context.

`powered_audio_turn_off` returns the exact retained cleanup Promise on every
call. `powered_audio_resume` returns the exact in-flight resume Promise while
`Restoring`; outside `Ready`/`Restoring` it returns a rejected Promise without
invoking native resume.

The module owns realtime context admission, suspended engine setup,
predecessor retirement, generation isolation, processor observation, and
complete resource cleanup.

The module does **not** own:

- graph descriptions or a one-graph convenience format;
- note, parameter, scheduler, or application command serialization;
- UI state or framework adapters;
- automatic retry or telemetry;
- caller-owned `AudioContext` or `OfflineAudioContext`;
- custom output destinations;
- a public platform/factory/test-injection port;
- `Symbol.asyncDispose`; or
- a global singleton.

Use root `GraphEngine` directly for ownership modes outside this contract.

## Scope

**In scope**:

- `docs/browser-api-contract.md`
- `packages/browser/host/moon.mod`
- `packages/browser/host/audio_power/` (create production JS-target executable package)
- `packages/browser/host/pkg.generated.mbti` only if the root host interface changes
- `web/audio-power-core.js` (generated, ignored, never committed)
- `web/audio-power.js` (create thin facade)
- `web/audio-power.d.ts` (create)
- `scripts/build-audio-power-core.mjs` (create)
- `scripts/build-browser-package.mjs`
- `playwright-serve.sh`
- `.gitignore`
- `packages/browser/package.json`
- `packages/browser/README.md`
- `playwright-tests/audio-power.spec.js` (create)
- `playwright-tests/audio-power.types.ts` (create)
- `playwright-tests/graph-engine.types.ts`
- `package.json`
- `README.mbt.md`
- `.github/workflows/browser-smoke.yml`
- `examples/basic-synth/core/audio.ts`
- `examples/basic-synth/core/result.ts` only if `attempt` becomes unused
- `examples/basic-synth/tests/lifetime.spec.js`
- `examples/basic-synth/README.md`
- `examples/basic-synth/package-lock.json` only for rebuilt tarball integrity
- `CHANGELOG.md`
- `plans/README.md` status row

Generated verification outputs are not committed unless repository convention
already tracks them:

- `web/audio-power-core.js`
- `packages/browser/host/_build/`
- `packages/browser/dist/`
- `packages/browser/moondsp-browser-0.6.0.tgz`
- `examples/basic-synth/{vanilla,svelte}/dist/`

**Out of scope**:

- changes to `GraphEngine`, `MountedGraph`, Worklet messages, Wasm exports,
  DSP/AudioWorklet MoonBit packages, or `browser/browser_abi.baseline`;
- `web/live/src/audio.ts`, which uses a different scheduler and Worklet protocol;
- npm publication, release automation, or package-version changes; and
- compatibility aliases for the local example ownership types removed by this migration.

## Commands

| Purpose | Command |
|---|---|
| Root per-edit check | `NEW_MOON_MOD=0 moon check` |
| Host per-edit check | `NEW_MOON_MOD=0 moon -C packages/browser/host check --target js` |
| Host lifecycle tests | `NEW_MOON_MOD=0 moon -C packages/browser/host test --target js` |
| Generated host core | `node scripts/build-audio-power-core.mjs web/audio-power-core.js` |
| Type contracts | `npm run typecheck:browser` |
| Package build | `npm run pack:browser` |
| Direct power tests | `npx playwright test --config playwright.config.js playwright-tests/audio-power.spec.js` |
| Example build | `npm --prefix examples/basic-synth run build` |
| Vanilla example | `npm run test:vanilla-synth` |
| Svelte example | `npm run test:svelte-synth` |
| Full Web Audio regression | `npm run test:browser` |
| Generated MoonBit interfaces | `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon -C packages/browser/host info` |
| Formatting | `NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon -C packages/browser/host fmt` |

After every edit under `packages/browser/host`, run the host per-edit check
before editing another file. After every other source edit, run the root
per-edit check.

Install dependencies only through repository-documented commands: `npm ci`,
`npm --prefix web/live ci`, `npm --prefix examples/basic-synth ci`, and
`npx playwright install chromium`.

## Implementation steps

### Step 1: Specify the public ownership contract

Update `docs/browser-api-contract.md` before implementation.

- Add `@moondsp/browser/audio` to the entry-point table.
- Add the domain language, public declarations, setup order, cleanup order,
  generation isolation, and result semantics from this plan.
- Extend “MoonBit lifetime observation on the JS host” into a host ownership
  section: the generated MoonBit core owns lifecycle policy, while JavaScript
  performs Web API effects and shapes the public npm surface.
- Document the payload-carrying generation/retirement states, the normative
  transition table, centralized post-await liveness arbitration, and
  late-result ownership handoff. Do not document an implementation based on
  phase checks plus optional resources.
- State explicitly that root `GraphEngine` remains caller-owned and unchanged.
- State that different `AudioPower` values are independent.

**Verify**: `NEW_MOON_MOD=0 moon check`.

### Step 2: Implement the MoonBit lifecycle owner

Update `packages/browser/host/moon.mod` so its description covers browser-host
lifecycle ownership rather than engine observation alone.

Create `packages/browser/host/audio_power/` as a production executable package
with ESM link output. Export only the snake_case bridge functions required by
the thin JavaScript facade. Keep all lifecycle structs, enums, and helpers
private to this package.

Use this file layout:

- `moon.pkg`: imports the root host package as `@host`,
  `moonbitlang/async`, and `moonbitlang/async/js_async`; declares an executable
  ESM package and exports only `audio_power_new`, `audio_power_turn_on`,
  `powered_audio_resume`, and `powered_audio_turn_off`;
- `native.mbt`: all `#external` native types, raw Web API/GraphEngine externs,
  retained JavaScript deferreds, and raw-to-typed parsing helpers;
- `model.mbt`: `CurrentSlot`, `GenerationState`, `RetirementStage`,
  `NativeOutcome`, `ContextDisposition`, and non-suspending transitions;
- `owner.mbt`: `await_owned`, async setup, processor observation, cumulative
  gate handling, and cancellation-protected retirement;
- `exports.mbt`: the four public bridge functions plus `fn main { () }`; and
- `audio_power_wbtest.mbt`: whitebox transition and ownership tests.

Do not make `NativeValue` generic. The MoonBit core retains arbitrary
JavaScript setup values opaquely; only the handwritten declaration file exposes
`Value`.

The MoonBit owner must:

- represent owner admission as `CurrentSlot` and cross-generation serialization
  as a `retirement_tail : EngineGate`;
- represent generation and retirement progress with payload-carrying variants
  from the state-space model; do not add a parallel phase field or optional
  resource bag;
- keep retained `ready` and `ended` sinks in the generation shell, outside the
  resource-state variants, and settle each exactly once;
- synchronously construct the context and invoke the first native `resume()`
  from the exported `turn_on` call before starting async continuation;
- perform all remaining setup ordering from the behavioral contract in one
  MoonBit orchestration flow;
- invoke `setupAudio` through the native adapter while the context is suspended,
  pass that generation's `AbortSignal`, and retain its opaque return value;
- settle `ready` with the setup value only after setup, final resume, and
  destination connection all succeed;
- use `EngineLifetime` for processor exit and engine close rather than adding a
  second native waiter registry;
- start processor observation as a non-blocking child whose cancellation cannot
  deadlock cleanup;
- observe context state changes through a native listener; external transition
  to `Closed` retires the generation cleanly unless a primary failure already
  exists, and cleanup removes the listener;
- abort setup and start cancellation-protected cleanup synchronously from the
  exported `turn_off` call;
- race or detach arbitrary pending setup work so cleanup never waits for the
  callback to settle;
- route every awaited admission/setup/resume operation through the centralized
  ownership and browser-liveness arbiter;
- retain the losing native operation when retirement wins and attach its
  operation-specific late-success handoff;
- close and join a `NativeEngine` acquired after retirement instead of
  publishing or dropping it;
- invoke native `context.resume()` synchronously from `PoweredAudio.resume()`,
  retain one in-flight resume task, and arbitrate its completion against
  retirement and current browser state;
- advance `RetirementStage` through disconnect, engine close, and context close
  while retaining the first failure;
- retain native `Error`, `GraphEngineError`, and `cause` identity across the
  MoonBit seam; and
- use exhaustive matches without a wildcard stale-event/no-op branch.

Use narrow `extern "js"` functions for platform effects. Parse their raw
outcomes immediately into `NativeOutcome` and `ContextDisposition`. Do not put
lifecycle branching, generation selection, cleanup order, error precedence, or
late-result disposal inside the extern JavaScript snippets.

Implement the four bridge exports exactly as specified in “Generated ESM
bridge contract.” Compare `browser_test/moon.pkg` and
`browser_test/driver.mbt`: synchronous code before
`@js_async.Promise::from_async` runs in the JavaScript caller's stack, while
`Promise::from_async` exports the remaining MoonBit async work.

Add focused MoonBit tests for deterministic policy:

1. `Vacant -> Occupied`, while `Occupied` rejects another start without
   allocation;
2. retirement releases the current slot but appends cleanup to the
   `retirement_tail`;
3. rapid A -> B -> C replacement cannot let C engine creation overtake A or B
   retirement;
4. each generation-state variant contains only its legal resources;
5. repeated retirement returns one cleanup task and duplicate terminal events
   return the retained terminal result;
6. setup/processor failure remains primary over cleanup failure;
7. a late engine success after retirement is closed exactly once and its close
   joins retirement;
8. browser closure after an awaited operation routes to retirement rather than
   advancing a stale typed snapshot; and
9. `ready` settles only on the successful `Resuming -> Ready` transition, and
   `Restoring` retains one promise for concurrent resume calls.

Do not add a public dependency-injection interface. A private test adapter is
allowed only for native completion ordering and late-result disposal that pure
transition tests cannot exercise.

**Verify after creating or editing each host file**:
`NEW_MOON_MOD=0 moon -C packages/browser/host check --target js`.

Then run:

1. `NEW_MOON_MOD=0 moon -C packages/browser/host test --target js`
2. `NEW_MOON_MOD=0 moon -C packages/browser/host info`
3. inspect the new package `.mbti`; it must expose only bridge entrypoints and
   opaque boundary types required for ESM linking

### Step 3: Build the generated core and thin JavaScript facade

Create `scripts/build-audio-power-core.mjs`.

- Accept one destination path.
- Run `moon -C packages/browser/host build audio_power --target js --release`
  with `NEW_MOON_MOD=0`.
- Copy
  `packages/browser/host/_build/js/release/build/audio_power/audio_power.js`
  to the requested destination.
- Fail if the command fails or that exact artifact is absent.
- Do not post-process generated JavaScript.

Add `web/audio-power-core.js` to `.gitignore`. Update `playwright-serve.sh` to
build it before serving `web/`. Update `scripts/build-browser-package.mjs` to
build the generated core directly into `packages/browser/dist/` and then copy
the handwritten facade and declarations.

Create `web/audio-power.js` as a thin adapter over generated bridge exports. It
may translate camelCase public calls to bridge calls and construct/freeze public
objects. It must not contain generation state, Promise races, setup sequencing,
cleanup sequencing, or failure precedence.

The facade shape is fixed:

```js
import { GraphEngine } from "./graph-engine.js";
import {
  audio_power_new,
  audio_power_turn_on,
  powered_audio_resume,
  powered_audio_turn_off,
} from "./audio-power-core.js";

export function AudioPower(options) {
  const owner = audio_power_new(options, GraphEngine);
  return Object.freeze({
    turnOn(setupAudio) {
      const started = audio_power_turn_on(owner, setupAudio);
      if (!started.ok) throw started.error;
      const generation = started.generation;
      return Object.freeze({
        context: started.context,
        ready: started.ready,
        ended: started.ended,
        resume: () => powered_audio_resume(generation),
        turnOff: () => powered_audio_turn_off(generation),
      });
    },
  });
}
```

Equivalent formatting is allowed; additional state, fallback behavior, or
Promise wrapping is not. In particular, use the retained `ready`, `ended`,
resume, and cleanup Promise identities supplied by the core.

Create `web/audio-power.d.ts` with the public interface in this plan.

**Verify after each edited file**: `NEW_MOON_MOD=0 moon check`.

Then run:

1. `node scripts/build-audio-power-core.mjs web/audio-power-core.js`
2. import `web/audio-power-core.js` in Node and assert its sorted exports are
   exactly `audio_power_new`, `audio_power_turn_on`, `powered_audio_resume`, and
   `powered_audio_turn_off`
3. import `web/audio-power.js` in Node and assert its only export is
   `AudioPower`
4. `NEW_MOON_MOD=0 moon -C packages/browser/host test --target js`

### Step 4: Package and type the subpath

Add this export to `packages/browser/package.json`:

```json
"./audio": {
  "types": "./dist/audio-power.d.ts",
  "import": "./dist/audio-power.js"
}
```

The tarball must include `audio-power-core.js` because `audio-power.js` imports
it, but must not expose the core as a documented package subpath.

Create `playwright-tests/audio-power.types.ts` covering:

- `AudioPower(options): AudioPower`;
- `poweredAudio.ready` is `Promise<Value>`;
- generic inference flows from `turnOn(setupAudio)` to
  `await poweredAudio.ready`;
- `PoweredAudio<Value>` contains `context`, `ready`, `ended`, `resume`, and
  `turnOff` as readonly members;
- `AudioEnd` narrowing by `reason`;
- readonly public members;
- independent `AudioPower` values;
- rejection of caller-provided/Offline contexts and a missing setup callback; and
- absence of `wait`, builder setters, and async-dispose surface.

Rename `typecheck:graph` to `typecheck:browser` and compile both
`graph-engine.types.ts` and `audio-power.types.ts`. Update operational references
in `.github/workflows/browser-smoke.yml`, `docs/browser-api-contract.md`, and
`README.mbt.md`. Leave past changelog entries unchanged.

Update `packages/browser/README.md` with:

- the root caller-owned `GraphEngine` entry point;
- the owned `@moondsp/browser/audio` entry point;
- one complete `AudioPower` example; and
- guidance to use `GraphEngine` for custom contexts, destinations, or offline rendering.

**Verify**:

1. `NEW_MOON_MOD=0 moon check`
2. `NEW_MOON_MOD=0 moon -C packages/browser/host check --target js`
3. `npm run typecheck:browser`
4. `npm run pack:browser`
5. `tar -tf packages/browser/moondsp-browser-0.6.0.tgz` contains
   `package/dist/audio-power.js`, `package/dist/audio-power-core.js`, and
   `package/dist/audio-power.d.ts` exactly once each

### Step 5: Test the public power contract

Create `playwright-tests/audio-power.spec.js`. Import `/audio-power.js` through
the existing Chromium server. Exercise real `AudioContext`,
`AudioWorkletNode`, Worklet/Wasm, context state, and analyser output. Existing
platform-global fault injection is allowed; do not mock `GraphEngine` or assert
private MoonBit state.

Required cases:

1. **One gesture**: delay Wasm until activation expires; `ready` resolves with the exact setup return value, context is running, and output RMS exceeds `0.01`.
2. **Turn off during Wasm**: `turnOff()` completes, context closes, `ready` rejects `AbortError`, and `ended.reason` is `turnedOff`.
3. **Turn off during mount**: hold the real mount acknowledgement; `turnOff()` completes without releasing it; the late acknowledgement cannot publish readiness.
4. **Processor failure**: real `onprocessorerror` resolves failed `ended` with `GraphEngineError` code `PROCESSOR_FAILED`; context cleanup follows.
5. **Serialized replacement**: after failure, admit a replacement from the same `AudioPower`; prove no replacement `AudioWorkletNode` is created until every earlier retirement barrier settles; then prove audible output.
6. **Already powered on**: a second `turnOn()` on the same `AudioPower` throws `InvalidStateError` and creates no context; another `AudioPower` can turn on independently.
7. **Immediate external close before engine creation**: gate completion of the
   real first `resume()` without delaying its synchronous invocation, call
   `poweredAudio.context.close()` immediately after `turnOn()` returns, then
   release the admission gate. Prove setup is never invoked, no
   `AudioWorkletNode` is constructed, `ready` rejects `AbortError`, and `ended`
   resolves as `turnedOff`.
8. **External close after setup starts**: let setup signal an entered latch,
   capture its engine, and block on a separate setup gate. After the latch
   resolves, close `poweredAudio.context` without releasing setup. Prove the
   setup signal aborts, `ready` rejects `AbortError`, `ended` resolves as
   `turnedOff`, and the captured engine's `wait()` settles after cleanup.
   Release setup afterward and prove the late value cannot revive readiness.
9. **Setup failure**: the same sentinel `Error` rejects `ready` and appears in failed `ended`; cleanup completes and another power cycle succeeds.
10. **Idempotent turn-off**: concurrent/repeated `turnOff()` calls share one promise; early and late `ended` observers receive the same frozen result.
11. **Resume before readiness**: call `poweredAudio.resume()` while setup is held; it rejects `InvalidStateError` and does not invoke native resume.
12. **Concurrent resume retired**: after readiness, delay native resume completion, call `poweredAudio.resume()` twice and prove both calls return the same promise; call `turnOff()`, release resume, and prove the retained resume rejects without reviving or affecting replacement audio.

Do not add per-observer cancellation to `ended`; it is intentionally one
retained resolving promise.

The browser tests prove that the generated MoonBit bridge preserves synchronous
gesture admission. A MoonBit unit test or Node-only test is not sufficient for
that property.

**Verify**:

1. `NEW_MOON_MOD=0 moon check`
2. `NEW_MOON_MOD=0 moon -C packages/browser/host test --target js`
3. `npx playwright test --config playwright.config.js playwright-tests/audio-power.spec.js`
4. `npm run test:browser`

### Step 6: Migrate basic-synth

Refactor `examples/basic-synth/core/audio.ts` to create one `AudioPower` inside `createAudio`.

- Replace local context/engine ownership with one generation-scoped
  `PoweredAudio` returned by `AudioPower.turnOn()`.
- Delete `OwnedResources`, `AudioOwner`, `createAudioOwner`, and
  `cleanupResources` after all callers move.
- Keep the application command queue, `noteEpoch`, note release, settings
  preservation, UI phases, error wording, and both UI adapter interfaces.
- In `setupAudio`, mount `SYNTH_GRAPH`, read current settings at setup time,
  call `setParams`, call `play`, and return the mounted graph.
- Attach `statechange` inside `setupAudio` with `{ signal: powerOff }` so
  observation begins immediately and detaches when turn-off starts.
- Project every context state other than `running` and `closed` as temporarily
  non-playing so `interrupted` releases notes and updates UI.
- Publish the mounted graph only when the current generation's `ready` resolves;
  publish `ended` only for that generation.
- Use `poweredAudio.resume()` only for the current temporarily non-playing
  generation.
- Power-off and failure must call only that generation's
  `poweredAudio.turnOff()`.

If `attempt` becomes unused, remove only that export from `examples/basic-synth/core/result.ts`; keep `attemptAsync`.

Update `examples/basic-synth/README.md` to distinguish package-owned context/engine power from application-owned UI and instrument command policy.

Repack and reinstall the tarball. Update `examples/basic-synth/package-lock.json` only for tarball content/integrity.

**Verify after every edited file**: `NEW_MOON_MOD=0 moon check`.

Then run:

1. `npm run pack:browser`
2. `npm --prefix examples/basic-synth install ../../packages/browser/moondsp-browser-0.6.0.tgz`
3. `npm --prefix examples/basic-synth run build`
4. `npm run test:vanilla-synth`
5. `npm run test:svelte-synth`

### Step 7: Move package-owned assertions

After direct power tests pass, remove only assertions from `examples/basic-synth/tests/lifetime.spec.js` that exclusively verify package-owned setup or cleanup sequencing.

Keep coverage of:

- visible power states;
- error presentation and retry controls;
- settings and keyboard behavior;
- one-gesture audible output;
- release-to-silence; and
- processor-failure recovery in both UIs.

**Verify**:

1. `NEW_MOON_MOD=0 moon check`
2. `npm run test:vanilla-synth`
3. `npm run test:svelte-synth`

### Step 8: Document and run final gates

Add concise Unreleased changelog entries for the owned audio-power interface and basic-synth migration. Do not claim cross-browser, hard-real-time, scheduling, or automatic-retry guarantees.

Run in order:

1. `NEW_MOON_MOD=0 moon check`
2. `NEW_MOON_MOD=0 moon -C packages/browser/host check --target js`
3. `NEW_MOON_MOD=0 moon -C packages/browser/host test --target js`
4. `node scripts/build-audio-power-core.mjs web/audio-power-core.js`
5. `npm run typecheck:browser`
6. `npm run pack:browser`
7. reinstall the tarball in `examples/basic-synth`
8. `npm --prefix examples/basic-synth run build`
9. direct `audio-power.spec.js`
10. `npm run test:vanilla-synth`
11. `npm run test:svelte-synth`
12. `npm run test:browser`
13. `NEW_MOON_MOD=0 moon info`
14. `NEW_MOON_MOD=0 moon -C packages/browser/host info`
15. inspect tracked `.mbti` changes: only the new host bridge package interface
    or an explicitly required host-root interface change is allowed
16. `NEW_MOON_MOD=0 moon fmt`
17. `NEW_MOON_MOD=0 moon -C packages/browser/host fmt`
18. final root and host `moon check`

Mark the plan `DONE` in `plans/README.md` only after all gates pass.

## Done criteria

- [ ] Root `@moondsp/browser` remains the unchanged caller-owned `GraphEngine` interface.
- [ ] Packed `@moondsp/browser/audio` exports the `AudioPower` value/type pair, `PoweredAudio`, and adjacent declarations.
- [ ] Lifecycle state, async sequencing, liveness arbitration, cleanup order, and error precedence live in the MoonBit JS-host package, not the handwritten JavaScript facade.
- [ ] Generation and retirement variants carry only resources legal in that state; there is no independent phase plus optional-resource bag.
- [ ] Every awaited live-generation operation uses the central ownership/liveness arbiter, while browser state is re-read after suspension; retirement cleanup advances through its own cancellation-protected state machine.
- [ ] A native resource acquired after retirement is handed to a disposer and joined with retirement; no resource-owning loser is dropped.
- [ ] `ready` settles with the setup value only after successful connection; the single `PoweredAudio` handle owns resume and turn-off for its lifetime.
- [ ] Handwritten JavaScript contains only Web API effects, opaque-value/error adaptation, and public-object shaping.
- [ ] The generated `audio-power-core.js` is reproducible, ignored under `web/`, included once in the npm tarball, and not exposed as a documented subpath.
- [ ] One `AudioPower` gates engine creation on its cumulative retirement tail while separate `AudioPower` values remain independent.
- [ ] `turnOff()` during fetch, engine creation, mount, or resume cannot publish stale readiness or leak an owned context or engine.
- [ ] A stale `PoweredAudio.turnOff()` cannot affect replacement audio.
- [ ] `ended` resolves once without rejection; setup/processor failure remains primary; clean turn-off is distinct.
- [ ] `PoweredAudio.resume()` and example state projection cover `suspended` and `interrupted` states.
- [ ] Both basic-synth adapters use the package interface and retain their application behavior.
- [ ] Host MoonBit policy tests, typecheck, twelve direct power tests, both synth suites, and full browser regression pass.
- [ ] Root and host `moon check`, `moon info`, and `moon fmt` pass; only intended new host bridge `.mbti` output changes.
- [ ] No source or documentation file outside Scope is modified.
- [ ] `plans/README.md` status is `DONE`.

## STOP conditions

Stop and report if:

- the exported MoonBit `turn_on` path cannot invoke the first native
  `AudioContext.resume()` in the same JavaScript user-gesture stack;
- replacement context admission cannot precede the retirement tail without
  violating suspended engine creation;
- correct cleanup requires Worklet, Wasm, DSP MoonBit, or ABI changes;
- the MoonBit async runtime cannot detach arbitrary pending setup while allowing
  cancellation-protected cleanup to complete;
- the MoonBit async/runtime and `GraphEngine` cancellation contracts cannot
  provide a bounded ownership disposition for engine creation;
- a losing resource-acquiring operation cannot be retained long enough to
  dispose a late result before retirement settles;
- native JavaScript error identity cannot survive the MoonBit boundary;
- public-interface Chromium tests require mocking `GraphEngine`;
- generation-scoped `turnOff()` can affect replacement powered audio;
- migration requires framework-specific audio logic or removal of the command
  queue/note epoch;
- an in-scope file has semantic drift from the repository baseline; or
- a verification fails twice after a reasonable correction.

## Maintenance notes

- `AudioPower` is application-scoped, never global.
- Engine creation awaits the cumulative retirement tail within one
  `AudioPower`; each generation's cleanup starts immediately and may overlap
  other cleanup.
- `PoweredAudio` is generation-scoped; preserve that capability boundary.
- Keep the single `PoweredAudio` handle human-oriented: `ready` returns the setup
  value, while `resume()` and `turnOff()` remain on that handle.
- Keep `ended` resolving to avoid unhandled ambient promise rejection.
- Keep `PoweredAudio.resume()` gesture-synchronous and generation-aware.
- Post-await liveness arbitration is required because browser state changes
  externally; centralize it rather than scattering phase/generation guards.
- A race loser that can acquire a native resource must retain a late-success
  disposer and join disposal with retirement.
- Keep custom destinations, adopted contexts, and offline rendering on `GraphEngine` until another production ownership mode is proven.
- Keep the handwritten JavaScript facade free of lifecycle state and Promise
  orchestration; platform effects belong in narrow extern adapters and policy
  belongs in MoonBit.
