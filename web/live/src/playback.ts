import type { AudioEngine, AudioEvent, AudioStatus, OpenSessionResult, SchedulerSession } from "./audio";
import { RequestId } from "./playback-protocol";
import type { PlayerOperation, PlayerReceipt, PlayerSnapshot } from "./playback-protocol";

type Feedback = Readonly<{ message: string; kind: "error" | "info" }>;
type Diagnostic = Readonly<{ message: string; documentLength: number }>;
export type PlaybackView = Readonly<{
  status: AudioStatus;
  state: PlayerSnapshot["state"] | "Starting";
  currentSource: string | null;
  tempoText: string;
  samplePosition: number;
  pendingCount: number;
  skippedCount: number;
  feedback: Feedback | null;
  diagnostic: Diagnostic | null;
}>;
type Pending = {
  operation: PlayerOperation;
  source: string | undefined;
  edit: number;
  resolve: (receipt: PlayerReceipt) => void;
  reject: (error: Error) => void;
};
type Connection =
  | { kind: "closed" }
  | { kind: "opening"; promise: Promise<SchedulerSession>; retirement: () => Promise<void>; controller: AbortController }
  | { kind: "open"; session: SchedulerSession };
/** Owns musical commands and their receipts, not AudioContext power policy. */
export class Player {
  private connection: Connection = { kind: "closed" };
  private snapshot: PlayerSnapshot = { state: "Empty", tempo: 60, samplePosition: 0, pendingCount: 0, skippedCount: 0 };
  private source: string;
  private currentSource: string | null = null;
  private feedback: Feedback | null = null;
  private diagnostic: Diagnostic | null = null;
  private next = RequestId.first();
  private epoch = 0;
  private intent = 0;
  private editVersion = 0;
  private lastReceipt = 0;
  private pending = new Map<number, Pending>();
  private retirement: Promise<void> | undefined;
  private debounce: ReturnType<typeof setTimeout> | undefined;

  constructor(
    private readonly engine: Pick<AudioEngine, "openSession">,
    initial: { text: string },
    private readonly present: (view: PlaybackView) => void,
  ) {
    this.source = initial.text;
    this.render();
  }

  view(): PlaybackView {
    const state = this.connection.kind === "opening" ? "Starting" : this.snapshot.state;
    const status: AudioStatus = state === "Starting" ? { kind: "starting" }
      : state === "Fault" ? { kind: "error", message: this.feedback?.message ?? "Audio failed" }
      : this.connection.kind === "open" ? { kind: "running" } : { kind: "idle" };
    return { ...this.snapshot, state, status, currentSource: this.currentSource,
      tempoText: String(this.snapshot.tempo), feedback: this.feedback, diagnostic: this.diagnostic };
  }

  private render(): void { this.present(this.view()); }
  private cancelDebounce(): void { clearTimeout(this.debounce); this.debounce = undefined; }
  private setSource(source: string): void {
    if (source !== this.source) {
      this.source = source;
      this.editVersion++;
      this.diagnostic = null;
      this.feedback = null;
    }
  }

  /** Editor convenience: incomplete input never replaces Current song. */
  edit(source: string): void {
    this.setSource(source);
    this.cancelDebounce();
    if (this.connection.kind === "open") {
      this.debounce = setTimeout(() => {
        this.debounce = undefined;
        void this.update(this.source).catch(error => this.report(error));
      }, 200);
    }
    this.render();
  }

  update(source: string): Promise<PlayerReceipt> {
    this.setSource(source);
    this.cancelDebounce();
    return this.send("update", source);
  }

  async restart(source: string): Promise<PlayerReceipt> {
    this.setSource(source);
    this.cancelDebounce();
    const intent = ++this.intent;
    const session = await this.open();
    if (intent !== this.intent) throw new DOMException("Restart cancelled", "AbortError");
    const result = await this.send("restart", source);
    if (result.kind === "accepted" && intent === this.intent) session.fadeIn();
    return result;
  }

  async play(): Promise<PlayerReceipt> {
    const intent = ++this.intent;
    const session = await this.open();
    if (intent !== this.intent) throw new DOMException("Play cancelled", "AbortError");
    // Only bootstrap needs editor input. Resume/Ended Play uses Current song,
    // even when the editor currently contains a syntax error.
    const result = this.currentSource === null
      ? await this.send("restart", this.source)
      : await this.send("play");
    if (result.kind === "accepted" && intent === this.intent) session.fadeIn();
    return result;
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
    this.cancelDebounce();
    const previous = this.connection;
    this.connection = { kind: "closed" };
    if (previous.kind === "opening") previous.controller.abort();
    this.rejectPending(new DOMException("Player closed", "AbortError"));
    this.currentSource = null;
    this.snapshot = { state: "Empty", tempo: 60, samplePosition: 0, pendingCount: 0, skippedCount: 0 };
    this.feedback = null;
    this.diagnostic = null;
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
  private send(operation: PlayerOperation, source?: string): Promise<PlayerReceipt> {
    if (this.connection.kind !== "open") return Promise.reject(new Error("Player is not open"));
    const session = this.connection.session;
    const id = this.next;
    this.next = id.next();
    return new Promise((resolve, reject) => {
      this.pending.set(id.value, { operation, source, edit: this.editVersion, resolve, reject });
      try {
        const result = operation === "update" ? session.update(id, source!)
          : operation === "restart" ? session.restart(id, source!)
          : operation === "play" ? session.play(id) : session.pause(id);
        if (result === "session-expired") {
          this.pending.delete(id.value);
          reject(new Error("Player session expired"));
        }
      } catch (error) {
        this.pending.delete(id.value);
        reject(error);
      }
    });
  }

  report(error: unknown): void {
    if (error instanceof Error && error.name === "AbortError") return;
    this.feedback = { kind: "error", message: error instanceof Error ? error.message : String(error) };
    this.render();
  }

  private rejectPending(error: Error): void {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }

  private fail(message: string): void {
    ++this.epoch;
    ++this.intent;
    this.cancelDebounce();
    const previous = this.connection;
    if (previous.kind === "opening") previous.controller.abort();
    this.connection = { kind: "closed" };
    this.currentSource = null;
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
    if (!pending) return; // Reply belongs to an already-retired request.
    this.pending.delete(receipt.id.value);
    if (receipt.operation !== pending.operation) {
      pending.reject(new Error("Player receipt operation mismatch"));
      this.fail("Player receipt operation mismatch");
      return;
    }
    if (receipt.id.value > this.lastReceipt) {
      this.lastReceipt = receipt.id.value;
      this.snapshot = receipt;
      if (pending.source !== undefined) {
        if (receipt.kind === "accepted") this.currentSource = pending.source;
        if (pending.edit === this.editVersion) {
          this.diagnostic = receipt.kind === "rejected" ? { message: receipt.message, documentLength: pending.source.length } : null;
          this.feedback = receipt.kind === "rejected" ? { kind: "error", message: receipt.message } : null;
        }
      } else if (receipt.kind === "rejected") {
        this.feedback = { kind: "error", message: receipt.message };
      }
    }
    pending.resolve(receipt);
    this.render();
  }
}
