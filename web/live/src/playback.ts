import type { AudioEngine, AudioEvent, AudioStatus, OpenSessionResult, SchedulerSession } from "./audio";
import { Draft, PlaybackInput, sameDraftVersion, type DraftState, type DraftVersion } from "./authoring";
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
  inFlightVersions: readonly (DraftVersion | null)[];
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
type Connection =
  | { kind: "closed" }
  | { kind: "opening"; promise: Promise<SchedulerSession>; retirement: () => Promise<void>; controller: AbortController }
  | { kind: "open"; session: SchedulerSession };
export class Player {
  private connection: Connection = { kind: "closed" };
  private snapshot: PlayerSnapshot = { state: "Empty", mode: "none", cyclePosition: 0, tempo: 60, samplePosition: 0, pendingCount: 0, skippedCount: 0 };
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
  private retirement: Promise<void> | undefined;
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
    this.diagnostic = this.draftState.diagnostic === null ? null : { message: this.draftState.diagnostic, documentLength: this.draftState.text.length };
    this.render();
  }

  view(): PlaybackView {
    const state = this.connection.kind === "opening" ? "Starting" : this.snapshot.state;
    const status: AudioStatus = state === "Starting" ? { kind: "starting" }
      : state === "Fault" ? { kind: "error", message: this.feedback?.message ?? "Audio failed" }
      : this.connection.kind === "open" ? { kind: "running" } : { kind: "idle" };
    const draftState = this.draftState;
    const inFlightVersions: (DraftVersion | null)[] = [];
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
      this.diagnostic = state.diagnostic === null ? null : { message: state.diagnostic, documentLength: state.text.length };
      this.feedback = state.diagnostic === null ? null : { kind: "error", message: state.diagnostic };
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
    this.diagnostic = state.diagnostic === null ? null : { message: state.diagnostic, documentLength: state.text.length };
    this.feedback = state.diagnostic === null ? null : { kind: "error", message: state.diagnostic };
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
    ++this.epoch;
    ++this.intent;
    this.cancelAutomatic();
    this.automaticInFlight = undefined;
    const previous = this.connection;
    this.connection = { kind: "closed" };
    if (previous.kind === "opening") previous.controller.abort();
    this.rejectPending(new DOMException("Player closed", "AbortError"));
    this.currentSource = null;
    this.acceptedVersion = null;
    this.latestAcceptedSourceId = 0;
    this.latestRejectedVersion = null;
    this.latestDraftReceipt = 0;
    this.snapshot = { state: "Empty", mode: "none", cyclePosition: 0, tempo: 60, samplePosition: 0, pendingCount: 0, skippedCount: 0 };
    this.feedback = null;
    this.refreshDraft();
    const state = this.draftState;
    this.diagnostic = state.diagnostic === null ? null : { message: state.diagnostic, documentLength: state.text.length };
    const retirement = this.retire(previous);
    this.render();
    await retirement;
  }

  private retire(previous: Connection): Promise<void> {
    if (this.retirement !== undefined) return this.retirement;
    const closing = previous.kind === "open" ? previous.session.close()
      : previous.kind === "opening" ? previous.retirement() : Promise.resolve();
    let retirement: Promise<void>;
    retirement = Promise.resolve(closing).then(() => undefined).finally(() => {
      if (this.retirement === retirement) this.retirement = undefined;
    });
    this.retirement = retirement;
    return retirement;
  }
  private open(): Promise<SchedulerSession> {
    if (this.connection.kind === "open") return Promise.resolve(this.connection.session);
    if (this.connection.kind === "opening") return this.connection.promise;
    const epoch = ++this.epoch;
    const controller = new AbortController();
    const raw = (async (): Promise<OpenSessionResult> => {
      if (this.retirement !== undefined) await this.retirement;
      if (epoch !== this.epoch) throw new DOMException("Player closed during startup", "AbortError");
      return this.engine.openSession(event => {
        if (epoch === this.epoch) this.receive(event);
      }, controller.signal);
    })();
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
      if (opened.session.kind !== "scheduler") {
        await opened.session.close();
        throw new Error("Player requires the scheduler audio engine");
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
    ++this.epoch;
    ++this.intent;
    this.cancelAutomatic();
    this.automaticInFlight = undefined;
    const previous = this.connection;
    if (previous.kind === "opening") previous.controller.abort();
    this.connection = { kind: "closed" };
    this.currentSource = null;
    this.acceptedVersion = null;
    this.latestAcceptedSourceId = 0;
    this.latestRejectedVersion = null;
    this.latestDraftReceipt = 0;
    this.snapshot = { ...this.snapshot, state: "Fault" };
    this.feedback = { kind: "error", message };
    this.rejectPending(new Error(message));
    const retirement = this.retire(previous);
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
      } else if (version === null && receipt.kind === "rejected" && receipt.id.value === this.lastReceipt) {
        this.feedback = { kind: "error", message: receipt.message };
      }
    }
    pending.resolve(receipt);
    this.render();
  }
}
