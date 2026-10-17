import type { AudioEngine, AudioEvent, AudioSession, AudioStatus } from "./audio";
import { Draft, PlaybackInput, type DraftState } from "./authoring";
import { sameDraftVersion, type DraftVersion } from "./draft-version";
import { RequestId } from "./playback-protocol";
import type { PlayerOperation, PlayerReceipt, PlayerSnapshot } from "./playback-protocol";
type Feedback = Readonly<{ message: string; kind: "error" | "info" }>;
type Diagnostic = Readonly<{ message: string; documentLength: number }>;
export type DraftStatus = "unsubmitted" | "queued" | "submitting" | "accepted" | "rejected" | "invalid";
export type PlaybackView = Readonly<{
  status: AudioStatus;
  state: PlayerSnapshot["state"] | "Starting";
  currentSource: string | null;
  acceptedVersion: DraftVersion | null;
  draftVersion: DraftVersion;
  inFlightVersions: readonly DraftVersion[];
  draftStatus: DraftStatus;
  tempoText: string;
  samplePosition: number;
  mode: PlayerSnapshot["mode"];
  cyclePosition: number;
  pendingCount: number;
  skippedCount: number;
  feedback: Feedback | null;
  diagnostic: Diagnostic | null;
}>;
type Pending = {
  operation: PlayerOperation;
  input: PlaybackInput | undefined;
  resolve: (receipt: PlayerReceipt) => void;
  reject: (error: Error) => void;
};
const EMPTY: PlayerSnapshot = { state: "Empty", mode: "none", cyclePosition: 0, tempo: 60, samplePosition: 0, pendingCount: 0, skippedCount: 0 };

/** The draft's own parse error, shown until the draft changes or audio reports another. */
function draftDiagnostic(state: DraftState): Diagnostic | null {
  return state.diagnostic === null ? null : { message: state.diagnostic, documentLength: state.text.length };
}
function draftFeedback(state: DraftState): Feedback | null {
  return state.diagnostic === null ? null : { kind: "error", message: state.diagnostic };
}

type Connection =
  | { kind: "closed" }
  | { kind: "opening"; promise: Promise<AudioSession>; retirement: () => Promise<void>; controller: AbortController }
  | { kind: "open"; session: AudioSession };
export class Player {
  private connection: Connection = { kind: "closed" };
  private snapshot: PlayerSnapshot = EMPTY;
  private readonly draft: Draft;
  private currentSource: string | null = null;
  private acceptedVersion: DraftVersion | null = null;
  private latestAcceptedSourceId = 0;
  private latestRejectedVersion: DraftVersion | null = null;
  private latestDraftReceipt = 0;
  private feedback: Feedback | null = null;
  private diagnostic: Diagnostic | null = null;
  private next = RequestId.first();
  private epoch = 0;
  private intent = 0;
  private lastReceipt = 0;
  private pending = new Map<number, Pending>();
  private debounce: ReturnType<typeof setTimeout> | undefined;
  private automaticInFlight: symbol | undefined;
  private latestUnsent: PlaybackInput | undefined;
  private queuedVersion: DraftVersion | null = null;
  private draftState: DraftState;

  constructor(
    private readonly engine: Pick<AudioEngine, "openSession">,
    initial: { draft: Draft },
    private readonly present: (view: PlaybackView) => void,
  ) {
    this.draft = initial.draft;
    this.draftState = this.draft.state();
    this.diagnostic = draftDiagnostic(this.draftState);
    this.render();
  }

  view(): PlaybackView {
    const state = this.connection.kind === "opening" ? "Starting" : this.snapshot.state;
    const status: AudioStatus = state === "Starting" ? { kind: "starting" }
      : state === "Fault" ? { kind: "error", message: this.feedback?.message ?? "Audio failed" }
      : this.connection.kind === "open" ? { kind: "running" } : { kind: "idle" };
    const draftState = this.draftState;
    const inFlightVersions: DraftVersion[] = [];
    for (const pending of this.pending.values()) {
      if (pending.input !== undefined) inFlightVersions.push(pending.input.draftVersion);
    }
    let draftStatus: DraftStatus = "unsubmitted";
    if (draftState.diagnostic !== null ||
        (this.diagnostic !== null && !sameDraftVersion(this.latestRejectedVersion, draftState.version))) draftStatus = "invalid";
    else if (inFlightVersions.some(version => sameDraftVersion(version, draftState.version))) draftStatus = "submitting";
    else if (sameDraftVersion(this.queuedVersion, draftState.version)) draftStatus = "queued";
    else if (sameDraftVersion(this.latestRejectedVersion, draftState.version)) draftStatus = "rejected";
    else if (sameDraftVersion(this.acceptedVersion, draftState.version)) draftStatus = "accepted";
    return { ...this.snapshot, state, status, currentSource: this.currentSource,
      draftVersion: draftState.version, acceptedVersion: this.acceptedVersion, inFlightVersions, draftStatus,
      tempoText: String(this.snapshot.tempo), feedback: this.feedback, diagnostic: this.diagnostic };
  }
  private render(): void { this.present(this.view()); }
  private refreshDraft(): void {
    const state = this.draft.state();
    if (!sameDraftVersion(state.version, this.draftState.version)) {
      this.latestDraftReceipt = 0;
      this.latestRejectedVersion = null;
      this.diagnostic = draftDiagnostic(state);
      this.feedback = draftFeedback(state);
    }
    this.draftState = state;
  }
  private cancelAutomatic(): void {
    clearTimeout(this.debounce);
    this.debounce = undefined;
    this.latestUnsent = undefined;
    this.queuedVersion = null;
  }

  /** Every committed edit invalidates unsent work, even equal-text replacements. */
  editDraft(): void {
    this.cancelAutomatic();
    this.refreshDraft();
    const state = this.draftState;
    this.diagnostic = draftDiagnostic(state);
    this.feedback = draftFeedback(state);
    if (state.diagnostic === null && this.connection.kind === "open") {
      this.queuedVersion = state.version;
      this.debounce = setTimeout(() => {
        this.debounce = undefined;
        try {
          this.latestUnsent = this.draft.prepare();
          this.flushAutomatic();
        } catch (error) {
          this.reportDraftFailure(error);
        }
      }, 200);
    }
    this.render();
  }

  private flushAutomatic(): void {
    if (this.automaticInFlight !== undefined || this.latestUnsent === undefined || this.connection.kind !== "open") return;
    const input = this.latestUnsent;
    this.latestUnsent = undefined;
    this.queuedVersion = null;
    const flight = Symbol();
    this.automaticInFlight = flight;
    void this.send("update", input).catch(error => this.report(error)).finally(() => {
      if (this.automaticInFlight !== flight) return;
      this.automaticInFlight = undefined;
      this.flushAutomatic();
    });
  }

  update(input: PlaybackInput): Promise<PlayerReceipt> {
    this.cancelAutomatic();
    return this.send("update", input);
  }

  async restart(input: PlaybackInput): Promise<PlayerReceipt> {
    this.cancelAutomatic();
    const intent = ++this.intent;
    const session = await this.open();
    if (intent !== this.intent) throw new DOMException("Restart cancelled", "AbortError");
    const result = await this.send("restart", input);
    if (result.kind === "accepted" && intent === this.intent) session.fadeIn();
    return result;
  }
  async play(): Promise<PlayerReceipt> {
    const intent = ++this.intent;
    const session = await this.open();
    if (intent !== this.intent) throw new DOMException("Play cancelled", "AbortError");
    try {
      const result = this.currentSource === null
        ? await this.send("restart", this.draft.prepare())
        : await this.send("play");
      if (result.kind === "accepted" && intent === this.intent) session.fadeIn();
      return result;
    } catch (error) {
      if (this.draft.state().diagnostic !== null) this.reportDraftFailure(error);
      throw error;
    }
  }

  async pause(): Promise<PlayerReceipt> {
    // While opening, cancel initialization and reclaim its resources. Pause
    // is a local cancellation, not a command to an Empty session.
    if (this.connection.kind === "opening") {
      ++this.intent;
      ++this.epoch;
      const opening = this.connection;
      this.connection = { kind: "closed" };
      opening.controller.abort();
      const retirement = this.retire(opening);
      this.render();
      await retirement;
      throw new DOMException("Pause cancelled startup", "AbortError");
    }
    ++this.intent;
    return this.send("pause");
  }

  async close(): Promise<void> {
    const retirement = this.endRun(new DOMException("Player closed", "AbortError"));
    this.snapshot = EMPTY;
    this.feedback = null;
    this.refreshDraft();
    this.diagnostic = draftDiagnostic(this.draftState);
    this.render();
    await retirement;
  }

  /**
   * Ends the current run, whether it is open or still starting: its pending
   * commands fail with `reason`, its accepted score is forgotten, and its
   * connection is closed in the background.
   */
  private endRun(reason: Error): Promise<void> {
    ++this.epoch;
    ++this.intent;
    this.cancelAutomatic();
    this.automaticInFlight = undefined;
    const previous = this.connection;
    this.connection = { kind: "closed" };
    if (previous.kind === "opening") previous.controller.abort();
    this.rejectPending(reason);
    this.currentSource = null;
    this.acceptedVersion = null;
    this.latestAcceptedSourceId = 0;
    this.latestRejectedVersion = null;
    this.latestDraftReceipt = 0;
    return this.retire(previous);
  }

  /** Closes a connection the player has already let go of. */
  private async retire(previous: Connection): Promise<void> {
    if (previous.kind === "open") await previous.session.close();
    else if (previous.kind === "opening") await previous.retirement();
  }
  private open(): Promise<AudioSession> {
    if (this.connection.kind === "open") return Promise.resolve(this.connection.session);
    if (this.connection.kind === "opening") return this.connection.promise;
    const epoch = ++this.epoch;
    const controller = new AbortController();
    // Called within the user's gesture, which a browser requires to start
    // audio; the engine lets a retiring session give way rather than wait.
    const raw = this.engine.openSession(event => {
      if (epoch === this.epoch) this.receive(event);
    }, controller.signal);
    let retirement: Promise<void> | undefined;
    const retireOpening = (): Promise<void> => {
      if (retirement !== undefined) return retirement;
      retirement = raw.then(async opened => {
        if (opened.kind === "opened") await opened.session.close();
      }, () => undefined);
      return retirement;
    };
    const promise = raw.then(async opened => {
      if (epoch !== this.epoch) throw new DOMException("Player closed during startup", "AbortError");
      if (opened.kind !== "opened") {
        throw new Error(opened.kind === "failed" ? opened.message : "Audio owner is busy");
      }
      this.connection = { kind: "open", session: opened.session };
      this.render();
      return opened.session;
    }).catch(error => {
      if (epoch === this.epoch && !(error instanceof DOMException && error.name === "AbortError")) {
        this.fail(error instanceof Error ? error.message : String(error));
      } else if (epoch === this.epoch && this.connection.kind === "opening") {
        this.connection = { kind: "closed" };
        this.render();
      }
      throw error;
    });
    this.connection = { kind: "opening", promise, retirement: retireOpening, controller };
    this.render();
    return promise;
  }
  private send(operation: PlayerOperation, input?: PlaybackInput): Promise<PlayerReceipt> {
    if (input !== undefined) this.refreshDraft();
    if (this.connection.kind !== "open") return Promise.reject(new Error("Player is not open"));
    const session = this.connection.session;
    const id = this.next;
    this.next = id.next();
    return new Promise((resolve, reject) => {
      this.pending.set(id.value, { operation, input, resolve, reject });
      this.render();
      try {
        const result = operation === "update" ? session.update(id, input!)
          : operation === "restart" ? session.restart(id, input!)
          : operation === "play" ? session.play(id) : session.pause(id);
        if (result === "session-expired") {
          this.pending.delete(id.value);
          reject(new Error("Player session expired"));
          this.render();
        }
      } catch (error) {
        this.pending.delete(id.value);
        reject(error);
        this.render();
      }
    });
  }

  report(error: unknown): void {
    if (error instanceof Error && error.name === "AbortError") return;
    this.feedback = { kind: "error", message: error instanceof Error ? error.message : String(error) };
    this.render();
  }
  reportDraftFailure(error: unknown): void {
    if (error instanceof Error && error.name === "AbortError") return;
    this.cancelAutomatic();
    this.refreshDraft();
    const message = error instanceof Error ? error.message : String(error);
    this.feedback = { kind: "error", message };
    this.diagnostic = { message, documentLength: this.draftState.text.length };
    this.render();
  }
  private rejectPending(error: Error): void {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
  private fail(message: string): void {
    const retirement = this.endRun(new Error(message));
    this.snapshot = { ...this.snapshot, state: "Fault" };
    this.feedback = { kind: "error", message };
    this.render();
    void retirement.catch(error => this.report(error));
  }
  private receive(event: AudioEvent): void {
    if (event.kind === "failed") { this.fail(event.message); return; }
    if (event.kind === "status") { this.snapshot = event; this.render(); return; }
    const receipt = event.receipt;
    const pending = this.pending.get(receipt.id.value);
    if (!pending) return;
    this.pending.delete(receipt.id.value);
    if (receipt.operation !== pending.operation ||
        !sameDraftVersion(receipt.draftVersion, pending.input?.draftVersion ?? null)) {
      const error = new Error("Player receipt operation/version mismatch");
      pending.reject(error);
      this.fail(error.message);
      return;
    }
    if (receipt.id.value > this.lastReceipt) {
      this.lastReceipt = receipt.id.value;
      this.snapshot = receipt;
      if (receipt.kind === "rejected" && pending.input === undefined) {
        this.feedback = { kind: "error", message: receipt.message };
      }
    }
    if (pending.input !== undefined) {
      const version = pending.input.draftVersion;
      if (receipt.kind === "accepted" && receipt.id.value > this.latestAcceptedSourceId) {
        this.latestAcceptedSourceId = receipt.id.value;
        this.currentSource = pending.input.source;
        this.acceptedVersion = version;
      }
      if (sameDraftVersion(version, this.draftState.version) && receipt.id.value > this.latestDraftReceipt) {
        this.latestDraftReceipt = receipt.id.value;
        this.latestRejectedVersion = receipt.kind === "rejected" ? version : null;
        this.diagnostic = receipt.kind === "rejected" ? { message: receipt.message, documentLength: pending.input.source.length } : null;
        this.feedback = receipt.kind === "rejected" ? { kind: "error", message: receipt.message } : null;
      }
    }
    pending.resolve(receipt);
    this.render();
  }
}
