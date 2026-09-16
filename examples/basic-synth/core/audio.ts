import { GraphEngineError } from "@moondsp/browser";
import type { GraphControl, MountedGraph } from "@moondsp/browser";
import { AudioPower, type PoweredAudio } from "@moondsp/browser/audio";
import { errorMessage, type ControlState } from "./controls";
import { attempt, attemptAsync, type Result } from "./result";
import { SYNTH_GRAPH, noteOn, noteOff, type Settings } from "./synth";

export interface AudioView {
  render(state: ControlState): void;
  clearNotes(): void;
}

export interface AudioActions {
  powerOn(): void;
  stopNotes(): void;
  powerOff(): void;
  press(midi: number): void;
  release(nextMidi: number | null): void;
  volumeChanged(value: number): void;
  cutoffChanged(value: number): void;
}

type SynthPower = PoweredAudio<MountedGraph<keyof Settings>>;

// The application owns command ordering and note epochs, not audio resources.
interface AudioSession {
  readonly powered: SynthPower;
  readonly graph: MountedGraph<keyof Settings>;
  operations: Promise<void>;
  noteEpoch: number;
}

type AudioState =
  | { phase: "idle" | "disposed" }
  | { phase: "loading" | "disposing"; powered: SynthPower }
  | { phase: "suspended" | "resuming" | "running"; session: AudioSession }
  | { phase: "error"; powered: SynthPower | undefined; error: Error };

/** Audio effects only. Values and commands arrive as data; no DOM reads occur here. */
export function createAudio(view: AudioView, initialSettings: Settings): AudioActions {
  const audioPower = AudioPower();
  let settings = initialSettings;
  let state: AudioState = { phase: "idle" };

  function currentPower(): SynthPower | undefined {
    if ("powered" in state) return state.powered;
    if ("session" in state) return state.session.powered;
    return undefined;
  }

  function currentSession(): AudioSession | undefined {
    return "session" in state ? state.session : undefined;
  }

  function canControl(): boolean {
    return state.phase === "suspended" || state.phase === "running";
  }

  function render(): void {
    let errorText = "";
    if (state.phase === "error") {
      const { error } = state;
      const detail = error instanceof GraphEngineError ? `${error.code}: ${error.message}` : error.message;
      errorText = errorMessage(detail);
    }
    view.render({ phase: state.phase, errorText });
  }

  // Only readiness publishes a complete session. Retired work cannot publish.
  function requestInitializeAudio(): void {
    const started: Result<SynthPower> = attempt(() => audioPower.turnOn(async ({ context, engine, powerOff }) => {
      context.addEventListener("statechange", () => {
        if (!started.ok || currentPower() !== started.value) return;
        if (context.state === "closed") requestDispose();
        else if (context.state !== "running" && state.phase === "running") {
          state = { phase: "suspended", session: state.session };
          stopNotes();
          render();
        }
      }, { signal: powerOff });
      powerOff.throwIfAborted();
      const graph = await engine.mount(SYNTH_GRAPH);
      powerOff.throwIfAborted();
      await graph.setParams(settings);
      powerOff.throwIfAborted();
      await graph.play();
      powerOff.throwIfAborted();
      return graph;
    }));
    view.clearNotes();
    if (!started.ok) {
      state = { phase: "error", powered: undefined, error: started.error };
      render();
      return;
    }
    const powered = started.value;
    state = { phase: "loading", powered };
    render();
    void attemptAsync(() => powered.ready).then(result => {
      if (state.phase !== "loading" || state.powered !== powered) return;
      if (!result.ok) {
        if (result.error.name === "AbortError") requestDispose();
        else failAudio(result.error, powered);
        return;
      }
      const session: AudioSession = {
        powered, graph: result.value, operations: Promise.resolve(), noteEpoch: 0,
      };
      state = { phase: powered.context.state === "running" ? "running" : "suspended", session };
      render();
    });
    void powered.ended.then(end => {
      if (currentPower() !== powered) return;
      if (end.reason === "failed") failAudio(end.error, powered);
      else if (state.phase !== "disposing" && state.phase !== "error") requestDispose();
    });
  }

  function powerOnFromGesture(): void {
    if (state.phase === "error" || state.phase === "idle" || state.phase === "disposed") {
      requestInitializeAudio();
      return;
    }
    if (state.phase !== "suspended") return;
    const { session } = state;
    const { powered, graph } = session;
    state = { phase: "resuming", session };
    render();
    // Invoke immediately: native resume must stay in this gesture, not the queue.
    const resume = attemptAsync(() => powered.resume());
    enqueue(session, async () => {
      const resumed = await resume;
      if (!resumed.ok) throw resumed.error;
      if (currentSession() !== session) return;
      await graph.play();
      if (currentSession() !== session) return;
      state = { phase: powered.context.state === "running" ? "running" : "suspended", session };
      render();
    });
  }

  function stopNotes(): void {
    const session = currentSession();
    if (session) session.noteEpoch += 1;
    view.clearNotes();
    queueControls(noteOff());
  }

  // Commands serialize within a session, never across retired and new sessions.
  function enqueue(session: AudioSession, operation: () => Promise<void>): void {
    const run = session.operations.then(() => attemptAsync(async () => {
      if (currentSession() === session) await operation();
    }));
    session.operations = run.then(result => {
      if (!result.ok && currentSession() === session) failAudio(result.error, session.powered);
    });
  }

  function queueControls(changes: readonly GraphControl[]): void {
    const session = currentSession();
    if (!session) return;
    const epoch = session.noteEpoch;
    enqueue(session, async () => {
      if (!canControl() || epoch !== session.noteEpoch) return;
      await session.graph.applyControls(changes);
    });
  }

  function queueParams(values: Partial<Settings>): void {
    const session = currentSession();
    if (!session) return;
    enqueue(session, async () => {
      if (!canControl()) return;
      await session.graph.setParams(values);
    });
  }

  function requestDispose(): void {
    const powered = currentPower();
    view.clearNotes();
    if (!powered) {
      state = { phase: "disposed" };
      render();
      return;
    }
    const disposing: AudioState = { phase: "disposing", powered };
    state = disposing;
    const closing = attemptAsync(() => powered.turnOff());
    render();
    void closing.then(result => {
      if (state !== disposing) return;
      if (!result.ok) failAudio(result.error, powered);
      else {
        state = { phase: "disposed" };
        render();
      }
    });
  }

  function failAudio(error: Error, powered: SynthPower): void {
    if (currentPower() !== powered || state.phase === "error") return;
    const failed: AudioState = { phase: "error", powered, error };
    state = failed;
    view.clearNotes();
    const closing = attemptAsync(() => powered.turnOff());
    render(); // Publish the primary failure without waiting for cleanup.
    void closing.then(() => {
      if (state === failed) render();
    });
  }

  return {
    powerOn: powerOnFromGesture,
    stopNotes,
    powerOff: requestDispose,
    press(midi: number) {
      queueControls(noteOn(midi));
    },
    release(nextMidi: number | null) {
      queueControls(noteOff(nextMidi));
    },
    volumeChanged(value: number) {
      settings = { ...settings, volume: value };
      queueParams({ volume: value });
    },
    cutoffChanged(value: number) {
      settings = { ...settings, cutoff: value };
      queueParams({ cutoff: value });
    },
  };
}
